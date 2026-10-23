using System.IO;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Automation;
using System.Windows.Controls.Primitives;
using System.Windows.Data;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Reviset.Windows;

internal sealed record GridRow(int Row, string[] Values)
{
    public string Number => Row.ToString(System.Globalization.CultureInfo.InvariantCulture);
}
internal sealed record PaneSelection(string Revision, string Sheet, string Page, int Row, int Column, double Zoom, string Absence);

internal sealed class ComparePane
{
    private readonly MainWindow owner;
    private readonly bool after;
    private readonly ComboBox revision = new() { Margin = new Thickness(5), MinWidth = 100, HorizontalAlignment = HorizontalAlignment.Stretch };
    private readonly ComboBox page = new() { Margin = new Thickness(5), MinWidth = 100 };
    private readonly ComboBox sheet = new() { Margin = new Thickness(5), MinWidth = 100 };
    private readonly TextBlock heading = new() { FontWeight = FontWeights.SemiBold, Margin = new Thickness(10, 8, 10, 2) };
    private readonly TextBlock source = new() { TextTrimming = TextTrimming.CharacterEllipsis, MaxHeight = 21, Margin = new Thickness(6, 2, 6, 2), Foreground = Brushes.DimGray };
    private readonly TextBlock sparse = new() { TextWrapping = TextWrapping.Wrap, MaxHeight = 32, FontSize = 11, Margin = new Thickness(6, 1, 6, 3), Foreground = Brushes.DimGray };
    private readonly TextBlock pageCaption = new() { Margin = new Thickness(7, 2, 4, 0) };
    private readonly TextBlock sheetCaption = new() { Margin = new Thickness(7, 2, 4, 0) };
    private readonly TextBox fallback = MainWindow.SourceText();
    internal readonly DataGrid Cells = new() { AutoGenerateColumns = false, IsReadOnly = true, CanUserAddRows = false, CanUserDeleteRows = false, CanUserReorderColumns = false, HeadersVisibility = DataGridHeadersVisibility.Column, EnableRowVirtualization = true, EnableColumnVirtualization = true, SelectionMode = DataGridSelectionMode.Single, SelectionUnit = DataGridSelectionUnit.Cell, GridLinesVisibility = DataGridGridLinesVisibility.All, RowHeight = 26, FontFamily = new FontFamily("Consolas, Segoe UI"), BorderThickness = new Thickness(0) };
    internal readonly Image PageImage = new() { Stretch = Stretch.Uniform, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Top };
    internal readonly ScrollViewer PageScroll = new() { HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    private readonly Slider zoom = new() { Minimum = .5, Maximum = 2, Value = 1, Width = 95, Margin = new Thickness(5), ToolTip = "50–200%" };
    private readonly TextBox address = new() { Text = "A1", Width = 80, Margin = new Thickness(4), MaxLength = 12 };
    private readonly TextBox rowStart = new() { Text = "1", Width = 65, Margin = new Thickness(4), MaxLength = 7 };
    private readonly TextBox colStart = new() { Text = "1", Width = 55, Margin = new Thickness(4), MaxLength = 5 };
    private readonly CheckBox showFormula = new() { Margin = new Thickness(8, 4, 8, 4) };
    private readonly StackPanel docControls = new();
    private readonly StackPanel workbookControls = new();
    private readonly Grid visual = new();
    private readonly Button retry;
    private readonly List<FrameworkElement> navigation = [];
    private readonly List<(Button Button, string Key)> arrows = [];
    private List<JsonElement> pageValues = [];
    private List<JsonElement> revisions = [];
    private JsonElement gridValue;
    private (string Project, string Report, string Revision, string Sheet, int Row, int Column)? loadedGridScope;
    internal string ReadState { get; private set; } = "empty";
    private string evidenceAbsence = "";
    private bool binding;
    private int row = 1;
    private int column = 1;
    private long pageGeneration;
    private long gridGeneration;
    private CancellationTokenSource pageRead = new();
    internal readonly Border Host = new() { BorderBrush = new SolidColorBrush(Color.FromRgb(225, 229, 235)), BorderThickness = new Thickness(1), Background = Brushes.White, ClipToBounds = true };
    internal string RevisionId => (revision.SelectedItem as Choice)?.Id ?? "";
    internal string SheetId => (sheet.SelectedItem as Choice)?.Id ?? "";
    internal string PageId => (page.SelectedItem as Choice)?.Id ?? "";
    internal int SelectedRow => row;
    internal int SelectedColumn => column;
    internal double Zoom { get => zoom.Value; set => zoom.Value = value; }

    public ComparePane(MainWindow owner, bool after)
    {
        this.owner = owner; this.after = after;
        retry = Button("retry", owner.RetryComparison); retry.Visibility = Visibility.Collapsed;
        var dock = new DockPanel(); Host.Child = dock;
        var top = new StackPanel(); DockPanel.SetDock(top, Dock.Top); dock.Children.Add(top);
        var versionRow = new DockPanel(); DockPanel.SetDock(heading, Dock.Left); versionRow.Children.Add(heading); versionRow.Children.Add(revision); top.Children.Add(versionRow);
        docControls.Children.Add(page);
        var zoomRow = new StackPanel { Orientation = Orientation.Horizontal }; var zoomLabel = new TextBlock { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(8, 0, 2, 0) }; owner.BindText(zoomLabel, "zoom"); zoomRow.Children.Add(zoomLabel); zoomRow.Children.Add(zoom); docControls.Children.Add(zoomRow); top.Children.Add(docControls);
        workbookControls.Children.Add(sheet);
        var coordinates = new WrapPanel(); var rowLabel = new TextBlock { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(8, 0, 0, 0) }; owner.BindText(rowLabel, "row"); coordinates.Children.Add(rowLabel); coordinates.Children.Add(rowStart); var columnLabel = new TextBlock { VerticalAlignment = VerticalAlignment.Center }; owner.BindText(columnLabel, "column"); coordinates.Children.Add(columnLabel); coordinates.Children.Add(colStart); coordinates.Children.Add(Button("go", LoadCoordinates));
        var navigationRow = new StackPanel { Orientation = Orientation.Horizontal }; var previous = Arrow("previous", "◀", async () => { row = Math.Max(1, row - 50); await ReloadGrid(); }); var next = Arrow("next", "▶", async () => { row = Math.Min(1_048_527, row + 50); await ReloadGrid(); }); navigationRow.Children.Add(previous); navigationRow.Children.Add(next); address.Width = 65; navigationRow.Children.Add(address); navigationRow.Children.Add(Button("go", GoAddress)); workbookControls.Children.Add(navigationRow); workbookControls.Children.Add(showFormula);
        var advanced = new Expander { Header = "…", ToolTip = "Row / column · 행 / 열", Content = coordinates, IsExpanded = false, Margin = new Thickness(6, 0, 6, 0) }; workbookControls.Children.Add(advanced); top.Children.Add(workbookControls);
        var bottom = new StackPanel(); bottom.Children.Add(source); bottom.Children.Add(sparse); bottom.Children.Add(retry); DockPanel.SetDock(bottom, Dock.Bottom); dock.Children.Add(bottom);
        PageScroll.Content = PageImage; visual.Children.Add(PageScroll); visual.Children.Add(fallback); visual.Children.Add(Cells); dock.Children.Add(visual);
        VirtualizingPanel.SetVirtualizationMode(Cells, VirtualizationMode.Recycling); ScrollViewer.SetCanContentScroll(Cells, true);
        revision.SelectionChanged += async (_, _) => { if (binding) return; SetRevisionContents(); await owner.Guard(owner.ReloadComparison); };
        page.SelectionChanged += async (_, _) => { if (!binding && !owner.IsWorkbook) await owner.Guard(() => Load(owner.Generation, owner.ReadToken)); };
        sheet.SelectionChanged += async (_, _) => { if (!binding && owner.IsWorkbook) { evidenceAbsence = ""; Invalidate(); row = 1; column = 1; await owner.Guard(owner.ReloadComparison); } };
        zoom.ValueChanged += (_, _) => { PageImage.LayoutTransform = new ScaleTransform(zoom.Value, zoom.Value); };
        Host.SizeChanged += (_, _) => ResizePreview();
        showFormula.Checked += (_, _) => RenderGrid(); showFormula.Unchecked += (_, _) => RenderGrid();
        Cells.SelectedCellsChanged += async (_, _) =>
        {
            if (binding || ReadState != "ready" || Cells.SelectedCells.Count == 0 || Cells.SelectedCells[0].Item is not GridRow selected) return;
            var displayColumn = Cells.SelectedCells[0].Column.DisplayIndex - 1; if (displayColumn < 0) return;
            await owner.Guard(() => owner.SelectCell(this, selected.Row, column + displayColumn));
        };
        navigation.AddRange([revision, page, sheet, rowStart, colStart, address]); Localize(); Clear();
    }
    private Button Button(string key, Func<Task> action) { var button = new Button { Margin = new Thickness(3), Padding = new Thickness(8, 3, 8, 3) }; owner.BindText(button, key); button.Click += async (_, _) => await owner.Guard(action); navigation.Add(button); return button; }
    private Button Arrow(string key, string glyph, Func<Task> action) { var button = new Button { Content = glyph, Margin = new Thickness(3), Padding = new Thickness(7, 3, 7, 3) }; button.Click += async (_, _) => await owner.Guard(action); arrows.Add((button, key)); navigation.Add(button); return button; }
    internal void Localize()
    {
        heading.Text = owner.Copy[after ? "after" : "before"]; pageCaption.Text = owner.Copy["pages"]; sheetCaption.Text = owner.Copy["sheet"]; showFormula.Content = owner.Copy["showFormula"]; sparse.Text = owner.Copy["sparseShort"]; sparse.ToolTip = owner.Copy["sparse"]; address.ToolTip = owner.Copy["address"];
        AutomationProperties.SetName(Cells, owner.Copy[after ? "after" : "before"] + " · " + owner.Copy["sheet"]); AutomationProperties.SetName(revision, heading.Text + " · " + owner.Copy["label"]); AutomationProperties.SetName(sheet, heading.Text + " · " + owner.Copy["sheet"]); AutomationProperties.SetName(address, heading.Text + " · " + owner.Copy["address"]);
        foreach (var arrow in arrows) { arrow.Button.ToolTip = owner.Copy[arrow.Key]; AutomationProperties.SetName(arrow.Button, heading.Text + " · " + owner.Copy[arrow.Key]); }
        docControls.Visibility = owner.IsWorkbook ? Visibility.Collapsed : Visibility.Visible; workbookControls.Visibility = owner.IsWorkbook ? Visibility.Visible : Visibility.Collapsed; sparse.Visibility = owner.IsWorkbook ? Visibility.Visible : Visibility.Collapsed;
    }
    internal void NavigationEnabled(bool enabled) { foreach (var control in navigation) control.IsEnabled = enabled; showFormula.IsEnabled = enabled && ReadState == "ready" && loadedGridScope is not null; }
    internal PaneSelection CaptureSelection() => new(RevisionId, SheetId, PageId, row, column, Zoom, evidenceAbsence);
    internal void RestoreSelection(PaneSelection saved)
    {
        if (saved.Revision.Length == 0) { Clear(); return; } SetEvidenceRevision(saved.Revision); binding = true;
        if (sheet.ItemsSource is List<Choice> sheets) sheet.SelectedItem = sheets.Find(value => value.Id == saved.Sheet);
        if (page.ItemsSource is List<Choice> pages) page.SelectedItem = pages.Find(value => value.Id == saved.Page);
        row = saved.Row; column = saved.Column; Zoom = saved.Zoom; evidenceAbsence = saved.Absence; binding = false;
    }
    internal void Clear()
    {
        pageRead.Cancel(); ++pageGeneration; ++gridGeneration;
        Invalidate("empty"); binding = true; revision.ItemsSource = null; page.ItemsSource = null; sheet.ItemsSource = null; fallback.Text = owner.Copy["selectPage"]; evidenceAbsence = ""; binding = false;
    }
    internal void Invalidate(string state = "loading")
    {
        ++gridGeneration; ++pageGeneration; pageRead.Cancel(); ReadState = state; loadedGridScope = null; gridValue = default;
        var previous = binding; binding = true; Cells.SelectedCells.Clear(); Cells.ItemsSource = null; binding = previous; Cells.IsEnabled = false; showFormula.IsEnabled = false;
        PageImage.Source = null; PageScroll.Visibility = Visibility.Collapsed; Cells.Visibility = Visibility.Collapsed; fallback.Visibility = Visibility.Visible; fallback.Text = owner.Copy[state == "failed" ? "failed" : "loading"]; source.Text = ""; retry.Visibility = state == "failed" ? Visibility.Visible : Visibility.Collapsed;
    }
    internal bool AuthorizesCell(int requestedRow, int requestedColumn) => ReadState == "ready" && loadedGridScope is { } scope && scope.Project == owner.ProjectId && scope.Report == owner.ReportId && scope.Revision == RevisionId && scope.Sheet == SheetId && scope.Row == row && scope.Column == column && requestedRow >= row && requestedRow < row + 50 && requestedColumn >= column && requestedColumn < Math.Min(16385, column + 8);
    internal void SetRevisions(List<JsonElement> items, int index)
    {
        revisions = items; binding = true; revision.ItemsSource = items.Select(v => Choice.From(v, "revision_occurrence_id", "label")).ToList(); revision.SelectedIndex = items.Count > 0 ? Math.Clamp(index, 0, items.Count - 1) : -1; binding = false; SetRevisionContents(); Localize();
    }
    private void SetRevisionContents()
    {
        Invalidate(); evidenceAbsence = "";
        var selected = revisions.Find(v => v.Get("revision_occurrence_id").Text() == RevisionId); var oldPage = PageId; var oldSheet = (sheet.SelectedItem as Choice)?.Label;
        binding = true;
        if (owner.IsWorkbook)
        {
            var sheets = selected.Get("sheets").Items().Select(v => Choice.From(v, "sheet_id", "name")).ToList(); sheet.ItemsSource = sheets; sheet.SelectedItem = sheets.Find(v => v.Label == oldSheet) ?? sheets.FirstOrDefault(); row = 1; column = 1;
        }
        else
        {
            pageValues = selected.Get("pages").Items(); var pages = pageValues.Select(v => new Choice(v.Get("page_id").Text(), v.Get("page").Number().ToString(System.Globalization.CultureInfo.InvariantCulture) + " · " + v.Get("text").Text(), v)).ToList(); page.ItemsSource = pages; page.SelectedItem = pages.Find(v => v.Id == oldPage) ?? pages.FirstOrDefault();
        }
        binding = false;
    }
    internal bool HasPage(string id) => pageValues.Any(v => v.Get("page_id").Text() == id);
    internal void RestoreDefaultSelection() => SetRevisionContents();
    internal async Task SelectPage(string id, long ticket, CancellationToken token)
    {
        if (page.ItemsSource is not List<Choice> choices || !choices.Any(v => v.Id == id)) return; binding = true; page.SelectedItem = choices.Find(v => v.Id == id); binding = false; await LoadPage(ticket, token);
    }
    internal void SetEventPage(string? id)
    {
        binding = true; page.SelectedItem = page.ItemsSource is List<Choice> choices ? choices.Find(v => v.Id == id) : null; binding = false;
        evidenceAbsence = PageId.Length == 0 ? "absentPage" : "";
    }
    internal void SetEvidenceRevision(string id, string sheetId = "", JsonElement observation = default)
    {
        if (revision.ItemsSource is not List<Choice> choices || !choices.Any(v => v.Id == id)) throw new BridgeException("EVIDENCE_SCOPE", "Change occurrence is outside the fixed report.");
        binding = true; revision.SelectedItem = choices.Find(v => v.Id == id); binding = false; SetRevisionContents();
        if (owner.IsWorkbook)
        {
            binding = true;
            if (sheetId.Length == 0) { sheet.SelectedItem = null; evidenceAbsence = "absentSheet"; }
            else if (sheet.ItemsSource is List<Choice> sheets && sheets.Any(v => v.Id == sheetId)) sheet.SelectedItem = sheets.Find(v => v.Id == sheetId);
            else { sheet.SelectedItem = null; evidenceAbsence = "unsupportedSheet"; }
            // Sheet events need not identify a physical cell. Preserve absence.
            row = observation.Get("row").Number(0); column = observation.Get("column").Number(0); if (row < 1 || column < 1) { row = 0; column = 0; if (evidenceAbsence.Length == 0) evidenceAbsence = "sheetMetadata"; }
            binding = false;
        }
    }
    internal async Task Load(long ticket, CancellationToken token)
    {
        Localize(); try { if (owner.IsWorkbook) await LoadGrid(ticket, token); else await LoadPage(ticket, token); }
        catch { if (owner.IsCurrent(ticket) && !token.IsCancellationRequested) Invalidate("failed"); throw; }
    }
    private async Task LoadPage(long ticket, CancellationToken token)
    {
        pageRead.Cancel(); pageRead.Dispose(); pageRead = CancellationTokenSource.CreateLinkedTokenSource(token); token = pageRead.Token;
        var sequence = ++pageGeneration; var selected = PageId; if (selected.Length == 0) { Invalidate("absent"); ReadState = "absent"; fallback.Text = owner.Copy["absentPage"]; return; }
        PageImage.Source = null; fallback.Text = owner.Copy["analyzing"]; source.Text = ""; fallback.Visibility = Visibility.Visible; PageScroll.Visibility = Visibility.Collapsed; Cells.Visibility = Visibility.Collapsed;
        var value = await owner.Bridge.Call("pagePreview", new { project_id = owner.ProjectId, report_id = owner.ReportId, page_id = selected, max_width = 1600 }, token);
        if (!owner.IsCurrent(ticket) || sequence != pageGeneration || selected != PageId) return;
        if (value.Get("page_id").Text() != selected || value.Get("report_id").Text() != owner.ReportId) throw new BridgeException("PAGE_SCOPE", "The preview belongs to a different page or report.");
        var encoded = value.Get("png_base64").Text(); var origin = value.Get("source").Text(); source.Text = owner.Copy["source"] + ": " + origin;
        if (encoded.Length > 0)
        {
            if (encoded.Length > 24 * 1024 * 1024) throw new BridgeException("PREVIEW_LIMIT", "The page image exceeds the desktop preview limit.");
            var bitmap = new BitmapImage(); using var bytes = new MemoryStream(Convert.FromBase64String(encoded)); bitmap.BeginInit(); bitmap.CacheOption = BitmapCacheOption.OnLoad; bitmap.DecodePixelWidth = 1600; bitmap.StreamSource = bytes; bitmap.EndInit(); bitmap.Freeze();
            PageImage.Source = bitmap; ResizePreview(); fallback.Visibility = Visibility.Collapsed; PageScroll.Visibility = Visibility.Visible;
        }
        else
        {
            source.Text = owner.Copy["structural"] + " · " + origin + "\n" + value.Get("unavailable_reason").Text(); fallback.Text = value.Get("text").Text();
            if (value.Get("text_truncated").Flag()) fallback.Text += "\n… [" + value.Get("text_total_length").Text() + "]";
        }
        ReadState = "ready"; retry.Visibility = Visibility.Collapsed;
    }
    private async Task LoadGrid(long ticket, CancellationToken token)
    {
        Invalidate(); var sequence = gridGeneration;
        if (evidenceAbsence.Length > 0)
        {
            ReadState = "absent"; fallback.Text = owner.Copy[evidenceAbsence];
            if (evidenceAbsence == "sheetMetadata" && sheet.SelectedItem is Choice observedSheet) fallback.Text += "\n\n" + observedSheet.Label + "\n" + owner.Copy["row"] + ": " + observedSheet.Value.Get("row_count").Text() + "\n" + owner.Copy["column"] + ": " + observedSheet.Value.Get("column_count").Text();
            return;
        }
        if (RevisionId.Length == 0 || SheetId.Length == 0) { ReadState = "absent"; fallback.Text = owner.Copy[evidenceAbsence.Length > 0 ? evidenceAbsence : "absentSheet"]; return; }
        var revisionId = RevisionId; var sheetId = SheetId; var rowAt = row; var columnAt = column;
        var value = await owner.Bridge.Call("workbookGrid", new { project_id = owner.ProjectId, report_id = owner.ReportId, revision_occurrence_id = revisionId, sheet_id = sheetId, row_start = rowAt, row_limit = 50, column_start = columnAt, column_limit = 8 }, token);
        if (!owner.IsCurrent(ticket) || sequence != gridGeneration || RevisionId != revisionId || SheetId != sheetId || row != rowAt || column != columnAt) return;
        if (value.Get("revision_occurrence_id").Text() != revisionId || value.Get("sheet_id").Text() != sheetId || value.Get("report_id").Text() != owner.ReportId) throw new BridgeException("GRID_SCOPE", "Grid response is outside the selected source scope.");
        loadedGridScope = (owner.ProjectId, owner.ReportId, revisionId, sheetId, rowAt, columnAt); ReadState = "ready"; Cells.IsEnabled = owner.AllowsEvidence; showFormula.IsEnabled = owner.AllowsEvidence;
        gridValue = value; rowStart.Text = row.ToString(System.Globalization.CultureInfo.InvariantCulture); colStart.Text = column.ToString(System.Globalization.CultureInfo.InvariantCulture); RenderGrid();
        source.Text = (revision.SelectedItem as Choice)?.Label + " · " + (sheet.SelectedItem as Choice)?.Label + " · " + row + "–" + Math.Min(1048576, row + 49); source.ToolTip = revisionId + "\n" + sheetId; fallback.Visibility = Visibility.Collapsed; PageScroll.Visibility = Visibility.Collapsed; Cells.Visibility = Visibility.Visible;
    }
    private void RenderGrid()
    {
        if (ReadState != "ready" || loadedGridScope is null || gridValue.ValueKind == JsonValueKind.Undefined) return; binding = true; Cells.Columns.Clear();
        Cells.Columns.Add(new DataGridTextColumn { Header = "#", Binding = new Binding(nameof(GridRow.Number)), Width = 65, IsReadOnly = true });
        var columnCount = Math.Min(8, 16385 - column);
        for (var index = 0; index < columnCount; index++) Cells.Columns.Add(new DataGridTextColumn { Header = ColumnName(column + index), Binding = new Binding("Values[" + index + "]"), Width = 115, IsReadOnly = true });
        var observed = gridValue.Get("items").Items().ToDictionary(v => (v.Get("row").Number(), v.Get("column").Number()), v => v);
        var values = new List<GridRow>();
        for (var r = row; r < Math.Min(1_048_577, row + 50); r++)
        {
            var cells = new string[columnCount]; for (var index = 0; index < columnCount; index++)
            {
                if (!observed.TryGetValue((r, column + index), out var cell)) { cells[index] = "—"; continue; }
                var formula = cell.Get("formula").Text(); var value = showFormula.IsChecked == true && formula.Length > 0 ? formula : cell.Get("value").Text(); cells[index] = value + (cell.Get("text_truncated").Flag() ? "…" : "");
            }
            values.Add(new(r, cells));
        }
        Cells.ItemsSource = values; binding = false;
    }
    private async Task LoadCoordinates()
    {
        if (!int.TryParse(rowStart.Text, out var r) || !int.TryParse(colStart.Text, out var c) || r is < 1 or > 1_048_576 || c is < 1 or > 16_384) throw new BridgeException("ADDRESS", "Row 1–1048576; column 1–16384."); evidenceAbsence = ""; row = r; column = c; await ReloadGrid();
    }
    private async Task GoAddress()
    {
        var found = Regex.Match(address.Text.Trim(), "^([A-Za-z]{1,3})([1-9][0-9]{0,6})$", RegexOptions.CultureInvariant); if (!found.Success) throw new BridgeException("ADDRESS", "A1–XFD1048576");
        var c = 0; foreach (var letter in found.Groups[1].Value.ToUpperInvariant()) c = c * 26 + letter - 'A' + 1;
        var r = int.Parse(found.Groups[2].Value, System.Globalization.CultureInfo.InvariantCulture); if (c > 16384 || r > 1048576) throw new BridgeException("ADDRESS", "A1–XFD1048576");
        evidenceAbsence = ""; row = r; column = c; await ReloadGrid(); await owner.SelectCell(this, r, c);
    }
    private Task ReloadGrid() => owner.ReloadComparison();
    internal (double X, double Y, string Page, ImageSource? Image) CaptureViewport() => (PageScroll.HorizontalOffset, PageScroll.VerticalOffset, PageId, PageImage.Source);
    internal void RestoreViewport((double X, double Y, string Page, ImageSource? Image) saved)
    {
        if (PageId != saved.Page || !ReferenceEquals(PageImage.Source, saved.Image)) return;
        PageScroll.ScrollToHorizontalOffset(saved.X); PageScroll.ScrollToVerticalOffset(saved.Y);
    }
    internal ScrollViewer? GridScroll => Descendants(Cells).OfType<ScrollViewer>().FirstOrDefault();
    internal (double X, double Y, object? Rows) CaptureGridViewport() => (GridScroll?.HorizontalOffset ?? 0, GridScroll?.VerticalOffset ?? 0, Cells.ItemsSource);
    internal void RestoreGridViewport((double X, double Y, object? Rows) saved)
    {
        if (!ReferenceEquals(saved.Rows, Cells.ItemsSource) || GridScroll is not { } scroll) return; scroll.ScrollToHorizontalOffset(saved.X); scroll.ScrollToVerticalOffset(saved.Y);
    }
    private static IEnumerable<DependencyObject> Descendants(DependencyObject root)
    {
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(root); index++) { var child = VisualTreeHelper.GetChild(root, index); yield return child; foreach (var nested in Descendants(child)) yield return nested; }
    }
    private void ResizePreview()
    {
        if (PageImage.Source is BitmapSource bitmap) PageImage.Width = Math.Min(bitmap.PixelWidth, Math.Max(100, Host.ActualWidth - 35));
    }
    internal static string ColumnName(int column) { var name = ""; while (column > 0) { column--; name = (char)('A' + column % 26) + name; column /= 26; } return name; }
    internal async Task GoForSmoke(string cell) { address.Text = cell; await GoAddress(); }
}
