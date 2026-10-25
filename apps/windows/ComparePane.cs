using System.IO;
using System.ComponentModel;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Automation;
using System.Windows.Controls.Primitives;
using System.Windows.Data;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Input;

namespace Reviset.Windows;

internal sealed record GridCell(string Text, bool Annotation, string TooltipKey, Copy Copy) : INotifyPropertyChanged
{
    public string ToolTip => TooltipKey == "sparseCell" || Text.Length == 0 ? Copy[TooltipKey] : Text + "\n\n" + Copy[TooltipKey];
    public event PropertyChangedEventHandler? PropertyChanged;
    public void Localize() => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(ToolTip)));
    public Brush Foreground => Annotation ? Brushes.Gray : Brushes.Black;
    public FontStyle FontStyle => Annotation ? FontStyles.Italic : FontStyles.Normal;
}
internal sealed record GridRow(int Row, GridCell[] Values)
{
    public string Number => Row.ToString(System.Globalization.CultureInfo.InvariantCulture);
}
internal sealed record PaneSelection(string Revision, string Sheet, string Page, int Row, int Column, double Zoom, string Absence, string RequestedSheet = "", int? FocusedRow = null, int? FocusedColumn = null, string MetadataKind = "");

internal sealed class ComparePane
{
    private readonly MainWindow owner;
    private readonly bool after;
    private readonly ComboBox revision = new() { Margin = new Thickness(5), MinWidth = 100, HorizontalAlignment = HorizontalAlignment.Stretch };
    private readonly ComboBox page = new() { Margin = new Thickness(5, 3, 5, 1), MinWidth = 100, Height = 28, HorizontalContentAlignment = HorizontalAlignment.Stretch };
    private readonly ComboBox sheet = new() { Margin = new Thickness(5), MinWidth = 100 };
    private readonly TextBlock heading = new() { FontWeight = FontWeights.SemiBold, Margin = new Thickness(10, 8, 10, 2) };
    private readonly TextBlock versionCaption = new() { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(6, 3, 6, 3), TextTrimming = TextTrimming.CharacterEllipsis };
    private readonly TextBlock source = new() { TextTrimming = TextTrimming.CharacterEllipsis, MaxHeight = 21, Margin = new Thickness(6, 2, 6, 2), Foreground = Brushes.DimGray };
    private readonly TextBlock sparse = new() { TextWrapping = TextWrapping.Wrap, MaxHeight = 32, FontSize = 11, Margin = new Thickness(6, 1, 6, 3), Foreground = Brushes.DimGray };
    private readonly TextBlock pageCaption = new() { Margin = new Thickness(7, 2, 4, 0) };
    private readonly TextBlock sheetCaption = new() { Margin = new Thickness(7, 2, 4, 0) };
    private readonly TextBox fallback = MainWindow.SourceText();
    internal readonly DataGrid Cells = new() { AutoGenerateColumns = false, IsReadOnly = true, CanUserAddRows = false, CanUserDeleteRows = false, CanUserReorderColumns = false, HeadersVisibility = DataGridHeadersVisibility.Column, EnableRowVirtualization = true, EnableColumnVirtualization = true, SelectionMode = DataGridSelectionMode.Single, SelectionUnit = DataGridSelectionUnit.Cell, GridLinesVisibility = DataGridGridLinesVisibility.All, RowHeight = 26, FontFamily = new FontFamily("Consolas, Segoe UI"), BorderThickness = new Thickness(0) };
    internal readonly Image PageImage = new() { Stretch = Stretch.Uniform, HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Top };
    internal readonly ScrollViewer PageScroll = new() { HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    private readonly Slider zoom = new() { Minimum = .1, Maximum = 2, Value = 1, Width = 95, Margin = new Thickness(5), VerticalAlignment = VerticalAlignment.Center };
    private readonly TextBlock zoomCaption = new() { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(6, 0, 0, 0) };
    private readonly TextBlock zoomPercent = new() { VerticalAlignment = VerticalAlignment.Center, MinWidth = 37 };
    private readonly Button fitWidth;
    private bool fittingWidth;
    private bool applyingFit;
    private bool presentationChosen;
    private string presentationReport = "";
    private readonly Border pageFrame = new() { BorderBrush = new SolidColorBrush(Color.FromRgb(174, 184, 198)), BorderThickness = new Thickness(1), Background = Brushes.White, Margin = new Thickness(12), HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Top };
    private readonly TextBox address = new() { Text = "A1", Width = 80, Margin = new Thickness(4), MaxLength = 12 };
    private readonly TextBox rowStart = new() { Text = "1", Width = 65, Margin = new Thickness(4), MaxLength = 7 };
    private readonly TextBox colStart = new() { Text = "1", Width = 55, Margin = new Thickness(4), MaxLength = 5 };
    private readonly CheckBox showFormula = new() { Margin = new Thickness(8, 4, 8, 4) };
    private readonly StackPanel docControls = new();
    private readonly StackPanel workbookControls = new();
    private readonly Expander cellDetails = new() { IsExpanded = false, Margin = new Thickness(6, 0, 6, 0) };
    private readonly ScrollViewer cellDetailsScroll = new() { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled, CanContentScroll = false, MaxHeight = 160 };
    private readonly TextBlock cellDetailsCaption = new() { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(4), FontSize = 11 };
    private readonly TextBox cellValue = MainWindow.SourceText();
    private readonly TextBox cellFormula = MainWindow.SourceText();
    private readonly TextBlock cellValueLabel = new() { Margin = new Thickness(4, 2, 4, 0), TextWrapping = TextWrapping.Wrap };
    private readonly TextBlock cellFormulaLabel = new() { Margin = new Thickness(4, 2, 4, 0), TextWrapping = TextWrapping.Wrap };
    private readonly Button openCellSource;
    private Task cellDetailsRequest = Task.CompletedTask;
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
    private sealed record IntendedPageCaption(string Kind, string Project, string Report, string Revision, string Page, long Generation);
    private IntendedPageCaption? intendedPageCaption;
    internal string CurrentIntendedEventKind => intendedPageCaption is { } value && owner.IsCurrent(value.Generation) && !owner.ReadToken.IsCancellationRequested && value.Project == owner.ProjectId && value.Report == owner.ReportId && value.Revision == RevisionId && value.Page == PageId ? value.Kind : "";
    internal void ClearEventPageCaption() => intendedPageCaption = null;
    private string requestedSheetName = "";
    private Task selectionRequest = Task.CompletedTask;
    private string previewSource = "";
    private string previewReason = "";
    private string previewText = "";
    private SourceTextObservation previewObservation = new(SourceTextState.Missing, "");
    private (string Project, string Report, string Revision, string Page)? previewScope;
    private bool binding;
    private bool lastNavigationEnabled;
    private string metadataKind = "";
    private int row = 1;
    private int column = 1;
    private int focusedRow;
    private int focusedColumn;
    private long pageGeneration;
    private long gridGeneration;
    private CancellationTokenSource pageRead = new();
    private Task? activePageRequest;
    internal Func<CancellationToken, Task>? PageBeforeInstallForSmoke { get; set; }
    internal readonly Border Host = new() { BorderBrush = new SolidColorBrush(Color.FromRgb(225, 229, 235)), BorderThickness = new Thickness(1), Background = Brushes.White, ClipToBounds = true };
    internal string RevisionId => (revision.SelectedItem as Choice)?.Id ?? "";
    internal string SheetId => (sheet.SelectedItem as Choice)?.Id ?? "";
    internal string PageId => (page.SelectedItem as Choice)?.Id ?? "";
    internal int SelectedRow => row;
    internal int SelectedColumn => column;
    internal int FocusedRow => focusedRow;
    internal int FocusedColumn => focusedColumn;
    internal string PresentedSideName => owner.Copy[owner.SingleSourceReading && after ? "reading" : after ? "after" : "before"];
    internal string HeadingForSmoke => heading.Text;
    internal string SourceAutomationNameForSmoke => AutomationProperties.GetName(owner.IsWorkbook ? Cells : PageScroll);
    internal string FocusedAddress => focusedRow > 0 && focusedColumn > 0 ? ColumnName(focusedColumn) + focusedRow.ToString(System.Globalization.CultureInfo.InvariantCulture) : "";
    internal string LocationCaption => owner.IsWorkbook ? WorkbookLocationCaption : PageId.Length == 0 ? owner.Copy[owner.MissingDocumentPageCaptionKey(after)] : owner.Copy["pages"] + " " + ((page.SelectedItem as Choice)?.Value.Get("page").Number() ?? 0);
    private string WorkbookLocationCaption
    {
        get
        {
            var name = (sheet.SelectedItem as Choice)?.Label ?? requestedSheetName;
            if (evidenceAbsence.Length > 0) return (name.Length > 0 ? name + " · " : "") + owner.Copy[evidenceAbsence];
            if (SheetId.Length == 0) return owner.Copy["absentSheet"];
            return name + (FocusedAddress.Length > 0 ? "!" + FocusedAddress : "");
        }
    }
    internal double Zoom { get => zoom.Value; set { presentationChosen = true; fittingWidth = false; zoom.Value = value; } }

    public ComparePane(MainWindow owner, bool after)
    {
        this.owner = owner; this.after = after;
        retry = Button("retry", owner.RetryComparison); retry.Visibility = Visibility.Collapsed;
        var dock = new DockPanel(); Host.Child = dock;
        var top = new StackPanel(); DockPanel.SetDock(top, Dock.Top); dock.Children.Add(top);
        var versionRow = new DockPanel(); DockPanel.SetDock(heading, Dock.Left); versionRow.Children.Add(heading); versionRow.Children.Add(versionCaption); top.Children.Add(versionRow);
        var pageLabel = new FrameworkElementFactory(typeof(TextBlock)); pageLabel.SetBinding(TextBlock.TextProperty, new Binding(nameof(Choice.Label)) { Converter = new SingleLinePageLabel() }); pageLabel.SetBinding(FrameworkElement.ToolTipProperty, new Binding(nameof(Choice.Label))); pageLabel.SetValue(TextBlock.TextTrimmingProperty, TextTrimming.CharacterEllipsis); pageLabel.SetValue(TextBlock.TextWrappingProperty, TextWrapping.NoWrap); page.ItemTemplate = new DataTemplate { VisualTree = pageLabel }; page.SetBinding(FrameworkElement.ToolTipProperty, new Binding("SelectedItem.Label") { Source = page });
        docControls.Children.Add(page); var zoomRow = new StackPanel { Orientation = Orientation.Horizontal }; zoomRow.Children.Add(zoomCaption); zoomRow.Children.Add(zoom); zoomRow.Children.Add(zoomPercent); fitWidth = Button("fitWidth", () => { FitPreview(); return Task.CompletedTask; }); zoomRow.Children.Add(fitWidth); docControls.Children.Add(zoomRow); top.Children.Add(docControls);
        workbookControls.Children.Add(sheet);
        var coordinates = new WrapPanel(); var rowLabel = new TextBlock { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(8, 0, 0, 0) }; owner.BindText(rowLabel, "row"); coordinates.Children.Add(rowLabel); coordinates.Children.Add(rowStart); var columnLabel = new TextBlock { VerticalAlignment = VerticalAlignment.Center }; owner.BindText(columnLabel, "column"); coordinates.Children.Add(columnLabel); coordinates.Children.Add(colStart); coordinates.Children.Add(Button("go", LoadCoordinates));
        var navigationRow = new WrapPanel(); var previous = Arrow("previous", "◀", async () => { row = Math.Max(1, row - 50); SetFocusCoordinates(row, column); await ReloadGrid(); }); var next = Arrow("next", "▶", async () => { row = Math.Min(1_048_527, row + 50); SetFocusCoordinates(row, column); await ReloadGrid(); }); navigationRow.Children.Add(previous); navigationRow.Children.Add(next); address.Width = 65; navigationRow.Children.Add(address); navigationRow.Children.Add(Button("go", GoAddress)); workbookControls.Children.Add(navigationRow); workbookControls.Children.Add(showFormula);
        var details = new StackPanel(); details.Children.Add(cellDetailsCaption); details.Children.Add(cellValueLabel); cellValue.MaxHeight = 66; cellValue.MinHeight = 26; details.Children.Add(cellValue); details.Children.Add(cellFormulaLabel); cellFormula.MaxHeight = 66; cellFormula.MinHeight = 26; details.Children.Add(cellFormula);
        openCellSource = Button("cellSourceAction", () => cellDetailsRequest = owner.OpenCellSource(this)); navigationRow.Children.Add(openCellSource); details.Children.Add(coordinates); cellDetailsScroll.Content = details; cellDetails.Content = cellDetailsScroll; workbookControls.Children.Add(cellDetails); top.Children.Add(workbookControls);
        cellDetails.Expanded += (_, _) => UpdateCellDetailsHeight(); visual.SizeChanged += (_, _) => UpdateCellDetailsHeight();
        var bottom = new StackPanel(); bottom.Children.Add(source); bottom.Children.Add(sparse); bottom.Children.Add(retry); DockPanel.SetDock(bottom, Dock.Bottom); dock.Children.Add(bottom);
        pageFrame.Child = PageImage; PageScroll.Content = pageFrame; PageScroll.Background = new SolidColorBrush(Color.FromRgb(238, 241, 245)); visual.Children.Add(PageScroll); visual.Children.Add(fallback); visual.Children.Add(Cells); dock.Children.Add(visual);
        VirtualizingPanel.SetVirtualizationMode(Cells, VirtualizationMode.Recycling); ScrollViewer.SetCanContentScroll(Cells, true);
        revision.SelectionChanged += async (_, _) => { if (binding) return; SetRevisionContents(true); selectionRequest = owner.ReloadComparison(); await owner.Guard(() => selectionRequest); };
        page.SelectionChanged += async (_, _) => { if (!binding && !owner.IsWorkbook) { owner.ClearEventPageCaptions(); var request = Load(owner.Generation, owner.ReadToken); owner.SourcePresentationChanged(); await owner.Guard(() => request); owner.SourcePresentationChanged(); } };
        sheet.SelectionChanged += async (_, _) => { if (!binding && owner.IsWorkbook) { evidenceAbsence = ""; metadataKind = ""; requestedSheetName = (sheet.SelectedItem as Choice)?.Label ?? ""; Invalidate(); row = 1; column = 1; SetFocusCoordinates(row, column); selectionRequest = owner.ReloadSourceWindow(); await owner.Guard(() => selectionRequest); } };
        zoom.ValueChanged += (_, _) => { if (!applyingFit) { presentationChosen = true; fittingWidth = false; } PageImage.LayoutTransform = new ScaleTransform(zoom.Value, zoom.Value); UpdateZoomCaption(); };
        Host.SizeChanged += (_, _) => ResizePreview();
        PageScroll.SizeChanged += (_, _) => { if (fittingWidth) ResizePreview(); };
        showFormula.Checked += (_, _) => RenderGrid(); showFormula.Unchecked += (_, _) => RenderGrid();
        Cells.SelectedCellsChanged += async (_, _) =>
        {
            if (binding || ReadState != "ready" || Cells.SelectedCells.Count == 0 || Cells.SelectedCells[0].Item is not GridRow selected) return;
            var displayColumn = Cells.SelectedCells[0].Column.DisplayIndex - 1; if (displayColumn < 0) return;
            selectionRequest = owner.SelectCell(this, selected.Row, column + displayColumn);
            await owner.Guard(() => selectionRequest);
        };
        navigation.AddRange([revision, page, sheet, rowStart, colStart, address]); Localize(); Clear();
    }
    private Button Button(string key, Func<Task> action) { var button = new Button { Margin = new Thickness(3), Padding = new Thickness(8, 3, 8, 3) }; owner.BindText(button, key); button.Click += async (_, _) => await owner.Guard(action); navigation.Add(button); return button; }
    private Button Arrow(string key, string glyph, Func<Task> action) { var button = new Button { Content = glyph, Margin = new Thickness(3), Padding = new Thickness(7, 3, 7, 3) }; button.Click += async (_, _) => { selectionRequest = action(); await owner.Guard(() => selectionRequest); }; arrows.Add((button, key)); navigation.Add(button); return button; }
    internal void Localize()
    {
        pageCaption.Text = owner.Copy["pages"]; sheetCaption.Text = owner.Copy["sheet"]; showFormula.Content = owner.Copy["showFormula"]; sparse.Text = owner.Copy["sparseShort"]; sparse.ToolTip = owner.Copy["sparse"]; address.ToolTip = owner.Copy["address"];
        zoomCaption.Text = owner.Copy["zoom"]; zoom.ToolTip = owner.Copy["zoom"] + " · 10–200%"; UpdateZoomCaption();
        RefreshReadingChrome();
        foreach (var arrow in arrows) arrow.Button.ToolTip = owner.Copy[arrow.Key];
        docControls.Visibility = owner.IsWorkbook ? Visibility.Collapsed : Visibility.Visible; workbookControls.Visibility = owner.IsWorkbook ? Visibility.Visible : Visibility.Collapsed; sparse.Visibility = owner.IsWorkbook ? Visibility.Visible : Visibility.Collapsed;
        cellDetails.Header = owner.Copy["cellDetails"]; cellDetails.ToolTip = owner.Copy["cellPreviewNotice"]; RerenderPresentation(); foreach (var cells in Cells.Items.OfType<GridRow>()) foreach (var cell in cells.Values) cell.Localize(); RefreshCellDetails();
    }
    internal void RefreshReadingChrome()
    {
        heading.Text = PresentedSideName; versionCaption.Text = (revision.SelectedItem as Choice)?.Label ?? ""; versionCaption.ToolTip = RevisionId;
        AutomationProperties.SetName(zoom, heading.Text + " · " + owner.Copy["zoom"]); AutomationProperties.SetName(fitWidth, heading.Text + " · " + owner.Copy["fitWidth"]);
        AutomationProperties.SetName(Cells, heading.Text + " · " + owner.Copy["sheet"]); AutomationProperties.SetName(PageScroll, heading.Text + " · " + owner.Copy["pages"]); AutomationProperties.SetName(PageImage, heading.Text + " · " + owner.Copy["pages"]); AutomationProperties.SetName(revision, heading.Text + " · " + owner.Copy["label"]); AutomationProperties.SetName(sheet, heading.Text + " · " + owner.Copy["sheet"]); AutomationProperties.SetName(page, heading.Text + " · " + owner.Copy["pages"]); AutomationProperties.SetName(address, heading.Text + " · " + owner.Copy["address"]);
        foreach (var arrow in arrows) AutomationProperties.SetName(arrow.Button, heading.Text + " · " + owner.Copy[arrow.Key]); RefreshCellDetails();
        if (!owner.IsWorkbook && PageId.Length == 0 && ReadState == "absent") RerenderPresentation();
    }
    internal object CheckReadingChromeForSmoke()
    {
        var expected = PresentedSideName; var expectedSourceName = expected + " · " + owner.Copy[owner.IsWorkbook ? "sheet" : "pages"];
        if (versionCaption.Text != ((revision.SelectedItem as Choice)?.Label ?? "") || versionCaption.ToolTip as string != RevisionId || heading.Text != expected || SourceAutomationNameForSmoke != expectedSourceName || AutomationProperties.GetName(sheet) != expected + " · " + owner.Copy["sheet"] || AutomationProperties.GetName(page) != expected + " · " + owner.Copy["pages"]) throw new InvalidOperationException("The native source heading or automation names do not match the current paired/single-source reading state and locale.");
        return new { single_source_reading = owner.SingleSourceReading, mounted_after_side = after, heading = heading.Text, source_automation_name = SourceAutomationNameForSmoke, native_control = owner.IsWorkbook ? "DataGrid" : "ScrollViewer", observation_scope = "Production native control properties; not an OS screen-reader traversal" };
    }
    internal void NavigationEnabled(bool enabled) { lastNavigationEnabled = enabled; foreach (var control in navigation) control.IsEnabled = enabled; showFormula.IsEnabled = enabled && ReadState == "ready" && loadedGridScope is not null; RefreshCellDetails(); }
    internal PaneSelection CaptureSelection() => new(RevisionId, SheetId, PageId, row, column, Zoom, evidenceAbsence, requestedSheetName, focusedRow, focusedColumn, metadataKind);
    internal void RestoreSelection(PaneSelection saved)
    {
        if (saved.Revision.Length == 0) { Clear(); return; } SetEvidenceRevision(saved.Revision); binding = true;
        if (sheet.ItemsSource is List<Choice> sheets) sheet.SelectedItem = sheets.Find(value => value.Id == saved.Sheet);
        if (page.ItemsSource is List<Choice> pages) page.SelectedItem = pages.Find(value => value.Id == saved.Page);
        row = saved.Row; column = saved.Column; SetFocusCoordinates(saved.FocusedRow ?? saved.Row, saved.FocusedColumn ?? saved.Column); Zoom = saved.Zoom; evidenceAbsence = saved.Absence; requestedSheetName = saved.RequestedSheet; metadataKind = saved.MetadataKind; binding = false;
    }
    internal void Clear()
    {
        pageRead.Cancel(); ++pageGeneration; ++gridGeneration; ClearEventPageCaption();
        Invalidate("empty"); binding = true; revision.ItemsSource = null; page.ItemsSource = null; sheet.ItemsSource = null; row = 1; column = 1; SetFocusCoordinates(0, 0); fallback.Text = owner.Copy["selectPage"]; evidenceAbsence = ""; metadataKind = ""; requestedSheetName = ""; binding = false; RefreshReadingChrome();
    }
    internal void Invalidate(string state = "loading")
    {
        if (state is "failed" or "invalid" or "empty") ClearEventPageCaption();
        ++gridGeneration; ++pageGeneration; pageRead.Cancel(); ReadState = state; loadedGridScope = null; gridValue = default; previewScope = null; previewSource = ""; previewReason = ""; previewText = ""; previewObservation = new(SourceTextState.Missing, ""); RefreshCellDetails();
        var previous = binding; binding = true; Cells.SelectedCells.Clear(); Cells.ItemsSource = null; binding = previous; Cells.IsEnabled = false; showFormula.IsEnabled = false;
        PageImage.Source = null; PageScroll.Visibility = Visibility.Collapsed; Cells.Visibility = Visibility.Collapsed; fallback.Visibility = Visibility.Visible; fallback.Text = owner.Copy[state == "invalid" ? "reverse" : state == "failed" ? "failed" : "loading"]; source.Text = ""; retry.Visibility = state == "failed" ? Visibility.Visible : Visibility.Collapsed;
    }
    internal bool AuthorizesCell(int requestedRow, int requestedColumn) => ReadState == "ready" && loadedGridScope is { } scope && scope.Project == owner.ProjectId && scope.Report == owner.ReportId && scope.Revision == RevisionId && scope.Sheet == SheetId && scope.Row == row && scope.Column == column && requestedRow >= row && requestedRow < Math.Min(1_048_577, row + 50) && requestedColumn >= column && requestedColumn < Math.Min(16385, column + 8);
    private void SetFocusCoordinates(int requestedRow, int requestedColumn)
    {
        focusedRow = requestedRow is >= 1 and <= 1_048_576 && requestedColumn is >= 1 and <= 16_384 ? requestedRow : 0;
        focusedColumn = focusedRow > 0 ? requestedColumn : 0; address.Text = FocusedAddress; RefreshColumnHeaders(); RefreshCellDetails();
    }
    private bool MetadataWithoutPhysicalCell => owner.IsWorkbook && RevisionId.Length > 0 && owner.ReportId.Length > 0 && focusedRow == 0 && focusedColumn == 0 && SourceDiffPolicy.SheetScoped(metadataKind);
    private void RefreshCellDetails()
    {
        var metadata = MetadataWithoutPhysicalCell;
        foreach (var field in new FrameworkElement[] { cellValueLabel, cellValue, cellFormulaLabel, cellFormula }) field.Visibility = metadata || owner.EvidencePresented ? Visibility.Collapsed : Visibility.Visible;
        showFormula.Visibility = metadata ? Visibility.Collapsed : Visibility.Visible;
        foreach (var arrow in arrows) arrow.Button.IsEnabled = lastNavigationEnabled && !metadata;
        cellDetailsCaption.Text = owner.EvidencePresented && !metadata ? owner.Copy["cellDetailsInEvidence"] : metadata ? owner.Copy[ReadState == "failed" ? "failed" : evidenceAbsence.Length > 0 ? evidenceAbsence : "metadataObservation"] : (FocusedAddress.Length > 0 ? FocusedAddress + " · " : "") + owner.Copy["cellPreviewNotice"];
        var materialized = TryGetFocusedMaterializedCell(out var cell);
        cellValue.Text = !owner.EvidencePresented && materialized && cell.Get("value").ValueKind == JsonValueKind.String ? cell.Get("value").Text() : "";
        cellFormula.Text = !owner.EvidencePresented && materialized && cell.Get("formula").ValueKind == JsonValueKind.String ? cell.Get("formula").Text() : "";
        var unavailable = ReadState == "ready" && AuthorizesCell(focusedRow, focusedColumn) ? owner.Copy["cellNotMaterialized"] : owner.Copy[ReadState switch { "failed" => "failed", "invalid" => "reverse", "empty" => "selectCell", "absent" => evidenceAbsence.Length > 0 ? evidenceAbsence : "cellNotMaterialized", _ => "loading" }];
        string Qualifier(string field) => " · " + string.Join(" · ", SourceDiffPolicy.WorkbookPreviewKeys(cell, field).Select(key => owner.Copy[key]));
        cellValueLabel.Text = owner.Copy["cached"] + (materialized ? SourceDiffPolicy.WorkbookPreviewKeys(cell, "value").Count > 0 ? Qualifier("value") : "" : " · " + unavailable);
        cellFormulaLabel.Text = owner.Copy["formula"] + (materialized ? SourceDiffPolicy.WorkbookPreviewKeys(cell, "formula").Count > 0 ? Qualifier("formula") : "" : " · " + unavailable);
        if (openCellSource is not null) { openCellSource.Visibility = metadata ? Visibility.Collapsed : Visibility.Visible; openCellSource.IsEnabled = lastNavigationEnabled && owner.AllowsEvidence && AuthorizesCell(focusedRow, focusedColumn); AutomationProperties.SetName(openCellSource, PresentedSideName + " " + FocusedAddress + " · " + owner.Copy["openCellSource"]); }
        AutomationProperties.SetName(cellValue, PresentedSideName + " " + FocusedAddress + " · " + owner.Copy["cached"]); AutomationProperties.SetName(cellFormula, PresentedSideName + " " + FocusedAddress + " · " + owner.Copy["formula"]);
    }
    private void UpdateCellDetailsHeight()
    {
        if (!owner.IsWorkbook || !cellDetails.IsExpanded || Host.ActualHeight <= 0) return;
        // The docked body shares its vertical budget with the native source
        // grid. Keep three full rows plus header/scrollbar before giving the
        // remaining space to an independently scrollable details body.
        var minimumGrid = 3 * Cells.RowHeight + 30 + SystemParameters.HorizontalScrollBarHeight + 4;
        var height = Math.Clamp(visual.ActualHeight + cellDetailsScroll.ActualHeight - minimumGrid, 32, 160);
        if (Math.Abs(cellDetailsScroll.MaxHeight - height) > 1) cellDetailsScroll.MaxHeight = height;
    }
    internal async Task<object> OpenCellDetailsForSmoke(string expectedValue)
    {
        cellDetails.IsExpanded = true; RefreshCellDetails(); Host.UpdateLayout(); await owner.Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle);
        if (!cellDetails.IsVisible || cellDetails.Header as string != owner.Copy["cellDetails"] || !cellValue.IsReadOnly || !cellValue.IsVisible || cellValue.Text != expectedValue || !openCellSource.IsEnabled) throw new InvalidOperationException("The focused physical cell has no visible selectable exact bounded value and named source-segment route.");
        var selection = CaptureSelection(); var valuePreview = cellValue.Text; var formulaPreview = cellFormula.Text; openCellSource.RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Button.ClickEvent)); await cellDetailsRequest;
        if (CaptureSelection() != selection || cellDetails.IsExpanded || cellValue.Text.Length != 0 || cellFormula.Text.Length != 0) throw new InvalidOperationException("Opening full source segments changed the focused physical cell or bounded source text.");
        return new { address = FocusedAddress, heading = cellDetails.Header, selectable_value_before_open = valuePreview, formula_preview_before_open = formulaPreview, duplicate_previews_cleared = true, bounded_notice = cellDetailsCaption.Text, full_source_action = openCellSource.Content, source_selection_unchanged = true };
    }
    internal object CheckCellDetailLabelsForSmoke()
    {
        if (!TryGetFocusedMaterializedCell(out var actual)) throw new InvalidOperationException("Cell-details label QA needs an actual scoped focused cell.");
        var saved = gridValue; var enabled = lastNavigationEnabled; var raw = actual.GetRawText();
        var results = new List<object>();
        try
        {
            foreach (var control in new[] { (Value: "", Formula: "=SYNTHETIC preview", ValueLength: 0, FormulaLength: 5000, ValueKey: "observationEmpty"), (Value: "", Formula: "", ValueLength: 5000, FormulaLength: 0, ValueKey: "partialSourceSegment") })
            {
                var fields = actual.EnumerateObject().ToDictionary(item => item.Name, item => (object?)item.Value); fields["value"] = control.Value; fields["formula"] = control.Formula; fields["source_lengths"] = new { value = control.ValueLength, formula = control.FormulaLength };
                var projection = saved.EnumerateObject().ToDictionary(item => item.Name, item => (object?)item.Value); projection["items"] = saved.Get("items").Items().Select(item => item.Get("address").Text() == FocusedAddress ? JsonSerializer.SerializeToElement(fields) : item).ToArray(); gridValue = JsonSerializer.SerializeToElement(projection); RefreshCellDetails();
                if (cellValue.Text != control.Value || cellFormula.Text != control.Formula || !cellValueLabel.Text.Contains(owner.Copy[control.ValueKey], StringComparison.Ordinal) || !cellFormulaLabel.Text.Contains(owner.Copy[control.FormulaLength > control.Formula.Length ? "partialSourceSegment" : "observationEmpty"], StringComparison.Ordinal)) throw new InvalidOperationException("Native field labels hid explicit empty source or independent preview truncation.");
                NavigationEnabled(false); RefreshReadingChrome(); if (openCellSource.IsEnabled) throw new InvalidOperationException("A local Cell details refresh re-enabled disabled source navigation."); NavigationEnabled(true);
                results.Add(new { value_label = cellValueLabel.Text, formula_label = cellFormulaLabel.Text, disabled_navigation_retained = true });
            }
            return new { scope = "Synthetic bounded preview controls on actual WPF labels, not canonical engine cells", address = FocusedAddress, cases = results };
        }
        finally { gridValue = saved; NavigationEnabled(enabled); RefreshCellDetails(); if (!TryGetFocusedMaterializedCell(out var restored) || restored.GetRawText() != raw) throw new InvalidOperationException("Cell-details label controls did not restore the exact scoped grid observation."); }
    }
    internal object CheckMetadataCellDetailsForSmoke(bool expectedMetadata)
    {
        var expanded = cellDetails.IsExpanded; var selection = CaptureSelection();
        try
        {
            cellDetails.IsExpanded = true; RefreshCellDetails(); Host.UpdateLayout();
            var fields = new FrameworkElement[] { cellValueLabel, cellValue, cellFormulaLabel, cellFormula };
            if (MetadataWithoutPhysicalCell != expectedMetadata || !cellDetails.IsVisible || !rowStart.IsVisible || !colStart.IsVisible || !rowStart.IsEnabled || !colStart.IsEnabled) throw new InvalidOperationException("Metadata Cell details did not preserve its explicit native coordinate Go exit.");
            if (expectedMetadata)
            {
                if (fields.Any(field => field.Visibility != Visibility.Collapsed) || openCellSource.Visibility != Visibility.Collapsed || arrows.Any(arrow => arrow.Button.IsEnabled) || cellDetailsCaption.Text != owner.Copy[evidenceAbsence.Length > 0 ? evidenceAbsence : "metadataObservation"]) throw new InvalidOperationException("A metadata event without a physical focused cell retained empty stored-value/formula rows or ineffective window arrows.");
            }
            else if (fields.Any(field => !field.IsVisible) || !TryGetFocusedMaterializedCell(out var cell) || cellValue.Text != cell.Get("value").Text() || openCellSource.Visibility != Visibility.Visible || !openCellSource.IsEnabled || arrows.Any(arrow => !arrow.Button.IsEnabled)) throw new InvalidOperationException("Manual navigation to an actual physical cell did not restore its real stored-value/formula rows and native window navigation.");
            return new { physical_address = FocusedAddress, metadata_kind = metadataKind, metadata_without_physical_cell = expectedMetadata, native_field_rows_visible = fields.All(field => field.IsVisible), metadata_caption = cellDetailsCaption.Text, coordinate_go_controls_visible_and_enabled = true, window_arrows_enabled = arrows.All(arrow => arrow.Button.IsEnabled), scope = "Production expanded WPF Cell details properties, not OS input or screen-reader traversal" };
        }
        finally { cellDetails.IsExpanded = expanded; if (CaptureSelection() != selection) throw new InvalidOperationException("Inspecting metadata Cell details moved its source selection."); }
    }
    internal void CloseCellDetailsForSmoke() => cellDetails.IsExpanded = false;
    internal void EvidencePresentationChanged(bool opened)
    {
        if (opened) cellDetails.IsExpanded = false;
        RefreshCellDetails();
    }
    internal object CheckEvidenceHomeForSmoke()
    {
        Host.UpdateLayout();
        var scroll = GridScroll ?? throw new InvalidOperationException("The retained source grid has no viewport.");
        if (!owner.EvidencePresented || cellDetails.IsExpanded || cellValue.Text.Length != 0 || cellFormula.Text.Length != 0 || cellValue.Visibility != Visibility.Collapsed || cellFormula.Visibility != Visibility.Collapsed || !openCellSource.IsVisible || !openCellSource.IsEnabled || Cells.ActualWidth < 300 || scroll.ViewportHeight < 3) throw new InvalidOperationException("Evidence did not collapse duplicate raw previews or retain a readable grid and visible source route.");
        return new { physical_address = FocusedAddress, inline_details_collapsed = true, duplicate_raw_previews_cleared = true, cell_source_action_visible = true, source_width = Cells.ActualWidth, visible_source_rows = scroll.ViewportHeight, scope = "Production retained native WPF controls; no OS input assertion" };
    }
    private void RefreshColumnHeaders()
    {
        for (var index = 0; index < Cells.Columns.Count; index++)
        {
            // Index zero is the frozen physical row-number column.
            var focused = index > 0 && focusedColumn > 0 && column + index - 1 == focusedColumn;
            var templateRoot = new FrameworkElementFactory(typeof(Grid)); var border = new FrameworkElementFactory(typeof(Border)); border.SetValue(Border.BorderBrushProperty, new SolidColorBrush(Color.FromRgb(207, 215, 225))); border.SetValue(Border.BorderThicknessProperty, new Thickness(0, 0, 1, 1)); border.SetBinding(Border.BackgroundProperty, new Binding(nameof(Control.Background)) { RelativeSource = RelativeSource.TemplatedParent });
            var content = new FrameworkElementFactory(typeof(ContentPresenter)); content.SetBinding(ContentPresenter.ContentProperty, new Binding(nameof(ContentControl.Content)) { RelativeSource = RelativeSource.TemplatedParent }); content.SetValue(FrameworkElement.HorizontalAlignmentProperty, HorizontalAlignment.Center); content.SetValue(FrameworkElement.VerticalAlignmentProperty, VerticalAlignment.Center); border.AppendChild(content); templateRoot.AppendChild(border);
            // Preserve native user column resizing through the WPF header's
            // documented template parts while removing only hover colour.
            foreach (var part in new[] { (Name: "PART_LeftHeaderGripper", Alignment: HorizontalAlignment.Left), (Name: "PART_RightHeaderGripper", Alignment: HorizontalAlignment.Right) }) { var thumb = new FrameworkElementFactory(typeof(Thumb), part.Name); thumb.SetValue(FrameworkElement.WidthProperty, 5d); thumb.SetValue(FrameworkElement.HorizontalAlignmentProperty, part.Alignment); thumb.SetValue(Control.BackgroundProperty, Brushes.Transparent); thumb.SetValue(FrameworkElement.CursorProperty, Cursors.SizeWE); templateRoot.AppendChild(thumb); }
            var style = new Style(typeof(DataGridColumnHeader)); style.Setters.Add(new Setter(Control.TemplateProperty, new ControlTemplate(typeof(DataGridColumnHeader)) { VisualTree = templateRoot })); style.Setters.Add(new Setter(Control.BackgroundProperty, new SolidColorBrush(focused ? Color.FromRgb(220, 235, 253) : Color.FromRgb(244, 246, 249)))); style.Setters.Add(new Setter(Control.ForegroundProperty, Brushes.Black)); style.Setters.Add(new Setter(Control.FontFamilyProperty, new FontFamily("Segoe UI"))); style.Setters.Add(new Setter(Control.FontWeightProperty, focused ? FontWeights.SemiBold : FontWeights.Normal)); style.Setters.Add(new Setter(FrameworkElement.HeightProperty, 26d));
            // No IsMouseOver trigger: pointer hover cannot impersonate selection.
            Cells.Columns[index].HeaderStyle = style;
        }
    }
    internal async Task<object> SelectNativePhysicalCellForSmoke(int physicalRow, int physicalColumn)
    {
        if (!AuthorizesCell(physicalRow, physicalColumn)) throw new InvalidOperationException("The native selection control must remain in its loaded physical window.");
        var item = Cells.Items.OfType<GridRow>().Single(item => item.Row == physicalRow); var index = physicalColumn - column + 1;
        Cells.SelectedCells.Clear(); Cells.SelectedCells.Add(new DataGridCellInfo(item, Cells.Columns[index])); await selectionRequest; Host.UpdateLayout(); await owner.Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle);
        if (focusedRow != physicalRow || focusedColumn != physicalColumn) throw new InvalidOperationException("The actual SelectedCellsChanged handler did not install the requested physical cell.");
        return CheckFocusedHeaderForSmoke();
    }
    internal object CheckFocusedHeaderForSmoke()
    {
        Cells.UpdateLayout(); var expected = ColumnName(focusedColumn); var selected = Cells.SelectedCells.SingleOrDefault();
        var physical = Cells.Columns.Select((item, index) => new { Column = item, Index = index }).Where(item => item.Index > 0 && item.Column.HeaderStyle?.Setters.OfType<Setter>().Any(setter => setter.Property == Control.FontWeightProperty && setter.Value.Equals(FontWeights.SemiBold)) == true).ToArray();
        var native = Descendants(Cells).OfType<DataGridColumnHeader>().Where(header => header.Column is not null && physical.Any(item => ReferenceEquals(item.Column, header.Column))).ToArray();
        if (physical.Length != 1 || physical[0].Column.Header as string != expected || physical[0].Index != focusedColumn - column + 1 || selected.Column?.Header as string != expected || address.Text != FocusedAddress || native.Length != 1 || native[0].Content as string != expected || native[0].Background is not SolidColorBrush fill || fill.Color != Color.FromRgb(220, 235, 253) || native[0].Template.Triggers.Count != 0) throw new InvalidOperationException("Native focused column header, selected cell and physical address disagree.");
        return new { address = FocusedAddress, selected_header = selected.Column.Header, focused_header = native[0].Content, frozen_row_number_offset = 1, native_background = fill.Color.ToString(), mouse_over_template_triggers = native[0].Template.Triggers.Count, scope = "Actual WPF generated header/selected-cell properties after application events; no OS mouse movement claimed" };
    }
    internal void FocusCell(int requestedRow, int requestedColumn)
    {
        if (!AuthorizesCell(requestedRow, requestedColumn)) return;
        SetFocusCoordinates(requestedRow, requestedColumn); SelectFocusedNativeCell();
    }
    private void SelectFocusedNativeCell()
    {
        if (!AuthorizesCell(focusedRow, focusedColumn) || Cells.Items.OfType<GridRow>().FirstOrDefault(item => item.Row == focusedRow) is not { } item) return;
        var index = focusedColumn - column + 1; if (index < 1 || index >= Cells.Columns.Count) return;
        if (Cells.SelectedCells.Count == 1 && ReferenceEquals(Cells.SelectedCells[0].Item, item) && ReferenceEquals(Cells.SelectedCells[0].Column, Cells.Columns[index])) return;
        var wasBinding = binding; binding = true;
        try
        {
            // Selecting the logical cell must not move the native viewport.
            // Setting CurrentCell can bring a virtualized container into view.
            Cells.SelectedCells.Clear(); Cells.SelectedCells.Add(new DataGridCellInfo(item, Cells.Columns[index]));
        }
        finally { binding = wasBinding; }
    }
    internal bool TryGetFocusedMaterializedCell(out JsonElement cell)
    {
        cell = default;
        if (!AuthorizesCell(focusedRow, focusedColumn) || gridValue.ValueKind != JsonValueKind.Object || gridValue.Get("project_id").Text() != owner.ProjectId || gridValue.Get("report_id").Text() != owner.ReportId || gridValue.Get("revision_occurrence_id").Text() != RevisionId || gridValue.Get("sheet_id").Text() != SheetId || gridValue.Get("row_start").Number() != row || gridValue.Get("column_start").Number() != column) return false;
        var matches = gridValue.Get("items").Items().Where(item => item.ValueKind == JsonValueKind.Object && item.Get("row").Number() == focusedRow && item.Get("column").Number() == focusedColumn).ToArray();
        if (matches.Length != 1 || matches[0].Get("address").ValueKind != JsonValueKind.String || matches[0].Get("address").Text() != FocusedAddress) return false;
        cell = matches[0]; return true;
    }
    internal void SetRevisions(List<JsonElement> items, int index)
    {
        revisions = items; requestedSheetName = ""; binding = true; revision.ItemsSource = items.Select(v => Choice.From(v, "revision_occurrence_id", "label")).ToList(); revision.SelectedIndex = items.Count > 0 ? Math.Clamp(index, 0, items.Count - 1) : -1; binding = false; SetRevisionContents(); Localize();
    }
    internal void SetSourceRevision(string id, bool preserveMissingSheet = true)
    {
        if (revision.ItemsSource is not List<Choice> choices || !choices.Any(v => v.Id == id)) return;
        binding = true; revision.SelectedItem = choices.Find(v => v.Id == id); binding = false; SetRevisionContents(preserveMissingSheet); Localize();
    }
    private void SetRevisionContents(bool explicitVersionChange = false)
    {
        ClearEventPageCaption(); Invalidate(); evidenceAbsence = ""; metadataKind = "";
        var selected = revisions.Find(v => v.Get("revision_occurrence_id").Text() == RevisionId); var oldPage = PageId; var oldSheet = (sheet.SelectedItem as Choice)?.Label ?? requestedSheetName;
        binding = true;
        if (owner.IsWorkbook)
        {
            var sheets = selected.Get("sheets").Items().Select(v => Choice.From(v, "sheet_id", "name")).ToList(); sheet.ItemsSource = sheets; var matching = sheets.Find(v => v.Label == oldSheet); sheet.SelectedItem = matching ?? (explicitVersionChange && oldSheet.Length > 0 ? null : sheets.FirstOrDefault()); requestedSheetName = (sheet.SelectedItem as Choice)?.Label ?? oldSheet; if (explicitVersionChange && oldSheet.Length > 0 && matching is null) evidenceAbsence = "missingSelectedSheet"; row = 1; column = 1; SetFocusCoordinates(SheetId.Length > 0 ? row : 0, SheetId.Length > 0 ? column : 0);
        }
        else
        {
            pageValues = selected.Get("pages").Items(); var pages = pageValues.Select(v => new Choice(v.Get("page_id").Text(), v.Get("page").Number().ToString(System.Globalization.CultureInfo.InvariantCulture) + " · " + v.Get("text").Text(), v)).ToList(); page.ItemsSource = pages; page.SelectedItem = pages.Find(v => v.Id == oldPage) ?? pages.FirstOrDefault();
        }
        binding = false; RefreshReadingChrome();
    }
    internal bool HasPage(string id) => pageValues.Any(v => v.Get("page_id").Text() == id);
    internal void RestoreDefaultSelection() => SetRevisionContents();
    internal async Task SelectPage(string id, long ticket, CancellationToken token)
    {
        if (page.ItemsSource is not List<Choice> choices || !choices.Any(v => v.Id == id)) return; owner.ClearEventPageCaptions(); binding = true; page.SelectedItem = choices.Find(v => v.Id == id); binding = false; await LoadPage(ticket, token);
    }
    internal void SetEventPage(string? id, string eventKind = "")
    {
        if (eventKind.Length == 0) owner.ClearEventPageCaptions(); else ClearEventPageCaption(); binding = true; page.SelectedItem = page.ItemsSource is List<Choice> choices ? choices.Find(v => v.Id == id) : null; binding = false;
        if (eventKind.Length > 0) intendedPageCaption = new(eventKind, owner.ProjectId, owner.ReportId, RevisionId, PageId, owner.Generation);
        evidenceAbsence = PageId.Length == 0 ? "noEvidencePageListed" : "";
    }
    internal void SetEvidenceRevision(string id, string sheetId = "", JsonElement observation = default, string eventKind = "")
    {
        if (revision.ItemsSource is not List<Choice> choices || !choices.Any(v => v.Id == id)) throw new BridgeException("EVIDENCE_SCOPE", "Change occurrence is outside the fixed report.");
        binding = true; revision.SelectedItem = choices.Find(v => v.Id == id); binding = false; SetRevisionContents();
        if (owner.IsWorkbook)
        {
            binding = true; metadataKind = eventKind;
            if (sheetId.Length == 0) { sheet.SelectedItem = null; evidenceAbsence = SourceDiffPolicy.WorkbookScoped(eventKind) ? "workbookMetadata" : "absentSheet"; }
            else if (sheet.ItemsSource is List<Choice> sheets && sheets.Any(v => v.Id == sheetId)) sheet.SelectedItem = sheets.Find(v => v.Id == sheetId);
            else { sheet.SelectedItem = null; evidenceAbsence = "unsupportedSheet"; }
            requestedSheetName = (sheet.SelectedItem as Choice)?.Label ?? "";
            // An existing sheet does not turn an absent cell observation into
            // sheet metadata. Only a sheet-scoped event asserts that meaning.
            row = observation.Get("row").Number(0); column = observation.Get("column").Number(0); if (row < 1 || column < 1) { row = 0; column = 0; if (evidenceAbsence.Length == 0) evidenceAbsence = SourceDiffPolicy.SheetScoped(eventKind) ? "sheetMetadata" : "cellNotMaterialized"; } SetFocusCoordinates(row, column);
            binding = false;
        }
        RefreshReadingChrome();
    }
    internal async Task Load(long ticket, CancellationToken token)
    {
        Localize(); if (owner.IsWorkbook)
        {
            var gridRequest = LoadGrid(ticket, token); var sequence = gridGeneration;
            try { await gridRequest; } catch (OperationCanceledException) when (!owner.IsCurrent(ticket) || token.IsCancellationRequested || sequence != gridGeneration) { }
            return;
        }
        var request = LoadPage(ticket, token);
        while (true)
        {
            try { await request; if (owner.IsCurrent(ticket) && !token.IsCancellationRequested && activePageRequest is { } latest && !ReferenceEquals(latest, request)) { request = latest; continue; } return; }
            catch (OperationCanceledException) when (owner.IsCurrent(ticket) && !token.IsCancellationRequested && activePageRequest is { } replacement && !ReferenceEquals(replacement, request)) { request = activePageRequest; }
            catch (OperationCanceledException) when (!owner.IsCurrent(ticket) || token.IsCancellationRequested) { return; }
        }
    }
    internal async Task<bool> AwaitCurrentPageRead(long ticket, CancellationToken token)
    {
        while (owner.IsCurrent(ticket) && !token.IsCancellationRequested && ReadState == "loading")
        {
            var request = activePageRequest; if (request is null) return false;
            try { await request; }
            catch (OperationCanceledException) when (owner.IsCurrent(ticket) && !token.IsCancellationRequested && activePageRequest is { } replacement && !ReferenceEquals(replacement, request)) { continue; }
            catch (OperationCanceledException) when (!owner.IsCurrent(ticket) || token.IsCancellationRequested) { return false; }
            if (ReferenceEquals(request, activePageRequest) && ReadState == "loading") return false;
        }
        return owner.IsCurrent(ticket) && !token.IsCancellationRequested && ReadState != "loading";
    }
    private Task LoadPage(long ticket, CancellationToken token, Func<CancellationToken, Task>? beforeInstallForSmoke = null)
    {
        var request = LoadPageCore(ticket, token, beforeInstallForSmoke ?? PageBeforeInstallForSmoke); activePageRequest = request; return request;
    }
    private async Task LoadPageCore(long ticket, CancellationToken token, Func<CancellationToken, Task>? beforeInstallForSmoke)
    {
        // Retire the old page's text, provenance and bitmap before replacing its
        // request owner. A locale update during the await may render only loading.
        Invalidate(); pageRead.Dispose(); pageRead = CancellationTokenSource.CreateLinkedTokenSource(token); token = pageRead.Token;
        var sequence = pageGeneration; var selected = PageId; var project = owner.ProjectId; var report = owner.ReportId; var occurrence = RevisionId; if (selected.Length == 0) { Invalidate("absent"); ReadState = "absent"; fallback.Text = owner.Copy[owner.MissingDocumentPageCaptionKey(after)]; return; }
        PageImage.Source = null; fallback.Text = owner.Copy["analyzing"]; source.Text = ""; fallback.Visibility = Visibility.Visible; PageScroll.Visibility = Visibility.Collapsed; Cells.Visibility = Visibility.Collapsed;
        try {
        var value = await owner.Bridge.Call("pagePreview", new { project_id = project, report_id = report, page_id = selected, max_width = 1600 }, token);
        // Isolated native QA may asynchronously hold the real returned payload
        // before installation; the owned page token cancels a superseded hold.
        if (beforeInstallForSmoke is not null) await beforeInstallForSmoke(token);
        if (!owner.IsCurrent(ticket) || sequence != pageGeneration || selected != PageId || project != owner.ProjectId || report != owner.ReportId || occurrence != RevisionId) return;
        if (value.Get("page_id").Text() != selected || value.Get("report_id").Text() != report) throw new BridgeException("PAGE_SCOPE", "The preview belongs to a different page or report.");
        var encoded = value.Get("png_base64").Text(); var origin = value.Get("source").Text(); previewSource = origin; previewReason = value.Get("unavailable_reason").Text(); previewObservation = ReadPreviewObservation(value); previewText = previewObservation.Text; source.Text = owner.Copy["source"] + ": " + origin;
        if (encoded.Length > 0)
        {
            if (encoded.Length > 24 * 1024 * 1024) throw new BridgeException("PREVIEW_LIMIT", "The page image exceeds the desktop preview limit.");
            var bitmap = new BitmapImage(); using var bytes = new MemoryStream(Convert.FromBase64String(encoded)); bitmap.BeginInit(); bitmap.CacheOption = BitmapCacheOption.OnLoad; bitmap.DecodePixelWidth = 1600; bitmap.StreamSource = bytes; bitmap.EndInit(); bitmap.Freeze();
            if (presentationReport != report) { presentationReport = report; if (!presentationChosen) { fittingWidth = owner.SingleSourceReading; if (!fittingWidth) { applyingFit = true; zoom.Value = 1; applyingFit = false; } } }
            PageImage.Source = bitmap; ResizePreview(); fallback.Visibility = Visibility.Collapsed; PageScroll.Visibility = Visibility.Visible;
        }
        else
        {
            source.Text = owner.Copy["structural"] + " · " + origin + "\n" + value.Get("unavailable_reason").Text();
        }
        previewScope = (project, report, occurrence, selected); ReadState = "ready"; retry.Visibility = Visibility.Collapsed; RerenderPresentation();
        } catch
        {
            if (owner.IsCurrent(ticket) && sequence == pageGeneration && !token.IsCancellationRequested && project == owner.ProjectId && report == owner.ReportId && occurrence == RevisionId && selected == PageId) { Invalidate("failed"); throw; }
            throw new OperationCanceledException("The page request was superseded.", token);
        }
    }
    private async Task LoadGrid(long ticket, CancellationToken token)
    {
        Invalidate(); var sequence = gridGeneration;
        if (evidenceAbsence.Length > 0)
        {
            ReadState = "absent"; fallback.Text = owner.Copy[evidenceAbsence] + (evidenceAbsence == "missingSelectedSheet" ? "\n\n" + requestedSheetName : "");
            if (evidenceAbsence is "sheetMetadata" or "workbookMetadata") fallback.Text += "\n\n" + MetadataPreview();
            return;
        }
        if (RevisionId.Length == 0 || SheetId.Length == 0) { ReadState = "absent"; fallback.Text = owner.Copy[evidenceAbsence.Length > 0 ? evidenceAbsence : "absentSheet"]; return; }
        var project = owner.ProjectId; var report = owner.ReportId; var revisionId = RevisionId; var sheetId = SheetId; var rowAt = row; var columnAt = column;
        try {
        var value = await owner.Bridge.Call("workbookGrid", new { project_id = project, report_id = report, revision_occurrence_id = revisionId, sheet_id = sheetId, row_start = rowAt, row_limit = 50, column_start = columnAt, column_limit = 8 }, token);
        if (!owner.IsCurrent(ticket) || sequence != gridGeneration || project != owner.ProjectId || report != owner.ReportId || RevisionId != revisionId || SheetId != sheetId || row != rowAt || column != columnAt) return;
        if (value.Get("project_id").Text() != project || value.Get("revision_occurrence_id").Text() != revisionId || value.Get("sheet_id").Text() != sheetId || value.Get("report_id").Text() != report || value.Get("row_start").Number() != rowAt || value.Get("column_start").Number() != columnAt || value.Get("row_limit").Number() != 50 || value.Get("column_limit").Number() != 8) throw new BridgeException("GRID_SCOPE", "Grid response is outside the selected source scope.");
        loadedGridScope = (project, report, revisionId, sheetId, rowAt, columnAt); ReadState = "ready"; Cells.IsEnabled = owner.AllowsEvidence; showFormula.IsEnabled = owner.AllowsEvidence;
        gridValue = value; rowStart.Text = row.ToString(System.Globalization.CultureInfo.InvariantCulture); colStart.Text = column.ToString(System.Globalization.CultureInfo.InvariantCulture); RenderGrid();
        source.Text = (revision.SelectedItem as Choice)?.Label + " · " + (sheet.SelectedItem as Choice)?.Label + " · " + row + "–" + Math.Min(1048576, row + 49); source.ToolTip = revisionId + "\n" + sheetId; fallback.Visibility = Visibility.Collapsed; PageScroll.Visibility = Visibility.Collapsed; Cells.Visibility = Visibility.Visible;
        } catch
        {
            if (owner.IsCurrent(ticket) && sequence == gridGeneration && !token.IsCancellationRequested && project == owner.ProjectId && report == owner.ReportId && RevisionId == revisionId && SheetId == sheetId && row == rowAt && column == columnAt) { Invalidate("failed"); throw; }
            throw new OperationCanceledException("The grid request was superseded.", token);
        }
    }
    private void RenderGrid()
    {
        if (ReadState != "ready" || loadedGridScope is null || gridValue.ValueKind == JsonValueKind.Undefined) return; var wasBinding = binding; binding = true;
        try
        {
            Cells.Columns.Clear();
            Cells.Columns.Add(new DataGridTextColumn { Header = "#", Binding = new Binding(nameof(GridRow.Number)), Width = 65, IsReadOnly = true });
            var columnCount = Math.Min(8, 16385 - column);
            for (var index = 0; index < columnCount; index++)
            {
                var path = "Values[" + index + "]"; var style = new Style(typeof(TextBlock)); style.Setters.Add(new Setter(TextBlock.ForegroundProperty, new Binding(path + ".Foreground"))); style.Setters.Add(new Setter(TextBlock.FontStyleProperty, new Binding(path + ".FontStyle"))); style.Setters.Add(new Setter(FrameworkElement.ToolTipProperty, new Binding(path + ".ToolTip")));
                // Keep the exact segment bound to the native text. Only its
                // visual presentation is shortened inside the physical cell.
                style.Setters.Add(new Setter(TextBlock.TextTrimmingProperty, TextTrimming.CharacterEllipsis)); style.Setters.Add(new Setter(TextBlock.TextWrappingProperty, TextWrapping.NoWrap)); style.Setters.Add(new Setter(TextBlock.PaddingProperty, new Thickness(4, 0, 4, 0))); style.Setters.Add(new Setter(UIElement.ClipToBoundsProperty, true)); style.Setters.Add(new Setter(FrameworkElement.HorizontalAlignmentProperty, HorizontalAlignment.Stretch)); style.Setters.Add(new Setter(FrameworkElement.VerticalAlignmentProperty, VerticalAlignment.Center));
                var cellStyle = new Style(typeof(DataGridCell)); cellStyle.Setters.Add(new Setter(UIElement.ClipToBoundsProperty, true));
                Cells.Columns.Add(new DataGridTextColumn { Header = ColumnName(column + index), Binding = new Binding(path + ".Text"), ElementStyle = style, CellStyle = cellStyle, Width = 115, IsReadOnly = true });
            }
            Cells.FrozenColumnCount = 1;
            var observed = gridValue.Get("items").Items().ToDictionary(v => (v.Get("row").Number(), v.Get("column").Number()), v => v);
            var values = new List<GridRow>();
            for (var r = row; r < Math.Min(1_048_577, row + 50); r++)
            {
                var cells = new GridCell[columnCount]; for (var index = 0; index < columnCount; index++)
                {
                    if (!observed.TryGetValue((r, column + index), out var cell)) { cells[index] = new("—", true, "sparseCell", owner.Copy); continue; }
                    var field = showFormula.IsChecked == true && cell.Get("formula") is { ValueKind: JsonValueKind.String } formula && formula.GetString()!.Length > 0 ? "formula" : "value";
                    var value = cell.Get(field).Text(); var total = cell.Get("source_lengths").Get(field); var truncated = total.ValueKind == JsonValueKind.Number && total.TryGetInt32(out var length) && length > value.Length;
                    cells[index] = new(value, truncated, truncated ? "truncatedCell" : "literalCell", owner.Copy);
                }
                values.Add(new(r, cells));
            }
            Cells.ItemsSource = values; RefreshColumnHeaders(); SelectFocusedNativeCell(); RefreshCellDetails();
        }
        finally { binding = wasBinding; }
    }
    internal async Task<object> CheckFrozenCoordinatesForSmoke(Func<object, Task>? observeBeforeAssertions = null)
    {
        Cells.UpdateLayout(); var scroll = GridScroll ?? throw new InvalidOperationException("Native grid has no viewport.");
        if (Cells.FrozenColumnCount != 1 || !Cells.Columns[0].IsFrozen || Cells.Columns[0].Header as string != "#" || Cells.CanUserReorderColumns) throw new InvalidOperationException("Native row-number column is not fixed before the source columns.");
        for (var index = 1; index < Cells.Columns.Count; index++) if (Cells.Columns[index].Header as string != ColumnName(column + index - 1)) throw new InvalidOperationException("A scrolled source header lost its physical column name.");
        var header = Descendants(Cells).OfType<DataGridColumnHeadersPresenter>().FirstOrDefault() ?? throw new InvalidOperationException("Native source headers are missing.");
        var headerBottom = header.TransformToAncestor(Cells).TransformBounds(new Rect(0, 0, header.ActualWidth, header.ActualHeight)).Bottom;
        var headerObservations = new List<object>(); var visibleHeaders = new List<string>();
        foreach (var item in Descendants(header).OfType<DataGridColumnHeader>().Where(item => item.IsVisible && item.ActualWidth > 0 && item.Column is not null && item.Column.DisplayIndex > 0))
        {
            var expected = ColumnName(column + item.Column.DisplayIndex - 1); var container = item.TransformToAncestor(Cells).TransformBounds(new Rect(0, 0, item.ActualWidth, item.ActualHeight)); var labels = new List<object>();
            foreach (var content in Descendants(item).OfType<FrameworkElement>())
            {
                var text = content switch { TextBlock block => block.Text, AccessText access => access.Text, _ => "" };
                if (text != expected || !content.IsVisible || content.ActualWidth <= 0 || content.ActualHeight <= 0) continue;
                var bounds = content.TransformToAncestor(Cells).TransformBounds(new Rect(0, 0, content.ActualWidth, content.ActualHeight));
                // Native text may remain completely visible when its column's
                // larger header container is partially clipped by scrolling.
                var visible = bounds.Left >= Cells.Columns[0].ActualWidth - 1 && bounds.Right <= Cells.ActualWidth + 1 && bounds.Top >= -1 && bounds.Bottom <= headerBottom + 1;
                if (visible) visibleHeaders.Add(expected);
                labels.Add(new { native_type = content.GetType().Name, text, left = bounds.Left, right = bounds.Right, top = bounds.Top, bottom = bounds.Bottom, fully_visible_native_label = visible });
            }
            headerObservations.Add(new { physical_column = expected, container_left = container.Left, container_right = container.Right, container_width = container.Width, native_labels = labels });
        }
        var rendered = new List<object>(); var failures = new List<string>();
        foreach (var nativeRow in Descendants(Cells).OfType<DataGridRow>())
        {
            if (!nativeRow.IsVisible || nativeRow.Item is not GridRow model) continue;
            var frozen = Descendants(nativeRow).OfType<DataGridCell>().FirstOrDefault(cell => ReferenceEquals(cell.Column, Cells.Columns[0])); if (frozen is null || !frozen.IsVisible) continue;
            var bounds = frozen.TransformToAncestor(Cells).TransformBounds(new Rect(0, 0, frozen.ActualWidth, frozen.ActualHeight));
            if (bounds.Top < headerBottom - 1 || bounds.Bottom > Cells.ActualHeight - 1 || bounds.Height <= 0) continue;
            var number = (frozen.Content as TextBlock)?.Text ?? "";
            if (bounds.Left < -1 || bounds.Left > 2 || bounds.Right > Cells.ActualWidth + 1 || number != model.Number || !AuthorizesCell(model.Row, column)) failures.Add("Frozen row number does not identify its visible physical row: row=" + model.Number + ", left=" + bounds.Left + ", right=" + bounds.Right);
            foreach (var cell in Descendants(nativeRow).OfType<DataGridCell>().Where(cell => cell.Column.DisplayIndex > 0))
            {
                var index = cell.Column.DisplayIndex - 1;
                if (cell.Content is TextBlock value && value.Text != model.Values[index].Text) failures.Add("Recycled source cell no longer matches its physical row/column.");
            }
            rendered.Add(new { row = model.Row, rendered_row_number = number, frozen_left = bounds.Left, frozen_right = bounds.Right, top = bounds.Top, bottom = bounds.Bottom });
        }
        if (rendered.Count == 0) failures.Add("No complete visible native row-number cell was qualified after scrolling.");
        var namedLabels = visibleHeaders.Distinct().ToArray(); if (namedLabels.Length == 0) failures.Add("No complete native physical source column label is visible beside the frozen coordinates.");
        if (observeBeforeAssertions is not null) await observeBeforeAssertions(new { horizontal_offset = scroll.HorizontalOffset, vertical_offset = scroll.VerticalOffset, viewport_width = Cells.ActualWidth, viewport_height = Cells.ActualHeight, frozen_columns = Cells.FrozenColumnCount, visible_source_header_labels = namedLabels, header_observations = headerObservations, visible_row_coordinates = rendered, assertion_failures = failures });
        if (failures.Count > 0) throw new InvalidOperationException(string.Join(" ", failures));
        var observed = gridValue.Get("items").Items().FirstOrDefault(); if (observed.ValueKind != JsonValueKind.Object) throw new InvalidOperationException("Stored physical cell query control is missing.");
        var selection = CaptureSelection(); var ticket = owner.Generation; var rows = Cells.ItemsSource; var x = scroll.HorizontalOffset; var y = scroll.VerticalOffset;
        var result = await owner.Query("get_workbook_cell", new() { ["revision_occurrence_id"] = RevisionId, ["sheet_id"] = SheetId, ["row"] = observed.Get("row").Number(), ["column"] = observed.Get("column").Number(), ["text_length"] = 4096 }, owner.ReadToken);
        var stored = result.Get("items").Items().FirstOrDefault(); var expectedAddress = ColumnName(observed.Get("column").Number()) + observed.Get("row").Number().ToString(System.Globalization.CultureInfo.InvariantCulture);
        if (!owner.IsCurrent(ticket) || CaptureSelection() != selection || !ReferenceEquals(rows, Cells.ItemsSource) || scroll.HorizontalOffset != x || scroll.VerticalOffset != y || stored.Get("address").Text() != expectedAddress || stored.Get("row").Number() != observed.Get("row").Number() || stored.Get("column").Number() != observed.Get("column").Number() || !stored.Get("value").Text().StartsWith(observed.Get("value").Text(), StringComparison.Ordinal) || !stored.Get("formula").Text().StartsWith(observed.Get("formula").Text(), StringComparison.Ordinal)) throw new InvalidOperationException("Frozen-grid source query altered the viewport/selection or used a different physical cell.");
        return new { horizontal_offset = x, vertical_offset = y, scrollable_width = scroll.ScrollableWidth, scrollable_height = scroll.ScrollableHeight, viewport_width = Cells.ActualWidth, viewport_height = Cells.ActualHeight, frozen_columns = Cells.FrozenColumnCount, visible_source_header_labels = namedLabels, header_observations = headerObservations, visible_row_coordinates = rendered, queried_stored_address = expectedAddress };
    }
    internal void CheckLiteralMarkerForSmoke(string literal)
    {
        if (Cells.Items.OfType<GridRow>().FirstOrDefault()?.Values.FirstOrDefault() is not { } cell || cell.Text != literal || cell.Annotation || cell.FontStyle != FontStyles.Normal || cell.Foreground != Brushes.Black) throw new InvalidOperationException("A literal source marker was styled as a generated annotation.");
        var sparseCell = Cells.Items.OfType<GridRow>().SelectMany(item => item.Values).FirstOrDefault(cell => cell.TooltipKey == "sparseCell");
        if (sparseCell is null || !sparseCell.Annotation || sparseCell.FontStyle != FontStyles.Italic || sparseCell.Foreground != Brushes.Gray || sparseCell.ToolTip == cell.ToolTip) throw new InvalidOperationException("Sparse absence does not have a distinct annotation style and explanation.");
    }
    internal void CheckTruncationForSmoke()
    {
        var truncated = Cells.Items.OfType<GridRow>().SelectMany(item => item.Values).FirstOrDefault(cell => cell.TooltipKey == "truncatedCell");
        if (truncated is null || !truncated.Annotation || truncated.FontStyle != FontStyles.Italic || truncated.ToolTip != truncated.Text + "\n\n" + owner.Copy["truncatedCell"]) throw new InvalidOperationException("Truncated source preview lacks its exact stored segment, distinct style and full-source reader guidance.");
    }
    internal void ShowFormulasForSmoke(bool enabled) => showFormula.IsChecked = enabled;
    internal object CheckCellClippingForSmoke(string expectedSource)
    {
        if (ReadState != "ready" || Cells.Visibility != Visibility.Visible) throw new InvalidOperationException("No native source grid is available for cell clipping qualification.");
        Cells.UpdateLayout();
        foreach (var nativeRow in Descendants(Cells).OfType<DataGridRow>().Where(item => item.IsVisible && item.Item is GridRow))
        {
            var model = (GridRow)nativeRow.Item;
            foreach (var nativeCell in Descendants(nativeRow).OfType<DataGridCell>().Where(item => item.IsVisible && item.Column.DisplayIndex > 0))
            {
                var index = nativeCell.Column.DisplayIndex - 1; if (index >= model.Values.Length || model.Values[index].Text != expectedSource) continue;
                var nativeText = nativeCell.Content as TextBlock ?? Descendants(nativeCell).OfType<TextBlock>().FirstOrDefault(item => item.Text == expectedSource);
                if (nativeText is null || nativeText.ActualWidth <= 0 || nativeText.ActualHeight <= 0) throw new InvalidOperationException("The exact source segment has no materialized native text element.");
                var cellBounds = nativeCell.TransformToAncestor(Cells).TransformBounds(new Rect(0, 0, nativeCell.ActualWidth, nativeCell.ActualHeight));
                var textBounds = nativeText.TransformToAncestor(Cells).TransformBounds(new Rect(0, 0, nativeText.ActualWidth, nativeText.ActualHeight));
                var value = model.Values[index]; var tooltip = nativeText.ToolTip as string ?? "";
                if (nativeText.Text != expectedSource || tooltip != value.ToolTip || !tooltip.StartsWith(expectedSource + "\n\n", StringComparison.Ordinal) || nativeText.TextTrimming != TextTrimming.CharacterEllipsis || nativeText.TextWrapping != TextWrapping.NoWrap || !nativeText.ClipToBounds || !nativeCell.ClipToBounds || nativeText.Padding.Left < 4 || nativeText.Padding.Right < 4 || textBounds.Left < cellBounds.Left - .5 || textBounds.Right > cellBounds.Right + .5 || textBounds.Top < cellBounds.Top - .5 || textBounds.Bottom > cellBounds.Bottom + .5) throw new InvalidOperationException("Native source text is not bounded by its physical cell with its exact stored segment retained in the tooltip.");
                var source = gridValue.Get("items").Items().Single(item => item.Get("row").Number() == model.Row && item.Get("column").Number() == column + index);
                var field = showFormula.IsChecked == true && source.Get("formula").ValueKind == JsonValueKind.String && source.Get("formula").Text().Length > 0 ? "formula" : "value";
                return new { address = ColumnName(column + index) + model.Number, displayed_text = nativeText.Text, active_field = field, active_field_truncated = value.Annotation, cell_text_truncated = source.Get("text_truncated").Flag(), tooltip, cell_left = cellBounds.Left, cell_right = cellBounds.Right, cell_top = cellBounds.Top, cell_bottom = cellBounds.Bottom, text_left = textBounds.Left, text_right = textBounds.Right, text_top = textBounds.Top, text_bottom = textBounds.Bottom, native_text_type = nativeText.GetType().Name, text_trimming = nativeText.TextTrimming.ToString(), text_wrapping = nativeText.TextWrapping.ToString(), text_clip_to_bounds = nativeText.ClipToBounds, cell_clip_to_bounds = nativeCell.ClipToBounds, padding_left = nativeText.Padding.Left, padding_right = nativeText.Padding.Right };
            }
        }
        throw new InvalidOperationException("The expected exact source segment is not currently materialized in the native grid viewport.");
    }
    private async Task LoadCoordinates()
    {
        if (!int.TryParse(rowStart.Text, out var r) || !int.TryParse(colStart.Text, out var c) || r is < 1 or > 1_048_576 || c is < 1 or > 16_384) throw new BridgeException("ADDRESS", "Row 1–1048576; column 1–16384."); evidenceAbsence = ""; metadataKind = ""; row = r; column = c; SetFocusCoordinates(row, column); await ReloadGrid();
    }
    private async Task GoAddress()
    {
        var found = Regex.Match(address.Text.Trim(), "^([A-Za-z]{1,3})([1-9][0-9]{0,6})$", RegexOptions.CultureInvariant); if (!found.Success) throw new BridgeException("ADDRESS", "A1–XFD1048576");
        var c = 0; foreach (var letter in found.Groups[1].Value.ToUpperInvariant()) c = c * 26 + letter - 'A' + 1;
        var r = int.Parse(found.Groups[2].Value, System.Globalization.CultureInfo.InvariantCulture); if (c > 16384 || r > 1048576) throw new BridgeException("ADDRESS", "A1–XFD1048576");
        evidenceAbsence = ""; metadataKind = ""; row = r; column = c; SetFocusCoordinates(row, column); await ReloadGrid(); await owner.SelectCell(this, r, c);
    }
    private Task ReloadGrid() => owner.ReloadSourceWindow();
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
        if (PageImage.Source is not BitmapSource bitmap) return;
        // 100% uses source page points where available. Shrinking every page
        // to a narrow comparison column made ordinary body text unreadable.
        // A manual scale therefore survives layout and presentation changes;
        // automatic fit is only for an untouched, fresh single-source presentation.
        PageImage.Width = PreviewPointWidth(bitmap);
        if (!fittingWidth) return;
        var viewport = PageScroll.ViewportWidth > 0 ? PageScroll.ViewportWidth : Math.Max(1, PageScroll.ActualWidth - SystemParameters.VerticalScrollBarWidth);
        if (viewport <= 1) return;
        applyingFit = true; zoom.Value = Math.Clamp(Math.Max(1, viewport - pageFrame.Margin.Left - pageFrame.Margin.Right - 2) / PageImage.Width, zoom.Minimum, zoom.Maximum); applyingFit = false;
    }
    private double PreviewPointWidth(BitmapSource bitmap)
    {
        if (page.SelectedItem is not Choice selected) return bitmap.Width;
        var revision = revisions.Find(value => value.Get("revision_occurrence_id").Text() == RevisionId);
        return SourcePreviewGeometry.PointWidth(revision, selected.Value, previewSource, bitmap.Width);
    }
    private void FitPreview() { presentationChosen = true; fittingWidth = true; ResizePreview(); }
    private void UpdateZoomCaption() => zoomPercent.Text = Math.Round(zoom.Value * 100).ToString(System.Globalization.CultureInfo.InvariantCulture) + "%";
    internal void FitPreviewForSmoke() => FitPreview();
    internal object CheckPreviewReadabilityForSmoke()
    {
        if (PageImage.Source is not BitmapSource bitmap || PageImage.Width != PreviewPointWidth(bitmap) || zoomPercent.Text != Math.Round(Zoom * 100).ToString(System.Globalization.CultureInfo.InvariantCulture) + "%" || page.Height != 28 || string.IsNullOrWhiteSpace(zoomCaption.Text) || string.IsNullOrWhiteSpace(fitWidth.Content as string) || pageFrame.Child != PageImage || pageFrame.BorderThickness.Left != 1 || PageScroll.Background is not SolidColorBrush backdrop || backdrop.Color == Colors.White) throw new InvalidOperationException("The native raster scale, labeled zoom or single-line page chooser is unavailable.");
        return new { source_point_width = PageImage.Width, native_raster_width = bitmap.Width, displayed_raster_width = PageImage.Width * Zoom, viewport_width = PageScroll.ViewportWidth, zoom_percent = zoomPercent.Text, fit_width = fittingWidth, page_boundary = pageFrame.BorderThickness.Left, contrasting_backdrop = PageScroll.Background.ToString(), page_picker_height = page.Height };
    }
    private sealed class SingleLinePageLabel : IValueConverter
    {
        public object Convert(object value, Type targetType, object parameter, System.Globalization.CultureInfo culture) => value is string text ? text.Replace("\r\n", " ", StringComparison.Ordinal).Replace('\r', ' ').Replace('\n', ' ') : "";
        public object ConvertBack(object value, Type targetType, object parameter, System.Globalization.CultureInfo culture) => throw new NotSupportedException();
    }
    private string MetadataPreview()
    {
        var projection = SourceDiffPolicy.WorkbookMetadataProjection(revisions.Find(item => item.Get("revision_occurrence_id").Text() == RevisionId), SheetId, metadataKind);
        return !projection.Available ? owner.Copy["observationMissing"] : owner.Copy["metadataObservation"] + "\n" + owner.Copy["metadataProjection"] + "\n" + projection.Json + (projection.Bounded ? "\n\n" + owner.Copy["metadataBounded"] : "");
    }
    private void RerenderPresentation()
    {
        if (ReadState == "invalid") { fallback.Text = owner.Copy["reverse"]; return; }
        if (ReadState == "failed") { fallback.Text = owner.Copy["failed"]; return; }
        if (ReadState == "loading") { fallback.Text = owner.Copy["loading"]; return; }
        if (ReadState == "empty") { fallback.Text = owner.Copy["selectPage"]; return; }
        if (ReadState == "absent")
        {
            fallback.Text = owner.Copy[!owner.IsWorkbook ? owner.MissingDocumentPageCaptionKey(after) : evidenceAbsence.Length > 0 ? evidenceAbsence : "absentSheet"] + (evidenceAbsence == "missingSelectedSheet" ? "\n\n" + requestedSheetName : "");
            if (evidenceAbsence is "sheetMetadata" or "workbookMetadata") fallback.Text += "\n\n" + MetadataPreview(); return;
        }
        if (!owner.IsWorkbook && ReadState == "ready")
        {
            if (!PreviewMatchesSelection) { source.Text = ""; fallback.Text = owner.Copy["loading"]; PageImage.Source = null; PageScroll.Visibility = Visibility.Collapsed; fallback.Visibility = Visibility.Visible; return; }
            source.Text = PageImage.Source is not null ? owner.Copy["source"] + ": " + owner.Copy.Code(previewSource) : owner.Copy["structural"] + " · " + owner.Copy.Code(previewSource); source.ToolTip = owner.Copy["technicalDetails"] + "\n" + previewSource + (previewReason.Length > 0 ? "\n" + previewReason : "");
            fallback.Text = FormatPreviewFallback(previewObservation, owner.Copy);
        }
    }
    internal static string FormatPreviewFallback(SourceTextObservation observation, Copy copy)
    {
        var annotation = observation.State switch
        {
            SourceTextState.Partial => copy["partialSourceSegment"] + " [" + observation.Range?.Total + "]",
            SourceTextState.Invalid => copy["invalidSourceSegment"],
            _ => ""
        };
        return observation.Text + (annotation.Length > 0 ? "\n\n" + annotation : "");
    }
    internal object CheckInvalidPreviewFallbackForSmoke()
    {
        if (owner.IsWorkbook || ReadState != "ready" || !PreviewMatchesSelection) throw new InvalidOperationException("The invalid preview control requires a currently verified document source pane.");
        const string raw = "Exact raw source\r\n한글 😀\n";
        var observed = ReadPreviewObservation(JsonSerializer.SerializeToElement(new { text = raw, text_total_length = raw.Length + 1, text_truncated = false }));
        if (observed.State != SourceTextState.Invalid || observed.Text != raw) throw new InvalidOperationException("The synthetic invalid metadata control did not retain its exact source.");
        var savedObservation = previewObservation; var savedText = previewText; var savedFallback = fallback.Text; var savedCaption = source.Text; var savedScope = previewScope; var selection = CaptureSelection(); var image = PageImage.Source; object result;
        try
        {
            previewObservation = observed; previewText = raw; RerenderPresentation();
            var expected = raw + "\n\n" + owner.Copy["invalidSourceSegment"];
            if (fallback.Text != expected || !fallback.IsReadOnly || PreviewObservation.State != SourceTextState.Invalid) throw new InvalidOperationException("The production native fallback did not preserve verbatim source and mark invalid preview metadata separately.");
            result = new { synthetic_presentation_control = true, exact_raw_source = raw, native_fallback_text = fallback.Text, marker = owner.Copy["invalidSourceSegment"], invalid_observation_is_not_complete = !PreviewObservation.Available, observation_scope = "Production native fallback text property with synthetic metadata; no visible-pixel or canonical-engine assertion" };
        }
        finally { previewObservation = savedObservation; previewText = savedText; previewScope = savedScope; RerenderPresentation(); fallback.Text = savedFallback; source.Text = savedCaption; }
        if (CaptureSelection() != selection || !ReferenceEquals(image, PageImage.Source) || previewObservation != savedObservation || previewText != savedText || previewScope != savedScope) throw new InvalidOperationException("The synthetic invalid fallback control changed the retained native source identity or payload.");
        return result;
    }
    private bool PreviewMatchesSelection => previewScope is { } scope && scope.Project == owner.ProjectId && scope.Report == owner.ReportId && scope.Revision == RevisionId && scope.Page == PageId;
    internal string VerifiedPreviewText => PreviewMatchesSelection ? previewText : "";
    internal bool DiffTextAvailable => PreviewMatchesSelection && ReadState == "ready" && (page.SelectedItem as Choice)?.Value.Get("capabilities").Get("text").Text() == "available";
    internal bool StructuralPreview => PreviewMatchesSelection && PageImage.Source is null;
    internal SourceTextObservation PreviewObservation => !PreviewMatchesSelection || ReadState != "ready" ? new(SourceTextState.Missing, "") : previewObservation;
    internal static SourceTextObservation ReadPreviewObservation(JsonElement value)
    {
        var raw = SourceTextObservation.Read(value.Get("text"));
        if (!raw.HasText) return raw;
        var lengthValue = value.Get("text_total_length"); int? total = lengthValue.ValueKind == JsonValueKind.Number && lengthValue.TryGetInt32(out var length) && length >= 0 ? length : null;
        var truncatedValue = value.Get("text_truncated"); bool? truncated = truncatedValue.ValueKind is JsonValueKind.True or JsonValueKind.False ? truncatedValue.GetBoolean() : null;
        var valid = total.HasValue && truncated.HasValue && (truncated.Value ? raw.Text.Length > 0 && total > raw.Text.Length : total == raw.Text.Length);
        var state = truncated == true ? "truncated" : raw.Text.Length == 0 ? "empty" : "complete";
        return new(!valid ? SourceTextState.Invalid : truncated == true ? SourceTextState.Partial : raw.State, raw.Text, new(valid, state, 0, total, truncated == true ? raw.Text.Length : null, raw.Text.Length)) { RawState = raw.State };
    }
    internal string PresentedSourceCaption => source.Text;
    internal string PresentedFallback => fallback.Text;
    internal async Task SelectPageForSmoke(string id, Func<CancellationToken, Task>? beforeInstall = null) { SetEventPage(id); var request = LoadPage(owner.Generation, owner.ReadToken, beforeInstall); owner.SourcePresentationChanged(); try { await request; } finally { owner.SourcePresentationChanged(); } }
    internal async Task SelectRevisionForSmoke(int index) { revision.SelectedIndex = index; await selectionRequest; }
    internal async Task SelectAvailableSheetForSmoke() { sheet.SelectedIndex = 0; await selectionRequest; }
    internal async Task SelectSheetForSmoke(string id) { sheet.SelectedItem = sheet.Items.OfType<Choice>().Single(item => item.Id == id); await selectionRequest; }
    internal async Task NextWindowForSmoke() { arrows.Single(item => item.Key == "next").Button.RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Button.ClickEvent)); await selectionRequest; }
    internal async Task ClickCellForSmoke(int requestedRow, int requestedColumn)
    {
        if (binding || !Cells.IsEnabled || !AuthorizesCell(requestedRow, requestedColumn)) throw new InvalidOperationException("The requested native cell is not authorized by a ready source window.");
        Cells.UpdateLayout(); var scroll = GridScroll ?? throw new InvalidOperationException("The native grid has no viewport.");
        var nativeRow = Descendants(Cells).OfType<DataGridRow>().FirstOrDefault(item => item.IsVisible && item.Item is GridRow model && model.Row == requestedRow);
        var index = requestedColumn - column + 1;
        if (index < 1 || index >= Cells.Columns.Count) throw new InvalidOperationException("The requested native source column is not installed.");
        var nativeCell = nativeRow is null ? null : Descendants(nativeRow).OfType<DataGridCell>().FirstOrDefault(item => item.IsVisible && ReferenceEquals(item.Column, Cells.Columns[index]));
        if (nativeCell is null || nativeCell.ActualWidth <= 0 || nativeCell.ActualHeight <= 0) throw new InvalidOperationException("The requested native cell is not currently materialized in the viewport.");
        DependencyObject? ancestor = nativeCell;
        while (ancestor is not null && ancestor is not ScrollContentPresenter && !ReferenceEquals(ancestor, Cells)) ancestor = VisualTreeHelper.GetParent(ancestor);
        if (ancestor is not ScrollContentPresenter viewport) throw new InvalidOperationException("The requested native cell has no visible scrolling content viewport.");
        var bounds = nativeCell.TransformToAncestor(Cells).TransformBounds(new Rect(0, 0, nativeCell.ActualWidth, nativeCell.ActualHeight));
        var visible = viewport.TransformToAncestor(Cells).TransformBounds(new Rect(0, 0, viewport.ActualWidth, viewport.ActualHeight));
        if (bounds.Left < Math.Max(Cells.Columns[0].ActualWidth, visible.Left) - .5 || bounds.Right > Math.Min(Cells.ActualWidth, visible.Right) + .5 || bounds.Top < Math.Max(0, visible.Top) - .5 || bounds.Bottom > Math.Min(Cells.ActualHeight, visible.Bottom) + .5) throw new InvalidOperationException("The requested native cell is clipped or outside the existing viewport.");
        var rowAt = row; var columnAt = column; var rows = Cells.ItemsSource; var x = scroll.HorizontalOffset; var y = scroll.VerticalOffset;
        // Exercise the production SelectedCellsChanged path without Go,
        // ScrollIntoView, a replacement source window, or a direct raw query.
        Cells.SelectedCells.Clear(); Cells.SelectedCells.Add(new DataGridCellInfo(nativeRow!.Item, nativeCell.Column)); await selectionRequest;
        if (row != rowAt || column != columnAt || !ReferenceEquals(rows, Cells.ItemsSource) || scroll.HorizontalOffset != x || scroll.VerticalOffset != y || focusedRow != requestedRow || focusedColumn != requestedColumn) throw new InvalidOperationException("Native cell selection moved the source window/viewport or failed to retain its physical focus.");
    }
    internal static string ColumnName(int column) { var name = ""; while (column > 0) { column--; name = (char)('A' + column % 26) + name; column /= 26; } return name; }
    internal async Task GoForSmoke(string cell) { address.Text = cell; await GoAddress(); }
}
