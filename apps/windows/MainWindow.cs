using System.Collections.ObjectModel;
using System.Globalization;
using System.IO;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Microsoft.Win32;

namespace Reviset.Windows;

internal sealed class MainWindow : Window
{
    internal readonly BridgeClient Bridge;
    internal readonly string PreferencesPath;
    internal AppPreferences Preferences { get; private set; }
    internal readonly Copy Copy = new();
    private readonly DockPanel root = new();
    private readonly Grid workspace = new() { Background = Brushes.White };
    private readonly Grid comparison = new();
    internal readonly Border SidebarPane = Pane();
    internal readonly Border ChangesPane = Pane();
    internal readonly Border InspectorPane = Pane();
    internal readonly ComparePane Before;
    internal readonly ComparePane After;
    private readonly ListBox projectList = new() { BorderThickness = new Thickness(0), HorizontalContentAlignment = HorizontalAlignment.Stretch };
    private readonly ListBox changeList = new() { BorderThickness = new Thickness(0), HorizontalContentAlignment = HorizontalAlignment.Stretch };
    private readonly ComboBox reports = new() { MinWidth = 180, MaxWidth = 390, Margin = new Thickness(6, 2, 12, 2) };
    private readonly TextBox detail = SourceText();
    private readonly TextBlock detailRange = new() { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(8) };
    private readonly TextBox detailMetadata = SourceText();
    private Button firstDetail = new();
    private Button nextDetail = new();
    private readonly CheckBox detailStyle = new() { Margin = new Thickness(8, 2, 8, 2) };
    private Button retryComparison = new();
    private Func<int, CancellationToken, Task<JsonElement>>? detailLoader;
    private int detailOffset;
    private int? detailNext;
    private string detailCursor = "";
    private string detailItemNext = "";
    private long detailGeneration;
    private bool changesReady;
    internal string ComparisonState { get; private set; } = "empty";
    private readonly TextBlock status = new() { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(12, 5, 12, 5), MaxHeight = 70 };
    private readonly TextBlock context = new() { FontSize = 12, Foreground = Brushes.DimGray, TextTrimming = TextTrimming.CharacterEllipsis, Margin = new Thickness(12, 2, 12, 5) };
    private readonly TextBlock intervalCaption = new() { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(10, 2, 10, 6), Foreground = Brushes.DimGray };
    private readonly ProgressBar progress = new() { Height = 3, IsIndeterminate = true, Visibility = Visibility.Collapsed };
    private readonly Menu menus = new();
    private readonly StackPanel toolbar = new() { Orientation = Orientation.Horizontal, Margin = new Thickness(6) };
    private readonly StackPanel reportBar = new() { Orientation = Orientation.Horizontal };
    private Button more = new();
    private readonly List<Action> relocalize = [];
    private CancellationTokenSource reads = new();
    private CancellationTokenSource cellReads = new();
    private CancellationTokenSource? operation;
    private long generation;
    private bool binding;
    private bool closed;
    private bool busy;
    private string projectId = "";
    private string reportId = "";
    private JsonElement currentProject;
    private JsonElement currentReport;
    private string nextChanges = "";
    private string intervalFrom = "";
    private string intervalTo = "";
    private readonly ObservableCollection<Choice> changes = [];
    private Button importButton = new();
    private Button analyzeButton = new();
    private Button reorderButton = new();
    private Button cancelButton = new();
    private Button exportButton = new();
    private Button mcpButton = new();
    private RadioButton documents = new();
    private RadioButton workbooks = new();
    private double lastLayoutWidth;
    private bool responsiveScheduled;
    internal bool IsWorkbook { get; private set; }
    internal WorkspaceLayout Layout => Preferences.For(IsWorkbook).Current;
    internal string ProjectId => projectId;
    internal string ReportId => reportId;
    internal JsonElement Report => currentReport;
    internal long Generation => generation;
    internal CancellationToken ReadToken => reads.Token;

    public MainWindow(BridgeClient bridge, string preferencesPath)
    {
        Bridge = bridge; PreferencesPath = preferencesPath; Preferences = AppPreferences.Load(preferencesPath); Copy.Language = Preferences.Language;
        Title = "Reviset"; Width = 1440; Height = 940; MinWidth = 1000; MinHeight = 640; Background = Brushes.WhiteSmoke;
        FontFamily = new FontFamily("Segoe UI"); FontSize = 13; Content = root;
        Before = new ComparePane(this, false); After = new ComparePane(this, true);
        BuildShell(); ApplyLayout(false); Localize();
        workspace.SizeChanged += (_, eventArgs) =>
        {
            if (!eventArgs.WidthChanged || Math.Abs(eventArgs.NewSize.Width - lastLayoutWidth) <= 1 || responsiveScheduled) return;
            responsiveScheduled = true; Dispatcher.BeginInvoke(System.Windows.Threading.DispatcherPriority.Loaded, () => { responsiveScheduled = false; if (!closed) ApplyLayout(false); });
        };
        Closing += (_, _) => { closed = true; reads.Cancel(); cellReads.Cancel(); operation?.Cancel(); SavePreferences(); };
    }

    private void BuildShell()
    {
        DockPanel.SetDock(menus, Dock.Top); root.Children.Add(menus);
        var languageMenu = new MenuItem { Header = "Language / 언어" };
        foreach (var language in new[] { "en", "ko" }) { var item = new MenuItem { Header = language == "en" ? "English" : "한국어", IsCheckable = true }; item.Click += (_, _) => SetLanguage(language); languageMenu.Items.Add(item); }
        menus.Items.Add(languageMenu);
        var actions = new MenuItem { Header = "Project / 프로젝트" }; menus.Items.Insert(0, actions);
        foreach (var command in new (string Key, Func<Task> Action)[] { ("import", Import), ("refresh", RefreshProjects), ("analyze", Analyze), ("reorder", Reorder), ("export", Export), ("mcp", CopyMcp) }) { var menuItem = new MenuItem(); BindText(menuItem, command.Key); var action = command.Action; menuItem.Click += async (_, _) => await Guard(action); actions.Items.Add(menuItem); }
        var layoutMenu = new MenuItem(); BindText(layoutMenu, "layout"); menus.Items.Add(layoutMenu); layoutMenu.SubmenuOpened += (_, _) => BuildLayoutMenu(layoutMenu);
        var modes = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(12, 4, 6, 4) };
        documents = new RadioButton { GroupName = "workspace", IsChecked = true, Margin = new Thickness(0, 0, 16, 0) }; BindText(documents, "documents");
        workbooks = new RadioButton { GroupName = "workspace" }; BindText(workbooks, "workbooks");
        documents.Checked += async (_, _) => { if (!binding && IsWorkbook) await Guard(() => SwitchWorkspace(false)); };
        workbooks.Checked += async (_, _) => { if (!binding && !IsWorkbook) await Guard(() => SwitchWorkspace(true)); };
        modes.Children.Add(documents); modes.Children.Add(workbooks); toolbar.Children.Add(modes);
        importButton = Command("import", Import); toolbar.Children.Add(importButton);
        analyzeButton = Command("analyze", Analyze); toolbar.Children.Add(analyzeButton);
        reorderButton = Command("reorder", Reorder);
        cancelButton = Command("cancel", () => { operation?.Cancel(); return Task.CompletedTask; }); toolbar.Children.Add(cancelButton);
        exportButton = Command("export", Export); toolbar.Children.Add(exportButton);
        mcpButton = Command("mcp", CopyMcp); toolbar.Children.Add(mcpButton);
        DockPanel.SetDock(toolbar, Dock.Top); root.Children.Add(toolbar);
        var reportCaption = new TextBlock { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(12, 0, 0, 0) }; BindText(reportCaption, "report"); reportBar.Children.Add(reportCaption); reportBar.Children.Add(reports);
        reports.SelectionChanged += async (_, _) => { if (!binding && reports.SelectedItem is Choice selected) await Guard(() => OpenReport(selected.Id)); };
        DockPanel.SetDock(reportBar, Dock.Top); root.Children.Add(reportBar);
        DockPanel.SetDock(context, Dock.Top); root.Children.Add(context);
        DockPanel.SetDock(progress, Dock.Top); root.Children.Add(progress);
        DockPanel.SetDock(status, Dock.Bottom); root.Children.Add(status);
        var side = new DockPanel(); var sideCaption = Caption("documents"); relocalize.Add(() => sideCaption.Text = Copy[IsWorkbook ? "workbooks" : "documents"]); DockPanel.SetDock(sideCaption, Dock.Top); side.Children.Add(sideCaption); side.Children.Add(projectList); SidebarPane.Child = side;
        projectList.SelectionChanged += async (_, _) => { if (!binding && projectList.SelectedItem is Choice choice) await Guard(() => OpenProject(choice.Value)); };
        var changeDock = new DockPanel(); var changeCaption = Caption("changes"); DockPanel.SetDock(changeCaption, Dock.Top); changeDock.Children.Add(changeCaption); DockPanel.SetDock(intervalCaption, Dock.Top); changeDock.Children.Add(intervalCaption);
        more = Command("more", LoadMoreChanges); DockPanel.SetDock(more, Dock.Bottom); changeDock.Children.Add(more);
        retryComparison = Command("retry", RetryComparison); retryComparison.Visibility = Visibility.Collapsed; DockPanel.SetDock(retryComparison, Dock.Bottom); changeDock.Children.Add(retryComparison);
        changeList.ItemsSource = changes; changeDock.Children.Add(changeList); ChangesPane.Child = changeDock;
        changeList.SelectionChanged += async (_, _) => { if (!binding && changeList.SelectedItem is Choice choice) await Guard(() => SelectChange(choice.Value)); };
        var inspector = new DockPanel(); var caption = Caption("evidence"); DockPanel.SetDock(caption, Dock.Top); inspector.Children.Add(caption);
        var paging = new StackPanel(); var pagingButtons = new WrapPanel(); firstDetail = Command("firstText", FirstDetail); nextDetail = Command("nextText", NextDetail); pagingButtons.Children.Add(firstDetail); pagingButtons.Children.Add(nextDetail); paging.Children.Add(pagingButtons); BindText(detailStyle, "styleDetail"); paging.Children.Add(detailStyle); detailStyle.Click += async (_, _) => await Guard(FirstDetail); paging.Children.Add(detailRange); DockPanel.SetDock(paging, Dock.Top); inspector.Children.Add(paging);
        var metadata = new Expander { Header = "Source metadata / 원본 메타데이터", IsExpanded = false, Content = detailMetadata, MaxHeight = 180 }; DockPanel.SetDock(metadata, Dock.Bottom); inspector.Children.Add(metadata); inspector.Children.Add(detail); InspectorPane.Child = inspector;
        root.Children.Add(workspace); ClearDetail(); SetBusy(false);
    }
    private static Border Pane() => new() { BorderBrush = new SolidColorBrush(Color.FromRgb(222, 226, 232)), BorderThickness = new Thickness(1), Background = Brushes.White, ClipToBounds = true };
    internal static TextBox SourceText() => new() { IsReadOnly = true, TextWrapping = TextWrapping.Wrap, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled, BorderThickness = new Thickness(0), Padding = new Thickness(10), FontFamily = new FontFamily("Consolas, Segoe UI") };
    private TextBlock Caption(string key) { var block = new TextBlock { FontWeight = FontWeights.SemiBold, Margin = new Thickness(10, 8, 10, 8) }; BindText(block, key); return block; }
    private Button Command(string key, Func<Task> action)
    {
        var button = new Button { Padding = new Thickness(10, 6, 10, 6), Margin = new Thickness(3), MinHeight = 30 }; BindText(button, key); button.Click += async (_, _) => await Guard(action); return button;
    }
    internal void BindText(FrameworkElement control, string key)
    {
        void Update() { switch (control) { case TextBlock text: text.Text = Copy[key]; break; case HeaderedItemsControl header: header.Header = Copy[key]; break; case ContentControl contentControl: contentControl.Content = Copy[key]; break; } }
        relocalize.Add(Update); Update();
    }
    internal async Task Guard(Func<Task> action)
    {
        try { await action(); }
        catch (OperationCanceledException) { if (!closed) status.Text = Copy["cancelled"]; }
        catch (Exception error) { if (!closed) { status.Text = error.Message; MessageBox.Show(this, error.Message, Copy["error"], MessageBoxButton.OK, MessageBoxImage.Error); } }
    }
    internal void SetLanguage(string language)
    {
        Copy.Language = language == "ko" ? "ko" : "en"; Preferences.Language = Copy.Language; Localize(); SavePreferences();
    }
    private void Localize()
    {
        foreach (var action in relocalize) action(); Before.Localize(); After.Localize();
        foreach (var splitter in NativeSplitters()) if (splitter.Tag is string key) { AutomationProperties.SetName(splitter, Copy[key]); splitter.ToolTip = Copy[key]; }
        if (!busy) status.Text = Copy["ready"]; UpdateContext(); UpdateInterval();
    }
    internal void SavePreferences()
    {
        try { Preferences.Save(PreferencesPath); } catch (Exception error) when (error is IOException or UnauthorizedAccessException) { status.Text = error.Message; }
    }
    internal void SetLayout(WorkspaceLayout layout) { Preferences.For(IsWorkbook).Current = layout.Bounded(); ApplyLayout(); }
    private void BuildLayoutMenu(MenuItem menu)
    {
        menu.Items.Clear();
        void Add(string key, Action action, bool check = false) { var item = new MenuItem { Header = Copy[key], IsCheckable = check }; item.Click += (_, _) => action(); menu.Items.Add(item); }
        foreach (var preset in new[] { "balanced", "focus", "review" }) { var name = preset; Add(name, () => SetLayout(WorkspaceLayout.Preset(name))); }
        menu.Items.Add(new Separator()); Add("sidebar", () => SetLayout(Layout with { Sidebar = !Layout.Sidebar })); Add("inspector", () => SetLayout(Layout with { Inspector = !Layout.Inspector })); Add("changes", () => SetLayout(Layout with { ChangesVisible = !Layout.ChangesVisible }));
        Add("changesBottom", () => SetLayout(Layout with { Changes = "bottom" })); Add("changesLeft", () => SetLayout(Layout with { Changes = "left" })); Add("changesRight", () => SetLayout(Layout with { Changes = "right" }));
        Add("inspectorLeft", () => SetLayout(Layout with { InspectorSide = "left" })); Add("inspectorRight", () => SetLayout(Layout with { InspectorSide = "right" })); Add("vertical", () => SetLayout(Layout with { VerticalComparison = !Layout.VerticalComparison }));
        menu.Items.Add(new Separator()); Add("saveLayout", SaveNamedLayout);
        var saved = new MenuItem { Header = Copy["applyLayout"] };
        foreach (var pair in Preferences.For(IsWorkbook).Named) { var layout = pair.Value; var item = new MenuItem { Header = new TextBlock { Text = pair.Key } }; item.Click += (_, _) => SetLayout(layout); saved.Items.Add(item); }
        saved.IsEnabled = saved.Items.Count != 0; menu.Items.Add(saved);
        var delete = new MenuItem { Header = Copy["deleteLayout"] }; foreach (var pair in Preferences.For(IsWorkbook).Named) { var name = pair.Key; var item = new MenuItem { Header = new TextBlock { Text = name } }; item.Click += (_, _) => { Preferences.For(IsWorkbook).Named.Remove(name); SavePreferences(); }; delete.Items.Add(item); } delete.IsEnabled = delete.Items.Count != 0; menu.Items.Add(delete);
        Add("reset", () => SetLayout(new()));
    }
    private void SaveNamedLayout()
    {
        var dialog = new Window { Owner = this, Title = Copy["saveLayout"], Width = 420, Height = 180, ResizeMode = ResizeMode.NoResize, WindowStartupLocation = WindowStartupLocation.CenterOwner };
        var stack = new StackPanel { Margin = new Thickness(16) }; var field = new TextBox { MaxLength = 48, Margin = new Thickness(0, 8, 0, 8) }; stack.Children.Add(new TextBlock { Text = Copy["layoutName"] }); stack.Children.Add(field);
        var save = new Button { Content = Copy["save"], IsDefault = true, Padding = new Thickness(12, 5, 12, 5), HorizontalAlignment = HorizontalAlignment.Right }; stack.Children.Add(save); dialog.Content = stack;
        save.Click += (_, _) => { var name = field.Text.Trim(); if (name.Length is < 1 or > 48 || name.Any(char.IsControl)) return; var named = Preferences.For(IsWorkbook).Named; if (!named.ContainsKey(name) && named.Count >= 12) { MessageBox.Show(dialog, "12", Copy["applyLayout"]); return; } named[name] = Layout; SavePreferences(); dialog.DialogResult = true; }; dialog.ShowDialog();
    }
    internal void ApplyLayout(bool save = true)
    {
        var focus = Keyboard.FocusedElement as UIElement;
        var beforeViewport = Before.CaptureViewport(); var afterViewport = After.CaptureViewport();
        var beforeGridViewport = Before.CaptureGridViewport(); var afterGridViewport = After.CaptureGridViewport();
        // Detach and reparent the exact existing panes. No model or pane recreation.
        foreach (var child in new UIElement[] { SidebarPane, ChangesPane, InspectorPane, Before.Host, After.Host, comparison }) if (System.Windows.Media.VisualTreeHelper.GetParent(child) is Panel parent) parent.Children.Remove(child);
        workspace.Children.Clear(); workspace.ColumnDefinitions.Clear(); workspace.RowDefinitions.Clear(); comparison.Children.Clear(); comparison.ColumnDefinitions.Clear(); comparison.RowDefinitions.Clear();
        var layout = Layout.Bounded();
        lastLayoutWidth = workspace.ActualWidth;
        var center = new Grid();
        if (layout.ChangesVisible && layout.Changes == "bottom")
        {
            center.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star), MinHeight = 180 }); center.RowDefinitions.Add(new RowDefinition { Height = new GridLength(5) }); center.RowDefinitions.Add(new RowDefinition { Height = new GridLength(Math.Min(layout.ChangesHeight, Math.Max(100, workspace.ActualHeight - 240))), MinHeight = 90 });
            center.Children.Add(comparison); Grid.SetRow(comparison, 0); Grid.SetColumn(comparison, 0); center.Children.Add(ChangesPane); Grid.SetRow(ChangesPane, 2); Grid.SetColumn(ChangesPane, 0);
            var splitter = Splitter(false, "resizeChanges", () => { Preferences.For(IsWorkbook).Current = (Layout with { ChangesHeight = center.RowDefinitions[2].ActualHeight }).Bounded(); SavePreferences(); }); Grid.SetRow(splitter, 1); center.Children.Add(splitter);
        }
        else { center.Children.Add(comparison); Grid.SetRow(comparison, 0); Grid.SetColumn(comparison, 0); }
        var columns = new List<(UIElement Element, double Width, string Role)>();
        if (layout.Sidebar) columns.Add((SidebarPane, layout.SidebarWidth, "sidebar"));
        if (layout.Inspector && layout.InspectorSide == "left") columns.Add((InspectorPane, layout.InspectorWidth, "inspector"));
        if (layout.ChangesVisible && layout.Changes == "left") columns.Add((ChangesPane, layout.ChangesWidth, "changes"));
        columns.Add((center, 0, "main"));
        if (layout.ChangesVisible && layout.Changes == "right") columns.Add((ChangesPane, layout.ChangesWidth, "changes"));
        if (layout.Inspector && layout.InspectorSide == "right") columns.Add((InspectorPane, layout.InspectorWidth, "inspector"));
        var preferredSideTotal = columns.Where(entry => entry.Role != "main").Sum(entry => entry.Width);
        var availableSides = Math.Max(0, (workspace.ActualWidth > 0 ? workspace.ActualWidth : Width) - 340 - (columns.Count - 1) * 5);
        var minimumSides = columns.Where(entry => entry.Role != "main").Sum(entry => entry.Role == "sidebar" ? 150d : 160d);
        var sideFactor = preferredSideTotal > minimumSides ? Math.Clamp((availableSides - minimumSides) / (preferredSideTotal - minimumSides), 0, 1) : 1;
        for (var index = 0; index < columns.Count; index++)
        {
            var entry = columns[index]; var columnIndex = workspace.ColumnDefinitions.Count;
            var minimum = entry.Role == "sidebar" ? 150 : 160;
            workspace.ColumnDefinitions.Add(new ColumnDefinition { Width = entry.Role == "main" ? new GridLength(1, GridUnitType.Star) : new GridLength(minimum + Math.Max(0, entry.Width - minimum) * sideFactor), MinWidth = entry.Role == "main" ? 300 : minimum });
            Grid.SetColumn(entry.Element, columnIndex); Grid.SetRow(entry.Element, 0); workspace.Children.Add(entry.Element);
            if (index < columns.Count - 1) { workspace.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(5) }); var leading = index; var role = entry.Role == "main" ? columns[index + 1].Role : entry.Role; var splitter = Splitter(true, role == "sidebar" ? "resizeSidebar" : role == "inspector" ? "resizeInspector" : "resizeChanges", () => { CaptureLayout(leading, leading + 1); SavePreferences(); }); Grid.SetColumn(splitter, columnIndex + 1); workspace.Children.Add(splitter); }
        }
        workspace.Tag = columns;
        if (layout.VerticalComparison)
        {
            comparison.RowDefinitions.Add(new RowDefinition { Height = new GridLength(layout.ComparisonRatio, GridUnitType.Star), MinHeight = 100 }); comparison.RowDefinitions.Add(new RowDefinition { Height = new GridLength(5) }); comparison.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1 - layout.ComparisonRatio, GridUnitType.Star), MinHeight = 100 });
            Grid.SetRow(Before.Host, 0); Grid.SetColumn(Before.Host, 0); Grid.SetRow(After.Host, 2); Grid.SetColumn(After.Host, 0); var splitter = Splitter(false, "resizeComparison", () => { CaptureLayout(); SavePreferences(); }); Grid.SetRow(splitter, 1); comparison.Children.Add(splitter);
        }
        else
        {
            comparison.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(layout.ComparisonRatio, GridUnitType.Star), MinWidth = 100 }); comparison.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(5) }); comparison.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1 - layout.ComparisonRatio, GridUnitType.Star), MinWidth = 100 });
            Grid.SetColumn(Before.Host, 0); Grid.SetRow(Before.Host, 0); Grid.SetColumn(After.Host, 2); Grid.SetRow(After.Host, 0); var splitter = Splitter(true, "resizeComparison", () => { CaptureLayout(); SavePreferences(); }); Grid.SetColumn(splitter, 1); comparison.Children.Add(splitter);
        }
        comparison.Children.Add(Before.Host); comparison.Children.Add(After.Host);
        Dispatcher.BeginInvoke(System.Windows.Threading.DispatcherPriority.Loaded, () => { Before.RestoreViewport(beforeViewport); After.RestoreViewport(afterViewport); Before.RestoreGridViewport(beforeGridViewport); After.RestoreGridViewport(afterGridViewport); });
        if (focus is not null) Dispatcher.BeginInvoke(() => { if (focus.IsVisible) focus.Focus(); });
        if (save) SavePreferences();
    }
    private GridSplitter Splitter(bool vertical, string name, Action persist)
    {
        var splitter = new GridSplitter { Background = new SolidColorBrush(Color.FromRgb(233, 236, 241)), HorizontalAlignment = HorizontalAlignment.Stretch, VerticalAlignment = VerticalAlignment.Stretch, ResizeDirection = vertical ? GridResizeDirection.Columns : GridResizeDirection.Rows, ResizeBehavior = GridResizeBehavior.PreviousAndNext, ShowsPreview = true, Focusable = true, KeyboardIncrement = 10 };
        AutomationProperties.SetName(splitter, Copy[name]); splitter.ToolTip = Copy[name]; splitter.Tag = name;
        splitter.DragCompleted += (_, _) => persist();
        splitter.AddHandler(Keyboard.KeyUpEvent, new KeyEventHandler((_, args) => { if (args.Key is Key.Left or Key.Right or Key.Up or Key.Down) persist(); }), true); return splitter;
    }
    private void CaptureLayout(int leading = -1, int trailing = -1)
    {
        var layout = Layout;
        if (workspace.Tag is List<(UIElement Element, double Width, string Role)> columns)
            for (var index = 0; index < columns.Count; index++) { if (index != leading && index != trailing) continue; var width = workspace.ColumnDefinitions[index * 2].ActualWidth; if (width <= 0) continue; layout = columns[index].Role switch { "sidebar" => layout with { SidebarWidth = width }, "inspector" => layout with { InspectorWidth = width }, "changes" => layout with { ChangesWidth = width }, _ => layout }; }
        var total = layout.VerticalComparison ? comparison.ActualHeight - 5 : comparison.ActualWidth - 5;
        if (total > 0) { var first = layout.VerticalComparison ? comparison.RowDefinitions.FirstOrDefault()?.ActualHeight ?? 0 : comparison.ColumnDefinitions.FirstOrDefault()?.ActualWidth ?? 0; layout = layout with { ComparisonRatio = first / total }; }
        Preferences.For(IsWorkbook).Current = layout.Bounded();
    }

    public async Task Initialize() => await Guard(async () => { await Bridge.Call("recover"); await Bridge.Call("workbookRecover"); await RefreshProjects(); });
    internal async Task SwitchWorkspace(bool workbook)
    {
        if (busy) return; SavePreferences(); IsWorkbook = workbook; binding = true; documents.IsChecked = !workbook; workbooks.IsChecked = workbook; binding = false;
        BeginScope(); projectId = ""; reportId = ""; currentReport = default; currentProject = default; binding = true; reports.ItemsSource = null; binding = false; ClearReport(); ApplyLayout(); Localize(); SetBusy(false); await RefreshProjects();
    }
    internal async Task RefreshProjects()
    {
        var ticket = generation; var workbook = IsWorkbook; var value = await Bridge.Call(workbook ? "workbookProjects" : "projects", token: reads.Token);
        if (ticket != generation || workbook != IsWorkbook) return;
        var items = value.Items().Select(v => Choice.From(v, "project_id", "title")).ToList();
        binding = true; projectList.ItemsSource = items; projectList.SelectedItem = items.Find(v => v.Id == projectId); binding = false;
        if (projectId.Length == 0) status.Text = Copy["chooseProject"];
    }
    internal async Task OpenProject(JsonElement project)
    {
        if (busy) return; var ticket = BeginScope(); currentProject = project; projectId = project.Get("project_id").Text(); reportId = ""; binding = true; reports.ItemsSource = null; binding = false; ClearReport(); UpdateContext();
        var value = await Bridge.Call(IsWorkbook ? "workbookReports" : "reports", new { project_id = projectId }, reads.Token);
        if (ticket != generation) return;
        var items = value.Items().Select(v => new Choice(v.Get("report_id").Text(), v.Get("created_at").Text() + " · " + v.Get("report_id").Text(), v)).ToList();
        binding = true; reports.ItemsSource = items; reports.SelectedIndex = items.Count > 0 ? 0 : -1; binding = false;
        if (items.Count > 0) await OpenReport(items[0].Id); else status.Text = Copy["noReport"]; SetBusy(false);
    }
    internal async Task OpenReport(string fixedReport)
    {
        if (busy || projectId.Length == 0 || fixedReport == "latest") return;
        var ticket = BeginScope(); reportId = fixedReport; currentReport = default; ClearReport();
        var value = await Bridge.Call(IsWorkbook ? "workbookView" : "view", Json.Scope(projectId, fixedReport), reads.Token);
        if (ticket != generation) return;
        if (value.Get("report_id").Text() != fixedReport || value.Get("project_id").Text() != projectId) throw new BridgeException("REPORT_SCOPE", "The report response is outside the selected fixed snapshot.");
        currentReport = value; var revisions = value.Get("revisions").Items();
        binding = true; Before.SetRevisions(revisions, 0); After.SetRevisions(revisions, Math.Max(0, revisions.Count - 1)); binding = false;
        UpdateContext(); await ReloadComparison(); SetBusy(false);
    }
    internal async Task ReloadComparison()
    {
        if (binding || reportId.Length == 0) return; var ticket = BeginScope();
        intervalFrom = Before.RevisionId; intervalTo = After.RevisionId; UpdateInterval();
        InvalidateAuthority(true); Before.Invalidate(); After.Invalidate();
        var revisions = currentReport.Get("revisions").Items(); var from = revisions.FindIndex(v => v.Get("revision_occurrence_id").Text() == intervalFrom); var to = revisions.FindIndex(v => v.Get("revision_occurrence_id").Text() == intervalTo);
        if (from < 0 || to < 0 || from > to) { ComparisonState = "invalid"; detail.Text = Copy["reverse"]; status.Text = Copy["reverse"]; return; }
        try { await Before.Load(ticket, reads.Token); if (ticket != generation) return; await After.Load(ticket, reads.Token); if (ticket != generation) return; await LoadChanges(false, ticket, reads.Token); }
        catch { if (IsCurrent(ticket) && !reads.IsCancellationRequested) FailComparison(); throw; }
    }
    internal Task RetryComparison()
    {
        if (reportId.Length == 0) return Task.CompletedTask;
        if (intervalFrom.Length > 0) Before.SetEvidenceRevision(intervalFrom);
        if (intervalTo.Length > 0) After.SetEvidenceRevision(intervalTo);
        // Restore normal selectors for retry; event absence must not substitute cells.
        Before.RestoreDefaultSelection(); After.RestoreDefaultSelection(); return ReloadComparison();
    }
    private void InvalidateAuthority(bool clearChanges)
    {
        changesReady = false; ComparisonState = "loading"; changeList.IsEnabled = false; more.IsEnabled = false; retryComparison.Visibility = Visibility.Collapsed; ClearDetail(); detail.Text = Copy["loading"];
        if (clearChanges) { binding = true; changeList.SelectedItem = null; changes.Clear(); binding = false; nextChanges = ""; }
    }
    private void FailComparison() { changesReady = false; ComparisonState = "failed"; changeList.IsEnabled = false; more.IsEnabled = false; Before.Invalidate("failed"); After.Invalidate("failed"); ClearDetail(); detail.Text = Copy["failed"]; retryComparison.Visibility = Visibility.Visible; }
    private long BeginScope() { reads.Cancel(); reads.Dispose(); reads = new(); cellReads.Cancel(); cellReads.Dispose(); cellReads = new(); return ++generation; }
    internal bool IsCurrent(long ticket) => !closed && ticket == generation;
    private void ClearReport() { InvalidateAuthority(true); ComparisonState = "empty"; binding = true; intervalFrom = ""; intervalTo = ""; UpdateInterval(); Before.Clear(); After.Clear(); detail.Text = Copy["selectCell"]; binding = false; }
    private string VersionLabel(string id) => currentReport.Get("revisions").Items().Find(v => v.Get("revision_occurrence_id").Text() == id).Get("label").Text();
    private void UpdateInterval() => intervalCaption.Text = intervalFrom.Length == 0 ? "" : Copy["interval"] + ": " + VersionLabel(intervalFrom) + " → " + VersionLabel(intervalTo);
    private void UpdateContext() { context.Text = projectId.Length == 0 ? Copy["chooseProject"] : currentProject.Get("title").Text() + "  ·  " + reportId + (currentReport.ValueKind == JsonValueKind.Undefined ? "" : "  ·  " + Copy["coverage"] + ": " + currentReport.Get("coverage_gap_count").Number(currentReport.Get("coverage_gaps").Items().Count)); }
    private void SetBusy(bool value)
    {
        busy = value; progress.Visibility = value ? Visibility.Visible : Visibility.Collapsed; cancelButton.IsEnabled = value; importButton.IsEnabled = !value; analyzeButton.IsEnabled = !value && projectId.Length > 0; reorderButton.IsEnabled = !value && !IsWorkbook && projectId.Length > 0; exportButton.IsEnabled = !value && reportId.Length > 0; mcpButton.IsEnabled = !value && reportId.Length > 0; documents.IsEnabled = !value; workbooks.IsEnabled = !value; projectList.IsEnabled = !value; reports.IsEnabled = !value; Before.NavigationEnabled(!value); After.NavigationEnabled(!value);
    }
    private async Task Import()
    {
        if (busy) return; var dialog = new ImportWindow(Copy, IsWorkbook) { Owner = this }; if (dialog.ShowDialog() != true) return;
        await ImportAndAnalyze(dialog.ProjectTitle, dialog.Rows.ToList());
    }
    internal async Task ImportAndAnalyze(string title, IReadOnlyList<ImportRow> rows)
    {
        if (busy) return; operation = new(); SetBusy(true); status.Text = Copy["importing"];
        try
        {
            var input = new List<object>(); foreach (var row in rows)
            {
                var hashes = new List<string>(); foreach (var path in row.Paths) hashes.Add(await ImportWindow.Identity(path, operation.Token));
                input.Add(IsWorkbook ? new { label = row.Label.Trim(), path = row.Paths[0], expected_sha256 = hashes[0] } : (object)new { label = row.Label.Trim(), files = row.Paths, expected_sha256 = hashes });
            }
            var project = await Bridge.Call(IsWorkbook ? "workbookCreate" : "create", new { title, revisions = input }, operation.Token);
            currentProject = project; projectId = project.Get("project_id").Text(); reportId = ""; BeginScope(); ClearReport();
            await AnalyzeCore(operation.Token);
        }
        finally { operation.Dispose(); operation = null; SetBusy(false); await RefreshProjects(); }
    }
    private async Task Analyze()
    {
        if (busy || projectId.Length == 0) return; operation = new(); SetBusy(true); BeginScope();
        try { await AnalyzeCore(operation.Token); }
        finally { operation.Dispose(); operation = null; SetBusy(false); }
    }
    private async Task AnalyzeCore(CancellationToken token)
    {
        var project = projectId; var workbook = IsWorkbook; status.Text = Copy["analyzing"]; var stage = await Bridge.Call(workbook ? "workbookAnalyze" : "analyze", new { project_id = project }, token, progress: value => Dispatcher.BeginInvoke(() => { if (!closed && busy) status.Text = Copy["analyzing"] + " " + value.Pretty(); }));
        status.Text = Copy["committing"];
        var saved = await AnalysisCommit.Save(project, workbook, stage, token, (action, args, cancel) => Bridge.Call(action, args, cancel));
        SetBusy(false); await OpenProject(currentProject); var fixedId = saved.Get("report_id").Text(); if (projectId == project && IsWorkbook == workbook && fixedId.Length > 0 && reportId != fixedId) await OpenReport(fixedId); status.Text = Copy["ready"];
    }
    private async Task Reorder()
    {
        if (busy || IsWorkbook || projectId.Length == 0) return;
        var projects = await Bridge.Call("projects"); var project = projects.Items().Find(v => v.Get("project_id").Text() == projectId); var dialog = new ImportWindow(Copy, false, project.Get("revisions").Items()) { Owner = this }; if (dialog.ShowDialog() != true) return;
        currentProject = await Bridge.Call("reorder", new { project_id = projectId, order = dialog.Rows.Select(v => v.OriginalIndex).ToArray(), draft_hash = project.Get("draft_hash").Text() }); await OpenProject(currentProject); await RefreshProjects();
    }
    private async Task Export()
    {
        if (reportId.Length == 0 || busy) return; var project = projectId; var report = reportId; var workbook = IsWorkbook; var language = Copy.Language;
        var folder = new OpenFolderDialog { Title = Copy["export"], Multiselect = false }; if (folder.ShowDialog(this) != true) return;
        operation = new(); SetBusy(true); try { await Bridge.Call(workbook ? "workbookExport" : "export", new { project_id = project, report_id = report, folder = folder.FolderName, language }, operation.Token); status.Text = Copy["exported"] + ": " + folder.FolderName; } finally { operation.Dispose(); operation = null; SetBusy(false); }
    }
    private async Task CopyMcp()
    {
        if (projectId.Length == 0 || busy) return; var ticket = generation; var project = projectId; var workbook = IsWorkbook;
        var config = await Bridge.Call(workbook ? "workbookMcpConfig" : "mcpConfig", new { project_id = project }, reads.Token);
        if (!IsCurrent(ticket) || projectId != project || IsWorkbook != workbook) return;
        Clipboard.SetText(config.Text()); status.Text = Copy["copied"];
    }
    internal async Task<JsonElement> McpConfig() => await Bridge.Call(IsWorkbook ? "workbookMcpConfig" : "mcpConfig", new { project_id = projectId });
    internal async Task<JsonElement> Query(string name, Dictionary<string, object?> args, CancellationToken token)
    { args["project_id"] = projectId; args["report_id"] = reportId; args["max_output_tokens"] = 8000; return await Bridge.Call("workbookQuery", new { name, args }, token); }
    private async Task LoadChanges(bool append, long ticket, CancellationToken token)
    {
        if (reportId.Length == 0 || intervalFrom.Length == 0 || intervalTo.Length == 0) return;
        var revisions = currentReport.Get("revisions").Items(); var from = revisions.FindIndex(v => v.Get("revision_occurrence_id").Text() == intervalFrom); var to = revisions.FindIndex(v => v.Get("revision_occurrence_id").Text() == intervalTo);
        if (from > to || from < 0 || to < 0) { if (IsCurrent(ticket)) { ComparisonState = "invalid"; changesReady = false; detail.Text = Copy["reverse"]; } return; }
        if (from == to) { if (IsCurrent(ticket)) { changes.Clear(); changesReady = true; ComparisonState = "ready"; changeList.IsEnabled = true; more.IsEnabled = false; detail.Text = Copy["noChanges"]; } return; }
        List<JsonElement> values; string next = "";
        if (IsWorkbook)
        {
            var args = new Dictionary<string, object?> { ["from_revision_occurrence_id"] = intervalFrom, ["to_revision_occurrence_id"] = intervalTo, ["mode"] = "history", ["limit"] = 100, ["text_length"] = 256 };
            if (append && nextChanges.Length > 0) args["cursor"] = nextChanges;
            var result = await Query("list_workbook_changes", args, token); values = result.Get("items").Items(); next = result.Get("next_cursor").Text();
        }
        else { values = (await Bridge.Call("changes", new { project_id = projectId, report_id = reportId, from = intervalFrom, to = intervalTo, mode = "history" }, token)).Items(); }
        if (!IsCurrent(ticket)) return; binding = true; if (!append) changes.Clear();
        foreach (var value in values) { var label = value.Get("kind").Text() + " · " + (IsWorkbook ? value.Get("description").Text() : value.Get("before").Text() + " → " + value.Get("after").Text()); changes.Add(new(value.Get("change_id").Text(), label.Length > 210 ? label[..210] + "…" : label, value)); }
        binding = false; nextChanges = next; changesReady = true; ComparisonState = "ready"; changeList.IsEnabled = true; more.IsEnabled = next.Length > 0; if (changes.Count == 0) detail.Text = Copy["noChanges"] + "\n\n" + Copy["coverage"] + "\n" + currentReport.Get("coverage_gaps").Pretty();
    }
    private async Task LoadMoreChanges()
    {
        if (!changesReady || !more.IsEnabled) return; more.IsEnabled = false; var ticket = generation;
        try { await LoadChanges(true, ticket, reads.Token); } catch { if (IsCurrent(ticket) && !reads.IsCancellationRequested) FailComparison(); throw; }
    }
    private async Task SelectChange(JsonElement change)
    {
        if (!changesReady || !changes.Any(c => c.Id == change.Get("change_id").Text())) return;
        var ticket = BeginScope(); var token = reads.Token;
        InvalidateAuthority(false); Before.Invalidate(); After.Invalidate();
        try {
        if (IsWorkbook)
        {
            var args = new Dictionary<string, object?> { ["change_id"] = change.Get("change_id").Text(), ["text_length"] = 4096, ["component"] = "before", ["from_revision_occurrence_id"] = change.Get("from_revision_occurrence_id").Text(), ["to_revision_occurrence_id"] = change.Get("to_revision_occurrence_id").Text() };
            var before = await Query("get_workbook_change", args, token); args["component"] = "after"; var after = await Query("get_workbook_change", args, token); if (!IsCurrent(ticket) || token.IsCancellationRequested) return;
            var beforeCell = before.Get("items").Items().FirstOrDefault().Get("before"); var afterCell = after.Get("items").Items().FirstOrDefault().Get("after");
            Before.SetEvidenceRevision(change.Get("from_revision_occurrence_id").Text(), change.Get("from_sheet_id").Text(), beforeCell); After.SetEvidenceRevision(change.Get("to_revision_occurrence_id").Text(), change.Get("to_sheet_id").Text(), afterCell);
            await Before.Load(ticket, token); await After.Load(ticket, token); if (!IsCurrent(ticket)) return;
            var project = projectId; var report = reportId;
            detailStyle.IsEnabled = false; detailLoader = async (offset, cancel) => { var request = new Dictionary<string, object?>(args) { ["text_offset"] = offset, ["component"] = "before" }; var a = await QueryFixed("get_workbook_change", request, project, report, cancel); request["component"] = "after"; var b = await QueryFixed("get_workbook_change", request, project, report, cancel); return JsonSerializer.SerializeToElement(new { before = a, after = b }); };
            await LoadDetail(0);
        }
        else
        {
            Before.SetEvidenceRevision(change.Get("from_occurrence").Text()); After.SetEvidenceRevision(change.Get("to_occurrence").Text());
            var evidence = change.Get("evidence").Items();
            var beforePage = evidence.Select(v => v.Get("page_id").Text()).FirstOrDefault(id => Before.HasPage(id)); var afterPage = evidence.Select(v => v.Get("page_id").Text()).FirstOrDefault(id => After.HasPage(id)); Before.SetEventPage(beforePage); After.SetEventPage(afterPage);
            await Before.Load(ticket, token); await After.Load(ticket, token); if (!IsCurrent(ticket)) return;
            detail.Text = Copy["event"] + ": " + VersionLabel(Before.RevisionId) + " → " + VersionLabel(After.RevisionId) + "\n\n" + Copy["before"] + "\n" + change.Get("before").Text() + "\n\n" + Copy["after"] + "\n" + change.Get("after").Text() + "\n\n" + Copy["evidence"] + "\n" + change.Get("evidence").Pretty() + "\n\n" + Copy["coverage"] + "\n" + change.Get("coverage_gaps").Pretty();
        }
        if (IsCurrent(ticket)) { changesReady = true; ComparisonState = "ready"; changeList.IsEnabled = true; more.IsEnabled = nextChanges.Length > 0; }
        } catch { if (IsCurrent(ticket) && !token.IsCancellationRequested) FailComparison(); throw; }
    }
    internal async Task CheckIntermediateEventForSmoke()
    {
        var revisions = currentReport.Get("revisions").Items(); if (revisions.Count < 3) throw new InvalidOperationException("An intermediate event needs three revisions");
        var first = revisions[0].Get("revision_occurrence_id").Text(); var middle = revisions[1].Get("revision_occurrence_id").Text(); var fromKey = IsWorkbook ? "from_revision_occurrence_id" : "from_occurrence"; var toKey = IsWorkbook ? "to_revision_occurrence_id" : "to_occurrence";
        var selected = changes.FirstOrDefault(c => c.Value.Get(fromKey).Text() == first && c.Value.Get(toKey).Text() == middle) ?? throw new InvalidOperationException("Intermediate fixture event is missing"); var intervalA = intervalFrom; var intervalB = intervalTo; var count = changes.Count;
        await SelectChange(selected.Value);
        if (Before.RevisionId != first || After.RevisionId != middle || intervalFrom != intervalA || intervalTo != intervalB || changes.Count != count) throw new InvalidOperationException("Event evidence changed the change-list interval or displayed wrong source occurrences");
    }
    internal async Task SelectCell(ComparePane pane, int row, int column)
    {
        if (!IsWorkbook || ComparisonState != "ready" || !pane.AuthorizesCell(row, column)) return;
        var args = new Dictionary<string, object?> { ["revision_occurrence_id"] = pane.RevisionId, ["sheet_id"] = pane.SheetId, ["row"] = row, ["column"] = column, ["text_length"] = 4096 };
        var project = projectId; var report = reportId; ClearDetail(); detailStyle.IsEnabled = true; detailLoader = (offset, cancel) => { var request = new Dictionary<string, object?>(args) { ["text_offset"] = offset, ["component"] = detailStyle.IsChecked == true ? "style" : "cell", ["limit"] = 1 }; if (detailStyle.IsChecked == true && detailCursor.Length > 0) request["cursor"] = detailCursor; return QueryFixed("get_workbook_cell", request, project, report, cancel); }; await LoadDetail(0);
    }
    private Task<JsonElement> QueryFixed(string name, Dictionary<string, object?> args, string project, string report, CancellationToken token) { args["project_id"] = project; args["report_id"] = report; args["max_output_tokens"] = 8000; return Bridge.Call("workbookQuery", new { name, args }, token); }
    private void ClearDetail() { ++detailGeneration; cellReads.Cancel(); detailLoader = null; detailNext = null; detailOffset = 0; detailCursor = ""; detailItemNext = ""; detailStyle.IsChecked = false; detailStyle.IsEnabled = false; detailRange.Text = ""; detailMetadata.Text = ""; firstDetail.IsEnabled = false; nextDetail.IsEnabled = false; }
    private Task FirstDetail() { detailCursor = ""; return LoadDetail(0); }
    private Task NextDetail() { if (detailNext is { } offset) return LoadDetail(offset); if (detailItemNext.Length > 0) { detailCursor = detailItemNext; return LoadDetail(0); } return Task.CompletedTask; }
    private async Task LoadDetail(int offset)
    {
        if (detailLoader is not { } loader) return; var sequence = ++detailGeneration; var ticket = generation; cellReads.Cancel(); cellReads.Dispose(); cellReads = new(); var token = cellReads.Token; firstDetail.IsEnabled = false; nextDetail.IsEnabled = false; detail.Text = Copy["loading"];
        try { var value = await loader(offset, token); if (!IsCurrent(ticket) || sequence != detailGeneration || token.IsCancellationRequested) return; detailOffset = offset; detailNext = RawSourcePaging.Next(value, offset); detailItemNext = value.Get("next_cursor").Text(); detail.Text = FormatDetail(value); detailRange.Text = Copy["textRange"] + ": " + offset + " → " + (detailNext?.ToString(CultureInfo.InvariantCulture) ?? "✓"); detailMetadata.Text = value.Pretty(); firstDetail.IsEnabled = offset > 0 || detailCursor.Length > 0; nextDetail.IsEnabled = detailNext is not null || detailItemNext.Length > 0; }
        catch { if (IsCurrent(ticket) && sequence == detailGeneration && !token.IsCancellationRequested) { detail.Text = Copy["failed"]; firstDetail.IsEnabled = true; } throw; }
    }
    private string FormatDetail(JsonElement value)
    {
        string Cell(JsonElement source)
        {
            if (source.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined) return Copy["missing"];
            return source.Get("address").Text() + "\n\n" + Copy["cached"] + ":\n" + source.Get("value").Text() + "\n\n" + Copy["formula"] + ":\n" + source.Get("formula").Text() + "\n\nnumber_format:\n" + source.Get("number_format").Text() + "\n\ncache_freshness: " + source.Get("cache_freshness").Text() + "\ncached_result: " + source.Get("cached_result").Pretty();
        }
        if (value.Get("before").ValueKind == JsonValueKind.Object) return Copy["before"] + "\n" + Cell(value.Get("before").Get("items").Items().FirstOrDefault().Get("before")) + "\n\n" + Copy["after"] + "\n" + Cell(value.Get("after").Get("items").Items().FirstOrDefault().Get("after"));
        if (value.Get("component").Text() == "style") return string.Join("\n\n", value.Get("items").Items().Select(item => item.Get("key").Text() + "\n" + item.Get("value").Text()));
        return Cell(value.Get("items").Items().FirstOrDefault());
    }
    internal IEnumerable<GridSplitter> NativeSplitters()
    {
        IEnumerable<DependencyObject> Visit(DependencyObject parent) { for (var index = 0; index < VisualTreeHelper.GetChildrenCount(parent); index++) { var child = VisualTreeHelper.GetChild(parent, index); yield return child; foreach (var nested in Visit(child)) yield return nested; } }
        return Visit(workspace).OfType<GridSplitter>();
    }
    internal int ActionableChanges => changesReady && changeList.IsEnabled ? changes.Count : 0;
    internal string DetailText => detail.Text;
    internal async Task CheckFailedGridForSmoke(Func<Task> corrupt, Func<Task> restore)
    {
        await corrupt();
        try
        {
            var loading = ReloadComparison();
            if (Before.Cells.Items.Count != 0 || Before.Cells.IsEnabled || Before.AuthorizesCell(Before.SelectedRow, Before.SelectedColumn) || ActionableChanges != 0 || nextDetail.IsEnabled) throw new InvalidOperationException("Old source remained actionable while a new grid scope was loading.");
            try { await loading; throw new InvalidOperationException("Corrupt indexed cell unexpectedly loaded."); } catch (BridgeException) { }
            if (Before.ReadState != "failed" || Before.Cells.Items.Count != 0 || ComparisonState != "failed" || ActionableChanges != 0 || retryComparison.Visibility != Visibility.Visible) throw new InvalidOperationException("Failed scoped grid retained stale payload or looked empty-success.");
            await SelectCell(Before, Before.SelectedRow, Before.SelectedColumn); if (detail.Text != Copy["failed"]) throw new InvalidOperationException("Failed grid selection replaced unavailable evidence.");
        }
        finally { await restore(); }
        await RetryComparison(); if (Before.ReadState != "ready" || ComparisonState != "ready") throw new InvalidOperationException("Scoped retry did not recover the selected comparison.");
    }
    internal async Task CheckFailedDetailForSmoke(Func<Task> corrupt, Func<Task> restore)
    {
        if (detailNext is null) throw new InvalidOperationException("Long source fixture did not expose a native continuation.");
        await corrupt(); try { try { await NextDetail(); throw new InvalidOperationException("Corrupt raw continuation unexpectedly loaded."); } catch (BridgeException) { } if (detail.Text != Copy["failed"] || nextDetail.IsEnabled) throw new InvalidOperationException("Failed continuation retained authoritative old source text."); } finally { await restore(); }
        await FirstDetail(); if (detailOffset != 0 || detailNext is null) throw new InvalidOperationException("Raw first/retry did not restore the exact selected source.");
    }
    internal async Task SelectSourcePairForSmoke(int before, int after)
    {
        var versions = currentReport.Get("revisions").Items(); Before.SetEvidenceRevision(versions[before].Get("revision_occurrence_id").Text()); After.SetEvidenceRevision(versions[after].Get("revision_occurrence_id").Text()); Before.RestoreDefaultSelection(); After.RestoreDefaultSelection(); await ReloadComparison();
    }
    internal async Task CheckOrderAndAbsenceForSmoke()
    {
        var versions = currentReport.Get("revisions").Items(); var first = versions.First().Get("revision_occurrence_id").Text(); var last = versions.Last().Get("revision_occurrence_id").Text();
        Before.SetEvidenceRevision(last); After.SetEvidenceRevision(first); await ReloadComparison(); if (ComparisonState != "invalid" || ActionableChanges != 0 || detail.Text != Copy["reverse"]) throw new InvalidOperationException("Reverse interval was presented as an empty success.");
        Before.SetEvidenceRevision(first); After.SetEvidenceRevision(last); Before.RestoreDefaultSelection(); After.RestoreDefaultSelection(); await ReloadComparison();
        if (IsWorkbook)
        {
            Before.SetEvidenceRevision(first, ""); await Before.Load(generation, reads.Token); if (Before.SheetId.Length != 0 || Before.ReadState != "absent" || Before.Cells.Items.Count != 0 || Before.AuthorizesCell(1, 1)) throw new InvalidOperationException("Absent evidence substituted a real sheet/cell.");
            Before.SetEvidenceRevision(first, "unknown_sheet_id"); await Before.Load(generation, reads.Token); if (Before.SheetId.Length != 0 || Before.ReadState != "absent" || Before.Cells.Items.Count != 0) throw new InvalidOperationException("Unknown evidence substituted a real sheet/cell.");
            await RetryComparison();
            var absent = changes.FirstOrDefault(c => c.Value.Get("from_sheet_id").Text().Length == 0 || c.Value.Get("to_sheet_id").Text().Length == 0);
            if (absent is null) throw new InvalidOperationException("Expected a genuine one-sided sheet event fixture.");
            await SelectChange(absent.Value);
            if (absent.Value.Get("from_sheet_id").Text().Length == 0 && (Before.ReadState != "absent" || Before.SheetId.Length != 0 || Before.Cells.Items.Count != 0)) throw new InvalidOperationException("One-sided before event invented a grid.");
            if (absent.Value.Get("to_sheet_id").Text().Length == 0 && (After.ReadState != "absent" || After.SheetId.Length != 0 || After.Cells.Items.Count != 0)) throw new InvalidOperationException("One-sided after event invented a grid.");
            await SelectSourcePairForSmoke(0, versions.Count - 1);
        }
    }
    internal async Task<string> ReadCellForSmoke(int versionIndex, string cell, string field)
    {
        var occurrence = currentReport.Get("revisions").Items()[versionIndex].Get("revision_occurrence_id").Text(); Before.SetEvidenceRevision(occurrence); After.SetEvidenceRevision(occurrence); Before.RestoreDefaultSelection(); After.RestoreDefaultSelection(); await ReloadComparison(); await Before.GoForSmoke(cell);
        var text = new System.Text.StringBuilder(); var offset = 0; var visited = new HashSet<int>();
        do
        {
            if (!visited.Add(offset) || visited.Count > 1000) throw new InvalidOperationException("Raw source continuation loop.");
            await LoadDetail(offset); var page = JsonSerializer.Deserialize<JsonElement>(detailMetadata.Text); var source = page.Get("items").Items().FirstOrDefault(); var continuation = source.Get("text_continuations").Get(field); var at = continuation.Get("offset").Number(); var fragment = source.Get(field).Text();
            if (at > text.Length) throw new InvalidOperationException("Raw source continuation skipped UTF16 units."); if (at + fragment.Length > text.Length) text.Append(fragment.AsSpan(Math.Max(0, text.Length - at)));
            if (detailNext is null) break; offset = detailNext.Value;
        } while (true);
        if (detailOffset > 0) { await LoadDetail(0); if (detailOffset != 0) throw new InvalidOperationException("First source segment did not reset."); }
        return text.ToString();
    }
    internal async Task ExportForSmoke(string folder) => await Bridge.Call(IsWorkbook ? "workbookExport" : "export", new { project_id = projectId, report_id = reportId, folder, language = Copy.Language });
    internal void ReloadPreferencesForSmoke() { Preferences = AppPreferences.Load(PreferencesPath); Copy.Language = Preferences.Language; ApplyLayout(false); Localize(); }
}
