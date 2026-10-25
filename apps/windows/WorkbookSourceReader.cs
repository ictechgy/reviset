using System.Text.Json;

namespace Reviset.Windows;

// A raw source reader owns physical observations, independently of the query
// mode, event membership and edit eligibility that first led to those cells.
internal sealed record WorkbookCellSource(string Occurrence, string Sheet, string Address, int Row, int Column)
{
    internal bool HasCell => Row > 0 && Column > 0;
    internal bool Matches(string occurrence, string sheet, string address, int row, int column) => Occurrence == occurrence && Sheet == sheet && Address == address && Row == row && Column == column;
    internal bool CellMatches(JsonElement cell) => HasCell ? cell.ValueKind == JsonValueKind.Object && cell.Get("address").Text() == Address && cell.Get("row").Number() == Row && cell.Get("column").Number() == Column : cell.ValueKind == JsonValueKind.Null;
}
// A single reader also owns the pane that supplied its immutable physical
// request. Style and absent-cell envelopes do not echo coordinates: those stay
// bound to this owner, while all identity actually returned is checked below.
internal sealed record WorkbookSingleSource(string Project, string Report, string Side, WorkbookCellSource Cell)
{
    internal bool Matches(string project, string report, string occurrence, string sheet, string address, int row, int column) => Project == project && Report == report && Cell.Matches(occurrence, sheet, address, row, column);
    internal bool ReadResponse(WorkbookCellRead read, JsonElement response, out JsonElement cell)
    {
        cell = default;
        if (!ReferenceEquals(read.Source, this) || !Cell.HasCell || read.Component is not ("cell" or "style") || response.Get("schema_version").Text() != "workbook.1" || response.Get("project_id").Text() != Project || response.Get("report_id").Text() != Report || response.Get("revision_occurrence_id").Text() != Cell.Occurrence || response.Get("sheet_id").Text() != Cell.Sheet || response.Get("items").ValueKind != JsonValueKind.Array || response.Get("total").ValueKind != JsonValueKind.Number || !response.Get("total").TryGetInt32(out var total) || total < 0 || response.Get("next_cursor").ValueKind is not (JsonValueKind.Null or JsonValueKind.String)) return false;
        var component = response.Get("component"); var style = read.Component == "style";
        if (style ? component.ValueKind != JsonValueKind.String || component.Text() != "style" : !WorkbookCellRead.IsCellComponent(component)) return false;
        var items = response.Get("items").Items(); var availability = response.Get("availability").Text();
        if (availability == "not_materialized") return total == 0 && items.Count == 0 && response.Get("next_cursor").ValueKind == JsonValueKind.Null;
        if (availability != "available" || items.Count > read.Limit || total < items.Count) return false;
        if (!style)
        {
            if (read.Cursor.Length != 0 || !WorkbookCellRead.IsOneCellEnvelope(response) || !Cell.CellMatches(items[0])) return false;
            cell = items[0]; return true;
        }
        // An available cell may have no style observations. A terminal style
        // cursor may also return no items; item cursors and text offsets differ.
        if (items.Count == 0 && (read.Cursor.Length == 0 && total > 0 || response.Get("next_cursor").ValueKind != JsonValueKind.Null) || read.Cursor.Length == 0 && total > items.Count && response.Get("next_cursor").Text().Length == 0 || total == 0 && response.Get("next_cursor").ValueKind != JsonValueKind.Null) return false;
        return items.All(item => item.ValueKind == JsonValueKind.Object && item.Get("key").ValueKind == JsonValueKind.String && item.Get("value").ValueKind == JsonValueKind.String && item.Get("text_continuations").Get("value").ValueKind == JsonValueKind.Object);
    }
}
internal sealed record WorkbookCellRead(WorkbookSingleSource Source, string Component, int Offset, string Cursor, int Limit = 1)
{
    internal static bool IsCellComponent(JsonElement component) => component.ValueKind == JsonValueKind.Undefined || component.ValueKind == JsonValueKind.String && component.Text() == "cell";
    internal static bool IsOneCellEnvelope(JsonElement response) => response.Get("schema_version").Text() == "workbook.1" && response.Get("items").ValueKind == JsonValueKind.Array && response.Get("items").GetArrayLength() == 1 && response.Get("total").ValueKind == JsonValueKind.Number && response.Get("total").TryGetInt32(out var total) && total == 1 && response.Get("next_cursor").ValueKind == JsonValueKind.Null;
    internal Dictionary<string, object?> Arguments()
    {
        var cell = Source.Cell;
        var args = new Dictionary<string, object?> { ["revision_occurrence_id"] = cell.Occurrence, ["sheet_id"] = cell.Sheet, ["row"] = cell.Row, ["column"] = cell.Column, ["text_offset"] = Offset, ["text_length"] = 4096, ["component"] = Component, ["limit"] = Limit };
        if (Component == "style" && Cursor.Length > 0) args["cursor"] = Cursor;
        return args;
    }
}
internal sealed record WorkbookPairSource(string Project, string Report, WorkbookCellSource Before, WorkbookCellSource After)
{
    internal WorkbookCellSource Side(string side) => side == "before" ? Before : After;
    internal bool Matches(string project, string report, WorkbookSourceScope scope, int beforeRow, int beforeColumn, int afterRow, int afterColumn) => Project == project && Report == report && Before.Matches(scope.BeforeOccurrence, scope.BeforeSheet, scope.BeforeAddress, beforeRow, beforeColumn) && After.Matches(scope.AfterOccurrence, scope.AfterSheet, scope.AfterAddress, afterRow, afterColumn);
    internal static bool TryCreate(string project, string report, JsonElement change, JsonElement before, JsonElement after, out WorkbookPairSource? owner)
    {
        owner = null;
        if (SourceDiffPolicy.SheetScoped(change.Get("kind").Text()) || !SourceDiffPolicy.WorkbookComponent(before, change, "before", project, report, out var a) || !SourceDiffPolicy.WorkbookComponent(after, change, "after", project, report, out var b)) return false;
        WorkbookCellSource Cell(string side, JsonElement cell) => new(change.Get(side == "before" ? "from_revision_occurrence_id" : "to_revision_occurrence_id").Text(), change.Get(side == "before" ? "from_sheet_id" : "to_sheet_id").Text(), change.Get(side + "_address").Text(), cell.Get("row").Number(), cell.Get("column").Number());
        var left = Cell("before", a); var right = Cell("after", b);
        if (project.Length == 0 || report.Length == 0 || left.Occurrence.Length == 0 || right.Occurrence.Length == 0 || !left.HasCell && !right.HasCell || left.HasCell && left.Sheet.Length == 0 || right.HasCell && right.Sheet.Length == 0) return false;
        owner = new(project, report, left, right); return true;
    }
    internal bool ReadCellResponse(string side, JsonElement response, out JsonElement cell)
    {
        cell = default; var source = Side(side); var items = response.Get("items").Items();
        if (!source.HasCell || !WorkbookCellRead.IsOneCellEnvelope(response) || response.Get("project_id").Text() != Project || response.Get("report_id").Text() != Report || response.Get("revision_occurrence_id").Text() != source.Occurrence || response.Get("sheet_id").Text() != source.Sheet || response.Get("availability").Text() != "available" || !WorkbookCellRead.IsCellComponent(response.Get("component")) || !source.CellMatches(items[0])) return false;
        cell = items[0]; return true;
    }
    internal int? NextOffset(JsonElement payload, int current)
    {
        int? next = null;
        foreach (var side in new[] { "before", "after" })
        {
            if (!ReadPayload(side, payload.Get(side), out var cell)) return null;
            var offset = RawSourcePaging.Next(cell.Get("text_continuations"), current);
            if (offset is { } value) next = next is null ? value : Math.Min(next.Value, value);
        }
        return next;
    }
    internal bool ReadPayload(string side, JsonElement response, out JsonElement cell)
    {
        // Initial event responses are retained exactly. Later segments are real
        // fixed-cell responses and carry no retired mode/event query closure.
        if (response.Get("revision_occurrence_id").ValueKind == JsonValueKind.String) return ReadCellResponse(side, response, out cell);
        cell = default; var source = Side(side); var items = response.Get("items").Items();
        if (response.Get("project_id").Text() != Project || response.Get("report_id").Text() != Report || items.Count != 1) return false;
        var item = items[0]; var prefix = side == "before" ? "from" : "to";
        if (item.Get("component").Text() != side || item.Get(prefix + "_revision_occurrence_id").Text() != source.Occurrence || item.Get(prefix + "_sheet_id").Text() != source.Sheet || item.Get(side + "_address").Text() != source.Address || !source.CellMatches(item.Get(side))) return false;
        cell = item.Get(side); return true;
    }
}
