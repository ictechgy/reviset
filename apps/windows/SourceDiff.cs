using System.Text.Json;

namespace Reviset.Windows;

// Presentation-only, bounded comparison of stored text. It does not infer
// document deletion, recalculate cells or change the canonical report.
internal sealed record SourceDiffLine(char Prefix, string Text, string Terminator = "")
{
    internal string RawText => Text + Terminator;
    internal string TerminatorLabel => Terminator switch { "\r\n" => "⟦CRLF⟧", "\r" => "⟦CR⟧", "\n" => "⟦LF⟧", _ => "⟦EOF⟧" };
}
internal sealed record SourceDiffResult(IReadOnlyList<SourceDiffLine> Lines, bool Truncated, bool Coarse, bool TerminatorsDiffer = false);
internal enum SourceTextState { Missing, Null, Empty, Present, Partial, AlreadyRead, Invalid }
internal sealed record SourceTextRange(bool Valid, string State, int? Offset, int? Total, int? Next, int Length);
internal sealed record SourceTextObservation(SourceTextState State, string Text, SourceTextRange? Range = null)
{
    internal SourceTextState RawState { get; init; } = State;
    internal bool Available => State is SourceTextState.Empty or SourceTextState.Present;
    internal bool HasText => RawState is SourceTextState.Empty or SourceTextState.Present;
    internal static SourceTextObservation Read(JsonElement value) => value.ValueKind switch
    {
        JsonValueKind.String => new(value.GetString()!.Length == 0 ? SourceTextState.Empty : SourceTextState.Present, value.GetString()!),
        JsonValueKind.Null => new(SourceTextState.Null, ""),
        _ => new(SourceTextState.Missing, "")
    };
    internal static SourceTextObservation ReadSegment(JsonElement value, JsonElement metadata)
    {
        var raw = Read(value); int? Number(string key) => metadata.Get(key).ValueKind == JsonValueKind.Number && metadata.Get(key).TryGetInt32(out var number) && number >= 0 ? number : null;
        var offset = Number("offset"); var total = Number("total_length"); var next = Number("next_offset"); var state = metadata.Get("state").Text(); var noNext = metadata.Get("next_offset").ValueKind == JsonValueKind.Null;
        var valid = metadata.ValueKind == JsonValueKind.Object && offset.HasValue && total.HasValue;
        var end = (long)(offset ?? 0) + raw.Text.Length;
        valid &= state switch
        {
            "missing" => value.ValueKind == JsonValueKind.Null && total == 0 && noNext,
            "empty" => value.ValueKind == JsonValueKind.String && raw.Text.Length == 0 && offset == 0 && total == 0 && noNext,
            "complete" => value.ValueKind == JsonValueKind.String && raw.Text.Length > 0 && offset == 0 && total == raw.Text.Length && noNext,
            "truncated" => value.ValueKind == JsonValueKind.String && total > 0 && offset <= total && end <= total && (offset > 0 || end < total) && (end < total ? raw.Text.Length > 0 && next == end : noNext),
            _ => false
        };
        var range = new SourceTextRange(valid, state.Length > 0 ? state : "not_recorded", offset, total, next, raw.Text.Length);
        return new(!valid ? SourceTextState.Invalid : state == "truncated" ? raw.Text.Length == 0 && offset == total ? SourceTextState.AlreadyRead : SourceTextState.Partial : raw.State, raw.Text, range) { RawState = raw.State };
    }
}
internal sealed record SourceDiffField(string Key, SourceTextObservation Before, SourceTextObservation After, bool Eligible, string Reason);
internal static class SourceDiffPolicy
{
    // Eligibility is decided on typed observations before any string conversion.
    // A null, absent observation or display-state event cannot become a +/- edit.
    internal static SourceDiffField Document(JsonElement change, bool pairedSourcesReady, bool structural)
    {
        var a = SourceTextObservation.Read(change.Get("before")); var b = SourceTextObservation.Read(change.Get("after"));
        var eligible = pairedSourcesReady && !structural && change.Get("kind").Text() == "text_modified" && change.Get("topology").ValueKind is JsonValueKind.Undefined or JsonValueKind.Null && a.Available && b.Available;
        return new("text", a, b, eligible, eligible ? "" : structural ? "structuralObservation" : "neutralObservation");
    }
    internal static IReadOnlyList<SourceDiffField> Workbook(JsonElement change, JsonElement before, JsonElement after)
    {
        var kind = change.Get("kind").Text(); var paired = before.ValueKind == JsonValueKind.Object && after.ValueKind == JsonValueKind.Object;
        var result = new List<SourceDiffField>();
        foreach (var field in new[] { "value", "formula", "number_format" })
        {
            var a = SourceTextObservation.ReadSegment(before.Get(field), before.Get("text_continuations").Get(field)); var b = SourceTextObservation.ReadSegment(after.Get(field), after.Get("text_continuations").Get(field));
            var unresolved = before.Get("formula_interpretation").Text() == "unresolved" || after.Get("formula_interpretation").Text() == "unresolved";
            var cacheMissing = field == "value" && (before.Get("cached_result").Text() is not ("present" or "not_applicable") || after.Get("cached_result").Text() is not ("present" or "not_applicable"));
            var eligibleKind = kind == (field == "value" ? "stored_value" : field);
            result.Add(new(field, a, b, paired && a.Available && b.Available && !unresolved && !cacheMissing && eligibleKind && change.Get("association").Text() != "needs_review", a.State == SourceTextState.Invalid || b.State == SourceTextState.Invalid ? "invalidSourceSegment" : a.State is SourceTextState.Partial or SourceTextState.AlreadyRead || b.State is SourceTextState.Partial or SourceTextState.AlreadyRead ? "partialSourceSegment" : cacheMissing ? "missingCacheObservation" : unresolved ? "unresolvedObservation" : "neutralObservation"));
        }
        return result;
    }
    internal static IReadOnlyList<(string Key, string Value)> SelectedNotices(JsonElement change)
    {
        var result = new List<(string Key, string Value)>();
        foreach (var key in new[] { "text_assessment", "region_pairing_assessment", "appearance_assessment" })
            if (change.Get(key).ValueKind == JsonValueKind.String) result.Add((key, change.Get(key).Text()));
        var lineage = change.Get("lineage"); if (lineage.Get("status").ValueKind == JsonValueKind.String) result.Add(("lineageAssessment", lineage.Get("status").Text()));
        foreach (var reason in lineage.Get("reasons").Items()) if (reason.ValueKind == JsonValueKind.String) result.Add(("lineageReason", reason.Text()));
        foreach (var gap in change.Get("coverage_gaps").Items()) result.Add(("selectedCoverage", gap.Get("feature").Text() + ": " + gap.Get("reason").Text()));
        if (change.Get("association").ValueKind == JsonValueKind.String) result.Add(("rowAssociation", change.Get("association").Text() + " · " + change.Get("alignment_method").Text()));
        return result;
    }
}
internal static class SourceDiff
{
    internal const int CharacterLimit = 16384;
    internal const int LineLimit = 300;
    internal static SourceDiffResult Build(string before, string after)
    {
        var truncated = false;
        SourceDiffLine[] Split(string value)
        {
            if (value.Length > CharacterLimit) { var end = CharacterLimit; if (char.IsHighSurrogate(value[end - 1]) || value[end - 1] == '\r' && value[end] == '\n') end--; value = value[..end]; truncated = true; }
            var lines = new List<SourceDiffLine>(); var start = 0;
            for (var index = 0; index < value.Length; index++)
            {
                if (value[index] is not ('\r' or '\n')) continue;
                var end = index + (value[index] == '\r' && index + 1 < value.Length && value[index + 1] == '\n' ? 2 : 1);
                lines.Add(new(' ', value[start..index], value[index..end])); start = end; index = end - 1;
                if (lines.Count == LineLimit) { if (start < value.Length) truncated = true; return lines.ToArray(); }
            }
            if (start < value.Length || lines.Count == 0) lines.Add(new(' ', value[start..]));
            return lines.ToArray();
        }
        var a = Split(before); var b = Split(after); var result = new List<SourceDiffLine>();
        // The matrix is at most 301 x 301; input lines/characters are bounded.
        var table = new int[a.Length + 1, b.Length + 1];
        for (var i = a.Length - 1; i >= 0; i--) for (var j = b.Length - 1; j >= 0; j--) table[i, j] = a[i].RawText == b[j].RawText ? 1 + table[i + 1, j + 1] : Math.Max(table[i + 1, j], table[i, j + 1]);
        var x = 0; var y = 0;
        while (x < a.Length || y < b.Length)
        {
            if (x < a.Length && y < b.Length && a[x].RawText == b[y].RawText) { result.Add(a[x] with { Prefix = ' ' }); x++; y++; }
            else if (x < a.Length && (y == b.Length || table[x + 1, y] >= table[x, y + 1])) result.Add(a[x++] with { Prefix = '-' });
            else result.Add(b[y++] with { Prefix = '+' });
        }
        return new(result, truncated, false, string.Concat(a.Select(line => line.Terminator)) != string.Concat(b.Select(line => line.Terminator)));
    }
    internal static (int Before, int After) PreviousToSelected(int selected, int count)
    {
        if (count < 1) return (-1, -1);
        var after = Math.Clamp(selected, 0, count - 1); return (Math.Max(0, after - 1), after);
    }
}
