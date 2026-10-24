using System.Text.Json;

namespace Reviset.Windows;

// Presentation-only, bounded comparison of stored text. It does not infer
// document deletion, recalculate cells or change the canonical report.
internal sealed record SourceDiffLine(char Prefix, string Text);
internal sealed record SourceDiffResult(IReadOnlyList<SourceDiffLine> Lines, bool Truncated, bool Coarse);
internal enum SourceTextState { Missing, Null, Empty, Present }
internal sealed record SourceTextObservation(SourceTextState State, string Text)
{
    internal bool Available => State is SourceTextState.Empty or SourceTextState.Present;
    internal static SourceTextObservation Read(JsonElement value) => value.ValueKind switch
    {
        JsonValueKind.String => new(value.GetString()!.Length == 0 ? SourceTextState.Empty : SourceTextState.Present, value.GetString()!),
        JsonValueKind.Null => new(SourceTextState.Null, ""),
        _ => new(SourceTextState.Missing, "")
    };
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
            var a = SourceTextObservation.Read(before.Get(field)); var b = SourceTextObservation.Read(after.Get(field));
            var unresolved = before.Get("formula_interpretation").Text() == "unresolved" || after.Get("formula_interpretation").Text() == "unresolved";
            var cacheMissing = field == "value" && (before.Get("cached_result").Text() is not ("present" or "not_applicable") || after.Get("cached_result").Text() is not ("present" or "not_applicable"));
            var eligibleKind = kind == (field == "value" ? "stored_value" : field);
            result.Add(new(field, a, b, paired && a.Available && b.Available && !unresolved && !cacheMissing && eligibleKind && change.Get("association").Text() != "needs_review", cacheMissing ? "missingCacheObservation" : unresolved ? "unresolvedObservation" : "neutralObservation"));
        }
        return result;
    }
    internal static IReadOnlyList<(string Key, string Value)> SelectedNotices(JsonElement change)
    {
        var result = new List<(string Key, string Value)>();
        foreach (var key in new[] { "text_assessment", "region_pairing_assessment", "appearance_assessment" })
            if (change.Get(key).ValueKind == JsonValueKind.String) result.Add((key, change.Get(key).Text()));
        var lineage = change.Get("lineage"); if (lineage.Get("status").ValueKind == JsonValueKind.String) result.Add(("lineageAssessment", lineage.Get("status").Text()));
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
        string[] Split(string value)
        {
            if (value.Length > CharacterLimit) { var end = CharacterLimit; if (char.IsHighSurrogate(value[end - 1])) end--; value = value[..end]; truncated = true; }
            var lines = value.Replace("\r\n", "\n", StringComparison.Ordinal).Replace('\r', '\n').Split('\n');
            if (lines.Length > LineLimit) { lines = lines[..LineLimit]; truncated = true; }
            return lines;
        }
        var a = Split(before); var b = Split(after); var result = new List<SourceDiffLine>();
        // The matrix is at most 301 x 301; input lines/characters are bounded.
        var table = new int[a.Length + 1, b.Length + 1];
        for (var i = a.Length - 1; i >= 0; i--) for (var j = b.Length - 1; j >= 0; j--) table[i, j] = a[i] == b[j] ? 1 + table[i + 1, j + 1] : Math.Max(table[i + 1, j], table[i, j + 1]);
        var x = 0; var y = 0;
        while (x < a.Length || y < b.Length)
        {
            if (x < a.Length && y < b.Length && a[x] == b[y]) { result.Add(new(' ', a[x])); x++; y++; }
            else if (x < a.Length && (y == b.Length || table[x + 1, y] >= table[x, y + 1])) result.Add(new('-', a[x++]));
            else result.Add(new('+', b[y++]));
        }
        return new(result, truncated, false);
    }
    internal static (int Before, int After) PreviousToSelected(int selected, int count)
    {
        if (count < 1) return (-1, -1);
        var after = Math.Clamp(selected, 0, count - 1); return (Math.Max(0, after - 1), after);
    }
}
