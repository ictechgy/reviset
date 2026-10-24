using System.Text.Json;

namespace Reviset.Windows;

// Presentation-only, bounded comparison of stored text. It does not infer
// document deletion, recalculate cells or change the canonical report.
internal sealed record SourceDiffLine(char Prefix, string Text, string Terminator = "", bool CutOff = false)
{
    internal string RawText => Text + Terminator;
    internal string TerminatorLabel => CutOff ? "⟦TRUNCATED⟧" : Terminator switch { "\r\n" => "⟦CRLF⟧", "\r" => "⟦CR⟧", "\n" => "⟦LF⟧", _ => "⟦EOF⟧" };
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
internal sealed record WorkbookSourceScope(string BeforeOccurrence, string AfterOccurrence, string BeforeSheet, string AfterSheet, string BeforeAddress, string AfterAddress);
internal static class SourceDiffPolicy
{
    internal static bool SheetScoped(string kind) => kind.StartsWith("sheet_", StringComparison.Ordinal) || kind is "merges" or "date_system" or "calculation_settings";
    internal static int WorkbookRow(JsonElement change, bool after)
    {
        var address = change.Get(after ? "after_address" : "before_address").Text(); var index = 0;
        while (index < address.Length && address[index] is >= 'A' and <= 'Z') index++;
        return index > 0 && index < address.Length && int.TryParse(address.AsSpan(index), System.Globalization.NumberStyles.None, System.Globalization.CultureInfo.InvariantCulture, out var row) && row is >= 1 and <= 1_048_576 ? row : 0;
    }
    // Translate only recognized producer templates. Unknown descriptions stay
    // verbatim; cell strings and authored descriptions never enter this table.
    internal static string WorkbookSummaryKey(JsonElement change) => change.Get("description").Text() switch
    {
        "Stored value changed; formula results may be stale" when change.Get("kind").Text() == "stored_value" => "summaryStoredValue",
        "Formula source changed; formulas were not recalculated" when change.Get("kind").Text() == "formula" => "summaryFormula",
        "Saved formula result availability changed; a missing cache is not a deleted cell" when change.Get("kind").Text() == "cache_availability" => "summaryCache",
        "Stored value type changed" when change.Get("kind").Text() == "value_type" => "summaryValueType",
        "Number format changed" when change.Get("kind").Text() == "number_format" => "summaryNumberFormat",
        "Supported basic style changed" when change.Get("kind").Text() == "style" => "summaryStyle",
        "Hidden row/column observation changed" when change.Get("kind").Text() == "visibility" => "summaryVisibility",
        "Cell observed on an unmatched row; no confirmed semantic deletion/addition" when change.Get("kind").Text() == "row_correspondence" => "summaryRowCorrespondence",
        "Materialized cell present on one endpoint; missing observation is distinct from explicit blank/zero" when change.Get("kind").Text() == "cell_observation" => "summaryCellObservation",
        "Sheet observed only on one endpoint; correspondence requires review, not confirmed addition/deletion" when change.Get("kind").Text() == "sheet_observation" => "summarySheetObservation",
        "Supported stored calculation flags changed; this neither executes recalculation nor certifies cached-result freshness" when change.Get("kind").Text() == "calculation_settings" => "summaryCalculation",
        "Supported row/column dimensions or hidden ranges changed, including unmaterialized blank cells" when change.Get("kind").Text() == "sheet_dimensions" => "summaryDimensions",
        "Merged range observations changed" when change.Get("kind").Text() == "merges" => "summaryMerges",
        "Raw cell/formula/cache observations changed; shared/array/spill formula role is unresolved. This is not an asserted formula removal, direct-input edit or recalculated result." when change.Get("kind").Text() == "cell_observation" => "summaryUnresolved",
        "Numeric date/time serial and ISO/date/time source representations are not normalized across formats; equivalence is unavailable and this is not an asserted value/type edit." when change.Get("kind").Text() == "cell_observation" => "summaryDateRepresentation",
        var text when change.Get("kind").Text() == "row_position" && WorkbookRow(change, false) > 0 && WorkbookRow(change, true) > 0 && text == "Inferred corresponding row moved from " + WorkbookRow(change, false) + " to " + WorkbookRow(change, true) => "summaryRowPosition",
        var text when change.Get("kind").Text() == "sheet_name" && text.StartsWith("Sheet name: ", StringComparison.Ordinal) && text.Contains(" → ", StringComparison.Ordinal) => "summarySheetName",
        var text when change.Get("kind").Text() == "sheet_position" && System.Text.RegularExpressions.Regex.IsMatch(text, @"\ASheet index: [0-9]+ → [0-9]+\z") => "summarySheetPosition",
        var text when change.Get("kind").Text() == "sheet_visibility" && System.Text.RegularExpressions.Regex.IsMatch(text, @"\ASheet hidden: (true|false) → (true|false)\z") => "summarySheetVisibility",
        var text when change.Get("kind").Text() == "date_system" && System.Text.RegularExpressions.Regex.IsMatch(text, @"\ADate system changed from (1900|1904|unknown) to (1900|1904|unknown); stored numeric dates are not converted or equated\z") => "summaryDateSystem",
        _ => ""
    };
    internal static string WorkbookObservationCaption(string field, JsonElement cell, SourceTextObservation value)
    {
        if (cell.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined) return "cellNotMaterialized";
        if (value.State == SourceTextState.Null && value.Range is { Valid: true })
        {
            if (field == "formula") return "formulaAbsent";
            if (field == "value" && cell.Get("cached_result").Text() == "missing") return "resultMissingShort";
            if (field == "value" && cell.Get("value_type").Text() == "blank") return "valueBlankShort";
        }
        return value.State switch { SourceTextState.Missing => "observationMissing", SourceTextState.Null => "observationNull", SourceTextState.Empty => "observationEmpty", SourceTextState.Partial => "partialSourceSegment", SourceTextState.AlreadyRead => "alreadyReadSegment", SourceTextState.Invalid => "invalidSourceSegment", _ => "observationPresent" };
    }
    internal static IReadOnlyList<string> WorkbookWarningKeys(JsonElement cell)
    {
        if (cell.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined) return ["cellNotMaterialized"];
        var warnings = new List<string>(); var missing = cell.Get("cached_result").Text() == "missing";
        if (cell.Get("formula_interpretation").Text() == "unresolved") warnings.Add("formulaUnresolvedShort");
        if (missing) warnings.Add("resultMissingShort");
        if (cell.Get("cache_freshness").Text() == "unknown") warnings.Add("freshnessUnknownShort");
        if (!missing && cell.Get("value").ValueKind == JsonValueKind.Null) warnings.Add(cell.Get("value_type").Text() == "blank" ? "valueBlankShort" : "valueUnrecordedShort");
        var empty = cell.Get("value").ValueKind == JsonValueKind.String && cell.Get("value").Text().Length == 0;
        var previewEmpty = cell.Get("source_lengths").Get("value").ValueKind == JsonValueKind.Number && cell.Get("source_lengths").Get("value").Number(-1) == 0;
        if (!missing && empty && (previewEmpty || SourceTextObservation.ReadSegment(cell.Get("value"), cell.Get("text_continuations").Get("value")).State == SourceTextState.Empty)) warnings.Add("valueEmptyShort");
        return warnings;
    }
    // Eligibility is decided on typed observations before any string conversion.
    // A null, absent observation or display-state event cannot become a +/- edit.
    internal static SourceDiffField Document(JsonElement change, bool pairedSourcesReady, bool structural)
    {
        var a = SourceTextObservation.Read(change.Get("before")); var b = SourceTextObservation.Read(change.Get("after"));
        var eligible = pairedSourcesReady && !structural && change.Get("kind").Text() == "text_modified" && change.Get("topology").ValueKind is JsonValueKind.Undefined or JsonValueKind.Null && a.Available && b.Available;
        return new("text", a, b, eligible, eligible ? "" : structural ? "structuralObservation" : "neutralObservation");
    }
    internal static bool WorkbookComponent(JsonElement response, JsonElement change, string component, string project, string report, out JsonElement cell)
    {
        cell = default; var items = response.Get("items").Items();
        if (response.Get("project_id").Text() != project || response.Get("report_id").Text() != report || items.Count != 1) return false;
        var item = items[0];
        foreach (var key in new[] { "change_id", "kind", "from_revision_occurrence_id", "to_revision_occurrence_id", "from_sheet_id", "to_sheet_id", "before_address", "after_address", "association", "alignment_method" })
        {
            var a = item.Get(key); var b = change.Get(key); if (a.ValueKind != b.ValueKind || a.ValueKind is not (JsonValueKind.String or JsonValueKind.Null) || a.GetRawText() != b.GetRawText()) return false;
        }
        if (item.Get("component").Text() != component) return false;
        cell = item.Get(component); var address = change.Get(component + "_address");
        if (cell.ValueKind == JsonValueKind.Null) return address.ValueKind == JsonValueKind.Null;
        if (cell.ValueKind != JsonValueKind.Object || address.ValueKind != JsonValueKind.String || address.Text().Length == 0 || cell.Get("address").Text() != address.Text()) return false;
        var row = cell.Get("row").Number(); var column = cell.Get("column").Number(); if (row is < 1 or > 1_048_576 || column is < 1 or > 16_384) return false;
        var letters = ""; for (var index = column; index > 0; index /= 26) { index--; letters = (char)('A' + index % 26) + letters; } return address.Text() == letters + row.ToString(System.Globalization.CultureInfo.InvariantCulture);
    }
    internal static IReadOnlyList<SourceDiffField> Workbook(JsonElement change, JsonElement before, JsonElement after, WorkbookSourceScope? source = null, int textOffset = 0)
    {
        var kind = change.Get("kind").Text(); var paired = before.ValueKind == JsonValueKind.Object && after.ValueKind == JsonValueKind.Object;
        var from = change.Get("from_revision_occurrence_id").Text(); var to = change.Get("to_revision_occurrence_id").Text(); var sheetA = change.Get("from_sheet_id").Text(); var sheetB = change.Get("to_sheet_id").Text();
        var addressA = change.Get("before_address").Text(); var addressB = change.Get("after_address").Text();
        var context = paired && from.Length > 0 && to.Length > 0 && from != to && sheetA.Length > 0 && sheetB.Length > 0 && addressA.Length > 0 && addressB.Length > 0 && addressA == before.Get("address").Text() && addressB == after.Get("address").Text() && change.Get("association").Text() is "exact" or "inferred" && change.Get("alignment_method").Text() is "unique_nonempty_first_column_key" or "unique_exact_row_content";
        if (source is not null) context &= source.BeforeOccurrence == from && source.AfterOccurrence == to && source.BeforeSheet == sheetA && source.AfterSheet == sheetB && source.BeforeAddress == addressA && source.AfterAddress == addressB;
        var result = new List<SourceDiffField>();
        foreach (var field in new[] { "value", "formula", "number_format" })
        {
            var a = before.ValueKind == JsonValueKind.Object ? SourceTextObservation.ReadSegment(before.Get(field), before.Get("text_continuations").Get(field)) : new(SourceTextState.Missing, ""); var b = after.ValueKind == JsonValueKind.Object ? SourceTextObservation.ReadSegment(after.Get(field), after.Get("text_continuations").Get(field)) : new(SourceTextState.Missing, "");
            var unresolved = before.Get("formula_interpretation").Text() == "unresolved" || after.Get("formula_interpretation").Text() == "unresolved";
            var cacheMissing = field == "value" && (before.Get("cached_result").Text() is not ("present" or "not_applicable") || after.Get("cached_result").Text() is not ("present" or "not_applicable"));
            var eligibleKind = field == "formula" ? kind == "formula" && before.Get("formula_dialect").Text() is "xlsx_a1" or "ods_openformula" && before.Get("formula_dialect").Text() == after.Get("formula_dialect").Text() : field == "value" && kind == "stored_value" && before.Get("value_type").Text() is "blank" or "string" or "number" or "boolean" or "date" or "time" or "error" && before.Get("value_type").Text() == after.Get("value_type").Text();
            var asserted = field == "formula" ? kind == "formula" : field == "value" && kind == "stored_value";
            var observedBlank = field == "value" && new[] { before, after }.Any(cell => cell.Get("value").ValueKind == JsonValueKind.Null && cell.Get("value_type").Text() == "blank" && cell.Get("cached_result").Text() != "missing");
            var reason = !paired ? "unavailableText" : a.State == SourceTextState.Invalid || b.State == SourceTextState.Invalid ? "invalidSourceSegment" : a.State is SourceTextState.Missing or SourceTextState.Null || b.State is SourceTextState.Missing or SourceTextState.Null ? observedBlank ? "valueBlankShort" : "missingObservation" : textOffset != 0 || a.State is SourceTextState.Partial or SourceTextState.AlreadyRead || b.State is SourceTextState.Partial or SourceTextState.AlreadyRead ? "partialSourceSegment" : !context ? "unmatchedSourceObservation" : field == "number_format" && kind == "number_format" ? "numberFormatObservation" : !asserted ? "notAssertedObservation" : unresolved ? "unresolvedObservation" : cacheMissing ? "missingCacheObservation" : !eligibleKind ? field == "formula" ? "formulaDialectObservation" : "valueTypeObservation" : a.Text == b.Text ? "identicalObservation" : "neutralObservation";
            result.Add(new(field, a, b, context && textOffset == 0 && a.Available && b.Available && !unresolved && !cacheMissing && eligibleKind, reason));
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
    // Summary chrome is a display projection. The full, exact source/reason
    // remains in its scrolling evidence surface and never passes through here.
    internal static string NoticeSummary(string value, int limit = 220)
    {
        var compact = string.Join(" ", value.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
        if (compact.Length <= limit) return compact;
        var end = limit; if (end > 0 && char.IsHighSurrogate(compact[end - 1])) end--;
        return compact[..end] + "…";
    }
    internal const int CharacterLimit = 16384;
    internal const int LineLimit = 300;
    internal static SourceDiffResult Build(string before, string after)
    {
        var truncated = false;
        SourceDiffLine[] Split(string value)
        {
            var cut = value.Length > CharacterLimit;
            if (cut) { var end = CharacterLimit; if (char.IsHighSurrogate(value[end - 1]) || value[end - 1] == '\r' && value[end] == '\n') end--; value = value[..end]; truncated = true; }
            var lines = new List<SourceDiffLine>(); var start = 0;
            for (var index = 0; index < value.Length; index++)
            {
                if (value[index] is not ('\r' or '\n')) continue;
                var end = index + (value[index] == '\r' && index + 1 < value.Length && value[index + 1] == '\n' ? 2 : 1);
                lines.Add(new(' ', value[start..index], value[index..end])); start = end; index = end - 1;
                if (lines.Count == LineLimit) { if (start < value.Length) truncated = true; return lines.ToArray(); }
            }
            if (start < value.Length || lines.Count == 0) lines.Add(new(' ', value[start..], "", cut));
            return lines.ToArray();
        }
        var a = Split(before); if (before == after) return new(a, truncated, false); var b = Split(after);
        // Independently clipped prefixes are reading observations, never edits.
        if (truncated) return new([], true, true);
        var result = new List<SourceDiffLine>();
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
    internal static string DocumentQueryMode(int from, int to, bool net) => net && to > from + 1 ? "range_net" : "history";
}
