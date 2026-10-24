using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Data;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Microsoft.Win32;

namespace Reviset.Windows;

internal sealed class MainWindow : Window
{
    private sealed class ChangeChoice(string id, string caption, JsonElement value) : INotifyPropertyChanged
    {
        public string Id { get; } = id;
        public JsonElement Value { get; } = value;
        public string Caption { get; private set; } = caption;
        public string Title => Caption.Split('\n')[0];
        public string Location => Caption.Split('\n').ElementAtOrDefault(1) ?? "";
        public string Preview => string.Join(" ", Caption.Split('\n').Skip(2));
        public event PropertyChangedEventHandler? PropertyChanged;
        public void Relabel(string text) { Caption = text; foreach (var name in new[] { nameof(Caption), nameof(Title), nameof(Location), nameof(Preview) }) PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name)); }
    }
    internal readonly BridgeClient Bridge;
    internal readonly string PreferencesPath;
    internal AppPreferences Preferences { get; private set; }
    internal readonly Copy Copy = new();
    private readonly DockPanel root = new();
    private readonly Grid workspace = new() { Background = Brushes.White };
    private readonly Grid comparison = new();
    private readonly DockPanel sourceStage = new();
    private readonly RichTextBox unified = new() { IsReadOnly = true, BorderThickness = new Thickness(0), FontFamily = new FontFamily("Consolas, Segoe UI"), FontSize = 13, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, Visibility = Visibility.Collapsed };
    private readonly TextBlock sourceNotice = new() { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(10, 3, 10, 4), Foreground = Brushes.DimGray, FontSize = 12 };
    private Button selectedLimitsButton = new();
    private readonly ComboBox sourceView = new() { Width = 155, Margin = new Thickness(4, 2, 4, 2) };
    private readonly StackPanel rawTextPaging = new() { Orientation = Orientation.Horizontal, Visibility = Visibility.Collapsed };
    private readonly CheckBox sourceDiagnostics = new() { Margin = new Thickness(10, 5, 4, 5), VerticalAlignment = VerticalAlignment.Center };
    private Button reportDetailsButton = new();
    private Button firstTextStage = new();
    private Button nextTextStage = new();
    private readonly ComboBox queryBefore = new() { Width = 145, Margin = new Thickness(4, 2, 0, 2) };
    private readonly ComboBox queryAfter = new() { Width = 145, Margin = new Thickness(0, 2, 4, 2) };
    private readonly TextBlock projectCaption = new() { VerticalAlignment = VerticalAlignment.Center, FontWeight = FontWeights.SemiBold, MaxWidth = 190, TextTrimming = TextTrimming.CharacterEllipsis, Margin = new Thickness(8, 0, 8, 0) };
    private readonly TextBlock sourcePair = new() { VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis, Margin = new Thickness(8, 0, 4, 0), FontSize = 12 };
    private Button previousChange = new();
    private Button nextChange = new();
    private Button returnChange = new();
    private Button versionsButton = new();
    private JsonElement selectedChange;
    private PaneSelection? selectedBefore;
    private PaneSelection? selectedAfter;
    private bool textView;
    private bool singleSource;
    internal readonly Border SidebarPane = Pane();
    internal readonly Border ChangesPane = Pane();
    internal readonly Border InspectorPane = Pane();
    internal readonly ComparePane Before;
    internal readonly ComparePane After;
    private readonly ListBox projectList = new() { BorderThickness = new Thickness(0), HorizontalContentAlignment = HorizontalAlignment.Stretch };
    private readonly ListBox changeList = new() { BorderThickness = new Thickness(0), HorizontalContentAlignment = HorizontalAlignment.Stretch };
    private readonly ComboBox reports = new() { Width = 245, Height = 30, VerticalContentAlignment = VerticalAlignment.Center, Margin = new Thickness(4, 2, 3, 2) };
    private readonly TextBox detail = SourceText();
    private readonly TextBlock detailRange = new() { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(8) };
    private readonly StackPanel detailPaging = new();
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
    private JsonElement detailPayload;
    private JsonElement documentDetail;
    private string inspectorMode = "prompt";
    private bool changesReady;
    internal string ComparisonState { get; private set; } = "empty";
    private readonly TextBlock status = new() { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(12, 5, 12, 5), MaxHeight = 70 };
    private readonly TextBlock context = new() { FontSize = 12, Foreground = Brushes.DimGray, TextTrimming = TextTrimming.CharacterEllipsis, Margin = new Thickness(12, 2, 12, 5) };
    private readonly TextBlock intervalCaption = new() { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(10, 2, 10, 6), Foreground = Brushes.DimGray };
    private readonly ProgressBar progress = new() { Height = 3, IsIndeterminate = true, Visibility = Visibility.Collapsed };
    private readonly Menu menus = new();
    private readonly Dictionary<string, MenuItem> languageItems = [];
    private readonly Dictionary<string, MenuItem> actionItems = [];
    private readonly ComboBox comparisonMode = new() { Width = 160, Margin = new Thickness(4, 2, 8, 2) };
    private bool documentNet = true;
    private bool workbookNet = true;
    private bool NetMode => IsWorkbook ? workbookNet : documentNet;
    private Task modeRequest = Task.CompletedTask;
    private Task reportRequest = Task.CompletedTask;
    private Task endpointRequest = Task.CompletedTask;
    private readonly WrapPanel toolbar = new() { Margin = new Thickness(6, 2, 6, 2) };
    private readonly WrapPanel reportBar = new() { Margin = new Thickness(6, 1, 6, 3) };
    private Button more = new();
    private readonly List<Action> relocalize = [];
    private CancellationTokenSource reads = new();
    private CancellationTokenSource cellReads = new();
    private CancellationTokenSource? operation;
    private long generation;
    private bool binding;
    private bool closed;
    private bool busy;
    private bool initializing = true;
    private bool restoringOperation;
    private bool projectChoicesReady;
    private long projectChoicesGeneration;
    private CancellationTokenSource? projectChoicesRead;
    private sealed record ComparisonSelection(string Project, string Report, bool Workbook, JsonElement Draft, JsonElement Snapshot, PaneSelection Before, PaneSelection After, string IntervalFrom, string IntervalTo, double BeforeX, double BeforeY, double AfterX, double AfterY);
    private string projectId = "";
    private string reportId = "";
    private JsonElement currentProject;
    private JsonElement currentReport;
    private string nextChanges = "";
    private string intervalFrom = "";
    private string intervalTo = "";
    private readonly ObservableCollection<ChangeChoice> changes = [];
    private Button importButton = new();
    private Button analyzeButton = new();
    private Button reorderButton = new();
    private Button cancelButton = new();
    private Button exportButton = new();
    private Button mcpButton = new();
    private RadioButton documents = new();
    private RadioButton workbooks = new();
    private double lastLayoutWidth;
    private double lastLayoutHeight;
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
            if (responsiveScheduled || (!eventArgs.WidthChanged || Math.Abs(eventArgs.NewSize.Width - lastLayoutWidth) <= 1) && (!eventArgs.HeightChanged || Math.Abs(eventArgs.NewSize.Height - lastLayoutHeight) <= 1)) return;
            responsiveScheduled = true; Dispatcher.BeginInvoke(System.Windows.Threading.DispatcherPriority.Loaded, () => { responsiveScheduled = false; if (!closed) ApplyLayout(false); });
        };
        Closing += (_, _) => { closed = true; CancelProjectChoices(); reads.Cancel(); cellReads.Cancel(); operation?.Cancel(); SavePreferences(); };
    }

    private void BuildShell()
    {
        DockPanel.SetDock(menus, Dock.Top); root.Children.Add(menus);
        var languageMenu = new MenuItem { Header = "Language / 언어" };
        foreach (var language in new[] { "en", "ko" }) { var item = new MenuItem { Header = language == "en" ? "English" : "한국어", IsCheckable = true }; item.Click += (_, _) => SetLanguage(language); languageItems[language] = item; languageMenu.Items.Add(item); }
        menus.Items.Add(languageMenu);
        var actions = new MenuItem(); BindText(actions, "projectMenu"); menus.Items.Insert(0, actions);
        foreach (var command in new (string Key, Func<Task> Action)[] { ("import", Import), ("refresh", RefreshProjects), ("analyze", Analyze), ("reorder", Reorder), ("export", Export), ("mcp", CopyMcp) }) { var menuItem = new MenuItem(); BindText(menuItem, command.Key); var action = command.Action; menuItem.Click += async (_, _) => await Guard(action); actions.Items.Add(menuItem); actionItems[command.Key] = menuItem; }
        var layoutMenu = new MenuItem(); BindText(layoutMenu, "layout"); menus.Items.Add(layoutMenu); layoutMenu.SubmenuOpened += (_, _) => BuildLayoutMenu(layoutMenu);
        var modes = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(12, 4, 6, 4) };
        documents = new RadioButton { GroupName = "workspace", IsChecked = true, Margin = new Thickness(0, 0, 16, 0) }; BindText(documents, "documents");
        workbooks = new RadioButton { GroupName = "workspace" }; BindText(workbooks, "workbooks");
        documents.Checked += async (_, _) => { if (!binding && IsWorkbook) await Guard(() => SwitchWorkspace(false)); };
        workbooks.Checked += async (_, _) => { if (!binding && !IsWorkbook) await Guard(() => SwitchWorkspace(true)); };
        modes.Children.Add(documents); modes.Children.Add(workbooks); toolbar.Children.Add(modes);
        toolbar.Children.Add(Command("projects", () => { SetLayout(Layout with { Sidebar = !Layout.Sidebar }); return Task.CompletedTask; }));
        toolbar.Children.Add(projectCaption);
        importButton = Command("import", Import);
        analyzeButton = Command("analyze", Analyze);
        reorderButton = Command("reorder", Reorder);
        cancelButton = Command("cancel", () => { operation?.Cancel(); return Task.CompletedTask; }); toolbar.Children.Add(cancelButton);
        exportButton = Command("export", Export);
        mcpButton = Command("mcp", CopyMcp);
        var reportCaption = new TextBlock { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(8, 0, 0, 0) }; BindText(reportCaption, "report"); toolbar.Children.Add(reportCaption); toolbar.Children.Add(reports);
        reportDetailsButton = Command("reportDetails", () => { CreateReportDetailsDialog().ShowDialog(); return Task.CompletedTask; }); toolbar.Children.Add(reportDetailsButton);
        toolbar.Children.Add(Command("evidence", () => { SetLayout(Layout with { Inspector = !Layout.Inspector }); return Task.CompletedTask; }));
        DockPanel.SetDock(toolbar, Dock.Top); root.Children.Add(toolbar);
        versionsButton = Command("versions", ShowVersions); reportBar.Children.Add(versionsButton);
        var intervalLabel = new TextBlock { VerticalAlignment = VerticalAlignment.Center }; BindText(intervalLabel, "interval"); reportBar.Children.Add(intervalLabel); reportBar.Children.Add(queryBefore); reportBar.Children.Add(new TextBlock { Text = "→", VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(5) }); reportBar.Children.Add(queryAfter); reportBar.Children.Add(comparisonMode);
        reportBar.Children.Add(Command("changes", () => { SetLayout(Layout with { ChangesVisible = !Layout.ChangesVisible }); return Task.CompletedTask; }));
        queryBefore.SelectionChanged += async (_, _) => { if (!binding && queryBefore.SelectedItem is Choice choice) { endpointRequest = ChooseEndpoint(false, choice.Id); await Guard(() => endpointRequest); } };
        queryAfter.SelectionChanged += async (_, _) => { if (!binding && queryAfter.SelectedItem is Choice choice) { endpointRequest = ChooseEndpoint(true, choice.Id); await Guard(() => endpointRequest); } };
        comparisonMode.SelectionChanged += async (_, _) => { if (!binding && comparisonMode.SelectedItem is Choice selected) { modeRequest = ChangeComparisonMode(selected.Id == "range_net"); await Guard(() => modeRequest); } };
        reports.SelectionChanged += async (_, _) => { if (!binding && reports.SelectedItem is Choice selected) { var request = OpenReport(selected.Id); reportRequest = request; await Guard(() => request); } };
        DockPanel.SetDock(reportBar, Dock.Top); root.Children.Add(reportBar);
        context.Visibility = Visibility.Collapsed;
        DockPanel.SetDock(progress, Dock.Top); root.Children.Add(progress);
        DockPanel.SetDock(status, Dock.Bottom); root.Children.Add(status);
        var side = new DockPanel(); var sideCaption = Caption("documents"); relocalize.Add(() => sideCaption.Text = Copy[IsWorkbook ? "workbooks" : "documents"]); DockPanel.SetDock(sideCaption, Dock.Top); side.Children.Add(sideCaption); side.Children.Add(projectList); SidebarPane.Child = side;
        projectList.SelectionChanged += async (_, _) => { if (!binding && projectList.SelectedItem is Choice choice) await Guard(() => OpenProject(choice.Value)); };
        var changeDock = new DockPanel(); var changeCaption = Caption("changes"); DockPanel.SetDock(changeCaption, Dock.Top); changeDock.Children.Add(changeCaption);
        intervalCaption.Visibility = Visibility.Collapsed;
        more = Command("more", LoadMoreChanges); DockPanel.SetDock(more, Dock.Bottom); changeDock.Children.Add(more);
        retryComparison = Command("retry", RetryComparison); retryComparison.Visibility = Visibility.Collapsed; DockPanel.SetDock(retryComparison, Dock.Bottom); changeDock.Children.Add(retryComparison);
        ConfigureChangeList(); changeList.ItemsSource = changes; changeDock.Children.Add(changeList); ChangesPane.Child = changeDock;
        changeList.SelectionChanged += async (_, _) => { if (!binding && changeList.SelectedItem is ChangeChoice choice) await Guard(() => SelectChange(choice.Value)); };
        var inspector = new DockPanel(); var caption = Caption("evidence"); DockPanel.SetDock(caption, Dock.Top); inspector.Children.Add(caption);
        var pagingButtons = new WrapPanel(); firstDetail = Command("firstText", FirstDetail); nextDetail = Command("nextText", NextDetail); pagingButtons.Children.Add(firstDetail); pagingButtons.Children.Add(nextDetail); detailPaging.Children.Add(pagingButtons); BindText(detailStyle, "styleDetail"); detailPaging.Children.Add(detailStyle); detailStyle.Click += async (_, _) => await Guard(FirstDetail); detailPaging.Children.Add(detailRange); DockPanel.SetDock(detailPaging, Dock.Top); inspector.Children.Add(detailPaging);
        var metadata = new Expander { Header = "Source metadata / 원본 메타데이터", IsExpanded = false, Content = detailMetadata, MaxHeight = 180 }; DockPanel.SetDock(metadata, Dock.Bottom); inspector.Children.Add(metadata); inspector.Children.Add(detail); InspectorPane.Child = inspector;
        var sourceTools = new DockPanel { Margin = new Thickness(4, 1, 4, 1), LastChildFill = true };
        var sourceActions = new StackPanel { Orientation = Orientation.Horizontal }; previousChange = Command("previousChange", () => MoveChange(-1)); nextChange = Command("nextChange", () => MoveChange(1)); returnChange = Command("returnChange", ReturnToChange); sourceActions.Children.Add(previousChange); sourceActions.Children.Add(nextChange); sourceActions.Children.Add(returnChange); sourceActions.Children.Add(sourceView); DockPanel.SetDock(sourceActions, Dock.Right); sourceTools.Children.Add(sourceActions); sourceTools.Children.Add(sourcePair); DockPanel.SetDock(sourceTools, Dock.Top); sourceStage.Children.Add(sourceTools);
        firstTextStage = Command("firstText", FirstDetail); nextTextStage = Command("nextText", NextDetail); rawTextPaging.Children.Add(firstTextStage); rawTextPaging.Children.Add(nextTextStage); BindText(sourceDiagnostics, "sourceDetails"); sourceDiagnostics.Click += (_, _) => RenderSourceDiff(); rawTextPaging.Children.Add(sourceDiagnostics); DockPanel.SetDock(rawTextPaging, Dock.Top); sourceStage.Children.Add(rawTextPaging);
        var sourceFooter = new DockPanel(); selectedLimitsButton = Command("selectedLimits", () => { CreateSelectedLimitsDialog().ShowDialog(); return Task.CompletedTask; }); DockPanel.SetDock(selectedLimitsButton, Dock.Right); sourceFooter.Children.Add(selectedLimitsButton); sourceFooter.Children.Add(sourceNotice); DockPanel.SetDock(sourceFooter, Dock.Bottom); sourceStage.Children.Add(sourceFooter); var sourceBody = new Grid(); sourceBody.Children.Add(comparison); sourceBody.Children.Add(unified); sourceStage.Children.Add(sourceBody);
        sourceView.SelectionChanged += (_, _) => { if (!binding) { textView = sourceView.SelectedIndex == 1; RenderSourceDiff(); } };
        root.Children.Add(workspace); ClearDetail(); SetBusy(false);
    }
    private static Border Pane() => new() { BorderBrush = new SolidColorBrush(Color.FromRgb(222, 226, 232)), BorderThickness = new Thickness(1), Background = Brushes.White, ClipToBounds = true };
    private void ConfigureChangeList()
    {
        var stack = new FrameworkElementFactory(typeof(StackPanel)); stack.SetValue(FrameworkElement.MarginProperty, new Thickness(9, 7, 9, 7));
        void Text(string property, bool title = false, int lines = 0)
        {
            var block = new FrameworkElementFactory(typeof(TextBlock)); block.SetBinding(TextBlock.TextProperty, new Binding(property)); block.SetValue(TextBlock.TextWrappingProperty, TextWrapping.Wrap); block.SetValue(TextBlock.TextTrimmingProperty, TextTrimming.CharacterEllipsis); block.SetValue(TextBlock.LineHeightProperty, 16d); block.SetValue(TextBlock.FontSizeProperty, 12d); block.SetValue(FrameworkElement.MarginProperty, new Thickness(0, 0, 0, 3)); if (title) block.SetValue(TextBlock.FontWeightProperty, FontWeights.SemiBold); if (lines > 0) block.SetValue(FrameworkElement.MaxHeightProperty, lines * 16d); stack.AppendChild(block);
        }
        Text(nameof(ChangeChoice.Title), true); Text(nameof(ChangeChoice.Location)); Text(nameof(ChangeChoice.Preview), lines: 2);
        changeList.ItemTemplate = new DataTemplate { VisualTree = stack }; var style = new Style(typeof(ListBoxItem)); style.Setters.Add(new Setter(Control.HorizontalContentAlignmentProperty, HorizontalAlignment.Stretch)); style.Setters.Add(new Setter(Control.PaddingProperty, new Thickness(0))); style.Setters.Add(new Setter(FrameworkElement.MarginProperty, new Thickness(2, 1, 2, 2))); style.Setters.Add(new Setter(Control.BorderThicknessProperty, new Thickness(2, 1, 1, 1))); style.Setters.Add(new Setter(Control.BorderBrushProperty, Brushes.Transparent)); style.Setters.Add(new Setter(FrameworkElement.ToolTipProperty, new Binding(nameof(ChangeChoice.Caption)))); style.Setters.Add(new Setter(AutomationProperties.NameProperty, new Binding(nameof(ChangeChoice.Caption)))); var selected = new Trigger { Property = ListBoxItem.IsSelectedProperty, Value = true }; selected.Setters.Add(new Setter(Control.BackgroundProperty, new SolidColorBrush(Color.FromRgb(231, 241, 255)))); selected.Setters.Add(new Setter(Control.BorderBrushProperty, new SolidColorBrush(Color.FromRgb(59, 130, 246)))); selected.Setters.Add(new Setter(Control.ForegroundProperty, Brushes.Black)); style.Triggers.Add(selected); changeList.ItemContainerStyle = style; ScrollViewer.SetHorizontalScrollBarVisibility(changeList, ScrollBarVisibility.Disabled); VirtualizingPanel.SetVirtualizationMode(changeList, VirtualizationMode.Recycling);
    }
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
        catch (Exception error) { if (!closed) { status.Text = Copy["requestFailed"] + " " + error.Message; MessageBox.Show(this, Copy["requestFailed"] + "\n\n" + error.Message, Copy["error"], MessageBoxButton.OK, MessageBoxImage.Error); } }
    }
    internal void SetLanguage(string language)
    {
        Copy.Language = language == "ko" ? "ko" : "en"; Preferences.Language = Copy.Language; Localize(); SavePreferences();
    }
    private void Localize()
    {
        foreach (var action in relocalize) action(); foreach (var pair in languageItems) pair.Value.IsChecked = pair.Key == Copy.Language;
        var wasBinding = binding; binding = true; comparisonMode.ItemsSource = new[] { new Choice("history", Copy["history"], default), new Choice("range_net", Copy["net"], default) }; comparisonMode.SelectedIndex = NetMode ? 1 : 0; binding = wasBinding;
        binding = true; sourceView.ItemsSource = new[] { new Choice("visual", Copy["visualView"], default), new Choice("text", Copy["textDiff"], default) }; sourceView.SelectedIndex = textView ? 1 : 0; binding = wasBinding;
        AutomationProperties.SetName(sourceView, Copy["sourceView"]); AutomationProperties.SetName(queryBefore, Copy["interval"] + " · " + Copy["before"]); AutomationProperties.SetName(queryAfter, Copy["interval"] + " · " + Copy["after"]); AutomationProperties.SetName(unified, Copy["textDiff"]);
        actionItems["mcp"].ToolTip = Copy["mcpReportScope"]; AutomationProperties.SetHelpText(actionItems["mcp"], Copy["mcpReportScope"]);
        previousChange.ToolTip = Copy["previous"] + " · " + Copy["changes"]; nextChange.ToolTip = Copy["next"] + " · " + Copy["changes"]; AutomationProperties.SetName(previousChange, previousChange.ToolTip.ToString()); AutomationProperties.SetName(nextChange, nextChange.ToolTip.ToString());
        AutomationProperties.SetName(comparisonMode, Copy["comparisonMode"]); foreach (var change in changes) change.Relabel(ChangeCaption(change.Value)); Before.Localize(); After.Localize();
        detailPaging.Visibility = IsWorkbook ? Visibility.Visible : Visibility.Collapsed;
        RerenderInspector();
        foreach (var splitter in NativeSplitters()) if (splitter.Tag is string key) { AutomationProperties.SetName(splitter, Copy[key]); splitter.ToolTip = Copy[key]; }
        if (!busy) status.Text = Copy[initializing ? "initializing" : Preferences.IsReadOnly ? "preferencesReadOnly" : "ready"]; UpdateContext(); UpdateInterval(); RenderSourceDiff();
    }
    internal void SavePreferences()
    {
        try { Preferences.Save(PreferencesPath); } catch (Exception error) when (error is IOException or UnauthorizedAccessException) { status.Text = error.Message; }
    }
    internal void SetLayout(WorkspaceLayout layout) { Preferences.For(IsWorkbook).Current = layout.Bounded(); ApplyLayout(); }
    private void BuildLayoutMenu(MenuItem menu)
    {
        menu.Items.Clear();
        var checks = new List<(MenuItem Item, Func<bool> Checked)>();
        void Add(string key, Action action, Func<bool>? check = null) { var item = new MenuItem { Header = Copy[key], IsCheckable = check is not null, IsChecked = check?.Invoke() ?? false }; if (check is not null) checks.Add((item, check)); item.Click += (_, _) => { action(); foreach (var pair in checks) pair.Item.IsChecked = pair.Checked(); }; menu.Items.Add(item); }
        foreach (var preset in new[] { "sourceFirst", "balanced", "focus", "review" }) { var name = preset; Add(name, () => SetLayout(WorkspaceLayout.Preset(name)), () => Layout == WorkspaceLayout.Preset(name)); }
        menu.Items.Add(new Separator()); Add("sidebar", () => SetLayout(Layout with { Sidebar = !Layout.Sidebar }), () => Layout.Sidebar); Add("inspector", () => SetLayout(Layout with { Inspector = !Layout.Inspector }), () => Layout.Inspector); Add("changes", () => SetLayout(Layout with { ChangesVisible = !Layout.ChangesVisible }), () => Layout.ChangesVisible);
        Add("changesBottom", () => SetLayout(Layout with { Changes = "bottom" }), () => Layout.Changes == "bottom"); Add("changesLeft", () => SetLayout(Layout with { Changes = "left" }), () => Layout.Changes == "left"); Add("changesRight", () => SetLayout(Layout with { Changes = "right" }), () => Layout.Changes == "right");
        Add("inspectorLeft", () => SetLayout(Layout with { InspectorSide = "left" }), () => Layout.InspectorSide == "left"); Add("inspectorRight", () => SetLayout(Layout with { InspectorSide = "right" }), () => Layout.InspectorSide == "right"); Add("vertical", () => SetLayout(Layout with { VerticalComparison = !Layout.VerticalComparison }), () => Layout.VerticalComparison);
        menu.Items.Add(new Separator()); Add("saveLayout", SaveNamedLayout);
        var saved = new MenuItem { Header = Copy["applyLayout"] };
        foreach (var pair in Preferences.For(IsWorkbook).Named) { var layout = pair.Value; var item = new MenuItem { Header = new TextBlock { Text = pair.Key } }; item.Click += (_, _) => SetLayout(layout); saved.Items.Add(item); }
        saved.IsEnabled = saved.Items.Count != 0; menu.Items.Add(saved);
        var delete = new MenuItem { Header = Copy["deleteLayout"] }; foreach (var pair in Preferences.For(IsWorkbook).Named) { var name = pair.Key; var item = new MenuItem { Header = new TextBlock { Text = name } }; item.Click += (_, _) => { Preferences.For(IsWorkbook).Named.Remove(name); SavePreferences(); }; delete.Items.Add(item); } delete.IsEnabled = delete.Items.Count != 0; menu.Items.Add(delete);
        Add("reset", () => SetLayout(new()));
    }
    private void SaveNamedLayout()
    {
        if (Preferences.IsReadOnly) { MessageBox.Show(this, Copy["preferencesReadOnly"], Copy["saveLayout"]); return; }
        CreateNamedLayoutDialog().ShowDialog();
    }
    private Window CreateNamedLayoutDialog()
    {
        var dialog = new Window { Owner = this, Title = Copy["saveLayout"], Width = 420, Height = 190, ResizeMode = ResizeMode.NoResize, WindowStartupLocation = WindowStartupLocation.CenterOwner };
        var stack = new StackPanel { Margin = new Thickness(16) }; var field = new TextBox { Name = "LayoutName", MaxLength = 48, Margin = new Thickness(0, 8, 0, 8) }; stack.Children.Add(new TextBlock { Text = Copy["layoutName"] }); stack.Children.Add(field);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var cancel = new Button { Name = "CancelLayout", Content = Copy["cancel"], IsCancel = true, Padding = new Thickness(12, 5, 12, 5), Margin = new Thickness(4) }; buttons.Children.Add(cancel); cancel.Click += (_, _) => dialog.DialogResult = false;
        var save = new Button { Name = "SaveLayout", Content = Copy["save"], IsDefault = true, Padding = new Thickness(12, 5, 12, 5), Margin = new Thickness(4) }; buttons.Children.Add(save); stack.Children.Add(buttons); dialog.Content = stack;
        save.Click += (_, _) => { var name = field.Text.Trim(); if (name.Length is < 1 or > 48 || name.Any(char.IsControl)) return; var named = Preferences.For(IsWorkbook).Named; if (!named.ContainsKey(name) && named.Count >= 12) { MessageBox.Show(dialog, Copy["layoutLimit"], Copy["applyLayout"]); return; } if (named.ContainsKey(name) && MessageBox.Show(dialog, Copy["replaceLayout"] + "\n\n" + name, Copy["saveLayout"], MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No) != MessageBoxResult.Yes) return; named[name] = Layout; SavePreferences(); dialog.DialogResult = true; };
        return dialog;
    }
    internal void ApplyLayout(bool save = true)
    {
        var focus = Keyboard.FocusedElement as UIElement;
        var beforeViewport = Before.CaptureViewport(); var afterViewport = After.CaptureViewport();
        var beforeGridViewport = Before.CaptureGridViewport(); var afterGridViewport = After.CaptureGridViewport();
        // Detach and reparent the exact existing panes. No model or pane recreation.
        foreach (var child in new UIElement[] { SidebarPane, ChangesPane, InspectorPane, Before.Host, After.Host, sourceStage }) if (System.Windows.Media.VisualTreeHelper.GetParent(child) is Panel parent) parent.Children.Remove(child);
        workspace.Children.Clear(); workspace.ColumnDefinitions.Clear(); workspace.RowDefinitions.Clear(); comparison.Children.Clear(); comparison.ColumnDefinitions.Clear(); comparison.RowDefinitions.Clear();
        var layout = Layout.Bounded();
        lastLayoutWidth = workspace.ActualWidth; lastLayoutHeight = workspace.ActualHeight;
        var center = new Grid();
        if (layout.ChangesVisible && layout.Changes == "bottom")
        {
            center.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star), MinHeight = 180 }); center.RowDefinitions.Add(new RowDefinition { Height = new GridLength(5) }); center.RowDefinitions.Add(new RowDefinition { Height = new GridLength(Math.Min(layout.ChangesHeight, Math.Max(100, workspace.ActualHeight - 240))), MinHeight = 90 });
            center.Children.Add(sourceStage); Grid.SetRow(sourceStage, 0); Grid.SetColumn(sourceStage, 0); center.Children.Add(ChangesPane); Grid.SetRow(ChangesPane, 2); Grid.SetColumn(ChangesPane, 0);
            var splitter = Splitter(false, "resizeChanges", () => { Preferences.For(IsWorkbook).Current = (Layout with { ChangesHeight = center.RowDefinitions[2].ActualHeight }).Bounded(); SavePreferences(); }); Grid.SetRow(splitter, 1); center.Children.Add(splitter);
        }
        else { center.Children.Add(sourceStage); Grid.SetRow(sourceStage, 0); Grid.SetColumn(sourceStage, 0); }
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
        if (singleSource)
        {
            Grid.SetRow(After.Host, 0); Grid.SetColumn(After.Host, 0);
        }
        else if (layout.VerticalComparison)
        {
            comparison.RowDefinitions.Add(new RowDefinition { Height = new GridLength(layout.ComparisonRatio, GridUnitType.Star), MinHeight = 100 }); comparison.RowDefinitions.Add(new RowDefinition { Height = new GridLength(5) }); comparison.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1 - layout.ComparisonRatio, GridUnitType.Star), MinHeight = 100 });
            Grid.SetRow(Before.Host, 0); Grid.SetColumn(Before.Host, 0); Grid.SetRow(After.Host, 2); Grid.SetColumn(After.Host, 0); var splitter = Splitter(false, "resizeComparison", () => { CaptureLayout(); SavePreferences(); }); Grid.SetRow(splitter, 1); comparison.Children.Add(splitter);
        }
        else
        {
            comparison.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(layout.ComparisonRatio, GridUnitType.Star), MinWidth = 100 }); comparison.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(5) }); comparison.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1 - layout.ComparisonRatio, GridUnitType.Star), MinWidth = 100 });
            Grid.SetColumn(Before.Host, 0); Grid.SetRow(Before.Host, 0); Grid.SetColumn(After.Host, 2); Grid.SetRow(After.Host, 0); var splitter = Splitter(true, "resizeComparison", () => { CaptureLayout(); SavePreferences(); }); Grid.SetColumn(splitter, 1); comparison.Children.Add(splitter);
        }
        if (!singleSource) comparison.Children.Add(Before.Host); comparison.Children.Add(After.Host);
        Dispatcher.BeginInvoke(System.Windows.Threading.DispatcherPriority.Loaded, () => { Before.RestoreViewport(beforeViewport); After.RestoreViewport(afterViewport); Before.RestoreGridViewport(beforeGridViewport); After.RestoreGridViewport(afterGridViewport); });
        if (focus is not null) Dispatcher.BeginInvoke(() => { if (focus.IsVisible) focus.Focus(); });
        if (save) SavePreferences();
    }
    private GridSplitter Splitter(bool vertical, string name, Action persist)
    {
        var splitter = new NativeSplitter { Persist = persist, Background = new SolidColorBrush(Color.FromRgb(233, 236, 241)), HorizontalAlignment = HorizontalAlignment.Stretch, VerticalAlignment = VerticalAlignment.Stretch, ResizeDirection = vertical ? GridResizeDirection.Columns : GridResizeDirection.Rows, ResizeBehavior = GridResizeBehavior.PreviousAndNext, ShowsPreview = true, Focusable = true, KeyboardIncrement = 10 };
        AutomationProperties.SetName(splitter, Copy[name]); splitter.ToolTip = Copy[name]; splitter.Tag = name;
        splitter.DragCompleted += (_, _) => { if (splitter.Parent is Grid parent) parent.UpdateLayout(); persist(); }; return splitter;
    }
    private void CaptureLayout(int leading = -1, int trailing = -1)
    {
        var layout = Layout;
        if (workspace.Tag is List<(UIElement Element, double Width, string Role)> columns)
            for (var index = 0; index < columns.Count; index++) { if (index != leading && index != trailing) continue; var width = workspace.ColumnDefinitions[index * 2].ActualWidth; if (width <= 0) continue; layout = columns[index].Role switch { "sidebar" => layout with { SidebarWidth = width }, "inspector" => layout with { InspectorWidth = width }, "changes" => layout with { ChangesWidth = width }, _ => layout }; }
        var total = layout.VerticalComparison ? comparison.ActualHeight - 5 : comparison.ActualWidth - 5;
        if (total > 0 && !singleSource) { var first = layout.VerticalComparison ? comparison.RowDefinitions.FirstOrDefault()?.ActualHeight ?? 0 : comparison.ColumnDefinitions.FirstOrDefault()?.ActualWidth ?? 0; layout = layout with { ComparisonRatio = first / total }; }
        Preferences.For(IsWorkbook).Current = layout.Bounded();
    }

    public async Task Initialize() => await Guard(async () => { initializing = true; SetBusy(busy); try { await Bridge.Call("recover"); await Bridge.Call("workbookRecover"); await RefreshProjects(); } finally { initializing = false; SetBusy(busy); } });
    internal async Task SwitchWorkspace(bool workbook, Func<Task>? beforeProjectsForSmoke = null)
    {
        if (busy) return; CancelProjectChoices(); SavePreferences(); IsWorkbook = workbook; binding = true; documents.IsChecked = !workbook; workbooks.IsChecked = workbook; binding = false;
        BeginScope(); projectId = ""; reportId = ""; currentReport = default; currentProject = default; binding = true; reports.ItemsSource = null; binding = false; ClearReport(); ApplyLayout(); Localize(); SetBusy(false); await RefreshProjectsCore(beforeProjectsForSmoke);
    }
    internal Task RefreshProjects() => RefreshProjectsCore(null);
    private void CancelProjectChoices()
    {
        ++projectChoicesGeneration; var prior = projectChoicesRead; projectChoicesRead = null; prior?.Cancel();
        // Its own async invocation disposes the source after its await settles.
    }
    private async Task RefreshProjectsCore(Func<Task>? beforeInstallForSmoke)
    {
        if (closed) return;
        CancelProjectChoices(); var workbook = IsWorkbook; var sequence = projectChoicesGeneration;
        var owned = new CancellationTokenSource(); projectChoicesRead = owned; var token = owned.Token;
        projectChoicesReady = false; binding = true; projectList.ItemsSource = null; binding = false; projectList.IsEnabled = false;
        try
        {
            var value = await Bridge.Call(workbook ? "workbookProjects" : "projects", token: token);
            if (beforeInstallForSmoke is not null) await beforeInstallForSmoke();
            if (closed || token.IsCancellationRequested || workbook != IsWorkbook || sequence != projectChoicesGeneration) return;
            if (value.ValueKind != JsonValueKind.Array || value.Items().Any(item => !ProjectKindMatches(item.Get("project_id").Text(), workbook))) throw new BridgeException("PROJECT_SCOPE", "The project list does not belong to the selected workspace.");
            var items = value.Items().Select(v => Choice.From(v, "project_id", "title")).ToList();
            binding = true; projectList.ItemsSource = items; projectList.SelectedItem = items.Find(v => v.Id == projectId); binding = false; projectChoicesReady = true; projectList.IsEnabled = !busy;
            if (projectId.Length == 0) status.Text = Copy["chooseProject"];
        }
        catch (OperationCanceledException) when (closed || token.IsCancellationRequested || workbook != IsWorkbook || sequence != projectChoicesGeneration) { }
        finally { if (ReferenceEquals(projectChoicesRead, owned)) projectChoicesRead = null; owned.Dispose(); }
    }
    private static bool ProjectKindMatches(string id, bool workbook) => Regex.IsMatch(id, workbook ? "^wprj_[a-zA-Z0-9_-]{1,155}$" : "^prj_[a-zA-Z0-9_-]{1,156}$", RegexOptions.CultureInvariant);
    internal async Task OpenProject(JsonElement project, Func<CancellationToken, Task>? afterReportsForSmoke = null)
    {
        if (busy || !projectChoicesReady || !ProjectKindMatches(project.Get("project_id").Text(), IsWorkbook)) return; var current = projectList.Items.OfType<Choice>().FirstOrDefault(item => item.Id == project.Get("project_id").Text()); if (current is null) return; await OpenProjectCore(current.Value, afterReportsForSmoke: afterReportsForSmoke);
    }
    private async Task OpenProjectCore(JsonElement project, string preferredReport = "", Func<CancellationToken, Task>? afterReportsForSmoke = null)
    {
        var candidate = project.Get("project_id").Text(); var workbook = IsWorkbook; if (!ProjectKindMatches(candidate, workbook)) throw new BridgeException("PROJECT_SCOPE", "The project belongs to a different workspace.");
        var ticket = BeginScope(); var token = reads.Token;
        // A visible candidate is not yet an authoritative project. Revoke the
        // previous writer target synchronously before the first suspended read.
        projectId = ""; currentProject = default; reportId = ""; currentReport = default; binding = true; reports.ItemsSource = null; binding = false; ClearReport(); UpdateContext(); SetBusy(busy); status.Text = Copy["loading"];
        var value = await Bridge.Call(workbook ? "workbookReports" : "reports", new { project_id = candidate }, token);
        if (afterReportsForSmoke is not null) await afterReportsForSmoke(token);
        if (ticket != generation || workbook != IsWorkbook) return;
        if (value.ValueKind != JsonValueKind.Array || value.Items().Any(item => !item.Get("report_id").Text().StartsWith(workbook ? "wreport_" : "rpt_", StringComparison.Ordinal))) throw new BridgeException("REPORT_SCOPE", "The report list does not belong to the selected workspace.");
        currentProject = project; projectId = candidate;
        var items = value.Items().Select(v => new Choice(v.Get("report_id").Text(), CompactReport(v.Get("report_id").Text()) + " · " + v.Get("created_at").Text(), v)).ToList();
        var selected = preferredReport.Length > 0 ? items.Find(item => item.Id == preferredReport) : items.FirstOrDefault(); if (preferredReport.Length > 0 && selected is null) throw new BridgeException("REPORT_SCOPE", "The committed fixed report was not present in this project."); binding = true; reports.ItemsSource = items; reports.SelectedItem = selected; binding = false;
        if (selected is not null) await OpenReportCore(selected.Id); else status.Text = Copy["noReport"]; SetBusy(busy);
    }
    internal async Task OpenReport(string fixedReport)
    {
        if (busy || projectId.Length == 0 || fixedReport == "latest") return; await OpenReportCore(fixedReport);
    }
    private async Task OpenReportCore(string fixedReport)
    {
        var project = projectId; var workbook = IsWorkbook; var ticket = BeginScope(); reportId = fixedReport; currentReport = default; ClearReport();
        var value = await Bridge.Call(IsWorkbook ? "workbookView" : "view", Json.Scope(projectId, fixedReport), reads.Token);
        if (ticket != generation) return;
        if (value.Get("report_id").Text() != fixedReport || value.Get("project_id").Text() != projectId) throw new BridgeException("REPORT_SCOPE", "The report response is outside the selected fixed snapshot.");
        currentReport = value; var revisions = value.Get("revisions").Items();
        var endpoints = SourceDiff.PreviousToSelected(revisions.Count - 1, revisions.Count);
        binding = true; Before.SetRevisions(revisions, endpoints.Before); After.SetRevisions(revisions, endpoints.After); BindQueryChoices(); binding = false;
        selectedChange = default; singleSource = revisions.Count == 1; ApplyLayout(false);
        UpdateContext(); var comparisonRead = ReloadComparisonCore(); var comparisonTicket = generation; await comparisonRead;
        if (IsCurrent(comparisonTicket) && projectId == project && IsWorkbook == workbook && reportId == fixedReport && ComparisonState == "ready") status.Text = Copy[Preferences.IsReadOnly ? "preferencesReadOnly" : "ready"];
        SetBusy(busy);
    }
    internal async Task ReloadComparison()
    {
        if (binding || reportId.Length == 0 || busy && !restoringOperation) return; await ReloadComparisonCore();
    }
    internal Task ReloadSourceWindow()
    {
        if (binding || reportId.Length == 0 || busy && !restoringOperation) return Task.CompletedTask;
        return ReloadComparisonCore(true);
    }
    private async Task ReloadComparisonCore(bool preserveInterval = false)
    {
        var ticket = BeginScope();
        var oneSource = Before.RevisionId.Length > 0 && Before.RevisionId == After.RevisionId; if (singleSource != oneSource) { singleSource = oneSource; ApplyLayout(false); }
        if (!preserveInterval) { intervalFrom = Before.RevisionId; intervalTo = After.RevisionId; ClearSelectedChange(); } UpdateInterval();
        InvalidateAuthority(true); Before.Invalidate(); After.Invalidate();
        var revisions = currentReport.Get("revisions").Items(); var from = revisions.FindIndex(v => v.Get("revision_occurrence_id").Text() == intervalFrom); var to = revisions.FindIndex(v => v.Get("revision_occurrence_id").Text() == intervalTo);
        if (from < 0 || to < 0 || from > to) { ComparisonState = "invalid"; Before.Invalidate("invalid"); After.Invalidate("invalid"); detail.Text = Copy["reverse"]; status.Text = Copy["reverse"]; return; }
        try { await Before.Load(ticket, reads.Token); if (ticket != generation) return; await After.Load(ticket, reads.Token); if (ticket != generation) return; await LoadChanges(false, ticket, reads.Token); RenderSourceDiff(); }
        catch { if (IsCurrent(ticket) && !reads.IsCancellationRequested) FailComparison(); throw; }
    }
    internal Task RetryComparison()
    {
        if (busy || reportId.Length == 0) return Task.CompletedTask;
        // Invalidating a failed read never changes retained selectors. Retry the
        // exact event/page/sheet/window, independently of the change-list interval.
        return ReloadComparisonCore(true);
    }
    private void InvalidateAuthority(bool clearChanges)
    {
        changesReady = false; ComparisonState = "loading"; changeList.IsEnabled = false; more.IsEnabled = false; retryComparison.Visibility = Visibility.Collapsed; ClearDetail(); detail.Text = Copy["loading"]; RenderSourceDiff();
        if (clearChanges) { binding = true; changeList.SelectedItem = null; changes.Clear(); binding = false; nextChanges = ""; }
    }
    private void FailComparison() { changesReady = false; ComparisonState = "failed"; changeList.IsEnabled = false; more.IsEnabled = false; Before.Invalidate("failed"); After.Invalidate("failed"); ClearDetail(); detail.Text = Copy["failed"]; retryComparison.Visibility = Visibility.Visible; RenderSourceDiff(); }
    private long BeginScope() { reads.Cancel(); reads.Dispose(); reads = new(); cellReads.Cancel(); cellReads.Dispose(); cellReads = new(); return ++generation; }
    internal bool IsCurrent(long ticket) => !closed && ticket == generation;
    private void ClearReport() { selectedChange = default; InvalidateAuthority(true); ComparisonState = "empty"; binding = true; intervalFrom = ""; intervalTo = ""; queryBefore.ItemsSource = null; queryAfter.ItemsSource = null; UpdateInterval(); Before.Clear(); After.Clear(); detail.Text = Copy["selectCell"]; binding = false; RenderSourceDiff(); }
    private void ClearSelectedChange() { selectedChange = default; selectedBefore = null; selectedAfter = null; }
    private string VersionLabel(string id)
    {
        var revisions = currentReport.Get("revisions").Items(); var index = revisions.FindIndex(v => v.Get("revision_occurrence_id").Text() == id); return index < 0 ? "" : "v" + (index + 1) + " · " + revisions[index].Get("label").Text();
    }
    private string VersionOrdinal(string id) { var index = currentReport.Get("revisions").Items().FindIndex(v => v.Get("revision_occurrence_id").Text() == id); return index < 0 ? "?" : "v" + (index + 1); }
    private void BindQueryChoices()
    {
        var prior = binding; binding = true; var choices = currentReport.Get("revisions").Items().Select((value, index) => new Choice(value.Get("revision_occurrence_id").Text(), "v" + (index + 1) + " · " + value.Get("label").Text(), value)).ToList(); queryBefore.ItemsSource = choices; queryAfter.ItemsSource = choices.ToList(); binding = prior;
    }
    private void UpdateInterval()
    {
        intervalCaption.Text = intervalFrom.Length == 0 ? "" : Copy["interval"] + ": " + VersionLabel(intervalFrom) + " → " + VersionLabel(intervalTo) + " · " + Copy[NetMode ? "net" : "history"];
        var previous = binding; binding = true; queryBefore.SelectedItem = queryBefore.Items.OfType<Choice>().FirstOrDefault(v => v.Id == intervalFrom); queryAfter.SelectedItem = queryAfter.Items.OfType<Choice>().FirstOrDefault(v => v.Id == intervalTo); binding = previous;
        versionsButton.IsEnabled = !busy && reportId.Length > 0;
    }
    private static string CompactReport(string id) => id.Length <= 18 ? id : id[..10] + "…" + id[^6..];
    private void UpdateContext() { context.Text = projectId.Length == 0 ? Copy["chooseProject"] : currentProject.Get("title").Text() + "  ·  " + reportId + (currentReport.ValueKind == JsonValueKind.Undefined ? "" : "  ·  " + Copy["coverage"] + ": " + currentReport.Get("coverage_gap_count").Number(currentReport.Get("coverage_gaps").Items().Count)); projectCaption.Text = currentProject.Get("title").Text(); projectCaption.ToolTip = context.Text; reports.ToolTip = context.Text; }
    private async Task ChooseEndpoint(bool after, string id)
    {
        if (busy || reportId.Length == 0) return;
        // Endpoint selectors own the query interval. Event/source navigation does not.
        Before.SetSourceRevision(intervalFrom); After.SetSourceRevision(intervalTo);
        (after ? After : Before).SetSourceRevision(id); selectedChange = default;
        await ReloadComparison();
    }
    private Task ShowVersions()
    {
        var menu = new ContextMenu(); var revisions = currentReport.Get("revisions").Items();
        for (var i = 0; i < revisions.Count; i++)
        {
            var index = i; var item = new MenuItem { Header = new TextBlock { Text = "v" + (i + 1) + "  " + revisions[i].Get("label").Text() }, IsCheckable = true, IsChecked = intervalTo == revisions[i].Get("revision_occurrence_id").Text() };
            item.Click += async (_, _) => await Guard(() => SelectLogVersion(index)); menu.Items.Add(item);
        }
        versionsButton.ContextMenu = menu; menu.PlacementTarget = versionsButton; menu.Placement = PlacementMode.Bottom; menu.IsOpen = true; return Task.CompletedTask;
    }
    private async Task SelectLogVersion(int selected)
    {
        if (busy || reportId.Length == 0) return; var revisions = currentReport.Get("revisions").Items(); var pair = SourceDiff.PreviousToSelected(selected, revisions.Count); if (pair.Before < 0) return;
        Before.SetSourceRevision(revisions[pair.Before].Get("revision_occurrence_id").Text(), false); After.SetSourceRevision(revisions[pair.After].Get("revision_occurrence_id").Text(), false); selectedChange = default;
        await ReloadComparison();
    }
    private async Task MoveChange(int direction)
    {
        if (busy || !changesReady) return; var index = changes.ToList().FindIndex(c => c.Id == selectedChange.Get("change_id").Text()); var next = index < 0 ? direction > 0 ? 0 : changes.Count - 1 : index + direction;
        if (next == changes.Count && nextChanges.Length > 0) await LoadMoreChanges();
        if (next < 0 || next >= changes.Count) return;
        var choice = changes[next]; binding = true; changeList.SelectedItem = choice; changeList.ScrollIntoView(choice); binding = false; await SelectChange(choice.Value);
    }
    private Task ReturnToChange() => selectedChange.ValueKind == JsonValueKind.Object && changesReady ? SelectChange(selectedChange) : Task.CompletedTask;
    internal void SourcePresentationChanged() => RenderSourceDiff();
    private bool AtSelectedChange => selectedChange.ValueKind == JsonValueKind.Object && selectedBefore is { } a && selectedAfter is { } b && Before.RevisionId == a.Revision && Before.PageId == a.Page && Before.SheetId == a.Sheet && After.RevisionId == b.Revision && After.PageId == b.Page && After.SheetId == b.Sheet && (!IsWorkbook || Before.SelectedRow == a.Row && Before.SelectedColumn == a.Column && After.SelectedRow == b.Row && After.SelectedColumn == b.Column);
    private string SelectedNoticeText((string Key, string Value) notice) => Copy[notice.Key] + ": " + (notice.Value is "inferred" or "observed" or "human_confirmed" or "needs_review" ? Copy["assessment_" + notice.Value] : notice.Value);
    private Window CreateReportDetailsDialog()
    {
        var fixedReport = reportId; var content = new DockPanel { Margin = new Thickness(16) }; var top = new StackPanel(); top.Children.Add(new TextBlock { Text = currentProject.Get("title").Text(), FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap }); top.Children.Add(new TextBlock { Text = Copy["report"] + " · " + (reports.SelectedItem as Choice)?.Value.Get("created_at").Text(), Margin = new Thickness(0, 10, 0, 4) }); var identity = SourceText(); identity.Text = fixedReport; identity.MinHeight = 48; top.Children.Add(identity); var copy = new Button { Content = Copy["copyReportId"], HorizontalAlignment = HorizontalAlignment.Left, Padding = new Thickness(10, 5, 10, 5), Margin = new Thickness(0, 2, 0, 12) }; copy.Click += (_, _) => Clipboard.SetText(fixedReport); top.Children.Add(copy); top.Children.Add(new TextBlock { Text = Copy["mcpReportScope"], TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 12) }); top.Children.Add(new TextBlock { Text = Copy["reportCoverage"] + ": " + currentReport.Get("coverage_gap_count").Number(currentReport.Get("coverage_gaps").Items().Count), FontWeight = FontWeights.SemiBold }); DockPanel.SetDock(top, Dock.Top); content.Children.Add(top); var limits = SourceText(); limits.Text = currentReport.Get("coverage_gaps").Pretty(); content.Children.Add(limits);
        return new Window { Owner = this, Title = Copy["reportDetails"], Width = 720, Height = 530, MinWidth = 430, MinHeight = 320, WindowStartupLocation = WindowStartupLocation.CenterOwner, Content = content };
    }
    private Window CreateSelectedLimitsDialog()
    {
        var notes = SourceDiffPolicy.SelectedNotices(selectedChange); var text = SourceText(); text.Text = string.Join("\n\n", notes.Select(SelectedNoticeText));
        var content = new DockPanel { Margin = new Thickness(12) }; var scope = new TextBlock { Text = Copy["report"] + ": " + reportId + "\n" + sourcePair.Text, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(4, 0, 4, 12) }; DockPanel.SetDock(scope, Dock.Top); content.Children.Add(scope); content.Children.Add(text);
        return new Window { Owner = this, Title = Copy["selectedLimits"], Width = 720, Height = 430, MinWidth = 400, MinHeight = 250, WindowStartupLocation = WindowStartupLocation.CenterOwner, Content = content };
    }
    private void RenderSourceDiff()
    {
        // Hidden retains the native visual hosts' measured viewport while the
        // text layer is visible; neither the hosts nor source selections rebuild.
        comparison.Visibility = textView ? Visibility.Hidden : Visibility.Visible; unified.Visibility = textView ? Visibility.Visible : Visibility.Collapsed;
        var eventDifferent = Before.RevisionId != intervalFrom || After.RevisionId != intervalTo;
        sourcePair.Text = reportId.Length == 0 ? "" : (singleSource ? Copy["reading"] + " · " + VersionLabel(After.RevisionId) : Copy[eventDifferent ? "withinInterval" : "sourcePair"] + " · " + VersionLabel(Before.RevisionId) + " → " + VersionLabel(After.RevisionId));
        previousChange.IsEnabled = nextChange.IsEnabled = !busy && changesReady && changes.Count > 0; returnChange.Visibility = selectedChange.ValueKind == JsonValueKind.Object ? Visibility.Visible : Visibility.Collapsed; returnChange.IsEnabled = !busy && changesReady;
        var notice = new List<string>(); if (IsWorkbook) notice.Add(Copy["storedOnly"]);
        if (selectedChange.ValueKind == JsonValueKind.Object && !AtSelectedChange) notice.Add(Copy["outsideChange"]);
        var kind = selectedChange.Get("kind").Text(); if (kind == "row_correspondence") notice.Add(Copy["inferredRows"]);
        if (kind is "text_occluded" or "text_revealed" or "text_struck_through" or "coverage_gap") notice.Add(Copy["appearanceOnly"]);
        var selectedNotices = SourceDiffPolicy.SelectedNotices(selectedChange); var selectedGaps = selectedNotices.Where(item => item.Key is "selectedCoverage" or "lineageReason").ToArray();
        foreach (var selectedNotice in selectedNotices.Where(item => item.Key is not ("selectedCoverage" or "lineageReason"))) notice.Add(SelectedNoticeText(selectedNotice));
        if (selectedGaps.Length > 0) { var first = selectedGaps[0].Value; if (selectedGaps[0].Key == "lineageReason") { var key = "reason_" + first; if (Copy[key] != key) first = Copy[key]; } if (first.Length > 220) first = first[..(char.IsHighSurrogate(first[219]) ? 219 : 220)] + "…"; notice.Add(Copy[selectedGaps[0].Key] + ": " + first + (selectedGaps.Length > 1 ? " [1/" + selectedGaps.Length + "]" : "")); }
        selectedLimitsButton.Visibility = selectedGaps.Length > 0 ? Visibility.Visible : Visibility.Collapsed; selectedLimitsButton.IsEnabled = !busy;
        if (currentReport.Get("coverage_gap_count").Number(currentReport.Get("coverage_gaps").Items().Count) > 0) notice.Add((Copy["reportCoverage"] + ": " + currentReport.Get("coverage_gap_count").Number(currentReport.Get("coverage_gaps").Items().Count)).Replace(' ', '\u00a0'));
        sourceNotice.Text = string.Join(" · ", notice); sourceNotice.ToolTip = string.Join("\n", selectedNotices.Select(SelectedNoticeText)); AutomationProperties.SetHelpText(sourceNotice, sourceNotice.ToolTip.ToString()); sourceNotice.Visibility = notice.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        rawTextPaging.Visibility = textView && IsWorkbook && detailLoader is not null ? Visibility.Visible : Visibility.Collapsed; firstTextStage.IsEnabled = !busy && firstDetail.IsEnabled; nextTextStage.IsEnabled = !busy && nextDetail.IsEnabled;
        if (!textView) return;
        var flow = new FlowDocument { PagePadding = new Thickness(14), FontFamily = unified.FontFamily, FontSize = 13 }; unified.Document = flow;
        void Add(string text, Brush? color = null, Brush? background = null) { flow.Blocks.Add(new Paragraph(new Run(text)) { Margin = new Thickness(0), Foreground = color ?? Brushes.Black, Background = background ?? Brushes.Transparent }); }
        if (ComparisonState != "ready") { Add(Copy[ComparisonState == "failed" ? "failed" : ComparisonState == "invalid" ? "reverse" : ComparisonState == "empty" ? "chooseProject" : "loading"]); return; }
        Add(Copy["textDiffNotice"], Brushes.DimGray); Add(Copy["report"] + ": " + reportId + "\n" + sourcePair.Text, Brushes.DimGray);
        if (!singleSource) Add(Copy["before"] + " · " + Before.LocationCaption + " · " + Before.PresentedSourceCaption, Brushes.DimGray);
        Add(Copy["after"] + " · " + After.LocationCaption + " · " + After.PresentedSourceCaption, Brushes.DimGray);
        if (Before.ReadState is "loading" or "failed" || After.ReadState is "loading" or "failed") { Add(Copy[Before.ReadState == "failed" || After.ReadState == "failed" ? "failed" : "loading"], Brushes.DimGray); return; }
        void Observation(SourceTextObservation value)
        {
            Add(Copy[value.State switch { SourceTextState.Missing => "observationMissing", SourceTextState.Null => "observationNull", SourceTextState.Empty => "observationEmpty", SourceTextState.Partial => "partialSourceSegment", SourceTextState.AlreadyRead => "alreadyReadSegment", SourceTextState.Invalid => "invalidSourceSegment", _ => "observationPresent" }], Brushes.DimGray);
            if (value.State == SourceTextState.Invalid) Add(Copy[value.RawState switch { SourceTextState.Null => "observationNull", SourceTextState.Empty => "fragmentEmpty", SourceTextState.Missing => "observationMissing", _ => "observationPresent" }], Brushes.DimGray);
            if (sourceDiagnostics.IsChecked == true && value.Range is { Valid: true, State: "missing" } missing) Add(Copy["textRange"] + ": missing · " + Copy["requestedOffset"] + "=" + missing.Offset + " · total=0 · next=∅", Brushes.DimGray);
            else if (value.Range is { } range && (sourceDiagnostics.IsChecked == true || value.State is SourceTextState.Partial or SourceTextState.AlreadyRead or SourceTextState.Invalid or SourceTextState.Empty)) Add(Copy["textRange"] + ": [" + (range.Offset?.ToString(CultureInfo.InvariantCulture) ?? "?") + ", " + (range.Offset is { } at ? ((long)at + range.Length).ToString(CultureInfo.InvariantCulture) : "?") + ") / " + (range.Total?.ToString(CultureInfo.InvariantCulture) ?? "?") + " · " + range.State + " · " + Copy[range.Valid ? "validSourceRange" : "invalidSourceRange"] + " · next=" + (range.Next?.ToString(CultureInfo.InvariantCulture) ?? (range.Valid ? "∅" : "?")), Brushes.DimGray);
            if (!value.HasText) return; var bounded = SourceDiff.Build(value.Text, value.Text); if (bounded.Truncated) Add(Copy["boundedDiff"], Brushes.DarkOrange); foreach (var line in bounded.Lines) Add(line.Text + (line.Terminator.Length > 0 || line.CutOff ? " " + line.TerminatorLabel : ""));
        }
        void Field(SourceDiffField field)
        {
            Add(Copy[field.Key == "value" ? "cached" : field.Key == "text" ? "textObservation" : field.Key], Brushes.DimGray);
            if (!field.Eligible) { Add(Copy[field.Reason], Brushes.DimGray); Add(Copy["before"], Brushes.DimGray); Observation(field.Before); Add(Copy["after"], Brushes.DimGray); Observation(field.After); return; }
            if (field.Before.Range is { } a && (sourceDiagnostics.IsChecked == true || field.Before.State == SourceTextState.Empty)) Add(Copy["before"] + " · " + Copy["textRange"] + ": [0, " + a.Length + ") / " + a.Total + " · " + a.State, Brushes.DimGray);
            if (field.After.Range is { } b && (sourceDiagnostics.IsChecked == true || field.After.State == SourceTextState.Empty)) Add(Copy["after"] + " · " + Copy["textRange"] + ": [0, " + b.Length + ") / " + b.Total + " · " + b.State, Brushes.DimGray);
            var diff = SourceDiff.Build(field.Before.Text, field.After.Text); if (diff.Truncated) Add(Copy["boundedDiff"], Brushes.DarkOrange);
            foreach (var line in diff.Lines) Add(line.Prefix + " " + line.Text + (diff.TerminatorsDiffer || line.CutOff ? " " + line.TerminatorLabel : ""), line.Prefix == '-' ? Brushes.DarkRed : line.Prefix == '+' ? Brushes.DarkGreen : Brushes.Black, line.Prefix == '-' ? new SolidColorBrush(Color.FromRgb(255, 241, 240)) : line.Prefix == '+' ? new SolidColorBrush(Color.FromRgb(237, 250, 240)) : null);
        }
        if (IsWorkbook)
        {
            if (inspectorMode is "loading" or "failed") { Add(Copy[inspectorMode == "failed" ? "failed" : "loading"], Brushes.DimGray); return; }
            if (inspectorMode != "raw" || detailPayload.Get("before").ValueKind != JsonValueKind.Object) { Add(Copy["selectDiffChange"], Brushes.DimGray); return; }
            Add(Copy["textSegmentOnly"], Brushes.DimGray);
            var a = detailPayload.Get("before").Get("items").Items().FirstOrDefault().Get("before"); var b = detailPayload.Get("after").Get("items").Items().FirstOrDefault().Get("after");
            Add(Copy["before"] + " " + a.Get("address").Text() + " → " + Copy["after"] + " " + b.Get("address").Text(), Brushes.DimGray);
            if (sourceDiagnostics.IsChecked == true) foreach (var side in new[] { (Label: Copy["before"], Cell: a), (Label: Copy["after"], Cell: b) }) Add(side.Label + " · " + Copy["cacheState"] + ": " + side.Cell.Get("cached_result").Text() + " · " + Copy["cacheFreshness"] + ": " + side.Cell.Get("cache_freshness").Text() + " · " + Copy["formulaInterpretation"] + ": " + side.Cell.Get("formula_interpretation").Text(), Brushes.DimGray);
            var displayed = new WorkbookSourceScope(Before.RevisionId, After.RevisionId, Before.SheetId, After.SheetId, Before.SelectedRow > 0 && Before.SelectedColumn > 0 ? ComparePane.ColumnName(Before.SelectedColumn) + Before.SelectedRow.ToString(CultureInfo.InvariantCulture) : "", After.SelectedRow > 0 && After.SelectedColumn > 0 ? ComparePane.ColumnName(After.SelectedColumn) + After.SelectedRow.ToString(CultureInfo.InvariantCulture) : "");
            foreach (var field in SourceDiffPolicy.Workbook(AtSelectedChange ? selectedChange : default, a, b, displayed, detailOffset)) Field(field);
        }
        else if (AtSelectedChange && documentDetail.ValueKind == JsonValueKind.Object)
        {
            Add(Copy["selectedSnippet"], Brushes.DimGray); Field(SourceDiffPolicy.Document(documentDetail, Before.DiffTextAvailable && After.DiffTextAvailable, Before.StructuralPreview || After.StructuralPreview));
        }
        else
        {
            if (Before.ReadState != "ready" || After.ReadState != "ready") { Add(Copy["unavailableText"], Brushes.DimGray); return; }
            Add(Copy["pageText"], Brushes.DimGray); Add(Copy["unselectedObservation"], Brushes.DimGray);
            if (!singleSource) { Add(Copy["before"], Brushes.DimGray); Observation(Before.PreviewObservation); }
            Add(Copy["after"], Brushes.DimGray); Observation(After.PreviewObservation);
        }
    }
    private void SetBusy(bool value)
    {
        busy = value; var ready = !value && !initializing; progress.Visibility = value ? Visibility.Visible : Visibility.Collapsed; cancelButton.Visibility = value ? Visibility.Visible : Visibility.Collapsed; cancelButton.IsEnabled = value; importButton.IsEnabled = ready; analyzeButton.IsEnabled = ready && projectId.Length > 0; reorderButton.IsEnabled = ready && !IsWorkbook && projectId.Length > 0; exportButton.IsEnabled = ready && reportId.Length > 0; mcpButton.IsEnabled = ready && reportId.Length > 0; documents.IsEnabled = ready; workbooks.IsEnabled = ready; projectList.IsEnabled = ready && projectChoicesReady; reports.IsEnabled = ready; comparisonMode.IsEnabled = ready && reportId.Length > 0; Before.NavigationEnabled(ready);
        After.NavigationEnabled(ready); foreach (var pair in actionItems) pair.Value.IsEnabled = pair.Key switch { "import" or "refresh" => ready, "analyze" => analyzeButton.IsEnabled, "reorder" => reorderButton.IsEnabled, "export" => exportButton.IsEnabled, "mcp" => mcpButton.IsEnabled, _ => ready };
        queryBefore.IsEnabled = queryAfter.IsEnabled = versionsButton.IsEnabled = reportDetailsButton.IsEnabled = ready && reportId.Length > 0; sourceView.IsEnabled = ready;
        changeList.IsEnabled = !value && changesReady; more.IsEnabled = !value && changesReady && nextChanges.Length > 0; Before.Cells.IsEnabled = !value && Before.ReadState == "ready"; After.Cells.IsEnabled = !value && After.ReadState == "ready"; firstDetail.IsEnabled = !value && detailLoader is not null && (detailOffset > 0 || detailCursor.Length > 0); nextDetail.IsEnabled = !value && detailLoader is not null && (detailNext is not null || detailItemNext.Length > 0);
        RenderSourceDiff();
    }
    private ComparisonSelection AdmitMutation()
    {
        var beforeScroll = IsWorkbook ? Before.GridScroll : Before.PageScroll; var afterScroll = IsWorkbook ? After.GridScroll : After.PageScroll;
        var saved = new ComparisonSelection(projectId, reportId, IsWorkbook, currentProject, currentReport, Before.CaptureSelection(), After.CaptureSelection(), intervalFrom, intervalTo, beforeScroll?.HorizontalOffset ?? 0, beforeScroll?.VerticalOffset ?? 0, afterScroll?.HorizontalOffset ?? 0, afterScroll?.VerticalOffset ?? 0);
        BeginScope(); InvalidateAuthority(true); Before.Invalidate(); After.Invalidate(); SetBusy(true); return saved;
    }
    private async Task FinishMutation(CancellationTokenSource owned, ComparisonSelection previous, bool completed)
    {
        try { if (ReferenceEquals(operation, owned)) { if (!completed) await RestoreAfterMutation(previous); try { await RefreshProjects(); } catch (Exception error) when (error is BridgeException or IOException or OperationCanceledException) { status.Text = Copy["projectRefreshFailed"]; } } }
        finally { if (ReferenceEquals(operation, owned)) { operation = null; SetBusy(false); } owned.Dispose(); }
    }
    private async Task RestoreAfterMutation(ComparisonSelection saved)
    {
        if (closed) return;
        if (saved.Project.Length == 0 || saved.Report.Length == 0 || saved.Snapshot.ValueKind != JsonValueKind.Object)
        {
            var draft = saved.Project.Length > 0 ? saved.Draft : currentProject;
            if (draft.Get("project_id").Text().Length > 0) { try { await OpenProjectCore(draft); ComparisonState = "draft"; inspectorMode = "draft"; detail.Text = Copy["noReport"]; retryComparison.Visibility = Visibility.Collapsed; } catch { ClearReport(); ComparisonState = "draft"; inspectorMode = "draft"; detail.Text = Copy["noReport"]; } }
            else { BeginScope(); projectId = ""; reportId = ""; currentProject = default; currentReport = default; ClearReport(); inspectorMode = "empty"; detail.Text = Copy["chooseProject"]; }
            return;
        }
        restoringOperation = true;
        try
        {
            projectId = saved.Project; reportId = saved.Report; IsWorkbook = saved.Workbook; currentProject = saved.Draft; currentReport = saved.Snapshot;
            var revisions = currentReport.Get("revisions").Items(); Before.SetRevisions(revisions, 0); After.SetRevisions(revisions, Math.Max(0, revisions.Count - 1)); Before.RestoreSelection(saved.Before); After.RestoreSelection(saved.After); BindQueryChoices(); intervalFrom = saved.IntervalFrom; intervalTo = saved.IntervalTo; UpdateInterval(); UpdateContext();
            var restore = ReloadComparisonCore(true); var ticket = generation; await restore;
            UpdateLayout(); await Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle);
            if (!IsCurrent(ticket) || projectId != saved.Project || reportId != saved.Report) return;
            var beforeScroll = IsWorkbook ? Before.GridScroll : Before.PageScroll; var afterScroll = IsWorkbook ? After.GridScroll : After.PageScroll;
            beforeScroll?.ScrollToHorizontalOffset(Math.Min(saved.BeforeX, beforeScroll.ScrollableWidth)); beforeScroll?.ScrollToVerticalOffset(Math.Min(saved.BeforeY, beforeScroll.ScrollableHeight));
            afterScroll?.ScrollToHorizontalOffset(Math.Min(saved.AfterX, afterScroll.ScrollableWidth)); afterScroll?.ScrollToVerticalOffset(Math.Min(saved.AfterY, afterScroll.ScrollableHeight));
        }
        catch { FailComparison(); }
        finally { restoringOperation = false; }
    }
    private async Task Import()
    {
        if (busy || initializing) return; var dialog = new ImportWindow(Copy, IsWorkbook) { Owner = this }; if (dialog.ShowDialog() != true) return;
        await ImportAndAnalyze(dialog.ProjectTitle, dialog.Rows.ToList());
    }
    internal async Task ImportAndAnalyze(string title, IReadOnlyList<ImportRow> rows, Action<int>? startedForSmoke = null, Action? afterCreateForSmoke = null)
    {
        if (busy || initializing) return; var owned = new CancellationTokenSource(); operation = owned; var previous = AdmitMutation(); var completed = false; status.Text = Copy["importing"];
        try
        {
            await RecoverBeforeMutation(owned.Token);
            var input = new List<object>(); foreach (var row in rows)
            {
                var hashes = new List<string>(); foreach (var path in row.Paths) hashes.Add(await ImportWindow.Identity(path, owned.Token));
                input.Add(IsWorkbook ? new { label = row.Label.Trim(), path = row.Paths[0], expected_sha256 = hashes[0] } : (object)new { label = row.Label.Trim(), files = row.Paths, expected_sha256 = hashes });
            }
            var project = await Bridge.Call(IsWorkbook ? "workbookCreate" : "create", new { title, revisions = input }, owned.Token);
            currentProject = project; projectId = project.Get("project_id").Text(); reportId = ""; BeginScope(); ClearReport(); afterCreateForSmoke?.Invoke();
            await AnalyzeCore(owned.Token, startedForSmoke); await RefreshProjects();
            completed = true;
        }
        finally { await FinishMutation(owned, previous, completed); }
    }
    private Task Analyze() => AnalyzeWithStarted(null);
    private async Task AnalyzeWithStarted(Action<int>? startedForSmoke, Func<Task>? afterCommitForSmoke = null, Func<JsonElement, CancellationToken, Task>? beforeReplyForSmoke = null)
    {
        if (busy || initializing || projectId.Length == 0) return; var owned = new CancellationTokenSource(); operation = owned; var previous = AdmitMutation(); var completed = false;
        try { await RecoverBeforeMutation(owned.Token); await AnalyzeCore(owned.Token, startedForSmoke, afterCommitForSmoke, beforeReplyForSmoke); completed = true; }
        finally { await FinishMutation(owned, previous, completed); }
    }
    private async Task AnalyzeCore(CancellationToken token, Action<int>? startedForSmoke = null, Func<Task>? afterCommitForSmoke = null, Func<JsonElement, CancellationToken, Task>? beforeReplyForSmoke = null)
    {
        var project = projectId; var workbook = IsWorkbook; status.Text = Copy["analyzing"]; var stage = await Bridge.Call(workbook ? "workbookAnalyze" : "analyze", new { project_id = project }, token, progress: value => Dispatcher.BeginInvoke(() => { if (!closed && busy && operation is { } current && current.Token == token) status.Text = ProgressSummary(value); }), startedForSmoke: startedForSmoke, beforeReplyForSmoke: beforeReplyForSmoke);
        status.Text = Copy["committing"];
        var saved = await AnalysisCommit.Save(project, workbook, stage, token, (action, args, cancel) => Bridge.Call(action, args, cancel));
        if (afterCommitForSmoke is not null) await afterCommitForSmoke();
        await OpenProjectCore(currentProject, saved.Get("report_id").Text()); status.Text = Copy["ready"];
    }
    private async Task RecoverBeforeMutation(CancellationToken token)
    {
        // GUI lifetime library lock plus writer admission exclude another writer.
        // Recover interrupted/staged attempts whose helper died before handing
        // the application an exact descriptor; fixed reports remain untouched.
        await Bridge.Call("recover", token: token); await Bridge.Call("workbookRecover", token: token);
    }
    private Task Reorder() => ReorderCore(null);
    private async Task ReorderCore(Action<ImportWindow>? prepareForSmoke)
    {
        if (busy || IsWorkbook || projectId.Length == 0) return;
        var selectedProject = projectId; var ticket = generation; var projects = await Bridge.Call("projects", token: reads.Token); if (!IsCurrent(ticket) || busy || IsWorkbook || projectId != selectedProject) return; var project = projects.Items().Find(v => v.Get("project_id").Text() == selectedProject); var dialog = new ImportWindow(Copy, false, project.Get("revisions").Items()) { Owner = this }; prepareForSmoke?.Invoke(dialog); if (dialog.ShowDialog() != true || busy || projectId != selectedProject) return;
        var owned = new CancellationTokenSource(); operation = owned; var previous = AdmitMutation(); var completed = false;
        try
        {
            await RecoverBeforeMutation(owned.Token);
            var draft = await Bridge.Call("reorder", new { project_id = selectedProject, order = dialog.Rows.Select(v => v.OriginalIndex).ToArray(), draft_hash = project.Get("draft_hash").Text() }, owned.Token);
            if (draft.Get("project_id").Text() != selectedProject) throw new BridgeException("PROJECT_SCOPE", "Reorder returned another project.");
            if (previous.Report.Length > 0 && previous.Snapshot.ValueKind == JsonValueKind.Object)
            {
                // Only the draft changed. Re-read the explicitly pinned snapshot to
                // refresh its draft identity, then restore the exact evidence scope.
                var snapshot = await Bridge.Call("view", Json.Scope(selectedProject, previous.Report), owned.Token);
                if (snapshot.Get("project_id").Text() != selectedProject || snapshot.Get("report_id").Text() != previous.Report) throw new BridgeException("REPORT_SCOPE", "Reorder refresh returned another fixed snapshot.");
                await RestoreAfterMutation(previous with { Draft = draft, Snapshot = snapshot });
                if (projectId != selectedProject || reportId != previous.Report || ComparisonState is not ("ready" or "invalid")) throw new BridgeException("REPORT_SCOPE", "The pinned comparison could not be restored after reordering its draft.");
            }
            else await OpenProjectCore(draft, previous.Report);
            await RefreshProjects(); completed = true;
        }
        finally { await FinishMutation(owned, previous, completed); }
    }
    private async Task Export()
    {
        if (reportId.Length == 0 || busy) return; var project = projectId; var report = reportId; var workbook = IsWorkbook; var language = Copy.Language;
        var folder = new OpenFolderDialog { Title = Copy["exportFolder"], Multiselect = false }; if (folder.ShowDialog(this) != true) return;
        if (Directory.EnumerateFileSystemEntries(folder.FolderName).Any()) { MessageBox.Show(this, Copy["exportEmpty"], Copy["export"]); return; }
        var owned = new CancellationTokenSource(); operation = owned; SetBusy(true); try { await RecoverBeforeMutation(owned.Token); await Bridge.Call(workbook ? "workbookExport" : "export", new { project_id = project, report_id = report, folder = folder.FolderName, language }, owned.Token); status.Text = Copy["exported"] + ": " + folder.FolderName; } finally { if (ReferenceEquals(operation, owned)) { operation = null; SetBusy(false); } owned.Dispose(); }
    }
    private async Task CopyMcp()
    {
        if (projectId.Length == 0 || busy) return; var ticket = generation; var project = projectId; var workbook = IsWorkbook;
        var config = await Bridge.Call(workbook ? "workbookMcpConfig" : "mcpConfig", new { project_id = project }, reads.Token);
        if (!IsCurrent(ticket) || projectId != project || IsWorkbook != workbook) return;
        Clipboard.SetText(config.Text()); status.Text = Copy["copied"] + " " + Copy["mcpReportScope"];
    }
    internal async Task<JsonElement> McpConfig() => await Bridge.Call(IsWorkbook ? "workbookMcpConfig" : "mcpConfig", new { project_id = projectId });
    internal async Task<JsonElement> Query(string name, Dictionary<string, object?> args, CancellationToken token)
    { args["project_id"] = projectId; args["report_id"] = reportId; args["max_output_tokens"] = 8000; return await Bridge.Call("workbookQuery", new { name, args }, token); }
    private string ProgressSummary(JsonElement value)
    {
        var phase = value.Get("phase").Text(); var label = value.Get("label").Text(); if (label.Length > 160) label = label[..160] + "…";
        return Copy["analyzing"] + " " + Copy["phase_" + phase] + " · " + value.Get("current").Number() + " / " + value.Get("total").Number() + (label.Length == 0 ? "" : " · " + label);
    }
    private async Task ChangeComparisonMode(bool net)
    {
        if (busy || net == NetMode) return;
        if (IsWorkbook) workbookNet = net; else documentNet = net; ClearSelectedChange();
        UpdateInterval(); if (reportId.Length == 0) return;
        var ticket = BeginScope(); InvalidateAuthority(true);
        try { if (Before.ReadState is "loading" or "failed" or "empty") await Before.Load(ticket, reads.Token); if (!IsCurrent(ticket)) return; if (After.ReadState is "loading" or "failed" or "empty") await After.Load(ticket, reads.Token); if (!IsCurrent(ticket)) return; await LoadChanges(false, ticket, reads.Token); RenderSourceDiff(); }
        catch { if (IsCurrent(ticket) && !reads.IsCancellationRequested) FailComparison(); throw; }
    }
    private string ChangeCaption(JsonElement change)
    {
        string Side(bool after)
        {
            var occurrence = change.Get(IsWorkbook ? after ? "to_revision_occurrence_id" : "from_revision_occurrence_id" : after ? "to_occurrence" : "from_occurrence").Text(); var version = VersionOrdinal(occurrence);
            if (IsWorkbook) { var sheetId = change.Get(after ? "to_sheet_id" : "from_sheet_id").Text(); var sheet = currentReport.Get("revisions").Items().Find(v => v.Get("revision_occurrence_id").Text() == occurrence).Get("sheets").Items().Find(s => s.Get("sheet_id").Text() == sheetId).Get("name").Text().Replace('\r', ' ').Replace('\n', ' '); var address = change.Get(after ? "after_address" : "before_address").Text(); return version + " · " + sheet + (address.Length > 0 ? "!" + address : " · " + Copy["missing"]); }
            var pages = change.Get("evidence").Items().Where(item => item.Get("revision_occurrence_id").Text() == occurrence).Select(item => item.Get("page").Number()).Distinct().Take(3).ToArray(); return version + " · " + (pages.Length > 0 ? "p." + string.Join(",", pages) : Copy["missing"]);
        }
        var preview = IsWorkbook ? change.Get("description").Text() : change.Get("before").Text().Split('\r', '\n').FirstOrDefault() + " → " + change.Get("after").Text().Split('\r', '\n').FirstOrDefault();
        if (preview.Length > 180) preview = preview[..(char.IsHighSurrogate(preview[179]) ? 179 : 180)] + "…";
        return Copy["kind_" + change.Get("kind").Text()] + "\n" + Side(false) + " → " + Side(true) + "\n" + preview;
    }
    private async Task LoadChanges(bool append, long ticket, CancellationToken token)
    {
        if (reportId.Length == 0 || intervalFrom.Length == 0 || intervalTo.Length == 0) return;
        var revisions = currentReport.Get("revisions").Items(); var from = revisions.FindIndex(v => v.Get("revision_occurrence_id").Text() == intervalFrom); var to = revisions.FindIndex(v => v.Get("revision_occurrence_id").Text() == intervalTo);
        if (from > to || from < 0 || to < 0) { if (IsCurrent(ticket)) { ComparisonState = "invalid"; changesReady = false; detail.Text = Copy["reverse"]; } return; }
        if (from == to) { if (IsCurrent(ticket)) { changes.Clear(); changesReady = true; ComparisonState = "ready"; changeList.IsEnabled = !busy; more.IsEnabled = false; detail.Text = Copy["noChanges"]; } return; }
        List<JsonElement> values; string next = "";
        if (IsWorkbook)
        {
            var args = new Dictionary<string, object?> { ["from_revision_occurrence_id"] = intervalFrom, ["to_revision_occurrence_id"] = intervalTo, ["mode"] = NetMode ? "range_net" : "history", ["limit"] = 100, ["text_length"] = 256 };
            if (append && nextChanges.Length > 0) args["cursor"] = nextChanges;
            var result = await Query("list_workbook_changes", args, token); values = result.Get("items").Items(); next = result.Get("next_cursor").Text();
        }
        else { values = (await Bridge.Call("changes", new { project_id = projectId, report_id = reportId, from = intervalFrom, to = intervalTo, mode = NetMode ? "range_net" : "history" }, token)).Items(); }
        if (!IsCurrent(ticket)) return; binding = true; if (!append) changes.Clear();
        foreach (var value in values) changes.Add(new(value.Get("change_id").Text(), ChangeCaption(value), value));
        binding = false; nextChanges = next; changesReady = true; ComparisonState = "ready"; changeList.IsEnabled = !busy; more.IsEnabled = !busy && next.Length > 0; if (changes.Count == 0) detail.Text = Copy["noChanges"] + "\n\n" + Copy["coverage"] + "\n" + currentReport.Get("coverage_gaps").Pretty(); else if (!append) detail.Text = Copy["selectCell"];
    }
    private async Task LoadMoreChanges()
    {
        if (!changesReady || !more.IsEnabled) return; more.IsEnabled = false; var ticket = generation;
        try { await LoadChanges(true, ticket, reads.Token); } catch { if (IsCurrent(ticket) && !reads.IsCancellationRequested) FailComparison(); throw; }
    }
    private async Task SelectChange(JsonElement change)
    {
        if (busy || !changesReady || !changes.Any(c => c.Id == change.Get("change_id").Text())) return;
        var selectedRow = changes.First(c => c.Id == change.Get("change_id").Text()); binding = true; changeList.SelectedItem = selectedRow; changeList.ScrollIntoView(selectedRow); binding = false;
        var ticket = BeginScope(); var token = reads.Token;
        InvalidateAuthority(false); Before.Invalidate(); After.Invalidate();
        try {
        if (IsWorkbook)
        {
            var args = new Dictionary<string, object?> { ["change_id"] = change.Get("change_id").Text(), ["mode"] = NetMode ? "range_net" : "history", ["text_length"] = 4096, ["component"] = "before", ["from_revision_occurrence_id"] = change.Get("from_revision_occurrence_id").Text(), ["to_revision_occurrence_id"] = change.Get("to_revision_occurrence_id").Text() };
            var before = await Query("get_workbook_change", args, token); args["component"] = "after"; var after = await Query("get_workbook_change", args, token); if (!IsCurrent(ticket) || token.IsCancellationRequested) return;
            if (!SourceDiffPolicy.WorkbookComponent(before, change, "before", projectId, reportId, out var beforeCell) || !SourceDiffPolicy.WorkbookComponent(after, change, "after", projectId, reportId, out var afterCell)) throw new BridgeException("EVIDENCE_SCOPE", "Workbook details do not match the selected fixed change and physical cells.");
            Before.SetEvidenceRevision(change.Get("from_revision_occurrence_id").Text(), change.Get("from_sheet_id").Text(), beforeCell); After.SetEvidenceRevision(change.Get("to_revision_occurrence_id").Text(), change.Get("to_sheet_id").Text(), afterCell);
            await Before.Load(ticket, token); await After.Load(ticket, token); if (!IsCurrent(ticket)) return;
            var project = projectId; var report = reportId;
            detailStyle.IsEnabled = false; detailLoader = async (offset, cancel) => { var request = new Dictionary<string, object?>(args) { ["text_offset"] = offset, ["component"] = "before" }; var a = await QueryFixed("get_workbook_change", request, project, report, cancel); request["component"] = "after"; var b = await QueryFixed("get_workbook_change", request, project, report, cancel); if (!SourceDiffPolicy.WorkbookComponent(a, change, "before", project, report, out _) || !SourceDiffPolicy.WorkbookComponent(b, change, "after", project, report, out _)) throw new BridgeException("EVIDENCE_SCOPE", "Workbook source continuation no longer matches the selected fixed change."); return JsonSerializer.SerializeToElement(new { before = a, after = b }); };
            await LoadDetail(0);
        }
        else
        {
            Before.SetEvidenceRevision(change.Get("from_occurrence").Text()); After.SetEvidenceRevision(change.Get("to_occurrence").Text());
            var evidence = change.Get("evidence").Items();
            var beforePage = evidence.Select(v => v.Get("page_id").Text()).FirstOrDefault(id => Before.HasPage(id)); var afterPage = evidence.Select(v => v.Get("page_id").Text()).FirstOrDefault(id => After.HasPage(id)); Before.SetEventPage(beforePage); After.SetEventPage(afterPage);
            await Before.Load(ticket, token); await After.Load(ticket, token); if (!IsCurrent(ticket)) return;
            documentDetail = change; inspectorMode = "event"; RerenderInspector(); detailMetadata.Text = change.Pretty();
        }
        if (IsCurrent(ticket)) { selectedChange = change; selectedBefore = Before.CaptureSelection(); selectedAfter = After.CaptureSelection(); if (singleSource) { singleSource = false; ApplyLayout(false); } changesReady = true; ComparisonState = "ready"; changeList.IsEnabled = true; more.IsEnabled = nextChanges.Length > 0; RenderSourceDiff(); }
        } catch { if (IsCurrent(ticket) && !token.IsCancellationRequested) FailComparison(); throw; }
    }
    internal async Task CheckIntermediateEventForSmoke()
    {
        var revisions = currentReport.Get("revisions").Items(); if (revisions.Count < 3) throw new InvalidOperationException("An intermediate event needs three revisions");
        // Previous→latest is now the default; this control explicitly requests
        // the wider history interval needed by the intermediate-event fixture.
        if (intervalFrom != revisions[0].Get("revision_occurrence_id").Text() || revisions.FindIndex(v => v.Get("revision_occurrence_id").Text() == intervalTo) < 1) await SelectSourcePairForSmoke(0, revisions.Count - 1);
        var first = revisions[0].Get("revision_occurrence_id").Text(); var middle = revisions[1].Get("revision_occurrence_id").Text(); var fromKey = IsWorkbook ? "from_revision_occurrence_id" : "from_occurrence"; var toKey = IsWorkbook ? "to_revision_occurrence_id" : "to_occurrence";
        ChangeChoice? FindIntermediate() => changes.FirstOrDefault(c => c.Value.Get(fromKey).Text() == first && c.Value.Get(toKey).Text() == middle);
        var selected = FindIntermediate(); var pages = 0; while (selected is null && nextChanges.Length > 0 && pages++ < 100) { await LoadMoreChanges(); selected = FindIntermediate(); }
        if (selected is null) throw new InvalidOperationException("Intermediate fixture event is missing"); var intervalA = intervalFrom; var intervalB = intervalTo; var count = changes.Count;
        await SelectChange(selected.Value);
        if (Before.RevisionId != first || After.RevisionId != middle || intervalFrom != intervalA || intervalTo != intervalB || changes.Count != count) throw new InvalidOperationException("Event evidence changed the change-list interval or displayed wrong source occurrences");
    }
    internal async Task CheckGitWorkflowForSmoke(Func<string, Task> capture)
    {
        var revisions = currentReport.Get("revisions").Items(); if (revisions.Count < 3) throw new InvalidOperationException("Git workflow control needs at least three imported versions.");
        var fixedReport = reportId; var layout = Layout; var hostA = Before.Host; var hostB = After.Host; var priorText = textView;
        async Task Settle() { UpdateLayout(); await Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle); }
        SetLayout(WorkspaceLayout.Preset("sourceFirst")); await SelectLogVersion(revisions.Count - 1); await Settle();
        if (Before.RevisionId != revisions[^2].Get("revision_occurrence_id").Text() || After.RevisionId != revisions[^1].Get("revision_occurrence_id").Text() || !reports.IsVisible || SidebarPane.IsVisible || InspectorPane.IsVisible || !ChangesPane.IsVisible || Layout.Changes != "left" || cancelButton.IsVisible || toolbar.Children.Contains(importButton) || toolbar.Children.Contains(exportButton) || !actionItems["export"].IsEnabled) throw new InvalidOperationException("Source-first default, previous→latest, compact actions or pinned-report reachability failed.");
        if (!IsWorkbook && Before.PageImage.Source is not null)
        {
            var preview = JsonSerializer.SerializeToElement(Before.CheckPreviewReadabilityForSmoke()); var zoom = Before.Zoom; if (preview.Get("source_point_width").Number() != 720 || preview.Get("displayed_raster_width").Number() < 600 || preview.Get("page_picker_height").Number() != 28) throw new InvalidOperationException("The known720-point PDF source was shrunk below its readable default or its chooser geometry diverged."); Before.FitPreviewForSmoke(); await Settle(); var fitted = JsonSerializer.SerializeToElement(Before.CheckPreviewReadabilityForSmoke()); if (!fitted.Get("fit_width").Flag() || !fitted.Get("displayed_raster_width").TryGetDouble(out var width) || !fitted.Get("viewport_width").TryGetDouble(out var viewport) || width > viewport + 1) throw new InvalidOperationException("Explicit native Fit width did not fit the retained original page."); Before.Zoom = zoom; await Settle();
        }
        await capture("source-first");
        await SelectLogVersion(0); await Settle(); if (!singleSource || ComparisonState != "ready" || After.ReadState != "ready" || comparison.Children.Contains(Before.Host) || !comparison.Children.Contains(After.Host) || intervalFrom != intervalTo || reportId != fixedReport) throw new InvalidOperationException("The first version is not a ready, readable single-source within its fixed report."); await capture("first-version-read");
        // The real query selectors remain independent of the event source pair.
        await SelectSourcePairForSmoke(0, revisions.Count - 1); comparisonMode.SelectedIndex = 0; await modeRequest; await CheckIntermediateEventForSmoke(); await Settle();
        var representative = changes.FirstOrDefault(item => item.Value.Get("kind").Text() == (IsWorkbook ? "stored_value" : "text_modified") && item.Value.Get(IsWorkbook ? "from_revision_occurrence_id" : "from_occurrence").Text() == revisions[0].Get("revision_occurrence_id").Text() && item.Value.Get(IsWorkbook ? "to_revision_occurrence_id" : "to_occurrence").Text() == revisions[1].Get("revision_occurrence_id").Text()); if (representative is not null) await SelectChange(representative.Value); await Settle();
        var queryA = intervalFrom; var queryB = intervalTo; var count = changes.Count; var sourceA = Before.CaptureSelection(); var sourceB = After.CaptureSelection(); var selected = selectedChange.Get("change_id").Text();
        if (queryBefore.SelectedItem is not Choice selectedA || selectedA.Id != queryA || queryAfter.SelectedItem is not Choice selectedB || selectedB.Id != queryB || !sourcePair.Text.Contains(Copy["withinInterval"], StringComparison.Ordinal) || (changeList.SelectedItem as ChangeChoice)?.Id != selected || changeList.ItemContainerGenerator.ContainerFromItem(changeList.SelectedItem) is not ListBoxItem { IsSelected: true, IsVisible: true } || ScrollViewer.GetHorizontalScrollBarVisibility(changeList) != ScrollBarVisibility.Disabled || !changes.Any(item => item.Location.Contains("→", StringComparison.Ordinal))) throw new InvalidOperationException("Query endpoints, visible native change selection or wrapped physical change rows failed.");
        await capture("history-event");
        await capture("source-first-selected");
        sourceView.SelectedIndex = 1; await Settle();
        var text = new TextRange(unified.Document.ContentStart, unified.Document.ContentEnd).Text;
        if (!unified.IsVisible || comparison.Visibility != Visibility.Hidden || !text.Contains(Copy["textDiffNotice"], StringComparison.Ordinal) || IsWorkbook && !text.Contains(Copy["textSegmentOnly"], StringComparison.Ordinal) || !ReferenceEquals(hostA, Before.Host) || !ReferenceEquals(hostB, After.Host) || Before.CaptureSelection() != sourceA || After.CaptureSelection() != sourceB || intervalFrom != queryA || intervalTo != queryB || changes.Count != count) throw new InvalidOperationException("Native text diff lost its bounded/source semantics, query interval or retained native pane selection.");
        await capture("text-diff");
        foreach (var language in new[] { "ko", "en" }) { SetLanguage(language); if (selectedChange.Get("change_id").Text() != selected || intervalFrom != queryA || intervalTo != queryB || Before.CaptureSelection() != sourceA || After.CaptureSelection() != sourceB || reportId != fixedReport) throw new InvalidOperationException("Text diff language changes altered evidence identity."); }
        if (IsWorkbook && representative is not null)
        {
            var manual = Before.SelectedRow == 3 && Before.SelectedColumn == 3 ? "D4" : "C3"; await Before.GoForSmoke(manual); await Settle(); if (AtSelectedChange || intervalFrom != queryA || intervalTo != queryB || unified.Document.Blocks.OfType<Paragraph>().Any(paragraph => ReferenceEquals(paragraph.Foreground, Brushes.DarkRed) || ReferenceEquals(paragraph.Foreground, Brushes.DarkGreen))) throw new InvalidOperationException("Manual workbook browsing retained colored selected-event authority or replaced the query."); await ReturnToChange(); await Settle(); if (!AtSelectedChange || Before.CaptureSelection() != sourceA || After.CaptureSelection() != sourceB || intervalFrom != queryA || intervalTo != queryB) throw new InvalidOperationException("Returning from manual workbook browsing did not restore the selected physical pair.");
        }
        sourceView.SelectedIndex = 0; await MoveChange(1); await Settle(); if (intervalFrom != queryA || intervalTo != queryB || changes.Count != count || reportId != fixedReport) throw new InvalidOperationException("Next-change navigation replaced the wider history query.");
        SetLayout(WorkspaceLayout.Preset("focus")); await Settle(); if (!reports.IsVisible || ChangesPane.IsVisible || !queryBefore.IsVisible || !sourceView.IsVisible) throw new InvalidOperationException("Focus mode hid the pinned report or query/source controls.");
        var reportDialog = CreateReportDetailsDialog(); var identityPanel = ((DockPanel)reportDialog.Content).Children.OfType<StackPanel>().Single(); if (!reportDetailsButton.IsVisible || !reportDetailsButton.IsEnabled || !identityPanel.Children.OfType<TextBox>().Any(field => field.IsReadOnly && field.Text == fixedReport) || !identityPanel.Children.OfType<TextBlock>().Any(field => field.Text.Contains(Copy["mcpReportScope"], StringComparison.Ordinal))) throw new InvalidOperationException("Full report identity and MCP scope details are not reachable in Focus."); var copyId = identityPanel.Children.OfType<Button>().Single(); copyId.RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); if (Clipboard.GetText() != fixedReport) throw new InvalidOperationException("Native report details did not copy the exact fixed report ID."); reportDialog.Close();
        SetLayout(layout); sourceView.SelectedIndex = priorText ? 1 : 0; await CheckIntermediateEventForSmoke(); await Settle();
    }
    internal async Task CheckRevertedHistoryForSmoke(Func<string, Task> capture)
    {
        if (IsWorkbook) throw new InvalidOperationException("Reverted source control requires the PDF workspace.");
        var revisions = currentReport.Get("revisions").Items(); if (revisions.Count != 3) throw new InvalidOperationException("Reverted control needs exactly three PDF occurrences.");
        SetLayout(WorkspaceLayout.Preset("sourceFirst")); await SelectSourcePairForSmoke(0, 2); comparisonMode.SelectedIndex = 1; await modeRequest;
        if (!Before.VerifiedPreviewText.Contains("Revenue 100", StringComparison.Ordinal) || !After.VerifiedPreviewText.Contains("Revenue 100", StringComparison.Ordinal) || changes.Count != 0) throw new InvalidOperationException("100→120→100 endpoint mode did not show identical 100 sources with no observed net changes.");
        await capture("reverted-endpoints"); var from = intervalFrom; var to = intervalTo;
        comparisonMode.SelectedIndex = 0; await modeRequest;
        var ids = revisions.Select(v => v.Get("revision_occurrence_id").Text()).ToArray();
        var first = changes.FirstOrDefault(c => c.Value.Get("from_occurrence").Text() == ids[0] && c.Value.Get("to_occurrence").Text() == ids[1] && c.Value.Get("before").Text().Contains("Revenue 100", StringComparison.Ordinal) && c.Value.Get("after").Text().Contains("Revenue 120", StringComparison.Ordinal));
        var reverted = changes.FirstOrDefault(c => c.Value.Get("from_occurrence").Text() == ids[1] && c.Value.Get("to_occurrence").Text() == ids[2] && c.Value.Get("before").Text().Contains("Revenue 120", StringComparison.Ordinal) && c.Value.Get("after").Text().Contains("Revenue 100", StringComparison.Ordinal));
        if (first is null || reverted is null) throw new InvalidOperationException("Intermediate history did not expose both 100→120 and 120→100 source observations.");
        await SelectChange(first.Value); sourceView.SelectedIndex = 1;
        if (intervalFrom != from || intervalTo != to || Before.RevisionId != ids[0] || After.RevisionId != ids[1] || !Before.VerifiedPreviewText.Contains("Revenue 100", StringComparison.Ordinal) || !After.VerifiedPreviewText.Contains("Revenue 120", StringComparison.Ordinal)) throw new InvalidOperationException("Intermediate source selection replaced the wider reverted query or showed wrong evidence.");
        await capture("reverted-history-text-diff"); sourceView.SelectedIndex = 0;
    }
    internal async Task CheckTypedDiffPresentationForSmoke(Func<string, Task> capture)
    {
        // Explicit synthetic presentation controls over verified native source
        // hosts. They are never committed to a report, queried as real evidence
        // or counted as observed OCR/appearance engine behavior.
        var fixedReport = reportId; var reportBytes = currentReport.GetRawText(); var layout = Layout; var previousView = textView;
        await SelectSourcePairForSmoke(0, 1); SetLayout(WorkspaceLayout.Preset("sourceFirst")); sourceView.SelectedIndex = 1;
        if (IsWorkbook) { await Before.GoForSmoke("C2"); await After.GoForSmoke("C3"); }
        JsonElement J(object value) => JsonSerializer.SerializeToElement(value);
        JsonElement CompleteCell(object value)
        {
            var cell = J(value); var fields = cell.EnumerateObject().ToDictionary(property => property.Name, property => (object?)property.Value); var ranges = new Dictionary<string, object?>();
            fields["value_type"] = "string"; fields["formula_dialect"] = cell.Get("formula").ValueKind == JsonValueKind.Null ? null : "xlsx_a1";
            foreach (var field in new[] { "value", "formula", "number_format" }) { var raw = cell.Get(field); ranges[field] = new { offset = 0, total_length = raw.Text().Length, next_offset = (int?)null, state = raw.ValueKind == JsonValueKind.Null ? "missing" : raw.Text().Length == 0 ? "empty" : "complete" }; }
            fields["text_continuations"] = ranges; return J(fields);
        }
        JsonElement WithRange(JsonElement cell, string field, object metadata)
        {
            var fields = cell.EnumerateObject().ToDictionary(property => property.Name, property => (object?)property.Value); var ranges = cell.Get("text_continuations").EnumerateObject().ToDictionary(property => property.Name, property => (object?)property.Value); ranges[field] = metadata; fields["text_continuations"] = ranges; return J(fields);
        }
        void Install(JsonElement change, JsonElement payload = default)
        {
            if (IsWorkbook)
            {
                var meta = change.EnumerateObject().ToDictionary(property => property.Name, property => (object?)property.Value); meta["from_revision_occurrence_id"] = Before.RevisionId; meta["to_revision_occurrence_id"] = After.RevisionId; meta["from_sheet_id"] = Before.SheetId; meta["to_sheet_id"] = After.SheetId; meta["before_address"] = payload.Get("before").Get("items").Items().FirstOrDefault().Get("before").Get("address").Text(); meta["after_address"] = payload.Get("after").Get("items").Items().FirstOrDefault().Get("after").Get("address").Text(); if (!meta.ContainsKey("association")) meta["association"] = "inferred"; if (!meta.ContainsKey("alignment_method")) meta["alignment_method"] = "unique_nonempty_first_column_key"; change = J(meta);
            }
            selectedChange = change; selectedBefore = Before.CaptureSelection(); selectedAfter = After.CaptureSelection(); documentDetail = change; detailPayload = payload; inspectorMode = IsWorkbook ? "raw" : "event"; RenderSourceDiff();
        }
        string Text() => new TextRange(unified.Document.ContentStart, unified.Document.ContentEnd).Text;
        bool Colored() => unified.Document.Blocks.OfType<Paragraph>().Any(paragraph => ReferenceEquals(paragraph.Foreground, Brushes.DarkRed) || ReferenceEquals(paragraph.Foreground, Brushes.DarkGreen));
        if (!IsWorkbook)
        {
            foreach (var kind in new[] { "coverage_gap", "text_occluded", "text_struck_through", "text_revealed", "page_added", "page_deleted", "page_split", "page_merged", "page_lineage_changed", "visual_region_changed" })
            {
                Install(J(new { kind, before = "SYNTHETIC neutral 100", after = "SYNTHETIC neutral 120" }));
                if (Colored() || !Text().Contains("SYNTHETIC neutral 100", StringComparison.Ordinal) || !Text().Contains(Copy["neutralObservation"], StringComparison.Ordinal)) throw new InvalidOperationException("Synthetic " + kind + " became a colored text edit or lost paired observations.");
            }
            Install(J(new { kind = "text_modified", before = (string?)null, after = "" }));
            if (Colored() || !Text().Contains(Copy["observationNull"], StringComparison.Ordinal) || !Text().Contains(Copy["observationEmpty"], StringComparison.Ordinal)) throw new InvalidOperationException("Native text view collapsed null observation into explicit empty/deletion.");
            Install(J(new { kind = "text_modified", before = "SYNTHETIC same\r\n", after = "SYNTHETIC same\n" })); if (!Colored() || !Text().Contains("⟦CRLF⟧", StringComparison.Ordinal) || !Text().Contains("⟦LF⟧", StringComparison.Ordinal)) throw new InvalidOperationException("Terminator-only source edit lost its exact CRLF/LF presentation."); await capture("synthetic-newline-only-diff");
            Install(J(new { kind = "text_modified", before = "SYNTHETIC inferred 100", after = "SYNTHETIC inferred 120", text_assessment = "inferred", region_pairing_assessment = "inferred", coverage_gaps = new[] { new { feature = "ocr", reason = "SYNTHETIC_ocr_requires_source_review" }, new { feature = "comparison", reason = "SYNTHETIC_other_regions_unresolved" } } }));
            if (!Colored()) throw new InvalidOperationException("Eligible synthetic paired text edit did not reach the native +/- renderer.");
            foreach (var name in new[] { "sourceFirst", "focus" })
            {
                SetLayout(WorkspaceLayout.Preset(name)); UpdateLayout();
                foreach (var language in new[] { "ko", "en" })
                {
                    SetLanguage(language);
                    var limitsDialog = CreateSelectedLimitsDialog(); var fullLimits = ((DockPanel)limitsDialog.Content).Children.OfType<TextBox>().Single().Text; limitsDialog.Close();
                    if (!sourceNotice.IsVisible || InspectorPane.IsVisible || !sourceNotice.Text.Contains(Copy["text_assessment"], StringComparison.Ordinal) || !sourceNotice.Text.Contains(Copy["region_pairing_assessment"], StringComparison.Ordinal) || !sourceNotice.Text.Contains(Copy["assessment_inferred"], StringComparison.Ordinal) || !sourceNotice.Text.Contains("SYNTHETIC_ocr_requires_source_review", StringComparison.Ordinal) || !sourceNotice.Text.Contains("[1/2]", StringComparison.Ordinal) || !selectedLimitsButton.IsVisible || !fullLimits.Contains("SYNTHETIC_other_regions_unresolved", StringComparison.Ordinal)) throw new InvalidOperationException("Selected inference/limit reasons disappeared outside the inspector in " + name + "/" + language);
                }
            }
            await capture("synthetic-inference-focus");
            Install(J(new { kind = "coverage_gap", before = "SYNTHETIC neutral 100", after = "SYNTHETIC neutral 120" })); await capture("synthetic-neutral-coverage");
            await SelectSourcePairForSmoke(1, 2); Install(J(new { kind = "text_modified", before = "SYNTHETIC PDF observation", after = "SYNTHETIC PPTX structure" }));
            if (!After.StructuralPreview || Colored() || !Text().Contains(Copy["structuralObservation"], StringComparison.Ordinal) || !Text().Contains("SYNTHETIC PPTX structure", StringComparison.Ordinal)) throw new InvalidOperationException("Actual unsupported Windows PPTX source fallback received text-edit styling."); await capture("synthetic-structural-fallback-neutral");
        }
        else
        {
            var a = CompleteCell(new { address = "C2", value = "SYNTHETIC stored 100", formula = "=SUM(A1:A3)", number_format = "0", cached_result = "present", formula_interpretation = "explicit" });
            var b = CompleteCell(new { address = "C3", value = (string?)null, formula = "=SUM(B1:B3)", number_format = "0", cached_result = "missing", formula_interpretation = "explicit" });
            JsonElement Payload(JsonElement left, JsonElement right) => J(new { before = new { items = new[] { new { before = left } } }, after = new { items = new[] { new { after = right } } } });
            foreach (var kind in new[] { "cache_availability", "stored_value", "cell_observation", "row_correspondence", "sheet_observation", "formatting_range" })
            {
                Install(J(new { kind, association = "inferred", alignment_method = "synthetic_control" }), Payload(a, b));
                if (Colored() || !Text().Contains("=SUM(A1:A3)", StringComparison.Ordinal) || !Text().Contains(Copy["observationNull"], StringComparison.Ordinal) || !Text().Contains("C2", StringComparison.Ordinal) || !Text().Contains("C3", StringComparison.Ordinal)) throw new InvalidOperationException("Unavailable/structural workbook observations became colored deletion or lost exact source fields.");
            }
            await capture("synthetic-missing-cache-neutral");
            Install(J(new { kind = "formula" }), Payload(a, b)); if (!Colored() || !Text().Contains(Copy["missingCacheObservation"], StringComparison.Ordinal) || !Text().Contains("=SUM(B1:B3)", StringComparison.Ordinal)) throw new InvalidOperationException("Exact eligible formulas were conflated with missing saved values."); await capture("synthetic-formula-independent-cache");
            var firstA = CompleteCell(new { address = "C2", value = "100", formula = (string?)null, number_format = "0", cached_result = "not_applicable", formula_interpretation = "not_formula" });
            var firstB = WithRange(CompleteCell(new { address = "C3", value = "120", formula = (string?)null, number_format = "0", cached_result = "not_applicable", formula_interpretation = "not_formula" }), "value", new { offset = 0, total_length = 9, next_offset = 3, state = "truncated" });
            var laterA = WithRange(CompleteCell(new { address = "C2", value = "", formula = (string?)null, number_format = "0", cached_result = "not_applicable", formula_interpretation = "not_formula" }), "value", new { offset = 3, total_length = 3, next_offset = (int?)null, state = "truncated" });
            var laterB = WithRange(CompleteCell(new { address = "C3", value = "LONGER", formula = (string?)null, number_format = "0", cached_result = "not_applicable", formula_interpretation = "not_formula" }), "value", new { offset = 3, total_length = 9, next_offset = (int?)null, state = "truncated" });
            Install(J(new { kind = "stored_value" }), Payload(firstA, firstB)); detailLoader = (offset, _) => Task.FromResult(offset == 0 ? Payload(firstA, firstB) : Payload(laterA, laterB)); await LoadDetail(0); SetLayout(WorkspaceLayout.Preset("focus"));
            foreach (var language in new[] { "ko", "en" })
            {
                SetLanguage(language); if (Colored() || !rawTextPaging.IsVisible || !nextTextStage.IsVisible || !nextTextStage.IsEnabled || InspectorPane.IsVisible || !Text().Contains("[0, 3) / 9", StringComparison.Ordinal) || !Text().Contains(Copy["partialSourceSegment"], StringComparison.Ordinal)) throw new InvalidOperationException("Budget-shortened source ranges or native text pager disappeared in Focus/" + language);
                await NextDetail(); if (Colored() || !Text().Contains(Copy["alreadyReadSegment"], StringComparison.Ordinal) || !Text().Contains("[3, 3) / 3", StringComparison.Ordinal) || !Text().Contains("[3, 9) / 9", StringComparison.Ordinal) || !firstTextStage.IsEnabled) throw new InvalidOperationException("Already-read field became an empty-value edit or lost independent source ranges in " + language); await FirstDetail();
            }
            await capture("synthetic-partial-source-ranges-pager");
            Install(J(new { kind = "stored_value" }), Payload(firstA, WithRange(firstB, "value", new { offset = 0, total_length = 9, next_offset = (int?)null, state = "complete" }))); if (Colored() || !Text().Contains(Copy["invalidSourceSegment"], StringComparison.Ordinal) || !Text().Contains(Copy["invalidSourceRange"], StringComparison.Ordinal)) throw new InvalidOperationException("Contradictory source metadata certified a complete field.");
            var empty = CompleteCell(new { address = "C3", value = "", formula = (string?)null, number_format = "0", cached_result = "not_applicable", formula_interpretation = "not_formula" }); Install(J(new { kind = "stored_value" }), Payload(firstA, empty)); if (!Colored() || !Text().Contains("[0, 0) / 0", StringComparison.Ordinal)) throw new InvalidOperationException("A validated genuine empty string was confused with a later empty fragment.");
        }
        if (reportId != fixedReport || currentReport.GetRawText() != reportBytes) throw new InvalidOperationException("Presentation-only controls changed the fixed report.");
        selectedChange = default; sourceView.SelectedIndex = previousView ? 1 : 0; SetLayout(layout); await SelectSourcePairForSmoke(0, currentReport.Get("revisions").Items().Count - 1); await CheckIntermediateEventForSmoke();
    }
    internal async Task SelectCell(ComparePane pane, int row, int column)
    {
        if (busy || !IsWorkbook || ComparisonState != "ready" || !pane.AuthorizesCell(row, column)) return;
        var args = new Dictionary<string, object?> { ["revision_occurrence_id"] = pane.RevisionId, ["sheet_id"] = pane.SheetId, ["row"] = row, ["column"] = column, ["text_length"] = 4096 };
        var project = projectId; var report = reportId; ClearDetail(); detailStyle.IsEnabled = true; detailLoader = (offset, cancel) => { var request = new Dictionary<string, object?>(args) { ["text_offset"] = offset, ["component"] = detailStyle.IsChecked == true ? "style" : "cell", ["limit"] = 1 }; if (detailStyle.IsChecked == true && detailCursor.Length > 0) request["cursor"] = detailCursor; return QueryFixed("get_workbook_cell", request, project, report, cancel); }; await LoadDetail(0);
    }
    private Task<JsonElement> QueryFixed(string name, Dictionary<string, object?> args, string project, string report, CancellationToken token) { args["project_id"] = project; args["report_id"] = report; args["max_output_tokens"] = 8000; return Bridge.Call("workbookQuery", new { name, args }, token); }
    private void ClearDetail() { ++detailGeneration; cellReads.Cancel(); detailLoader = null; detailPayload = default; documentDetail = default; inspectorMode = "prompt"; detailNext = null; detailOffset = 0; detailCursor = ""; detailItemNext = ""; detailStyle.IsChecked = false; detailStyle.IsEnabled = false; detailRange.Text = ""; detailMetadata.Text = ""; firstDetail.IsEnabled = false; nextDetail.IsEnabled = false; }
    private Task FirstDetail() { detailCursor = ""; return LoadDetail(0); }
    private Task NextDetail() { if (detailNext is { } offset) return LoadDetail(offset); if (detailItemNext.Length > 0) { detailCursor = detailItemNext; return LoadDetail(0); } return Task.CompletedTask; }
    private async Task LoadDetail(int offset)
    {
        if (detailLoader is not { } loader) return; var sequence = ++detailGeneration; var ticket = generation; cellReads.Cancel(); cellReads.Dispose(); cellReads = new(); var token = cellReads.Token; firstDetail.IsEnabled = false; nextDetail.IsEnabled = false; detailPayload = default; documentDetail = default; inspectorMode = "loading"; detailMetadata.Text = ""; detailRange.Text = ""; detail.Text = Copy["loading"]; RenderSourceDiff();
        try { var value = await loader(offset, token); if (!IsCurrent(ticket) || sequence != detailGeneration || token.IsCancellationRequested) return; detailOffset = offset; detailNext = RawSourcePaging.Next(value, offset); detailItemNext = value.Get("next_cursor").Text(); detailPayload = value; inspectorMode = "raw"; RerenderInspector(); detailMetadata.Text = value.Pretty(); firstDetail.IsEnabled = !busy && (offset > 0 || detailCursor.Length > 0); nextDetail.IsEnabled = !busy && (detailNext is not null || detailItemNext.Length > 0); RenderSourceDiff(); }
        catch { if (IsCurrent(ticket) && sequence == detailGeneration && !token.IsCancellationRequested) { inspectorMode = "failed"; detail.Text = Copy["failed"]; firstDetail.IsEnabled = true; RenderSourceDiff(); } throw; }
    }
    private void RerenderInspector()
    {
        if (inspectorMode == "raw" && detailPayload.ValueKind == JsonValueKind.Object) { detail.Text = FormatDetail(detailPayload); detailRange.Text = FormatRanges(detailPayload); return; }
        if (inspectorMode == "event" && documentDetail.ValueKind == JsonValueKind.Object) { detail.Text = Copy["event"] + ": " + VersionLabel(Before.RevisionId) + " → " + VersionLabel(After.RevisionId) + "\n\n" + Copy["before"] + "\n" + documentDetail.Get("before").Text() + "\n\n" + Copy["after"] + "\n" + documentDetail.Get("after").Text(); return; }
        if (inspectorMode == "failed" || ComparisonState == "failed") detail.Text = Copy["failed"];
        else if (inspectorMode == "loading" || ComparisonState == "loading") detail.Text = Copy["loading"];
        else if (ComparisonState == "invalid") detail.Text = Copy["reverse"];
        else if (ComparisonState == "ready" && changes.Count == 0) detail.Text = Copy["noChanges"] + "\n\n" + Copy["coverage"] + "\n" + currentReport.Get("coverage_gaps").Pretty();
        else if (inspectorMode == "draft") detail.Text = Copy["noReport"];
        else if (inspectorMode == "empty") detail.Text = Copy["chooseProject"];
        else detail.Text = Copy["selectCell"];
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
    private string FormatRanges(JsonElement value)
    {
        var lines = new List<string> { Copy["textRange"] };
        void Cell(JsonElement cell, string side)
        {
            foreach (var field in new[] { "value", "formula", "number_format" })
            {
                var range = cell.Get("text_continuations").Get(field); if (range.ValueKind != JsonValueKind.Object) continue;
                var start = range.Get("offset").Number(); var end = start + cell.Get(field).Text().Length; var total = range.Get("total_length").Number();
                lines.Add(side + (side.Length > 0 ? " · " : "") + (field == "value" ? Copy["cached"] : field == "formula" ? Copy["formula"] : field) + ": [" + start + ", " + end + ") / " + total + " · " + range.Get("state").Text());
            }
        }
        if (value.Get("before").ValueKind == JsonValueKind.Object) { Cell(value.Get("before").Get("items").Items().FirstOrDefault().Get("before"), Copy["before"]); Cell(value.Get("after").Get("items").Items().FirstOrDefault().Get("after"), Copy["after"]); }
        else if (value.Get("component").Text() == "style") foreach (var item in value.Get("items").Items()) { var range = item.Get("text_continuations").Get("value"); var start = range.Get("offset").Number(); lines.Add(item.Get("key").Text() + ": [" + start + ", " + (start + item.Get("value").Text().Length) + ") / " + range.Get("total_length").Number()); }
        else Cell(value.Get("items").Items().FirstOrDefault(), "");
        return string.Join("\n", lines);
    }
    internal IEnumerable<GridSplitter> NativeSplitters()
    {
        IEnumerable<DependencyObject> Visit(DependencyObject parent) { for (var index = 0; index < VisualTreeHelper.GetChildrenCount(parent); index++) { var child = VisualTreeHelper.GetChild(parent, index); yield return child; foreach (var nested in Visit(child)) yield return nested; } }
        return Visit(workspace).OfType<GridSplitter>();
    }
    internal int ActionableChanges => changesReady && changeList.IsEnabled ? changes.Count : 0;
    internal string DetailText => detail.Text;
    internal async Task CheckNarrowSidebarForSmoke()
    {
        var fixedReport = reportId; var project = projectId;
        if (!Layout.Sidebar) SetLayout(Layout with { Sidebar = true });
        var preferred = (Layout.SidebarWidth, Layout.InspectorWidth, Layout.ChangesWidth, Layout.ChangesHeight, Layout.ComparisonRatio);
        var layoutMenu = new MenuItem(); BuildLayoutMenu(layoutMenu);
        var toggle = layoutMenu.Items.OfType<MenuItem>().Single(item => item.Header as string == Copy["sidebar"]);
        if (!SidebarPane.IsVisible || !projectList.IsVisible || projectList.Items.Count == 0) throw new InvalidOperationException("Narrow window does not expose its requested existing-project sidebar.");
        toggle.RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent, toggle)); UpdateLayout();
        if (SidebarPane.IsVisible || Layout.Sidebar) throw new InvalidOperationException("Native Layout menu did not hide the project sidebar.");
        toggle.RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent, toggle)); UpdateLayout();
        if (!SidebarPane.IsVisible || !projectList.IsVisible || !Layout.Sidebar) throw new InvalidOperationException("Native Layout menu could not restore the project sidebar in a narrow window.");
        if (preferred != (Layout.SidebarWidth, Layout.InspectorWidth, Layout.ChangesWidth, Layout.ChangesHeight, Layout.ComparisonRatio)) throw new InvalidOperationException("Narrow sidebar toggle overwrote preferred dimensions.");
        var existing = projectList.Items.OfType<Choice>().FirstOrDefault(item => item.Id == project) ?? throw new InvalidOperationException("The current existing project was not reachable in the native list.");
        await OpenProject(existing.Value);
        if (ComparisonState != "ready" || status.Text != Copy[Preferences.IsReadOnly ? "preferencesReadOnly" : "ready"]) throw new InvalidOperationException("Existing-project reselection retained loading after a verified comparison.");
        await OpenReport(fixedReport);
        if (projectId != project || reportId != fixedReport || ComparisonState != "ready" || status.Text != Copy[Preferences.IsReadOnly ? "preferencesReadOnly" : "ready"]) throw new InvalidOperationException("Selecting an existing project did not return to its pinned report with settled ready status.");
    }
    internal async Task CheckProjectTransitionAuthorityForSmoke(Func<Task<string>> counts)
    {
        var source = projectList.Items.OfType<Choice>().First(item => item.Id == projectId); var fixedReport = reportId;
        var candidate = projectList.Items.OfType<Choice>().FirstOrDefault(item => item.Id != source.Id) ?? throw new InvalidOperationException("Project transition control requires a second real project.");
        var initialCounts = await counts(); var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously); var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        binding = true; projectList.SelectedItem = candidate; binding = false;
        var loading = OpenProject(candidate.Value, async token => { entered.TrySetResult(); await release.Task.WaitAsync(TimeSpan.FromSeconds(20), token); });
        void AssertNoWriterTarget()
        {
            if (projectId.Length != 0 || reportId.Length != 0 || currentProject.ValueKind != JsonValueKind.Undefined || currentReport.ValueKind != JsonValueKind.Undefined || analyzeButton.IsEnabled || reorderButton.IsEnabled || exportButton.IsEnabled || mcpButton.IsEnabled) throw new InvalidOperationException("Pending/failed project selection retained an actionable previous or unverified writer target.");
        }
        try
        {
            AssertNoWriterTarget(); await entered.Task.WaitAsync(TimeSpan.FromSeconds(10)); AssertNoWriterTarget();
            await Analyze(); await Reorder(); await Export(); AssertNoWriterTarget();
            if (initialCounts != await counts()) throw new InvalidOperationException("A project mutation dispatched while its real reports reply was pending.");
        }
        finally { release.TrySetResult(); }
        await loading; if (projectId != candidate.Id || currentProject.Get("project_id").Text() != candidate.Id || status.Text == Copy["loading"] || reportId.Length == 0 && status.Text != Copy["noReport"] || reportId.Length > 0 && (ComparisonState != "ready" || status.Text != Copy[Preferences.IsReadOnly ? "preferencesReadOnly" : "ready"])) throw new InvalidOperationException("Validated candidate did not become authoritative with its draft/ready status after its reports read settled.");
        binding = true; projectList.SelectedItem = source; binding = false; await OpenProject(source.Value);
        if (ComparisonState != "ready" || status.Text != Copy[Preferences.IsReadOnly ? "preferencesReadOnly" : "ready"]) throw new InvalidOperationException("Reselecting the saved project left a loading caption after verified comparison readiness.");
        await OpenReport(fixedReport);
        binding = true; projectList.SelectedItem = candidate; binding = false;
        try { await OpenProject(candidate.Value, _ => throw new IOException("Isolated post-reply project transition settlement failure")); throw new InvalidOperationException("Post-reply transition failure control unexpectedly installed the candidate."); } catch (IOException) { }
        AssertNoWriterTarget(); await Analyze(); await Reorder(); await Export();
        if (initialCounts != await counts()) throw new InvalidOperationException("A failed transition dispatched analysis or changed pinned report counts.");
        binding = true; projectList.SelectedItem = source; binding = false; await OpenProject(source.Value); await OpenReport(fixedReport);
        if (projectId != source.Id || reportId != fixedReport || ComparisonState != "ready" || status.Text != Copy[Preferences.IsReadOnly ? "preferencesReadOnly" : "ready"]) throw new InvalidOperationException("Project selection did not recover its exact previous pinned report and ready status.");
    }
    internal async Task CheckIndependentProjectRefreshForSmoke()
    {
        var project = projectId; var fixedReport = reportId; var from = intervalFrom; var to = intervalTo; var mode = NetMode;
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously); var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var refresh = RefreshProjectsCore(async () => { entered.TrySetResult(); await release.Task.WaitAsync(TimeSpan.FromSeconds(20)); });
        try
        {
            await entered.Task.WaitAsync(TimeSpan.FromSeconds(10)); var initialGeneration = generation;
            comparisonMode.SelectedIndex = mode ? 0 : 1; await modeRequest; await ReloadSourceWindow();
            if (generation <= initialGeneration || projectId != project || reportId != fixedReport || intervalFrom != from || intervalTo != to || NetMode == mode || ComparisonState != "ready") throw new InvalidOperationException("Comparison mode/source changes did not retain their authoritative scope while the independent project list was pending.");
        }
        finally { release.TrySetResult(); }
        await refresh;
        if (!projectChoicesReady || !projectList.IsEnabled || !projectList.Items.OfType<Choice>().Any(item => item.Id == project) || projectId != project || reportId != fixedReport || ComparisonState != "ready") throw new InvalidOperationException("Same-workspace comparison changes stranded the project list refresh.");
        comparisonMode.SelectedIndex = mode ? 1 : 0; await modeRequest;
    }
    internal async Task CheckWorkspaceListForSmoke()
    {
        var workbook = IsWorkbook; var existing = projectList.Items.OfType<Choice>().First(item => item.Id == projectId); var fixedReport = reportId;
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously); var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var switching = SwitchWorkspace(!workbook, async () => { entered.TrySetResult(); await release.Task.WaitAsync(TimeSpan.FromSeconds(20)); });
        try
        {
            await entered.Task.WaitAsync(TimeSpan.FromSeconds(10)); var ticket = generation;
            if (projectChoicesReady || projectList.IsEnabled || projectList.Items.Count != 0 || projectId.Length != 0 || IsWorkbook == workbook) throw new InvalidOperationException("Workspace transition retained actionable old project rows.");
            await OpenProject(existing.Value);
            if (generation != ticket || projectId.Length != 0 || IsWorkbook == workbook) throw new InvalidOperationException("Stale project activation poisoned the new workspace scope.");
        }
        finally { release.TrySetResult(); }
        await switching; if (!projectChoicesReady || !projectList.IsEnabled) throw new InvalidOperationException("The new workspace list did not become available.");
        await SwitchWorkspace(workbook); await OpenProject(existing.Value); await OpenReport(fixedReport);
        if (!projectChoicesReady || projectId != existing.Id || reportId != fixedReport || ComparisonState != "ready") throw new InvalidOperationException("Current workspace membership could not reopen its existing pinned report.");
    }
    internal async Task CheckModesForSmoke(bool transient)
    {
        async Task SetMode(bool net) { comparisonMode.SelectedIndex = net ? 1 : 0; await modeRequest; }
        await SetMode(false); await SelectSourcePairForSmoke(0, 2); await CheckIntermediateEventForSmoke();
        var a = intervalFrom; var b = intervalTo; var paneA = Before.CaptureSelection(); var paneB = After.CaptureSelection(); var fixedReport = reportId;
        async Task<bool> ContainsTemporary()
        {
            var pages = 0; while (nextChanges.Length > 0 && pages++ < 100) await LoadMoreChanges();
            if (nextChanges.Length > 0) throw new InvalidOperationException("Mode fixture exceeded bounded change paging.");
            foreach (var change in changes.Where(change => change.Value.Get("kind").Text() == "row_correspondence"))
            {
                foreach (var side in new[] { "before", "after" })
                {
                    var args = new Dictionary<string, object?> { ["change_id"] = change.Id, ["mode"] = NetMode ? "range_net" : "history", ["from_revision_occurrence_id"] = change.Value.Get("from_revision_occurrence_id").Text(), ["to_revision_occurrence_id"] = change.Value.Get("to_revision_occurrence_id").Text(), ["component"] = side, ["text_length"] = 256 };
                    var raw = await Query("get_workbook_change", args, reads.Token);
                    if (raw.Get("items").Items().Any(item => item.Get(side).Get("value").Text() == "SKU003")) return true;
                }
            }
            return false;
        }
        if (transient && !await ContainsTemporary()) throw new InvalidOperationException("History did not expose the temporary SKU003 event.");
        await SetMode(true);
        if (ComparisonState != "ready" || !NetMode || intervalFrom != a || intervalTo != b || reportId != fixedReport || Before.CaptureSelection() != paneA || After.CaptureSelection() != paneB) throw new InvalidOperationException("Mode toggle changed the pinned query interval or intermediate evidence pair.");
        if (selectedChange.ValueKind != JsonValueKind.Undefined || selectedBefore is not null || selectedAfter is not null || returnChange.Visibility != Visibility.Collapsed) throw new InvalidOperationException("Mode change retained selected-event metadata from the other change-list mode.");
        if (transient && await ContainsTemporary()) throw new InvalidOperationException("Endpoint net mode retained a reverted intermediate SKU003 event.");
        var eventToInspect = changes.FirstOrDefault(); if (eventToInspect is not null) await SelectChange(eventToInspect.Value);
        await SetMode(false);
        if (ComparisonState != "ready" || NetMode || intervalFrom != a || intervalTo != b || reportId != fixedReport) throw new InvalidOperationException("History toggle lost its explicit fixed interval.");
        await SelectSourcePairForSmoke(0, currentReport.Get("revisions").Items().Count - 1);
    }
    internal void CheckLayoutDialogForSmoke()
    {
        var expected = Layout; var name = "smoke_saved_{0}%_한글"; Preferences.For(IsWorkbook).Named.Remove(name);
        var dialog = CreateNamedLayoutDialog(); var stack = (StackPanel)dialog.Content; var field = stack.Children.OfType<TextBox>().Single(); var buttons = stack.Children.OfType<StackPanel>().Single();
        dialog.Loaded += (_, _) => dialog.Dispatcher.BeginInvoke(() => { field.Text = name; buttons.Children.OfType<Button>().Single(button => button.Name == "SaveLayout").RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); });
        if (dialog.ShowDialog() != true || !Preferences.For(IsWorkbook).Named.TryGetValue(name, out var saved) || saved != expected) throw new InvalidOperationException("Native layout dialog Save did not persist the opaque authored name.");
        SetLayout(WorkspaceLayout.Preset("focus")); var menu = new MenuItem(); BuildLayoutMenu(menu); var apply = menu.Items.OfType<MenuItem>().Single(item => item.Header as string == Copy["applyLayout"]); var savedItem = apply.Items.OfType<MenuItem>().Single(item => item.Header is TextBlock block && block.Text == name); savedItem.RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent));
        if (Layout != expected) throw new InvalidOperationException("Saved-layout native menu did not apply the saved configuration.");
        var cancelled = CreateNamedLayoutDialog(); var cancelledStack = (StackPanel)cancelled.Content; var cancelButtons = cancelledStack.Children.OfType<StackPanel>().Single(); cancelled.Loaded += (_, _) => cancelled.Dispatcher.BeginInvoke(() => { cancelledStack.Children.OfType<TextBox>().Single().Text = "must_not_save"; cancelButtons.Children.OfType<Button>().Single(button => button.Name == "CancelLayout").RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); });
        if (cancelled.ShowDialog() == true || Preferences.For(IsWorkbook).Named.ContainsKey("must_not_save")) throw new InvalidOperationException("Native layout dialog Cancel changed saved layouts.");
        foreach (var language in new[] { "ko", "en" }) { SetLanguage(language); if (languageItems.Count(item => item.Value.IsChecked) != 1 || !languageItems[language].IsChecked) throw new InvalidOperationException("Language menu check states are not exclusive."); }
    }
    internal async Task CheckFirstImportForSmoke(string title, IReadOnlyList<ImportRow> rows, bool cancel, Action? afterCreateForSmoke = null)
    {
        var startedPid = 0;
        try { await ImportAndAnalyze(title, rows, cancel ? pid => { startedPid = pid; operation?.Cancel(); } : null, afterCreateForSmoke); throw new InvalidOperationException("First-import negative control unexpectedly succeeded."); }
        catch (OperationCanceledException) when (cancel) { }
        catch (BridgeException) when (!cancel) { }
        if (busy || projectId.Length == 0 || reportId.Length != 0 || ComparisonState != "draft" || retryComparison.Visibility == Visibility.Visible || detail.Text != Copy["noReport"] || !projectList.Items.OfType<Choice>().Any(project => project.Id == projectId) || cancel && startedPid <= 0) throw new InvalidOperationException("Failed/cancelled first import did not expose its saved draft without a dead comparison retry.");
    }
    internal void CheckInitializationGateForSmoke()
    {
        if (!initializing || importButton.IsEnabled || documents.IsEnabled || workbooks.IsEnabled || projectList.IsEnabled || reports.IsEnabled || actionItems.Values.Any(item => item.IsEnabled)) throw new InvalidOperationException("A library action became available before initialization completed.");
    }
    internal async Task CheckRetainedImportRecoveryForSmoke(IReadOnlyList<ImportRow> rows)
    {
        var project = projectId; var fixedReport = reportId; var reportBytes = (await Bridge.Call(IsWorkbook ? "workbookView" : "view", Json.Scope(project, fixedReport))).GetRawText(); var revisions = currentReport.Get("revisions").Items();
        await SelectSourcePairForSmoke(0, revisions.Count - 1); comparisonMode.SelectedIndex = 0; await modeRequest; await CheckIntermediateEventForSmoke();
        var before = Before.CaptureSelection(); var after = After.CaptureSelection(); var from = intervalFrom; var to = intervalTo;
        foreach (var cancel in new[] { true, false })
        {
            var created = ""; var started = 0;
            try
            {
                await ImportAndAnalyze("Recovery query selectors " + (cancel ? "cancelled" : "post-create failure"), rows, cancel ? pid => { started = pid; operation?.Cancel(); } : null, () => { created = projectId; if (created == project || reportId.Length != 0 || queryBefore.Items.Count != 0 || queryAfter.Items.Count != 0) throw new InvalidOperationException("New-import control did not pass through the cleared new draft."); if (!cancel) throw new IOException("Synthetic failure immediately after durable new-draft creation"); });
                throw new InvalidOperationException("New-import recovery control unexpectedly completed.");
            }
            catch (OperationCanceledException) when (cancel) { }
            catch (IOException) when (!cancel) { }
            if (created.Length == 0 || cancel && started <= 0 || busy || projectId != project || reportId != fixedReport || ComparisonState != "ready" || Before.CaptureSelection() != before || After.CaptureSelection() != after || intervalFrom != from || intervalTo != to || queryBefore.Items.Count != revisions.Count || queryAfter.Items.Count != revisions.Count || (queryBefore.SelectedItem as Choice)?.Id != from || (queryAfter.SelectedItem as Choice)?.Id != to || !queryBefore.IsEnabled || !queryAfter.IsEnabled || !projectList.Items.OfType<Choice>().Any(item => item.Id == created)) throw new InvalidOperationException("Cancelled/failed new import did not restore populated exact saved-report query selectors and source selections.");
            var reread = await Bridge.Call(IsWorkbook ? "workbookView" : "view", Json.Scope(project, fixedReport)); if (reread.GetRawText() != reportBytes) throw new InvalidOperationException("New-import recovery changed the fixed report.");
        }
        var middle = revisions[1].Get("revision_occurrence_id").Text(); queryAfter.SelectedItem = queryAfter.Items.OfType<Choice>().Single(item => item.Id == middle); await endpointRequest;
        if (intervalFrom != from || intervalTo != middle || ComparisonState != "ready" || reportId != fixedReport || (queryAfter.SelectedItem as Choice)?.Id != middle) throw new InvalidOperationException("Restored native query selector could not perform a subsequent explicit endpoint change.");
        await SelectSourcePairForSmoke(0, revisions.Count - 1); await CheckIntermediateEventForSmoke();
    }
    internal async Task<object> CheckLostAnalysisReplyForSmoke()
    {
        var project = projectId; var fixedReport = reportId; var workbook = IsWorkbook;
        var oldSource = await Bridge.Call(workbook ? "workbookView" : "view", Json.Scope(project, fixedReport)); JsonElement lost = default;
        try
        {
            await AnalyzeWithStarted(null, beforeReplyForSmoke: (reply, token) => { lost = reply; operation?.Cancel(); return Task.CompletedTask; });
            throw new InvalidOperationException("Withheld descriptor cancellation unexpectedly reached the application.");
        }
        catch (OperationCanceledException) { }
        var run = lost.Get("analysis_run_id").Text(); var name = lost.Get("staged_name").Text();
        if (run.Length == 0 || name != run + ".json" || lost.Get("project_id").Text() != project || reportId != fixedReport || ComparisonState != "ready") throw new InvalidOperationException("Real withheld analysis descriptor or previous fixed report control is invalid.");
        var stagePath = Path.Combine(Bridge.Library, workbook ? "workbook-staging-v1" : "staging-v4", name);
        var before = await Bridge.Call(workbook ? "workbookRunStatus" : "runStatus", new { project_id = project, analysis_run_id = run });
        if (!File.Exists(stagePath) || before.Get("status").Text() is not ("running" or "staged")) throw new InvalidOperationException("The lost-descriptor control did not leave a real uncommitted stage/run.");
        await Analyze();
        var after = await Bridge.Call(workbook ? "workbookRunStatus" : "runStatus", new { project_id = project, analysis_run_id = run });
        var preserved = await Bridge.Call(workbook ? "workbookView" : "view", Json.Scope(project, fixedReport));
        if (after.Get("status").Text() is "running" or "staged" || File.Exists(stagePath) || oldSource.GetRawText() != preserved.GetRawText() || busy || ComparisonState != "ready" || reportId.Length == 0) throw new InvalidOperationException("Same-session admitted recovery did not retire the lost run/stage and preserve its prior fixed report.");
        return new { analysis_run_id = run, status_before = before.Get("status").Text(), status_after = after.Get("status").Text(), stage_existed_before = true, stage_exists_after = false, previous_report_id = fixedReport, previous_report_unchanged = true, boundary = "verified real helper reply withheld before caller receives descriptor" };
    }
    internal double WorkspaceHeightForSmoke => workspace.ActualHeight;
    internal double EffectiveChangesHeightForSmoke => Math.Min(Layout.ChangesHeight, Math.Max(100, workspace.ActualHeight - 240));
    internal async Task CheckMissingVersionSheetForSmoke()
    {
        await SelectSourcePairForSmoke(0, currentReport.Get("revisions").Items().Count - 1);
        await Before.SelectRevisionForSmoke(3);
        if (Before.ReadState != "absent" || Before.SheetId.Length != 0 || Before.Cells.Items.Count != 0 || Before.AuthorizesCell(1, 1) || !Before.PresentedFallback.Contains(Copy["missingSelectedSheet"], StringComparison.Ordinal)) throw new InvalidOperationException("Explicit version change substituted the first available sheet for the previous missing sheet.");
        await Before.SelectAvailableSheetForSmoke(); if (Before.ReadState != "ready" || Before.SheetId.Length == 0 || !Before.AuthorizesCell(1, 1)) throw new InvalidOperationException("Explicit available-sheet selection did not load its own source.");
        await SelectSourcePairForSmoke(0, currentReport.Get("revisions").Items().Count - 1);
    }
    internal void CheckChangeCaptionLanguageForSmoke()
    {
        if (changes.Count == 0) throw new InvalidOperationException("Caption locale qualification requires existing change rows.");
        var oldSelection = changeList.SelectedItem; binding = true; changeList.SelectedItem ??= changes[0]; binding = false;
        var selection = changeList.SelectedItem; var rows = changes.ToArray(); var raw = rows.Select(change => change.Value.GetRawText()).ToArray(); var english = rows.Select(change => change.Caption).ToArray(); var ticket = generation; var fixedReport = reportId; var from = intervalFrom; var to = intervalTo; var net = NetMode; var before = Before.CaptureSelection(); var after = After.CaptureSelection();
        foreach (var language in new[] { "ko", "en" })
        {
            SetLanguage(language);
            if (!ReferenceEquals(changeList.SelectedItem, selection) || generation != ticket || reportId != fixedReport || intervalFrom != from || intervalTo != to || NetMode != net || Before.CaptureSelection() != before || After.CaptureSelection() != after || !rows.SequenceEqual(changes) || rows.Where((row, index) => row.Value.GetRawText() != raw[index] || row.Caption != ChangeCaption(row.Value)).Any()) throw new InvalidOperationException("Existing change caption localization altered selection, source or comparison scope.");
            if (language == "ko" && rows.Select((row, index) => row.Caption != english[index]).All(changed => !changed)) throw new InvalidOperationException("Known change kinds did not translate in the native change list.");
        }
        binding = true; changeList.SelectedItem = oldSelection; binding = false;
    }
    internal void CheckLoadedLanguageForSmoke()
    {
        if (inspectorMode != "raw" || detailPayload.ValueKind != JsonValueKind.Object) throw new InvalidOperationException("Language qualification requires retained loaded source detail.");
        var payload = detailPayload.GetRawText(); var before = Before.CaptureSelection(); var after = After.CaptureSelection(); var report = reportId; var ticket = generation;
        foreach (var language in new[] { "ko", "en" }) { SetLanguage(language); if (!detail.Text.Contains(Copy["cached"], StringComparison.Ordinal) || !detail.Text.Contains(Copy["formula"], StringComparison.Ordinal) || detailPayload.GetRawText() != payload || generation != ticket || reportId != report || Before.CaptureSelection() != before || After.CaptureSelection() != after) throw new InvalidOperationException("Language change did not locally rerender retained detail without altering source/scope."); }
    }
    internal bool AllowsEvidence => !busy && !initializing;
    internal Task AnalyzeForSmoke() => Analyze();
    internal async Task CheckAnalysisCancellationForSmoke()
    {
        var fixedReport = reportId; var before = Before.CaptureSelection(); var after = After.CaptureSelection(); var oldChange = changes.FirstOrDefault()?.Value ?? default;
        var pending = ReloadComparison(); var startedPid = 0; var analysis = AnalyzeWithStarted(pid => { startedPid = pid; operation?.Cancel(); });
        if (!busy || ActionableChanges != 0 || Before.Cells.IsEnabled || After.Cells.IsEnabled || nextDetail.IsEnabled) throw new InvalidOperationException("Mutation admission retained actionable evidence.");
        var admitted = generation; await SelectCell(Before, before.Row, before.Column); await SelectChange(oldChange);
        if (generation != admitted || ActionableChanges != 0) throw new InvalidOperationException("Busy evidence interaction started a new request scope.");
        try { await analysis; throw new InvalidOperationException("Actual analysis cancellation unexpectedly completed."); } catch (OperationCanceledException) { }
        try { await pending; } catch (OperationCanceledException) { }
        if (startedPid <= 0 || busy || reportId != fixedReport || Before.CaptureSelection() != before || After.CaptureSelection() != after || ComparisonState != "ready" || detail.Text == Copy["loading"]) throw new InvalidOperationException("Cancelled analysis did not restore the exact comparison after a pending read.");
    }
    internal async Task CheckPostCommitAdmissionForSmoke()
    {
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously); var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var analysis = AnalyzeWithStarted(null, async () => { entered.TrySetResult(); await release.Task; });
        try
        {
            await entered.Task.WaitAsync(TimeSpan.FromSeconds(30)); var owner = operation; var ticket = generation;
            if (!busy || owner is null || !owner.Token.CanBeCanceled) throw new InvalidOperationException("Writer admission was released before successful report refresh.");
            await Analyze(); await ImportAndAnalyze("must remain rejected", []);
            if (!busy || !ReferenceEquals(operation, owner) || generation != ticket) throw new InvalidOperationException("A second mutation replaced the post-commit writer owner.");
            owner.Cancel(); if (!owner.IsCancellationRequested || !ReferenceEquals(operation, owner)) throw new InvalidOperationException("Post-commit cancellation did not belong to the admitted writer.");
        }
        finally { release.TrySetResult(); }
        await analysis; if (busy || operation is not null || ComparisonState != "ready" || reportId.Length == 0 || detail.Text == Copy["loading"]) throw new InvalidOperationException("Successful report refresh did not release its own writer cleanly.");
    }
    internal async Task CheckFailedGridForSmoke(Func<Task> corrupt, Func<Task> restore)
    {
        var expectedBefore = Before.CaptureSelection(); var expectedAfter = After.CaptureSelection(); var expectedFrom = intervalFrom; var expectedTo = intervalTo; var expectedMode = NetMode;
        await corrupt();
        try
        {
            var loading = ReloadComparisonCore(true);
            if (Before.Cells.Items.Count != 0 || Before.Cells.IsEnabled || Before.AuthorizesCell(Before.SelectedRow, Before.SelectedColumn) || ActionableChanges != 0 || nextDetail.IsEnabled) throw new InvalidOperationException("Old source remained actionable while a new grid scope was loading.");
            try { await loading; throw new InvalidOperationException("Corrupt indexed cell unexpectedly loaded."); } catch (BridgeException) { }
            if (Before.ReadState != "failed" || Before.Cells.Items.Count != 0 || ComparisonState != "failed" || ActionableChanges != 0 || retryComparison.Visibility != Visibility.Visible) throw new InvalidOperationException("Failed scoped grid retained stale payload or looked empty-success.");
            await SelectCell(Before, Before.SelectedRow, Before.SelectedColumn); if (detail.Text != Copy["failed"]) throw new InvalidOperationException("Failed grid selection replaced unavailable evidence.");
        }
        finally { await restore(); }
        await RetryComparison(); if (Before.ReadState != "ready" || ComparisonState != "ready" || Before.CaptureSelection() != expectedBefore || After.CaptureSelection() != expectedAfter || intervalFrom != expectedFrom || intervalTo != expectedTo || NetMode != expectedMode || !Before.AuthorizesCell(expectedBefore.Row, expectedBefore.Column)) throw new InvalidOperationException("Scoped retry did not recover the exact event/page/sheet/grid window and list interval.");
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
    internal async Task<object> CheckReorderForSmoke(Func<string, Task<string>> fixedReportDigest)
    {
        if (IsWorkbook || reportId.Length == 0) throw new InvalidOperationException("Draft reorder control requires a pinned document report.");
        var project = projectId; var originalReport = reportId; var originalDigest = await fixedReportDigest(originalReport); var savedLayout = Layout;
        static IEnumerable<DependencyObject> Visit(DependencyObject parent) { for (var index = 0; index < VisualTreeHelper.GetChildrenCount(parent); index++) { var child = VisualTreeHelper.GetChild(parent, index); yield return child; foreach (var nested in Visit(child)) yield return nested; } }
        async Task Settle() { UpdateLayout(); await Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle); }
        async Task<JsonElement> Draft() => (await Bridge.Call("projects")).Items().First(item => item.Get("project_id").Text() == project);
        async Task SelectReport(string id)
        {
            var choice = reports.Items.OfType<Choice>().Single(item => item.Id == id);
            if (!ReferenceEquals(reports.SelectedItem, choice)) { reports.SelectedItem = choice; await reportRequest; }
            if (reportId != id || ComparisonState != "ready" || busy) throw new InvalidOperationException("Native fixed-report picker did not select its exact report.");
        }
        async Task MoveAndSave(int selectedIndex, string[] expected)
        {
            Exception? dialogFailure = null;
            await ReorderCore(dialog => dialog.Loaded += (_, _) => dialog.Dispatcher.BeginInvoke(() =>
            {
                try
                {
                    var table = Visit(dialog).OfType<DataGrid>().Single(); var buttons = Visit(dialog).OfType<Button>().ToArray(); table.SelectedIndex = selectedIndex;
                    var expectedIndexes = Enumerable.Range(0, dialog.Rows.Count).ToArray(); (expectedIndexes[selectedIndex], expectedIndexes[selectedIndex + 1]) = (expectedIndexes[selectedIndex + 1], expectedIndexes[selectedIndex]);
                    buttons.Single(button => button.Content as string == Copy["down"]).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
                    if (!dialog.Rows.Select(item => item.Label).SequenceEqual(expected) || !dialog.Rows.Select(item => item.OriginalIndex).SequenceEqual(expectedIndexes)) throw new InvalidOperationException("Native reorder Move down did not change the actual labelled input order.");
                    buttons.Single(button => button.Content as string == Copy["save"]).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
                }
                catch (Exception error) { dialogFailure = error; dialog.DialogResult = false; }
            }));
            if (dialogFailure is not null) throw new InvalidOperationException("Native production reorder dialog failed.", dialogFailure);
        }
        string[] Labels(JsonElement draft) => draft.Get("revisions").Items().Select(item => item.Get("label").Text()).ToArray();
        var initial = await Draft(); var labels = Labels(initial); if (labels.Length < 3) throw new InvalidOperationException("Multi-report reorder needs three document revisions.");
        var orderB = labels.ToArray(); (orderB[0], orderB[1]) = (orderB[1], orderB[0]); await MoveAndSave(0, orderB); await Analyze(); var olderPin = reportId;
        var orderC = orderB.ToArray(); (orderC[1], orderC[2]) = (orderC[2], orderC[1]); await MoveAndSave(1, orderC); await Analyze(); var latestReport = reportId;
        var allReports = (await Bridge.Call("reports", new { project_id = project })).Items();
        if (olderPin == originalReport || olderPin == latestReport || allReports.Count < 3 || allReports[0].Get("report_id").Text() == olderPin || allReports[^1].Get("report_id").Text() != latestReport) throw new InvalidOperationException("Reorder regression requires a distinct older pin which is neither the first nor latest report.");
        await SelectReport(olderPin); comparisonMode.SelectedIndex = 0; await modeRequest; await CheckIntermediateEventForSmoke();
        var revisions = currentReport.Get("revisions").Items(); var beforePages = revisions[0].Get("pages").Items(); var afterPages = revisions[1].Get("pages").Items();
        if (beforePages.Count < 2 || afterPages.Count < 2) throw new InvalidOperationException("Older pinned report must expose two distinct PDF pages on both evidence sides.");
        await Before.SelectPageForSmoke(beforePages[1].Get("page_id").Text()); await After.SelectPageForSmoke(afterPages[1].Get("page_id").Text());
        comparisonMode.SelectedIndex = 1; await modeRequest; SetLayout(WorkspaceLayout.Preset("focus")); Before.Zoom = 2; After.Zoom = 2; await Settle();
        Before.PageScroll.ScrollToHorizontalOffset(80); Before.PageScroll.ScrollToVerticalOffset(35); After.PageScroll.ScrollToHorizontalOffset(90); After.PageScroll.ScrollToVerticalOffset(30); await Settle();
        var beforeSelection = Before.CaptureSelection(); var afterSelection = After.CaptureSelection(); var beforePosition = Before.CaptureViewport(); var afterPosition = After.CaptureViewport(); var fixedFrom = intervalFrom; var fixedTo = intervalTo; var layout = Layout; var beforeHost = Before.Host; var afterHost = After.Host;
        if (!NetMode || fixedFrom == Before.RevisionId && fixedTo == After.RevisionId || beforePosition.Y <= 0 || afterPosition.Y <= 0 || beforePosition.Page != beforePages[1].Get("page_id").Text() || afterPosition.Page != afterPages[1].Get("page_id").Text()) throw new InvalidOperationException("Reorder control did not establish nondefault pages, manual scroll, and an event pair independent of its net interval.");
        var before = await Draft(); var original = Labels(before); if (!Regex.IsMatch(before.Get("draft_hash").Text(), "^[a-f0-9]{64}$", RegexOptions.CultureInvariant)) throw new InvalidOperationException("Production projects response lacks the current reorder draft identity.");
        var expected = original.ToArray(); (expected[0], expected[1]) = (expected[1], expected[0]);
        var reportsBefore = (await Bridge.Call("reports", new { project_id = project })).GetRawText(); var digests = new Dictionary<string, string>(); foreach (var item in allReports) { var id = item.Get("report_id").Text(); digests[id] = await fixedReportDigest(id); }
        await MoveAndSave(0, expected); await Settle();
        var after = await Draft(); var reportsAfter = (await Bridge.Call("reports", new { project_id = project })).GetRawText();
        foreach (var entry in digests) if (await fixedReportDigest(entry.Key) != entry.Value) throw new InvalidOperationException("Draft reorder changed an immutable fixed report body.");
        bool SameViewport(ScrollViewer scroll, double x, double y) => Math.Abs(scroll.HorizontalOffset - Math.Min(x, scroll.ScrollableWidth)) <= 1 && Math.Abs(scroll.VerticalOffset - Math.Min(y, scroll.ScrollableHeight)) <= 1;
        if (!Labels(after).SequenceEqual(expected) || !after.Get("dirty").Flag() || after.Get("draft_hash").Text() == before.Get("draft_hash").Text() || !Regex.IsMatch(after.Get("draft_hash").Text(), "^[a-f0-9]{64}$", RegexOptions.CultureInvariant) || projectId != project || reportId != olderPin || (reports.SelectedItem as Choice)?.Id != olderPin || ComparisonState != "ready" || Before.CaptureSelection() != beforeSelection || After.CaptureSelection() != afterSelection || !NetMode || intervalFrom != fixedFrom || intervalTo != fixedTo || Layout != layout || !ReferenceEquals(beforeHost, Before.Host) || !ReferenceEquals(afterHost, After.Host) || !SameViewport(Before.PageScroll, beforePosition.X, beforePosition.Y) || !SameViewport(After.PageScroll, afterPosition.X, afterPosition.Y) || reportsBefore != reportsAfter || await fixedReportDigest(originalReport) != originalDigest) throw new InvalidOperationException("Production draft reorder lost its older pinned report, exact evidence scope, manual viewport, or immutable reports.");
        var restoredBefore = new { x = Before.PageScroll.HorizontalOffset, y = Before.PageScroll.VerticalOffset }; var restoredAfter = new { x = After.PageScroll.HorizontalOffset, y = After.PageScroll.VerticalOffset };
        // Independent subsequent user navigation restores the original five-page
        // fixture scope used by the bundled MCP verifier, after retention passed.
        SetLayout(savedLayout); await SelectReport(originalReport);
        if (currentReport.Get("revisions").Items().Sum(item => item.Get("pages").Items().Count) != 5) throw new InvalidOperationException("Original MCP document fixture was not restored after the multi-report regression.");
        return new { project_id = project, report_id = olderPin, latest_report_id = latestReport, original_and_final_fixture_report_id = originalReport, fixed_reports = digests, fixed_report_bytes_unchanged = true, reports_list_unchanged = true, draft_order_before = original, draft_order_after = expected, dirty = true, draft_hash_before = before.Get("draft_hash").Text(), draft_hash_after = after.Get("draft_hash").Text(), mode = "range_net", interval_from = fixedFrom, interval_to = fixedTo, before_selection = beforeSelection, after_selection = afterSelection, before_viewport = new { x = beforePosition.X, y = beforePosition.Y }, after_viewport = new { x = afterPosition.X, y = afterPosition.Y }, restored_before_viewport = restoredBefore, restored_after_viewport = restoredAfter, dialog_route = "three actual native Move down and Save actions; production Analyze twice; native report picker selects an older nonfirst fixed report" };
    }
    internal async Task CheckOrderAndAbsenceForSmoke()
    {
        var versions = currentReport.Get("revisions").Items(); var first = versions.First().Get("revision_occurrence_id").Text(); var last = versions.Last().Get("revision_occurrence_id").Text();
        Before.SetEvidenceRevision(last); After.SetEvidenceRevision(first); await ReloadComparison(); if (ComparisonState != "invalid" || ActionableChanges != 0 || detail.Text != Copy["reverse"] || Before.ReadState != "invalid" || After.ReadState != "invalid" || Before.PresentedFallback != Copy["reverse"] || After.PresentedFallback != Copy["reverse"] || Before.Cells.Items.Count != 0 || After.Cells.Items.Count != 0 || Before.PageImage.Source is not null || After.PageImage.Source is not null) throw new InvalidOperationException("Reverse interval retained source data or false loading instead of explicit invalid guidance.");
        var invalidTicket = generation; var invalidReport = reportId; foreach (var language in new[] { "ko", "en" }) { SetLanguage(language); if (generation != invalidTicket || reportId != invalidReport || Before.ReadState != "invalid" || After.ReadState != "invalid" || Before.PresentedFallback != Copy["reverse"] || After.PresentedFallback != Copy["reverse"]) throw new InvalidOperationException("Invalid interval locale update lost explicit guidance or changed source scope."); }
        Before.SetEvidenceRevision(first); After.SetEvidenceRevision(last); Before.RestoreDefaultSelection(); After.RestoreDefaultSelection(); await ReloadComparison();
        if (IsWorkbook)
        {
            Before.SetEvidenceRevision(first, ""); await Before.Load(generation, reads.Token); if (Before.SheetId.Length != 0 || Before.ReadState != "absent" || Before.Cells.Items.Count != 0 || Before.AuthorizesCell(1, 1)) throw new InvalidOperationException("Absent evidence substituted a real sheet/cell.");
            Before.SetEvidenceRevision(first, "unknown_sheet_id"); await Before.Load(generation, reads.Token); if (Before.SheetId.Length != 0 || Before.ReadState != "absent" || Before.Cells.Items.Count != 0) throw new InvalidOperationException("Unknown evidence substituted a real sheet/cell.");
            Before.SetEvidenceRevision(first); After.SetEvidenceRevision(last); Before.RestoreDefaultSelection(); After.RestoreDefaultSelection(); await ReloadComparison();
            ChangeChoice? FindAbsent() => changes.FirstOrDefault(c => c.Value.Get("kind").Text() == "sheet_observation" && (c.Value.Get("from_sheet_id").Text().Length == 0 ^ c.Value.Get("to_sheet_id").Text().Length == 0));
            var absent = FindAbsent(); var pages = 0; while (absent is null && nextChanges.Length > 0 && pages++ < 100) { await LoadMoreChanges(); absent = FindAbsent(); }
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
