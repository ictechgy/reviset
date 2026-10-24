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
    private sealed class ChangeChoice(string id, string caption, JsonElement value, string descriptionLabel = "") : INotifyPropertyChanged
    {
        public string Id { get; } = id;
        public JsonElement Value { get; } = value;
        public string Caption { get; private set; } = caption;
        public string Title => Caption.Split('\n')[0];
        public string Location => Caption.Split('\n').ElementAtOrDefault(1) ?? "";
        public string Preview => string.Join(" ", Caption.Split('\n').Skip(2));
        private string DescriptionLabel { get; set; } = descriptionLabel;
        public string Tooltip => Caption + (Value.Get("description").ValueKind == JsonValueKind.String ? "\n\n" + DescriptionLabel + ":\n" + Value.Get("description").Text() : "");
        public event PropertyChangedEventHandler? PropertyChanged;
        public void Relabel(string text, string label) { Caption = text; DescriptionLabel = label; foreach (var name in new[] { nameof(Caption), nameof(Title), nameof(Location), nameof(Preview), nameof(Tooltip) }) PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name)); }
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
    private readonly TextBlock sourceNotice = new() { TextWrapping = TextWrapping.Wrap, TextTrimming = TextTrimming.CharacterEllipsis, LineHeight = 16, LineStackingStrategy = LineStackingStrategy.BlockLineHeight, MaxHeight = 48, ClipToBounds = true, Margin = new Thickness(10, 3, 10, 4), Foreground = Brushes.DimGray, FontSize = 12 };
    private Button selectedLimitsButton = new();
    private Button storedHistoryButton = new();
    private Task storedHistoryRequest = Task.CompletedTask;
    private (string Project, string Report, string From, string To)? documentRecoveryScope;
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
    private readonly TextBlock queryProvenance = new() { MaxWidth = 185, LineHeight = 15, VerticalAlignment = VerticalAlignment.Center, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(6, 2, 4, 2), FontSize = 12, Foreground = Brushes.DimGray };
    private readonly StackPanel queryControls = new() { Orientation = Orientation.Horizontal };
    private readonly StackPanel soleChanges = new() { Margin = new Thickness(12) };
    private readonly TextBlock soleExplanation = new() { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 10) };
    private Button newComparison = new();
    private Button newComparisonStage = new();
    private string unifiedIdentity = "";
    private long unifiedRender;
    private bool unifiedRestorePending;
    private double unifiedRetainedX;
    private double unifiedRetainedY;
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
    private sealed record ChangeQueryScope(bool Workbook, string Project, string Report, string From, string To, bool Net);
    private ChangeQueryScope? loadedChangeScope;
    private bool sourceOnlyFailure;
    private sealed record EventRetry(ChangeQueryScope Scope, ChangeChoice Row);
    private EventRetry? eventRetry;
    private bool ChangeNavigationReady => !busy && startupReady && loadedChangeScope == CurrentChangeScope && (changesReady || eventRetry is { } pending && pending.Scope == CurrentChangeScope && changes.Contains(pending.Row));
    private ChangeQueryScope CurrentChangeScope => new(IsWorkbook, projectId, reportId, intervalFrom, intervalTo, NetMode);
    private int? workbookPageLimitForSmoke;
    private long changeQueryReadsForSmoke;
    internal string ComparisonState { get; private set; } = "empty";
    private readonly TextBlock status = new() { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(12, 5, 12, 5), MaxHeight = 70 };
    private readonly TextBlock context = new() { FontSize = 12, Foreground = Brushes.DimGray, TextTrimming = TextTrimming.CharacterEllipsis, Margin = new Thickness(12, 2, 12, 5) };
    private readonly TextBlock intervalCaption = new() { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(10, 2, 10, 6), Foreground = Brushes.DimGray };
    private readonly ProgressBar progress = new() { Height = 3, IsIndeterminate = true, Visibility = Visibility.Collapsed };
    private readonly Menu menus = new();
    private readonly MenuItem evidenceMenu = new() { IsCheckable = true };
    private readonly Dictionary<string, MenuItem> languageItems = [];
    private readonly Dictionary<string, MenuItem> actionItems = [];
    private readonly ComboBox comparisonMode = new() { Width = 160, Margin = new Thickness(4, 2, 8, 2) };
    private bool documentNet = true;
    private bool documentRangeUnavailable;
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
    private long operationCancellations;
    private long generation;
    private bool binding;
    private bool closed;
    private bool busy;
    private bool initializing = true;
    private bool startupReady;
    private bool startupFailed;
    private readonly StackPanel libraryPrompt = new() { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, MaxWidth = 440, Margin = new Thickness(20) };
    private readonly TextBlock libraryPromptText = new() { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(8) };
    private Button startupRetry = new();
    private Button firstImport = new();
    private Task startupRequest = Task.CompletedTask;
    private Task? initializationRead;
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
    private readonly FocusSession documentFocus = new();
    private readonly FocusSession workbookFocus = new();
    private FocusSession ActiveFocus => IsWorkbook ? workbookFocus : documentFocus;
    internal bool IsWorkbook { get; private set; }
    internal bool SingleSourceReading => singleSource;
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
        foreach (var command in new (string Key, Func<Task> Action)[] { ("import", Import), ("refresh", RefreshProjects), ("analyze", Analyze), ("reorder", Reorder), ("export", Export), ("mcp", CopyMcp) }) { var menuItem = new MenuItem(); BindText(menuItem, command.Key); var action = command.Action; var writer = command.Key is "import" or "analyze" or "reorder" or "export"; menuItem.Click += async (_, _) => await Guard(action, writer); actions.Items.Add(menuItem); actionItems[command.Key] = menuItem; }
        var layoutMenu = new MenuItem(); BindText(layoutMenu, "layout"); menus.Items.Add(layoutMenu); layoutMenu.SubmenuOpened += (_, _) => BuildLayoutMenu(layoutMenu);
        var modes = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(12, 4, 6, 4) };
        documents = new RadioButton { GroupName = "workspace", IsChecked = true, Margin = new Thickness(0, 0, 16, 0) }; BindText(documents, "documents");
        workbooks = new RadioButton { GroupName = "workspace" }; BindText(workbooks, "workbooks");
        documents.Checked += async (_, _) => { if (!binding && IsWorkbook) await Guard(() => SwitchWorkspace(false)); };
        workbooks.Checked += async (_, _) => { if (!binding && !IsWorkbook) await Guard(() => SwitchWorkspace(true)); };
        modes.Children.Add(documents); modes.Children.Add(workbooks); toolbar.Children.Add(modes);
        toolbar.Children.Add(Command("projects", () => { ChangeVisibility(sidebar: !Layout.Sidebar); return Task.CompletedTask; }));
        toolbar.Children.Add(projectCaption);
        importButton = Command("import", Import);
        analyzeButton = Command("analyze", Analyze);
        reorderButton = Command("reorder", Reorder);
        cancelButton = Command("cancel", () => { operation?.Cancel(); return Task.CompletedTask; }); toolbar.Children.Add(cancelButton);
        exportButton = Command("export", Export);
        mcpButton = Command("mcp", CopyMcp);
        var reportCaption = new TextBlock { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(8, 0, 0, 0) }; BindText(reportCaption, "report"); toolbar.Children.Add(reportCaption); toolbar.Children.Add(reports);
        reportDetailsButton = Command("reportDetails", () => { CreateReportDetailsDialog().ShowDialog(); return Task.CompletedTask; }); toolbar.Children.Add(reportDetailsButton);
        // The evidence action belongs in the native menu: its long caption can
        // otherwise create an entire extra toolbar row at a 1024 px window.
        BindText(evidenceMenu, "evidence"); evidenceMenu.Click += (_, _) => ChangeVisibility(inspector: !Layout.Inspector); menus.Items.Add(evidenceMenu);
        DockPanel.SetDock(toolbar, Dock.Top); root.Children.Add(toolbar);
        versionsButton = Command("versions", ShowVersions); reportBar.Children.Add(versionsButton);
        var intervalLabel = new TextBlock { VerticalAlignment = VerticalAlignment.Center }; BindText(intervalLabel, "interval"); queryControls.Children.Add(intervalLabel); queryControls.Children.Add(queryBefore); queryControls.Children.Add(new TextBlock { Text = "→", VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(5) }); queryControls.Children.Add(queryAfter); queryControls.Children.Add(comparisonMode); reportBar.Children.Add(queryControls); reportBar.Children.Add(queryProvenance);
        reportBar.Children.Add(Command("changes", () => { ChangeVisibility(changes: !Layout.ChangesVisible); return Task.CompletedTask; }));
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
        ConfigureChangeList(); changeList.ItemsSource = changes; soleChanges.Children.Add(soleExplanation); newComparison = Command("newComparison", Import); soleChanges.Children.Add(newComparison); var changeBody = new Grid(); changeBody.Children.Add(changeList); changeBody.Children.Add(soleChanges); changeDock.Children.Add(changeBody); ChangesPane.Child = changeDock;
        changeList.SelectionChanged += async (_, _) => { if (!binding && changeList.SelectedItem is ChangeChoice choice) await Guard(() => SelectChange(choice.Value)); };
        var inspector = new DockPanel(); var caption = Caption("evidence"); DockPanel.SetDock(caption, Dock.Top); inspector.Children.Add(caption);
        var pagingButtons = new WrapPanel(); firstDetail = Command("firstText", FirstDetail); nextDetail = Command("nextText", NextDetail); pagingButtons.Children.Add(firstDetail); pagingButtons.Children.Add(nextDetail); detailPaging.Children.Add(pagingButtons); BindText(detailStyle, "styleDetail"); detailPaging.Children.Add(detailStyle); detailStyle.Click += async (_, _) => await Guard(FirstDetail); detailPaging.Children.Add(detailRange); DockPanel.SetDock(detailPaging, Dock.Top); inspector.Children.Add(detailPaging);
        var metadata = new Expander { Header = "Source metadata / 원본 메타데이터", IsExpanded = false, Content = detailMetadata, MaxHeight = 180 }; DockPanel.SetDock(metadata, Dock.Bottom); inspector.Children.Add(metadata); inspector.Children.Add(detail); InspectorPane.Child = inspector;
        var sourceTools = new DockPanel { Margin = new Thickness(4, 1, 4, 1), LastChildFill = true };
        var sourceActions = new StackPanel { Orientation = Orientation.Horizontal }; previousChange = Command("previousChange", () => MoveChange(-1)); nextChange = Command("nextChange", () => MoveChange(1)); returnChange = Command("returnChange", ReturnToChange); sourceActions.Children.Add(previousChange); sourceActions.Children.Add(nextChange); sourceActions.Children.Add(returnChange); sourceActions.Children.Add(sourceView); DockPanel.SetDock(sourceActions, Dock.Right); sourceTools.Children.Add(sourceActions); sourceTools.Children.Add(sourcePair); DockPanel.SetDock(sourceTools, Dock.Top); sourceStage.Children.Add(sourceTools);
        firstTextStage = Command("firstText", FirstDetail); nextTextStage = Command("nextText", NextDetail); rawTextPaging.Children.Add(firstTextStage); rawTextPaging.Children.Add(nextTextStage); BindText(sourceDiagnostics, "sourceDetails"); sourceDiagnostics.Click += (_, _) => RenderSourceDiff(); rawTextPaging.Children.Add(sourceDiagnostics); DockPanel.SetDock(rawTextPaging, Dock.Top); sourceStage.Children.Add(rawTextPaging);
        var sourceFooter = new DockPanel(); newComparisonStage = Command("newComparison", Import); DockPanel.SetDock(newComparisonStage, Dock.Right); sourceFooter.Children.Add(newComparisonStage); storedHistoryButton = Command("openStoredHistory", () => storedHistoryRequest = OpenStoredHistory()); DockPanel.SetDock(storedHistoryButton, Dock.Right); sourceFooter.Children.Add(storedHistoryButton); selectedLimitsButton = Command("selectedLimits", () => { CreateSelectedLimitsDialog().ShowDialog(); return Task.CompletedTask; }); DockPanel.SetDock(selectedLimitsButton, Dock.Right); sourceFooter.Children.Add(selectedLimitsButton); sourceFooter.Children.Add(sourceNotice); DockPanel.SetDock(sourceFooter, Dock.Bottom); sourceStage.Children.Add(sourceFooter); var sourceBody = new Grid(); sourceBody.Children.Add(comparison); sourceBody.Children.Add(unified); libraryPrompt.Children.Add(libraryPromptText); startupRetry = Command("retryStartup", () => startupRequest = InitializeCore()); firstImport = Command("import", Import); libraryPrompt.Children.Add(startupRetry); libraryPrompt.Children.Add(firstImport); sourceBody.Children.Add(libraryPrompt); sourceStage.Children.Add(sourceBody);
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
        Text(nameof(ChangeChoice.Title), true); Text(nameof(ChangeChoice.Location)); Text(nameof(ChangeChoice.Preview), lines: 3);
        changeList.ItemTemplate = new DataTemplate { VisualTree = stack }; var style = new Style(typeof(ListBoxItem)); style.Setters.Add(new Setter(Control.HorizontalContentAlignmentProperty, HorizontalAlignment.Stretch)); style.Setters.Add(new Setter(Control.PaddingProperty, new Thickness(0))); style.Setters.Add(new Setter(FrameworkElement.MarginProperty, new Thickness(2, 1, 2, 2))); style.Setters.Add(new Setter(Control.BorderThicknessProperty, new Thickness(2, 1, 1, 1))); style.Setters.Add(new Setter(Control.BorderBrushProperty, Brushes.Transparent)); style.Setters.Add(new Setter(FrameworkElement.ToolTipProperty, new Binding(nameof(ChangeChoice.Tooltip)))); style.Setters.Add(new Setter(AutomationProperties.NameProperty, new Binding(nameof(ChangeChoice.Caption)))); var selected = new Trigger { Property = ListBoxItem.IsSelectedProperty, Value = true }; selected.Setters.Add(new Setter(Control.BackgroundProperty, new SolidColorBrush(Color.FromRgb(231, 241, 255)))); selected.Setters.Add(new Setter(Control.BorderBrushProperty, new SolidColorBrush(Color.FromRgb(59, 130, 246)))); selected.Setters.Add(new Setter(Control.ForegroundProperty, Brushes.Black)); style.Triggers.Add(selected); changeList.ItemContainerStyle = style; ScrollViewer.SetHorizontalScrollBarVisibility(changeList, ScrollBarVisibility.Disabled); VirtualizingPanel.SetVirtualizationMode(changeList, VirtualizationMode.Recycling);
    }
    internal static TextBox SourceText() => new() { IsReadOnly = true, TextWrapping = TextWrapping.Wrap, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled, BorderThickness = new Thickness(0), Padding = new Thickness(10), FontFamily = new FontFamily("Consolas, Segoe UI") };
    private TextBlock Caption(string key) { var block = new TextBlock { FontWeight = FontWeights.SemiBold, Margin = new Thickness(10, 8, 10, 8) }; BindText(block, key); return block; }
    private Button Command(string key, Func<Task> action)
    {
        var button = new Button { Padding = new Thickness(10, 6, 10, 6), Margin = new Thickness(3), MinHeight = 30 }; BindText(button, key); button.Click += async (_, _) => await Guard(action, key is "import" or "newComparison" or "analyze" or "reorder" or "export"); return button;
    }
    internal void BindText(FrameworkElement control, string key)
    {
        void Update() { switch (control) { case TextBlock text: text.Text = Copy[key]; break; case HeaderedItemsControl header: header.Header = Copy[key]; break; case ContentControl contentControl: contentControl.Content = Copy[key]; break; } }
        relocalize.Add(Update); Update();
    }
    internal async Task Guard(Func<Task> action, bool operationAction = false)
    {
        var cancellationsBefore = operationCancellations;
        try { await action(); }
        catch (OperationCanceledException) { if (!closed) { if (operationAction && operationCancellations > cancellationsBefore && !busy) status.Text = Copy["cancelled"]; else EvidenceReadSettled(); } }
        catch (Exception error) { if (!closed) { status.Text = startupFailed ? Copy["startupFailed"] : Copy["requestFailed"] + " " + error.Message; MessageBox.Show(this, Copy["requestFailed"] + "\n\n" + error.Message, Copy["error"], MessageBoxButton.OK, MessageBoxImage.Error); } }
    }
    internal void SetLanguage(string language)
    {
        Copy.Language = language == "ko" ? "ko" : "en"; Preferences.Language = Copy.Language; Localize(); SavePreferences();
    }
    private void Localize()
    {
        foreach (var action in relocalize) action(); foreach (var pair in languageItems) pair.Value.IsChecked = pair.Key == Copy.Language;
        var wasBinding = binding; UpdateComparisonModeChoices();
        binding = true; sourceView.ItemsSource = new[] { new Choice("visual", Copy[singleSource ? "reading" : "visualView"], default), new Choice("text", Copy["textDiff"], default) }; sourceView.SelectedIndex = textView ? 1 : 0; binding = wasBinding;
        AutomationProperties.SetName(sourceView, Copy["sourceView"]); AutomationProperties.SetName(queryBefore, Copy["interval"] + " · " + Copy["before"]); AutomationProperties.SetName(queryAfter, Copy["interval"] + " · " + Copy["after"]); AutomationProperties.SetName(unified, Copy["textDiff"]);
        actionItems["mcp"].ToolTip = Copy["mcpReportScope"]; AutomationProperties.SetHelpText(actionItems["mcp"], Copy["mcpReportScope"]);
        previousChange.ToolTip = Copy["previous"] + " · " + Copy["changes"]; nextChange.ToolTip = Copy["next"] + " · " + Copy["changes"]; AutomationProperties.SetName(previousChange, previousChange.ToolTip.ToString()); AutomationProperties.SetName(nextChange, nextChange.ToolTip.ToString());
        AutomationProperties.SetName(comparisonMode, Copy["comparisonMode"]); foreach (var change in changes) change.Relabel(ChangeCaption(change.Value), Copy["rawChangeDescription"]); Before.Localize(); After.Localize();
        detailPaging.Visibility = IsWorkbook ? Visibility.Visible : Visibility.Collapsed;
        RerenderInspector();
        foreach (var splitter in NativeSplitters()) if (splitter.Tag is string key) { AutomationProperties.SetName(splitter, Copy[key]); splitter.ToolTip = Copy[key]; }
        if (!busy) status.Text = Copy[initializing ? "initializing" : startupFailed ? "startupFailed" : Preferences.IsReadOnly ? "preferencesReadOnly" : "ready"]; UpdateContext(); UpdateInterval(); RenderSourceDiff();
    }
    internal void SavePreferences()
    {
        var documentShown = Preferences.Document.Current; var workbookShown = Preferences.Workbook.Current;
        try { Preferences.Document.Current = documentFocus.Persisted(documentShown); Preferences.Workbook.Current = workbookFocus.Persisted(workbookShown); Preferences.Save(PreferencesPath); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { status.Text = error.Message; }
        finally { Preferences.Document.Current = documentShown; Preferences.Workbook.Current = workbookShown; }
    }
    internal void SetLayout(WorkspaceLayout layout) { Preferences.For(IsWorkbook).Current = ActiveFocus.Baseline(layout); ApplyLayout(); }
    private void EditLayout(WorkspaceLayout layout) { Preferences.For(IsWorkbook).Current = ActiveFocus.Edit(layout); ApplyLayout(); }
    private void ToggleFocus() { Preferences.For(IsWorkbook).Current = ActiveFocus.Toggle(Layout); ApplyLayout(); }
    private void ChangeVisibility(bool? sidebar = null, bool? inspector = null, bool? changes = null) { Preferences.For(IsWorkbook).Current = ActiveFocus.Visibility(Layout, sidebar, inspector, changes); ApplyLayout(); }
    private void BuildLayoutMenu(MenuItem menu)
    {
        menu.Items.Clear();
        var checks = new List<(MenuItem Item, Func<bool> Checked)>();
        void Add(string key, Action action, Func<bool>? check = null) { var item = new MenuItem { Header = Copy[key], IsCheckable = check is not null, IsChecked = check?.Invoke() ?? false }; if (check is not null) checks.Add((item, check)); item.Click += (_, _) => { action(); foreach (var pair in checks) pair.Item.IsChecked = pair.Checked(); }; menu.Items.Add(item); }
        foreach (var preset in new[] { "sourceFirst", "balanced", "focus", "review" }) { var name = preset; if (name == "focus") Add(name, ToggleFocus, () => ActiveFocus.Active); else Add(name, () => SetLayout(WorkspaceLayout.Preset(name)), () => !ActiveFocus.Active && Layout == WorkspaceLayout.Preset(name)); }
        menu.Items.Add(new Separator()); Add("sidebar", () => ChangeVisibility(sidebar: !Layout.Sidebar), () => Layout.Sidebar); Add("inspector", () => ChangeVisibility(inspector: !Layout.Inspector), () => Layout.Inspector); Add("changes", () => ChangeVisibility(changes: !Layout.ChangesVisible), () => Layout.ChangesVisible);
        Add("changesBottom", () => EditLayout(Layout with { Changes = "bottom" }), () => Layout.Changes == "bottom"); Add("changesLeft", () => EditLayout(Layout with { Changes = "left" }), () => Layout.Changes == "left"); Add("changesRight", () => EditLayout(Layout with { Changes = "right" }), () => Layout.Changes == "right");
        Add("inspectorLeft", () => EditLayout(Layout with { InspectorSide = "left" }), () => Layout.InspectorSide == "left"); Add("inspectorRight", () => EditLayout(Layout with { InspectorSide = "right" }), () => Layout.InspectorSide == "right"); Add("vertical", () => EditLayout(Layout with { VerticalComparison = !Layout.VerticalComparison }), () => Layout.VerticalComparison);
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
        save.Click += (_, _) => { var name = field.Text.Trim(); if (name.Length is < 1 or > 48 || name.Any(char.IsControl)) return; var named = Preferences.For(IsWorkbook).Named; if (!named.ContainsKey(name) && named.Count >= 12) { MessageBox.Show(dialog, Copy["layoutLimit"], Copy["applyLayout"]); return; } if (named.ContainsKey(name) && MessageBox.Show(dialog, Copy["replaceLayout"] + "\n\n" + name, Copy["saveLayout"], MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No) != MessageBoxResult.Yes) return; named[name] = ActiveFocus.Persisted(Layout); SavePreferences(); dialog.DialogResult = true; };
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
        evidenceMenu.IsChecked = layout.Inspector;
        lastLayoutWidth = workspace.ActualWidth; lastLayoutHeight = workspace.ActualHeight;
        var center = new Grid();
        if (layout.ChangesVisible && layout.Changes == "bottom")
        {
            center.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star), MinHeight = 180 }); center.RowDefinitions.Add(new RowDefinition { Height = new GridLength(5) }); center.RowDefinitions.Add(new RowDefinition { Height = new GridLength(Math.Min(layout.ChangesHeight, Math.Max(100, workspace.ActualHeight - 240))), MinHeight = 90 });
            center.Children.Add(sourceStage); Grid.SetRow(sourceStage, 0); Grid.SetColumn(sourceStage, 0); center.Children.Add(ChangesPane); Grid.SetRow(ChangesPane, 2); Grid.SetColumn(ChangesPane, 0);
            var splitter = Splitter(false, "resizeChanges", () => { Preferences.For(IsWorkbook).Current = ActiveFocus.Edit(Layout with { ChangesHeight = center.RowDefinitions[2].ActualHeight }); SavePreferences(); }); Grid.SetRow(splitter, 1); center.Children.Add(splitter);
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
        Preferences.For(IsWorkbook).Current = ActiveFocus.Edit(layout);
    }

    public Task Initialize() => Guard(() => InitializeCore());
    private Task InitializeCore(Func<string, Task>? recoverForSmoke = null) => initializationRead is { IsCompleted: false } pending ? pending : initializationRead = InitializeLibrary(recoverForSmoke);
    private async Task InitializeLibrary(Func<string, Task>? recoverForSmoke)
    {
        if (closed || busy) return;
        initializing = true; startupReady = false; startupFailed = false; SetBusy(busy);
        try
        {
            foreach (var command in new[] { "recover", "workbookRecover" }) { if (recoverForSmoke is null) await Bridge.Call(command); else await recoverForSmoke(command); }
            await RefreshProjectsCore(null); startupReady = true;
        }
        catch { startupFailed = true; throw; }
        finally { initializing = false; SetBusy(busy); if (startupFailed) status.Text = Copy["startupFailed"]; }
    }
    internal async Task SwitchWorkspace(bool workbook, Func<Task>? beforeProjectsForSmoke = null)
    {
        if (busy || !startupReady || initializing) return; CancelProjectChoices(); SavePreferences(); IsWorkbook = workbook; binding = true; documents.IsChecked = !workbook; workbooks.IsChecked = workbook; binding = false;
        BeginScope(); projectId = ""; reportId = ""; currentReport = default; currentProject = default; binding = true; reports.ItemsSource = null; binding = false; ClearReport(); ApplyLayout(); Localize(); SetBusy(false); await RefreshProjectsCore(beforeProjectsForSmoke);
    }
    internal Task RefreshProjects() => startupReady ? RefreshProjectsCore(null) : InitializeCore();
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
            binding = true; projectList.ItemsSource = items; projectList.SelectedItem = items.Find(v => v.Id == projectId); binding = false; projectChoicesReady = true; projectList.IsEnabled = !busy && startupReady && !initializing;
            if (projectId.Length == 0) status.Text = Copy["chooseProject"]; RenderSourceDiff();
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
        return ReloadSourceOnly();
    }
    private async Task ReloadSourceOnly(Func<CancellationToken, Task>? beforeReadForSmoke = null)
    {
        // A source window is independent of the query's loaded continuation.
        // Only a previously installed exact query scope may be resumed here.
        var scope = CurrentChangeScope;
        if (loadedChangeScope != scope) { await ReloadComparisonCore(true); return; }
        var ticket = BeginScope(); var token = reads.Token;
        InvalidateAuthority(false); Before.Invalidate(); After.Invalidate();
        try
        {
            if (beforeReadForSmoke is not null) await beforeReadForSmoke(token);
            if (!IsCurrent(ticket) || token.IsCancellationRequested || loadedChangeScope != scope || CurrentChangeScope != scope) return;
            if (!singleSource) await Before.Load(ticket, token);
            if (!IsCurrent(ticket) || token.IsCancellationRequested || loadedChangeScope != scope || CurrentChangeScope != scope) return;
            await After.Load(ticket, token);
            if (!IsCurrent(ticket) || token.IsCancellationRequested || loadedChangeScope != scope || CurrentChangeScope != scope) return;
            if (!IsWorkbook)
            {
                do
                {
                    var beforeSettled = singleSource || await Before.AwaitCurrentPageRead(ticket, token); var afterSettled = await After.AwaitCurrentPageRead(ticket, token);
                    if (!IsCurrent(ticket) || token.IsCancellationRequested || loadedChangeScope != scope || CurrentChangeScope != scope) return;
                    if (!beforeSettled || !afterSettled) break;
                } while ((!singleSource && Before.ReadState == "loading") || After.ReadState == "loading");
            }
            if ((!singleSource && Before.ReadState is not ("ready" or "absent")) || After.ReadState is not ("ready" or "absent")) throw new BridgeException("SOURCE_UNSETTLED", "The selected native source has not finished installing its verified observation.");
            changesReady = true; ComparisonState = "ready"; changeList.IsEnabled = !busy; more.IsEnabled = !busy && nextChanges.Length > 0;
            detail.Text = singleSource ? SingleSourceGuidance : Copy["selectCell"];
            RenderSourceDiff(); EvidenceReadSettled();
        }
        catch { if (IsCurrent(ticket) && !token.IsCancellationRequested) FailComparison(false); throw; }
    }
    private async Task ReloadComparisonCore(bool preserveInterval = false, Func<string, CancellationToken, Task<JsonElement>>? documentReaderForSmoke = null)
    {
        var ticket = BeginScope();
        var oneSource = Before.RevisionId.Length > 0 && Before.RevisionId == After.RevisionId; if (singleSource != oneSource) { singleSource = oneSource; ApplyLayout(false); }
        if (!preserveInterval) { intervalFrom = Before.RevisionId; intervalTo = After.RevisionId; ClearSelectedChange(); } UpdateInterval();
        InvalidateAuthority(true); Before.Invalidate(); After.Invalidate();
        var revisions = currentReport.Get("revisions").Items(); var from = revisions.FindIndex(v => v.Get("revision_occurrence_id").Text() == intervalFrom); var to = revisions.FindIndex(v => v.Get("revision_occurrence_id").Text() == intervalTo);
        if (from < 0 || to < 0 || from > to) { ComparisonState = "invalid"; Before.Invalidate("invalid"); After.Invalidate("invalid"); detail.Text = Copy["reverse"]; status.Text = Copy["reverse"]; return; }
        try { if (!singleSource) await Before.Load(ticket, reads.Token); if (ticket != generation) return; await After.Load(ticket, reads.Token); if (ticket != generation) return; await LoadChanges(false, ticket, reads.Token, documentReaderForSmoke); RenderSourceDiff(); }
        catch (Exception error) { if (IsCurrent(ticket) && !reads.IsCancellationRequested) FailComparison(preserveSources: error is BridgeException { Code: "ENGINE_VERSION_UNAVAILABLE" } && documentRangeUnavailable); throw; }
    }
    internal Task RetryComparison()
    {
        if (busy || reportId.Length == 0 || !startupReady) return Task.CompletedTask;
        if (eventRetry is { } pending)
        {
            if (pending.Scope != CurrentChangeScope || loadedChangeScope != pending.Scope || !changes.Contains(pending.Row)) { eventRetry = null; return Task.CompletedTask; }
            return SelectChange(pending.Row.Value, retry: true);
        }
        // Invalidating a failed read never changes retained selectors. Retry the
        // exact event/page/sheet/window, independently of the change-list interval.
        return sourceOnlyFailure && loadedChangeScope == CurrentChangeScope ? ReloadSourceOnly() : ReloadComparisonCore(true);
    }
    private void InvalidateAuthority(bool clearChanges)
    {
        eventRetry = null; sourceOnlyFailure = false; changesReady = false; ComparisonState = "loading"; changeList.IsEnabled = false; more.IsEnabled = false; retryComparison.Visibility = Visibility.Collapsed; ClearDetail(); detail.Text = Copy["loading"]; RenderSourceDiff();
        if (clearChanges) { loadedChangeScope = null; binding = true; changeList.SelectedItem = null; changes.Clear(); binding = false; nextChanges = ""; }
    }
    private void FailComparison(bool retireQuery = true, bool preserveSources = false) { sourceOnlyFailure = !retireQuery; if (retireQuery) { loadedChangeScope = null; eventRetry = null; } changesReady = false; ComparisonState = "failed"; changeList.IsEnabled = ChangeNavigationReady; more.IsEnabled = ChangeNavigationReady && nextChanges.Length > 0; if (!preserveSources || Before.ReadState is not ("ready" or "absent") || After.ReadState is not ("ready" or "absent")) { Before.Invalidate("failed"); After.Invalidate("failed"); } ClearDetail(); detail.Text = Copy["failed"]; retryComparison.Visibility = Visibility.Visible; RenderSourceDiff(); }
    private long BeginScope() { reads.Cancel(); reads.Dispose(); reads = new(); cellReads.Cancel(); cellReads.Dispose(); cellReads = new(); return ++generation; }
    internal bool IsCurrent(long ticket) => !closed && ticket == generation;
    private void ClearReport() { RetireVersionsMenu(); documentRangeUnavailable = false; ClearSelectedChange(); InvalidateAuthority(true); ComparisonState = "empty"; binding = true; intervalFrom = ""; intervalTo = ""; queryBefore.ItemsSource = null; queryAfter.ItemsSource = null; UpdateInterval(); Before.Clear(); After.Clear(); detail.Text = Copy["selectCell"]; binding = false; RenderSourceDiff(); }
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
        UpdateComparisonModeChoices(); comparisonMode.IsEnabled = !busy && !initializing && reportId.Length > 0 && !singleSource;
        intervalCaption.Text = intervalFrom.Length == 0 ? "" : singleSource ? Copy["reading"] + " · " + VersionLabel(intervalTo) : Copy["interval"] + ": " + VersionLabel(intervalFrom) + " → " + VersionLabel(intervalTo) + " · " + Copy[NetMode ? "net" : "history"];
        var previous = binding; binding = true; queryBefore.SelectedItem = queryBefore.Items.OfType<Choice>().FirstOrDefault(v => v.Id == intervalFrom); queryAfter.SelectedItem = queryAfter.Items.OfType<Choice>().FirstOrDefault(v => v.Id == intervalTo); binding = previous;
        versionsButton.IsEnabled = !busy && reportId.Length > 0;
        var sole = reportId.Length > 0 && currentReport.Get("revisions").Items().Count == 1;
        queryControls.Visibility = sole ? Visibility.Collapsed : Visibility.Visible;
        var revisions = currentReport.Get("revisions").Items(); var from = revisions.FindIndex(v => v.Get("revision_occurrence_id").Text() == intervalFrom); var to = revisions.FindIndex(v => v.Get("revision_occurrence_id").Text() == intervalTo);
        queryProvenance.Text = reportId.Length == 0 ? "" : singleSource ? Copy["reading"] : Copy[!NetMode ? "storedInterval" : to == from + 1 ? "canonicalAdjacent" : IsWorkbook ? "workbookNetProvenance" : "computedNet"];
        queryProvenance.ToolTip = IsWorkbook ? Copy["workbookProvenanceHelp"] : Copy["queryProvenanceHelp"]; AutomationProperties.SetName(queryProvenance, queryProvenance.Text); AutomationProperties.SetHelpText(queryProvenance, queryProvenance.ToolTip.ToString());
    }
    private void UpdateComparisonModeChoices()
    {
        var wasBinding = binding; binding = true;
        comparisonMode.ItemsSource = singleSource ? new[] { new Choice("reading", Copy["reading"], default) } : new[] { new Choice("history", Copy["history"], default), new Choice("range_net", Copy["net"], default) };
        comparisonMode.SelectedIndex = singleSource ? 0 : NetMode ? 1 : 0; binding = wasBinding;
    }
    private string SingleSourceGuidance => Copy[currentReport.Get("revisions").Items().Count == 1 ? "singleImportedSourceView" : "singleSourceView"];
    private static string CompactReport(string id) => id.Length <= 18 ? id : id[..10] + "…" + id[^6..];
    private void UpdateContext() { context.Text = projectId.Length == 0 ? Copy["chooseProject"] : currentProject.Get("title").Text() + "  ·  " + reportId + (currentReport.ValueKind == JsonValueKind.Undefined ? "" : "  ·  " + Copy["coverage"] + ": " + currentReport.Get("coverage_gap_count").Number(currentReport.Get("coverage_gaps").Items().Count)); projectCaption.Text = currentProject.Get("title").Text(); projectCaption.ToolTip = context.Text; reports.ToolTip = context.Text; }
    private async Task ChooseEndpoint(bool after, string id)
    {
        if (busy || reportId.Length == 0) { UpdateInterval(); return; }
        documentRangeUnavailable = false;
        // Endpoint selectors own the query interval. Event/source navigation does not.
        Before.SetSourceRevision(intervalFrom, false); After.SetSourceRevision(intervalTo, false);
        // Query/log choices start a new interval with valid source sheets.
        // Direct pane navigation separately preserves an absent carried sheet.
        (after ? After : Before).SetSourceRevision(id, false); ClearSelectedChange();
        await ReloadComparison();
    }
    private Task ShowVersions()
    {
        RetireVersionsMenu(); var menu = new ContextMenu(); var revisions = currentReport.Get("revisions").Items(); var fixedReport = reportId; var project = projectId; var workbook = IsWorkbook;
        for (var i = 0; i < revisions.Count; i++)
        {
            var index = i; var item = new MenuItem { Header = new TextBlock { Text = "v" + (i + 1) + "  " + revisions[i].Get("label").Text() }, IsCheckable = true, IsChecked = intervalTo == revisions[i].Get("revision_occurrence_id").Text() };
            item.Click += async (_, _) => { if (reportId == fixedReport && projectId == project && IsWorkbook == workbook) await Guard(() => SelectLogVersion(index)); }; menu.Items.Add(item);
        }
        menu.Closed += (_, _) => { if (ReferenceEquals(versionsButton.ContextMenu, menu)) versionsButton.ContextMenu = null; };
        versionsButton.ContextMenu = menu; menu.PlacementTarget = versionsButton; menu.Placement = PlacementMode.Bottom; menu.IsOpen = true; return Task.CompletedTask;
    }
    private void RetireVersionsMenu() { if (versionsButton.ContextMenu is { } menu) { versionsButton.ContextMenu = null; menu.IsOpen = false; } }
    private async Task SelectLogVersion(int selected)
    {
        if (busy || reportId.Length == 0) return; var revisions = currentReport.Get("revisions").Items(); var pair = SourceDiff.PreviousToSelected(selected, revisions.Count); if (pair.Before < 0) return;
        documentRangeUnavailable = false;
        Before.SetSourceRevision(revisions[pair.Before].Get("revision_occurrence_id").Text(), false); After.SetSourceRevision(revisions[pair.After].Get("revision_occurrence_id").Text(), false); ClearSelectedChange();
        await ReloadComparison();
    }
    private async Task MoveChange(int direction)
    {
        if (!ChangeNavigationReady) return; var currentId = selectedChange.ValueKind == JsonValueKind.Object ? selectedChange.Get("change_id").Text() : (changeList.SelectedItem as ChangeChoice)?.Id; var index = changes.ToList().FindIndex(c => c.Id == currentId); var next = index < 0 ? direction > 0 ? 0 : changes.Count - 1 : index + direction;
        if (next == changes.Count && nextChanges.Length > 0) await LoadMoreChanges();
        if (next < 0 || next >= changes.Count) return;
        var choice = changes[next]; binding = true; changeList.SelectedItem = choice; changeList.ScrollIntoView(choice); binding = false; await SelectChange(choice.Value);
    }
    private Task ReturnToChange() => selectedChange.ValueKind == JsonValueKind.Object && changesReady ? SelectChange(selectedChange) : Task.CompletedTask;
    internal void SourcePresentationChanged() { RenderSourceDiff(); EvidenceReadSettled(); }
    private void EvidenceReadSettled() { if (!closed && !busy && !initializing && startupReady && ComparisonState == "ready" && inspectorMode is not ("loading" or "failed") && After.ReadState is ("ready" or "absent") && (singleSource || Before.ReadState is ("ready" or "absent"))) status.Text = Copy[Preferences.IsReadOnly ? "preferencesReadOnly" : "ready"]; }
    private bool AtSelectedChange => selectedChange.ValueKind == JsonValueKind.Object && selectedBefore is { } a && selectedAfter is { } b && Before.RevisionId == a.Revision && Before.PageId == a.Page && Before.SheetId == a.Sheet && After.RevisionId == b.Revision && After.PageId == b.Page && After.SheetId == b.Sheet && (IsWorkbook ? Before.FocusedRow == a.FocusedRow && Before.FocusedColumn == a.FocusedColumn && After.FocusedRow == b.FocusedRow && After.FocusedColumn == b.FocusedColumn : DocumentEventMatchesSources(selectedChange));
    internal string MissingDocumentPageCaptionKey(bool after) => AtSelectedChange ? SourceDiffPolicy.DocumentMissingPageCaption(selectedChange.Get("kind").Text(), after) : "absentPage";
    private WorkbookSourceScope DisplayedWorkbookScope => new(Before.RevisionId, After.RevisionId, Before.SheetId, After.SheetId, Before.FocusedAddress, After.FocusedAddress);
    private bool SelectedWorkbookMetadata => IsWorkbook && AtSelectedChange && SourceDiffPolicy.WorkbookMetadataContext(selectedChange, DisplayedWorkbookScope);
    private bool WorkbookMetadataPayload(JsonElement value) => SelectedWorkbookMetadata && SourceDiffPolicy.WorkbookComponent(value.Get("before"), selectedChange, "before", projectId, reportId, out _) && SourceDiffPolicy.WorkbookComponent(value.Get("after"), selectedChange, "after", projectId, reportId, out _);
    private JsonElement MetadataSide(bool after)
    {
        var revision = currentReport.Get("revisions").Items().Find(item => item.Get("revision_occurrence_id").Text() == (after ? After.RevisionId : Before.RevisionId));
        return SourceDiffPolicy.WorkbookMetadata(revision, after ? After.SheetId : Before.SheetId, selectedChange.Get("kind").Text());
    }
    private MetadataProjection MetadataSideProjection(bool after)
    {
        var revision = currentReport.Get("revisions").Items().Find(item => item.Get("revision_occurrence_id").Text() == (after ? After.RevisionId : Before.RevisionId));
        return SourceDiffPolicy.WorkbookMetadataProjection(revision, after ? After.SheetId : Before.SheetId, selectedChange.Get("kind").Text());
    }
    private string MetadataBoundedNotice() => Copy["metadataBounded"];
    private void AppendMetadataProjection(FlowDocument target, string side, MetadataProjection projection)
    {
        void System(string text, string tag) => target.Blocks.Add(new Paragraph(new Run(text)) { Margin = new Thickness(0), Foreground = Brushes.DimGray, Tag = tag });
        System(side, "metadataSide");
        if (!projection.Available) { System(Copy["observationMissing"], "metadataMissing"); return; }
        System(Copy["metadataProjection"], "metadataProjectionCaption");
        target.Blocks.Add(new Paragraph(new Run(projection.Json)) { Margin = new Thickness(0), Foreground = Brushes.Black, Tag = "metadataJsonProjection" });
        if (projection.Bounded) System(MetadataBoundedNotice(), "metadataBoundedNotice");
    }
    private string FormatMetadataDetail(MetadataProjection before, MetadataProjection after)
    {
        string Side(string label, MetadataProjection projection) => label + "\n" + (projection.Available ? projection.Json : Copy["observationMissing"]);
        return Copy["metadataObservation"] + "\n" + Copy["metadataProjection"] + "\n\n" + Side(Copy["before"], before) + "\n\n" + Side(Copy["after"], after);
    }
    private string FormatMetadataSummary(MetadataProjection before, MetadataProjection after) => string.Join("\n", new[] { Copy["metadataObservation"] }.Concat(new[] { (Label: Copy["before"], Projection: before), (Label: Copy["after"], Projection: after) }.Where(side => side.Projection.Bounded).Select(side => side.Label + " · " + MetadataBoundedNotice())));
    private (string Before, string After) DocumentEventPages(JsonElement change)
    {
        // Resolve through the existing native page choices, including their
        // primary/render-reference representation; do not invent alias rules.
        var ids = change.Get("evidence").Items().Select(item => item.Get("page_id").Text()).ToArray();
        return (ids.FirstOrDefault(Before.HasPage) ?? "", ids.FirstOrDefault(After.HasPage) ?? "");
    }
    private bool DocumentEventMatchesSources(JsonElement change)
    {
        if (change.Get("report_id").Text() != reportId || change.Get("from_occurrence").Text() != Before.RevisionId || change.Get("to_occurrence").Text() != After.RevisionId) return false;
        var intended = DocumentEventPages(change);
        return Before.PageId == intended.Before && After.PageId == intended.After && (intended.Before.Length > 0 || Before.ReadState == "absent") && (intended.After.Length > 0 || After.ReadState == "absent");
    }
    private string SelectedNoticeText((string Key, string Value) notice) => Copy[notice.Key] + ": " + ((notice.Key is "text_assessment" or "region_pairing_assessment" or "appearance_assessment" or "lineageAssessment") && (notice.Value is "inferred" or "observed" or "human_confirmed" or "needs_review") ? Copy["assessment_" + notice.Value] : notice.Value);
    private IReadOnlyList<string> WorkbookVisibleWarnings()
    {
        var warnings = new List<string>();
        if (!IsWorkbook || busy || ComparisonState != "ready" || inspectorMode is "loading" or "failed") return warnings;
        foreach (var pane in singleSource ? new[] { After } : new[] { Before, After })
        {
            if (pane.ReadState != "ready" || pane.FocusedAddress.Length == 0 || !pane.AuthorizesCell(pane.FocusedRow, pane.FocusedColumn)) continue;
            var side = ReferenceEquals(pane, Before) ? "before" : "after"; JsonElement cell = default;
            var paired = AtSelectedChange && inspectorMode == "raw" && SourceDiffPolicy.WorkbookComponent(detailPayload.Get(side), selectedChange, side, projectId, reportId, out cell) && cell.Get("address").Text() == pane.FocusedAddress;
            if (!paired && !pane.TryGetFocusedMaterializedCell(out cell)) cell = default;
            var keys = SourceDiffPolicy.WorkbookWarningKeys(cell);
            if (keys.Count > 0) warnings.Add(pane.PresentedSideName + " " + pane.FocusedAddress + ": " + string.Join(", ", keys.Select(key => Copy[key])));
        }
        return warnings;
    }
    private Window CreateReportDetailsDialog()
    {
        var fixedReport = reportId; var content = new DockPanel { Margin = new Thickness(16) }; var top = new StackPanel(); top.Children.Add(new TextBlock { Text = currentProject.Get("title").Text(), FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap }); top.Children.Add(new TextBlock { Text = Copy["report"] + " · " + (reports.SelectedItem as Choice)?.Value.Get("created_at").Text(), Margin = new Thickness(0, 10, 0, 4) }); var identity = SourceText(); identity.Text = fixedReport; identity.MinHeight = 48; top.Children.Add(identity); var copy = new Button { Content = Copy["copyReportId"], HorizontalAlignment = HorizontalAlignment.Left, Padding = new Thickness(10, 5, 10, 5), Margin = new Thickness(0, 2, 0, 12) }; copy.Click += async (_, _) => await Guard(() => { Clipboard.SetText(fixedReport); return Task.CompletedTask; }); top.Children.Add(copy); top.Children.Add(new TextBlock { Text = Copy["mcpReportScope"], TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 12) });
        var shown = currentReport.Get("coverage_gaps").Items().Count; var total = currentReport.Get("coverage_gap_count").Number(shown);
        top.Children.Add(new TextBlock { Name = "CoverageProjectionCount", Text = string.Format(CultureInfo.CurrentCulture, Copy["coverageShown"], shown, total), TextWrapping = TextWrapping.Wrap, FontWeight = FontWeights.SemiBold });
        if (shown < total || currentReport.Get("coverage_truncated").Flag()) top.Children.Add(new TextBlock { Name = "CoverageExportPath", Text = Copy["coverageExportPath"], TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 6, 0, 8) });
        DockPanel.SetDock(top, Dock.Top); content.Children.Add(top); var limits = SourceText(); limits.Text = currentReport.Get("coverage_gaps").Pretty(); content.Children.Add(limits);
        return new Window { Owner = this, Title = Copy["reportDetails"], Width = 720, Height = 530, MinWidth = 430, MinHeight = 320, WindowStartupLocation = WindowStartupLocation.CenterOwner, Content = content };
    }
    private Window CreateSelectedLimitsDialog()
    {
        var notes = SourceDiffPolicy.SelectedNotices(selectedChange); var text = SourceText(); text.Text = string.Join("\n\n", WorkbookVisibleWarnings().Concat(notes.Select(SelectedNoticeText)));
        var content = new DockPanel { Margin = new Thickness(12) }; var scope = new TextBlock { Text = Copy["report"] + ": " + reportId + "\n" + sourcePair.Text, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(4, 0, 4, 12) }; DockPanel.SetDock(scope, Dock.Top); content.Children.Add(scope); content.Children.Add(text);
        return new Window { Owner = this, Title = Copy["selectedLimits"], Width = 720, Height = 430, MinWidth = 400, MinHeight = 250, WindowStartupLocation = WindowStartupLocation.CenterOwner, Content = content };
    }
    private void RenderSourceDiff()
    {
        // A single occurrence is source reading, regardless of the previous
        // presentation. Keep renderer, native picker and pager in one state.
        if (singleSource) textView = false;
        if (sourceView.ItemsSource is IEnumerable<Choice> presentationChoices && presentationChoices.FirstOrDefault()?.Label != Copy[singleSource ? "reading" : "visualView"]) { var priorBinding = binding; binding = true; sourceView.ItemsSource = new[] { new Choice("visual", Copy[singleSource ? "reading" : "visualView"], default), new Choice("text", Copy["textDiff"], default) }; binding = priorBinding; }
        Before.RefreshReadingChrome(); After.RefreshReadingChrome();
        var wasBinding = binding; binding = true; sourceView.SelectedIndex = textView ? 1 : 0; binding = wasBinding;
        sourceView.IsEnabled = !busy && !initializing && !singleSource;
        sourceView.ToolTip = singleSource ? SingleSourceGuidance : Copy["sourceView"];
        // Hidden retains the native visual hosts' measured viewport while the
        // text layer is visible; neither the hosts nor source selections rebuild.
        comparison.Visibility = textView ? Visibility.Hidden : Visibility.Visible; unified.Visibility = textView ? Visibility.Visible : Visibility.Collapsed;
        var eventDifferent = Before.RevisionId != intervalFrom || After.RevisionId != intervalTo;
        sourcePair.Text = reportId.Length == 0 ? "" : (singleSource ? Copy["reading"] + " · " + VersionLabel(After.RevisionId) : Copy[eventDifferent ? "withinInterval" : "sourcePair"] + " · " + VersionLabel(Before.RevisionId) + " → " + VersionLabel(After.RevisionId));
        previousChange.IsEnabled = nextChange.IsEnabled = ChangeNavigationReady && changes.Count > 0; returnChange.Visibility = selectedChange.ValueKind == JsonValueKind.Object ? Visibility.Visible : Visibility.Collapsed; returnChange.IsEnabled = !busy && changesReady;
        var sole = reportId.Length > 0 && currentReport.Get("revisions").Items().Count == 1;
        soleChanges.Visibility = sole ? Visibility.Visible : Visibility.Collapsed; changeList.Visibility = sole ? Visibility.Collapsed : Visibility.Visible; soleExplanation.Text = Copy["soleListExplanation"]; newComparison.IsEnabled = newComparisonStage.IsEnabled = startupReady && !busy && !initializing; newComparisonStage.Visibility = sole ? Visibility.Visible : Visibility.Collapsed; previousChange.Visibility = nextChange.Visibility = more.Visibility = sole ? Visibility.Collapsed : Visibility.Visible;
        libraryPrompt.Visibility = startupFailed || startupReady && projectChoicesReady && projectList.Items.Count == 0 && projectId.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        libraryPromptText.Text = Copy[startupFailed ? "startupFailed" : "chooseProject"]; startupRetry.Visibility = startupFailed ? Visibility.Visible : Visibility.Collapsed; startupRetry.IsEnabled = !busy && !initializing; firstImport.Visibility = startupFailed ? Visibility.Collapsed : Visibility.Visible; firstImport.IsEnabled = startupReady && !busy && !initializing;
        retryComparison.Content = Copy[eventRetry is null ? "retry" : "retryEvent"];
        var workbookWarnings = WorkbookVisibleWarnings(); var notice = new List<string>(workbookWarnings); if (singleSource) notice.Add(Copy[currentReport.Get("revisions").Items().Count == 1 ? "singleImportedSourceNotice" : "singleSourceNotice"]); if (IsWorkbook && workbookWarnings.Count == 0) notice.Add(Copy["storedOnly"]);
        var canRecoverHistory = !IsWorkbook && NetMode && documentRangeUnavailable && documentRecoveryScope is { } recovery && recovery == (projectId, reportId, intervalFrom, intervalTo);
        storedHistoryButton.Visibility = canRecoverHistory ? Visibility.Visible : Visibility.Collapsed; storedHistoryButton.IsEnabled = canRecoverHistory && !busy;
        if (canRecoverHistory) notice.Add(Copy["documentNetUnavailable"]);
        if (selectedChange.ValueKind == JsonValueKind.Object && !AtSelectedChange) notice.Add(Copy["outsideChange"]);
        var kind = selectedChange.Get("kind").Text(); if (kind == "cache_availability") notice.Insert(0, Copy["cacheNotDeletion"]); if (kind == "row_correspondence") notice.Add(Copy["inferredRows"]);
        if (kind is "text_occluded" or "text_revealed" or "text_struck_through" or "coverage_gap") notice.Add(Copy["appearanceOnly"]);
        var selectedNotices = SourceDiffPolicy.SelectedNotices(selectedChange); var selectedGaps = selectedNotices.Where(item => item.Key is "selectedCoverage" or "lineageReason").ToArray();
        foreach (var selectedNotice in selectedNotices.Where(item => item.Key is not ("selectedCoverage" or "lineageReason"))) notice.Add(SelectedNoticeText((selectedNotice.Key, SourceDiff.NoticeSummary(selectedNotice.Value, 160))));
        var authoredReason = selectedChange.Get("lineage").Get("status").Text() == "human_confirmed" && selectedChange.Get("topology").Get("semantics").Text() != "directed_reachability";
        if (selectedGaps.Length > 0) { var first = selectedGaps[0].Value; if (selectedGaps[0].Key == "lineageReason" && !authoredReason) { var key = "reason_" + first; if (Copy[key] != key) first = Copy[key]; } first = SourceDiff.NoticeSummary(first, 160); notice.Add(Copy[selectedGaps[0].Key] + ": " + first + (selectedGaps.Length > 1 ? " [1/" + selectedGaps.Length + "]" : "")); }
        selectedLimitsButton.Visibility = selectedGaps.Length > 0 || workbookWarnings.Count > 0 ? Visibility.Visible : Visibility.Collapsed; selectedLimitsButton.IsEnabled = !busy;
        if (currentReport.Get("coverage_gap_count").Number(currentReport.Get("coverage_gaps").Items().Count) > 0) notice.Add((Copy["reportCoverage"] + ": " + currentReport.Get("coverage_gap_count").Number(currentReport.Get("coverage_gaps").Items().Count)).Replace(' ', '\u00a0'));
        sourceNotice.Text = string.Join(" · ", notice); sourceNotice.ToolTip = string.Join("\n", workbookWarnings.Concat(selectedNotices.Select(SelectedNoticeText))); AutomationProperties.SetHelpText(sourceNotice, sourceNotice.ToolTip.ToString()); sourceNotice.Visibility = notice.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        rawTextPaging.Visibility = textView ? Visibility.Visible : Visibility.Collapsed; firstTextStage.Visibility = nextTextStage.Visibility = IsWorkbook && detailLoader is not null ? Visibility.Visible : Visibility.Collapsed; firstTextStage.IsEnabled = !busy && firstDetail.IsEnabled; nextTextStage.IsEnabled = !busy && nextDetail.IsEnabled;
        if (!textView) return;
        var identity = JsonSerializer.Serialize(new { projectId, reportId, intervalFrom, intervalTo, net = NetMode, IsWorkbook, eventId = selectedChange.Get("change_id").Text(), a = new { Before.RevisionId, Before.PageId, Before.SheetId, Before.FocusedAddress }, b = new { After.RevisionId, After.PageId, After.SheetId, After.FocusedAddress }, detailOffset });
        var keepScroll = identity == unifiedIdentity; var scrollX = keepScroll && unifiedRestorePending ? unifiedRetainedX : unified.HorizontalOffset; var scrollY = keepScroll && unifiedRestorePending ? unifiedRetainedY : unified.VerticalOffset; unifiedIdentity = identity; var rendering = ++unifiedRender; unifiedRestorePending = keepScroll; unifiedRetainedX = scrollX; unifiedRetainedY = scrollY;
        var flow = new FlowDocument { PagePadding = new Thickness(14), FontFamily = unified.FontFamily, FontSize = 13 }; unified.Document = flow;
        if (keepScroll) Dispatcher.BeginInvoke(System.Windows.Threading.DispatcherPriority.Loaded, () => { if (textView && rendering == unifiedRender && identity == unifiedIdentity) { unified.UpdateLayout(); unified.ScrollToHorizontalOffset(scrollX); unified.ScrollToVerticalOffset(scrollY); unifiedRestorePending = false; } });
        void Add(string text, Brush? color = null, Brush? background = null) { flow.Blocks.Add(new Paragraph(new Run(text)) { Margin = new Thickness(0), Foreground = color ?? Brushes.Black, Background = background ?? Brushes.Transparent }); }
        if (ComparisonState != "ready") { Add(Copy[ComparisonState == "failed" ? "failed" : ComparisonState == "invalid" ? "reverse" : ComparisonState == "empty" ? "chooseProject" : "loading"]); return; }
        string Location(ComparePane pane) { if (IsWorkbook) return pane.LocationCaption; if (pane.PageId.Length == 0) return pane.LocationCaption; var number = currentReport.Get("revisions").Items().Find(revision => revision.Get("revision_occurrence_id").Text() == pane.RevisionId).Get("pages").Items().Find(page => page.Get("page_id").Text() == pane.PageId).Get("page").Number(); return number > 0 ? "p." + number : Copy["missing"]; }
        Add(Copy[AtSelectedChange ? "event" : "reading"] + " · " + VersionOrdinal(Before.RevisionId) + " " + Location(Before) + " → " + VersionOrdinal(After.RevisionId) + " " + Location(After), Brushes.DimGray);
        if (!SelectedWorkbookMetadata) Add(Copy["textDiffCompact"], Brushes.DimGray);
        if (sourceDiagnostics.IsChecked == true)
        {
            if (!SelectedWorkbookMetadata) Add(Copy["textDiffNotice"], Brushes.DimGray); Add(Copy["report"] + ": " + reportId + "\n" + sourcePair.Text, Brushes.DimGray);
            if (!singleSource) Add(Copy["before"] + " · " + Before.LocationCaption + " · " + Before.PresentedSourceCaption, Brushes.DimGray);
            Add(Copy["after"] + " · " + After.LocationCaption + " · " + After.PresentedSourceCaption, Brushes.DimGray);
        }
        if (Before.ReadState is "loading" or "failed" || After.ReadState is "loading" or "failed") { Add(Copy[Before.ReadState == "failed" || After.ReadState == "failed" ? "failed" : "loading"], Brushes.DimGray); return; }
        void Observation(SourceTextObservation value, string? caption = null)
        {
            Add(Copy[caption ?? (value.State switch { SourceTextState.Missing => "observationMissing", SourceTextState.Null => "observationNull", SourceTextState.Empty => "observationEmpty", SourceTextState.Partial => "partialSourceSegment", SourceTextState.AlreadyRead => "alreadyReadSegment", SourceTextState.Invalid => "invalidSourceSegment", _ => "observationPresent" })], Brushes.DimGray);
            if (value.State == SourceTextState.Invalid) Add(Copy[value.RawState switch { SourceTextState.Null => "observationNull", SourceTextState.Empty => "fragmentEmpty", SourceTextState.Missing => "observationMissing", _ => "observationPresent" }], Brushes.DimGray);
            if (sourceDiagnostics.IsChecked == true && value.Range is { Valid: true, State: "missing" } missing) Add(Copy["textRange"] + ": missing · " + Copy["requestedOffset"] + "=" + missing.Offset + " · total=0 · next=∅", Brushes.DimGray);
            else if (value.Range is { } range && (sourceDiagnostics.IsChecked == true || value.State is SourceTextState.Partial or SourceTextState.AlreadyRead or SourceTextState.Invalid or SourceTextState.Empty)) Add(Copy["textRange"] + ": [" + (range.Offset?.ToString(CultureInfo.InvariantCulture) ?? "?") + ", " + (range.Offset is { } at ? ((long)at + range.Length).ToString(CultureInfo.InvariantCulture) : "?") + ") / " + (range.Total?.ToString(CultureInfo.InvariantCulture) ?? "?") + " · " + range.State + " · " + Copy[range.Valid ? "validSourceRange" : "invalidSourceRange"] + " · next=" + (range.Next?.ToString(CultureInfo.InvariantCulture) ?? (range.Valid ? "∅" : "?")), Brushes.DimGray);
            if (!value.HasText) return; var bounded = SourceDiff.Build(value.Text, value.Text); if (bounded.Truncated) Add(Copy["boundedDiff"], Brushes.DarkOrange); foreach (var line in bounded.Lines) Add(line.Text + (line.Terminator.Length > 0 || line.CutOff ? " " + line.TerminatorLabel : ""));
        }
        void Field(SourceDiffField field, JsonElement cellA = default, JsonElement cellB = default)
        {
            Add(Copy[field.Key == "value" ? "cached" : field.Key == "text" ? "textObservation" : field.Key], Brushes.DimGray);
            if (!field.Eligible) { Add(Copy[field.Reason], Brushes.DimGray); Add(Copy["before"], Brushes.DimGray); Observation(field.Before, IsWorkbook ? SourceDiffPolicy.WorkbookObservationCaption(field.Key, cellA, field.Before) : null); Add(Copy["after"], Brushes.DimGray); Observation(field.After, IsWorkbook ? SourceDiffPolicy.WorkbookObservationCaption(field.Key, cellB, field.After) : null); return; }
            if (field.Before.Range is { } a && (sourceDiagnostics.IsChecked == true || field.Before.State == SourceTextState.Empty)) Add(Copy["before"] + " · " + Copy["textRange"] + ": [0, " + a.Length + ") / " + a.Total + " · " + a.State, Brushes.DimGray);
            if (field.After.Range is { } b && (sourceDiagnostics.IsChecked == true || field.After.State == SourceTextState.Empty)) Add(Copy["after"] + " · " + Copy["textRange"] + ": [0, " + b.Length + ") / " + b.Total + " · " + b.State, Brushes.DimGray);
            if (field.Before.Text == field.After.Text) Add(Copy["identicalObservation"], Brushes.DimGray);
            var diff = SourceDiff.Build(field.Before.Text, field.After.Text);
            if (diff.Truncated) { Add(Copy["boundedDiff"], Brushes.DarkOrange); Add(Copy["before"], Brushes.DimGray); Observation(field.Before); Add(Copy["after"], Brushes.DimGray); Observation(field.After); return; }
            foreach (var line in diff.Lines) Add(line.Prefix + " " + line.Text + (diff.TerminatorsDiffer || line.CutOff ? " " + line.TerminatorLabel : ""), line.Prefix == '-' ? Brushes.DarkRed : line.Prefix == '+' ? Brushes.DarkGreen : Brushes.Black, line.Prefix == '-' ? new SolidColorBrush(Color.FromRgb(255, 241, 240)) : line.Prefix == '+' ? new SolidColorBrush(Color.FromRgb(237, 250, 240)) : null);
        }
        if (IsWorkbook)
        {
            if (inspectorMode is "loading" or "failed") { Add(Copy[inspectorMode == "failed" ? "failed" : "loading"], Brushes.DimGray); return; }
            if (inspectorMode != "raw" || detailPayload.Get("before").ValueKind != JsonValueKind.Object) { Add(Copy["selectDiffChange"], Brushes.DimGray); return; }
            if (WorkbookMetadataPayload(detailPayload))
            {
                Add(Copy["kind_" + selectedChange.Get("kind").Text()], Brushes.DimGray); Add(Copy["metadataObservation"], Brushes.DimGray);
                foreach (var side in new[] { false, true }) AppendMetadataProjection(flow, Copy[side ? "after" : "before"], MetadataSideProjection(side));
                return;
            }
            Add(Copy["textSegmentOnly"], Brushes.DimGray);
            var a = detailPayload.Get("before").Get("items").Items().FirstOrDefault().Get("before"); var b = detailPayload.Get("after").Get("items").Items().FirstOrDefault().Get("after");
            Add(Copy["before"] + " " + a.Get("address").Text() + " → " + Copy["after"] + " " + b.Get("address").Text(), Brushes.DimGray);
            if (sourceDiagnostics.IsChecked == true) foreach (var side in new[] { (Label: Copy["before"], Cell: a), (Label: Copy["after"], Cell: b) }) Add(side.Label + " · " + Copy["cacheState"] + ": " + side.Cell.Get("cached_result").Text() + " · " + Copy["cacheFreshness"] + ": " + side.Cell.Get("cache_freshness").Text() + " · " + Copy["formulaInterpretation"] + ": " + side.Cell.Get("formula_interpretation").Text(), Brushes.DimGray);
            var displayed = new WorkbookSourceScope(Before.RevisionId, After.RevisionId, Before.SheetId, After.SheetId, Before.FocusedAddress, After.FocusedAddress);
            foreach (var field in SourceDiffPolicy.Workbook(AtSelectedChange ? selectedChange : default, a, b, displayed, detailOffset)) Field(field, a, b);
        }
        else if (AtSelectedChange && documentDetail.ValueKind == JsonValueKind.Object)
        {
            Add(Copy["selectedSnippet"], Brushes.DimGray); Field(SourceDiffPolicy.Document(documentDetail, DocumentEventMatchesSources(documentDetail) && documentDetail.Get("change_id").Text() == selectedChange.Get("change_id").Text() && Before.DiffTextAvailable && After.DiffTextAvailable, Before.StructuralPreview || After.StructuralPreview));
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
        busy = value; var ready = !value && !initializing && startupReady; progress.Visibility = value ? Visibility.Visible : Visibility.Collapsed; cancelButton.Visibility = value ? Visibility.Visible : Visibility.Collapsed; cancelButton.IsEnabled = value; importButton.IsEnabled = ready; analyzeButton.IsEnabled = ready && projectId.Length > 0; reorderButton.IsEnabled = ready && !IsWorkbook && projectId.Length > 0; exportButton.IsEnabled = ready && reportId.Length > 0; mcpButton.IsEnabled = ready && reportId.Length > 0; documents.IsEnabled = ready; workbooks.IsEnabled = ready; projectList.IsEnabled = ready && projectChoicesReady; reports.IsEnabled = ready; comparisonMode.IsEnabled = ready && reportId.Length > 0 && !singleSource; Before.NavigationEnabled(ready);
        After.NavigationEnabled(ready); foreach (var pair in actionItems) pair.Value.IsEnabled = pair.Key switch { "refresh" => !value && !initializing, "import" => ready, "analyze" => analyzeButton.IsEnabled, "reorder" => reorderButton.IsEnabled, "export" => exportButton.IsEnabled, "mcp" => mcpButton.IsEnabled, _ => ready };
        queryBefore.IsEnabled = queryAfter.IsEnabled = versionsButton.IsEnabled = reportDetailsButton.IsEnabled = ready && reportId.Length > 0; sourceView.IsEnabled = ready;
        changeList.IsEnabled = ChangeNavigationReady; more.IsEnabled = ChangeNavigationReady && nextChanges.Length > 0; Before.Cells.IsEnabled = !value && Before.ReadState == "ready"; After.Cells.IsEnabled = !value && After.ReadState == "ready"; firstDetail.IsEnabled = !value && detailLoader is not null && (detailOffset > 0 || detailCursor.Length > 0); nextDetail.IsEnabled = !value && detailLoader is not null && (detailNext is not null || detailItemNext.Length > 0);
        RenderSourceDiff();
    }
    private ComparisonSelection AdmitMutation()
    {
        if (!startupReady || initializing) throw new BridgeException("STARTUP_RECOVERY", Copy["startupFailed"]);
        var beforeScroll = IsWorkbook ? Before.GridScroll : Before.PageScroll; var afterScroll = IsWorkbook ? After.GridScroll : After.PageScroll;
        var saved = new ComparisonSelection(projectId, reportId, IsWorkbook, currentProject, currentReport, Before.CaptureSelection(), After.CaptureSelection(), intervalFrom, intervalTo, beforeScroll?.HorizontalOffset ?? 0, beforeScroll?.VerticalOffset ?? 0, afterScroll?.HorizontalOffset ?? 0, afterScroll?.VerticalOffset ?? 0);
        BeginScope(); InvalidateAuthority(true); Before.Invalidate(); After.Invalidate(); SetBusy(true); return saved;
    }
    private async Task FinishMutation(CancellationTokenSource owned, ComparisonSelection previous, bool completed)
    {
        try
        {
            if (ReferenceEquals(operation, owned))
            {
                if (!completed) { await RestoreAfterMutation(previous); if (ComparisonState == "ready") status.Text = Copy[Preferences.IsReadOnly ? "preferencesReadOnly" : "ready"]; }
                try { await RefreshProjects(); } catch (Exception error) when (error is BridgeException or IOException or OperationCanceledException) { status.Text = Copy["projectRefreshFailed"]; }
            }
        }
        finally { if (owned.IsCancellationRequested) operationCancellations++; if (ReferenceEquals(operation, owned)) { operation = null; SetBusy(false); } owned.Dispose(); }
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
        if (busy || initializing || !startupReady) return; var dialog = new ImportWindow(Copy, IsWorkbook) { Owner = this }; if (dialog.ShowDialog() != true) return;
        await ImportAndAnalyze(dialog.ProjectTitle, dialog.Rows.ToList());
    }
    internal async Task ImportAndAnalyze(string title, IReadOnlyList<ImportRow> rows, Action<int>? startedForSmoke = null, Action? afterCreateForSmoke = null)
    {
        if (busy || initializing || !startupReady) return; var owned = new CancellationTokenSource(); operation = owned; var previous = AdmitMutation(); var completed = false; status.Text = Copy["importing"];
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
        if (busy || initializing || !startupReady || projectId.Length == 0) return; var owned = new CancellationTokenSource(); operation = owned; var previous = AdmitMutation(); var completed = false;
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
        if (busy || !startupReady || IsWorkbook || projectId.Length == 0) return;
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
        if (reportId.Length == 0 || busy || !startupReady) return; var project = projectId; var report = reportId; var workbook = IsWorkbook; var language = Copy.Language;
        var folder = new OpenFolderDialog { Title = Copy["exportFolder"], Multiselect = false }; if (folder.ShowDialog(this) != true) return;
        if (Directory.EnumerateFileSystemEntries(folder.FolderName).Any()) { MessageBox.Show(this, Copy["exportEmpty"], Copy["export"]); return; }
        var owned = new CancellationTokenSource(); operation = owned; SetBusy(true); try { await RecoverBeforeMutation(owned.Token); await Bridge.Call(workbook ? "workbookExport" : "export", new { project_id = project, report_id = report, folder = folder.FolderName, language }, owned.Token); status.Text = Copy["exported"] + ": " + folder.FolderName; } finally { if (owned.IsCancellationRequested) operationCancellations++; if (ReferenceEquals(operation, owned)) { operation = null; SetBusy(false); } owned.Dispose(); }
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
        if (busy || singleSource || net == NetMode) return;
        if (IsWorkbook) workbookNet = net; else { documentNet = net; documentRangeUnavailable = false; } ClearSelectedChange();
        UpdateInterval(); if (reportId.Length == 0) return;
        var ticket = BeginScope(); InvalidateAuthority(true);
        try { if (Before.ReadState is "loading" or "failed" or "empty") await Before.Load(ticket, reads.Token); if (!IsCurrent(ticket)) return; if (After.ReadState is "loading" or "failed" or "empty") await After.Load(ticket, reads.Token); if (!IsCurrent(ticket)) return; await LoadChanges(false, ticket, reads.Token); RenderSourceDiff(); }
        catch (Exception error) { if (IsCurrent(ticket) && !reads.IsCancellationRequested) FailComparison(preserveSources: error is BridgeException { Code: "ENGINE_VERSION_UNAVAILABLE" } && documentRangeUnavailable); throw; }
    }
    private async Task OpenStoredHistory()
    {
        if (busy || IsWorkbook || !NetMode || !documentRangeUnavailable || documentRecoveryScope is not { } scope || scope != (projectId, reportId, intervalFrom, intervalTo)) return;
        await ChangeComparisonMode(false);
    }
    private string ChangeCaption(JsonElement change)
    {
        string Side(bool after)
        {
            var occurrence = change.Get(IsWorkbook ? after ? "to_revision_occurrence_id" : "from_revision_occurrence_id" : after ? "to_occurrence" : "from_occurrence").Text(); var version = VersionOrdinal(occurrence);
            if (IsWorkbook) { var sheetId = change.Get(after ? "to_sheet_id" : "from_sheet_id").Text(); var sheet = currentReport.Get("revisions").Items().Find(v => v.Get("revision_occurrence_id").Text() == occurrence).Get("sheets").Items().Find(s => s.Get("sheet_id").Text() == sheetId).Get("name").Text().Replace('\r', ' ').Replace('\n', ' '); var address = change.Get(after ? "after_address" : "before_address").Text(); return version + " · " + (sheet.Length > 0 ? sheet : Copy[SourceDiffPolicy.WorkbookScoped(change.Get("kind").Text()) ? "workbookMetadata" : sheetId.Length == 0 ? "absentSheet" : "unsupportedSheet"]) + (address.Length > 0 ? "!" + address : sheet.Length > 0 ? " · " + Copy[SourceDiffPolicy.SheetScoped(change.Get("kind").Text()) ? "sheetLevelSource" : "cellNotMaterialized"] : ""); }
            var pages = change.Get("evidence").Items().Where(item => item.Get("revision_occurrence_id").Text() == occurrence).Select(item => item.Get("page").Number()).Where(page => page > 0).Distinct().ToArray(); return version + " · " + (pages.Length > 0 ? "p." + string.Join(",", pages.Take(3)) + (pages.Length > 3 ? " " + string.Format(CultureInfo.CurrentCulture, Copy["morePages"], pages.Length - 3) : "") : Copy[SourceDiffPolicy.DocumentMissingPageCaption(change.Get("kind").Text(), after)]);
        }
        var summaryKey = IsWorkbook ? SourceDiffPolicy.WorkbookSummaryKey(change) : ""; var summary = summaryKey.Length == 0 ? change.Get("description").Text() : summaryKey == "summaryRowPosition" ? string.Format(CultureInfo.CurrentCulture, Copy[summaryKey], SourceDiffPolicy.WorkbookRow(change, false), SourceDiffPolicy.WorkbookRow(change, true)) : Copy[summaryKey];
        string Excerpt(JsonElement value) => value.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined ? Copy["missing"] : value.Text().Length == 0 ? Copy["observationEmpty"] : value.Text().Split('\r', '\n').FirstOrDefault(line => !string.IsNullOrWhiteSpace(line)) ?? Copy["whitespaceText"];
        var preview = IsWorkbook ? summary : Excerpt(change.Get("before")) + " → " + Excerpt(change.Get("after"));
        if (preview.Length > 180) preview = preview[..(char.IsHighSurrogate(preview[179]) ? 179 : 180)] + "…";
        return Copy["kind_" + change.Get("kind").Text()] + "\n" + Side(false) + " → " + Side(true) + "\n" + preview;
    }
    private async Task LoadChanges(bool append, long ticket, CancellationToken token, Func<string, CancellationToken, Task<JsonElement>>? documentReaderForSmoke = null, Func<CancellationToken, Task>? beforeInstallForSmoke = null)
    {
        if (reportId.Length == 0 || intervalFrom.Length == 0 || intervalTo.Length == 0) return;
        var scope = CurrentChangeScope; if (append && loadedChangeScope != scope) return; var retainedEventFailure = append ? eventRetry : null;
        var revisions = currentReport.Get("revisions").Items(); var from = revisions.FindIndex(v => v.Get("revision_occurrence_id").Text() == intervalFrom); var to = revisions.FindIndex(v => v.Get("revision_occurrence_id").Text() == intervalTo);
        if (from > to || from < 0 || to < 0) { if (IsCurrent(ticket)) { ComparisonState = "invalid"; changesReady = false; detail.Text = Copy["reverse"]; } return; }
        if (from == to) { if (IsCurrent(ticket)) { loadedChangeScope = scope; changes.Clear(); nextChanges = ""; changesReady = true; ComparisonState = "ready"; changeList.IsEnabled = !busy; more.IsEnabled = false; detail.Text = SingleSourceGuidance; } return; }
        List<JsonElement> values; string next = "";
        if (IsWorkbook)
        {
            var args = new Dictionary<string, object?> { ["from_revision_occurrence_id"] = intervalFrom, ["to_revision_occurrence_id"] = intervalTo, ["mode"] = NetMode ? "range_net" : "history", ["limit"] = workbookPageLimitForSmoke ?? 100, ["text_length"] = 256 };
            if (append && nextChanges.Length > 0) args["cursor"] = nextChanges;
            changeQueryReadsForSmoke++; var result = await Query("list_workbook_changes", args, token); values = result.Get("items").Items(); next = result.Get("next_cursor").Text();
        }
        else
        {
            var mode = SourceDiff.DocumentQueryMode(from, to, NetMode);
            Task<JsonElement> Read(string selectedMode) { changeQueryReadsForSmoke++; return documentReaderForSmoke is null ? Bridge.Call("changes", new { project_id = projectId, report_id = reportId, from = intervalFrom, to = intervalTo, mode = selectedMode }, token) : documentReaderForSmoke(selectedMode, token); }
            try { values = (await Read(mode)).Items(); }
            catch (BridgeException error) when (mode == "range_net" && error.Code == "ENGINE_VERSION_UNAVAILABLE")
            {
                token.ThrowIfCancellationRequested(); if (!IsCurrent(ticket)) return;
                documentRangeUnavailable = true; documentRecoveryScope = (projectId, reportId, intervalFrom, intervalTo); throw;
            }
        }
        if (beforeInstallForSmoke is not null) await beforeInstallForSmoke(token);
        if (!IsCurrent(ticket) || token.IsCancellationRequested || CurrentChangeScope != scope) return; binding = true; if (!append) changes.Clear();
        foreach (var value in values) changes.Add(new(value.Get("change_id").Text(), ChangeCaption(value), value, Copy["rawChangeDescription"]));
        if (!append && selectedChange.ValueKind == JsonValueKind.Object && !changes.Any(item => item.Id == selectedChange.Get("change_id").Text())) ClearSelectedChange();
        binding = false; loadedChangeScope = scope; nextChanges = next; var keepEventFailure = retainedEventFailure is not null && ReferenceEquals(eventRetry, retainedEventFailure); changesReady = !keepEventFailure; ComparisonState = keepEventFailure ? "failed" : "ready"; changeList.IsEnabled = ChangeNavigationReady; more.IsEnabled = ChangeNavigationReady && next.Length > 0; if (changes.Count == 0) detail.Text = Copy["noChanges"] + "\n\n" + Copy["coverage"] + "\n" + currentReport.Get("coverage_gaps").Pretty(); else if (!append) detail.Text = Copy["selectCell"];
    }
    private Task LoadMoreChanges() => LoadMoreChangesCore();
    private async Task LoadMoreChangesCore(Func<CancellationToken, Task>? beforeInstallForSmoke = null)
    {
        if (!ChangeNavigationReady || !more.IsEnabled) return; more.IsEnabled = false; var ticket = generation;
        try { await LoadChanges(true, ticket, reads.Token, beforeInstallForSmoke: beforeInstallForSmoke); } catch (Exception error) { if (IsCurrent(ticket) && !reads.IsCancellationRequested) FailComparison(preserveSources: error is BridgeException { Code: "ENGINE_VERSION_UNAVAILABLE" } && documentRangeUnavailable); throw; }
    }
    private async Task SelectChange(JsonElement change, bool retry = false, Func<string, JsonElement, CancellationToken, Task>? afterComponentForSmoke = null)
    {
        if (!ChangeNavigationReady || !changes.Any(c => c.Id == change.Get("change_id").Text())) return;
        var selectedRow = changes.First(c => c.Id == change.Get("change_id").Text()); change = selectedRow.Value; binding = true; changeList.SelectedItem = selectedRow; changeList.ScrollIntoView(selectedRow); binding = false;
        var scope = CurrentChangeScope; var ticket = BeginScope(); var token = reads.Token; PaneSelection? eventBefore = null; PaneSelection? eventAfter = null;
        ClearSelectedChange(); InvalidateAuthority(false); Before.Invalidate(); After.Invalidate();
        try {
        if (IsWorkbook)
        {
            var args = new Dictionary<string, object?> { ["change_id"] = change.Get("change_id").Text(), ["mode"] = NetMode ? "range_net" : "history", ["text_length"] = 4096, ["component"] = "before", ["from_revision_occurrence_id"] = change.Get("from_revision_occurrence_id").Text(), ["to_revision_occurrence_id"] = change.Get("to_revision_occurrence_id").Text() };
            var before = await Query("get_workbook_change", args, token); if (afterComponentForSmoke is not null) await afterComponentForSmoke("before", before, token); args["component"] = "after"; var after = await Query("get_workbook_change", args, token); if (afterComponentForSmoke is not null) await afterComponentForSmoke("after", after, token); if (!IsCurrent(ticket) || token.IsCancellationRequested) return;
            if (!SourceDiffPolicy.WorkbookComponent(before, change, "before", projectId, reportId, out var beforeCell) || !SourceDiffPolicy.WorkbookComponent(after, change, "after", projectId, reportId, out var afterCell)) throw new BridgeException("EVIDENCE_SCOPE", "Workbook details do not match the selected fixed change and physical cells.");
            Before.SetEvidenceRevision(change.Get("from_revision_occurrence_id").Text(), change.Get("from_sheet_id").Text(), beforeCell, change.Get("kind").Text()); After.SetEvidenceRevision(change.Get("to_revision_occurrence_id").Text(), change.Get("to_sheet_id").Text(), afterCell, change.Get("kind").Text());
            eventBefore = Before.CaptureSelection(); eventAfter = After.CaptureSelection();
            await Before.Load(ticket, token); await After.Load(ticket, token); if (!IsCurrent(ticket) || token.IsCancellationRequested || loadedChangeScope != scope || CurrentChangeScope != scope) return;
            var project = projectId; var report = reportId;
            detailStyle.IsEnabled = false; detailLoader = async (offset, cancel) => { var request = new Dictionary<string, object?>(args) { ["text_offset"] = offset, ["component"] = "before" }; var a = await QueryFixed("get_workbook_change", request, project, report, cancel); request["component"] = "after"; var b = await QueryFixed("get_workbook_change", request, project, report, cancel); if (!SourceDiffPolicy.WorkbookComponent(a, change, "before", project, report, out _) || !SourceDiffPolicy.WorkbookComponent(b, change, "after", project, report, out _)) throw new BridgeException("EVIDENCE_SCOPE", "Workbook source continuation no longer matches the selected fixed change."); return JsonSerializer.SerializeToElement(new { before = a, after = b }); };
            await LoadDetail(0);
        }
        else
        {
            Before.SetEvidenceRevision(change.Get("from_occurrence").Text()); After.SetEvidenceRevision(change.Get("to_occurrence").Text());
            var intended = DocumentEventPages(change); Before.SetEventPage(intended.Before); After.SetEventPage(intended.After);
            eventBefore = Before.CaptureSelection(); eventAfter = After.CaptureSelection();
            await Before.Load(ticket, token); await After.Load(ticket, token); if (!IsCurrent(ticket) || token.IsCancellationRequested || loadedChangeScope != scope || CurrentChangeScope != scope) return;
            do
            {
                var beforeSettled = await Before.AwaitCurrentPageRead(ticket, token); var afterSettled = await After.AwaitCurrentPageRead(ticket, token);
                if (!IsCurrent(ticket) || token.IsCancellationRequested || loadedChangeScope != scope || CurrentChangeScope != scope) return;
                if (!beforeSettled || !afterSettled) break;
            } while (Before.ReadState == "loading" || After.ReadState == "loading");
            documentDetail = change; inspectorMode = "event"; RerenderInspector(); detailMetadata.Text = change.Pretty();
        }
        if (!IsCurrent(ticket) || token.IsCancellationRequested || loadedChangeScope != scope || CurrentChangeScope != scope) return;
        if (eventBefore is null || eventAfter is null || Before.ReadState is not ("ready" or "absent") || After.ReadState is not ("ready" or "absent")) throw new BridgeException("SOURCE_UNSETTLED", "The selected event source has not finished installing its verified observation.");
        selectedChange = change; selectedBefore = eventBefore; selectedAfter = eventAfter; RerenderInspector(); if (singleSource) { singleSource = false; ApplyLayout(false); } changesReady = true; ComparisonState = "ready"; changeList.IsEnabled = true; more.IsEnabled = nextChanges.Length > 0; RenderSourceDiff(); EvidenceReadSettled();
        } catch { if (IsCurrent(ticket) && !token.IsCancellationRequested && loadedChangeScope == scope && CurrentChangeScope == scope && changes.Contains(selectedRow)) { ClearSelectedChange(); eventRetry = new(scope, selectedRow); FailComparison(false); } throw; }
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
        await SelectChange(selected.Value); Before.CheckReadingChromeForSmoke(); After.CheckReadingChromeForSmoke();
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
        void AssertSingleSource(string occurrence)
        {
            var diagnostics = JsonSerializer.Serialize(new { singleSource, ComparisonState, after_read_state = After.ReadState, comparison_visible = comparison.IsVisible, overlay = unified.Visibility.ToString(), textView, picker_index = sourceView.SelectedIndex, picker_enabled = sourceView.IsEnabled, raw_pager = rawTextPaging.Visibility.ToString(), before_host_mounted = comparison.Children.Contains(Before.Host), after_host_mounted = comparison.Children.Contains(After.Host), intervalFrom, intervalTo, expected_occurrence = occurrence, after_occurrence = After.RevisionId, after_sheet = After.SheetId, reportId, expected_report = fixedReport, retained_host = ReferenceEquals(hostB, After.Host) });
            if (!singleSource || !queryControls.IsVisible || ComparisonState != "ready" || After.ReadState != "ready" || !comparison.IsVisible || unified.Visibility != Visibility.Collapsed || textView || sourceView.SelectedIndex != 0 || sourceView.IsEnabled || rawTextPaging.Visibility != Visibility.Collapsed || comparison.Children.Contains(Before.Host) || !comparison.Children.Contains(After.Host) || intervalFrom != occurrence || intervalTo != occurrence || After.RevisionId != occurrence || reportId != fixedReport || !ReferenceEquals(hostB, After.Host)) throw new InvalidOperationException("Single-source reading state failed: " + diagnostics);
            if (comparisonMode.IsEnabled || (comparisonMode.SelectedItem as Choice)?.Label != Copy["reading"] || !detail.Text.Contains(Copy["singleSourceView"], StringComparison.Ordinal) || !sourceNotice.IsVisible || !sourceNotice.Text.Contains(Copy["singleSourceNotice"], StringComparison.Ordinal) || sourceNotice.Text.Contains(Copy["singleImportedSourceNotice"], StringComparison.Ordinal) || Before.ReadState != "loading" || Before.PageImage.Source is not null || Before.Cells.Items.Count != 0) throw new InvalidOperationException("Multi-version single-source read lost visible different-endpoint guidance, retained comparison-result copy or loaded its unmounted Before source.");
            if (IsWorkbook) { if (!After.Cells.IsVisible || After.Cells.Items.Count != 50 || After.GridScroll is not { ViewportHeight: >= 5 } || After.Cells.ActualHeight < 150) throw new InvalidOperationException("Single workbook source does not expose a useful native grid with at least five rows."); }
            else if (!After.PageImage.IsVisible || After.PageImage.Source is null || After.PageScroll.ActualHeight < 150) throw new InvalidOperationException("Single PDF source did not expose its verified native image with a useful viewport.");
        }
        sourceView.SelectedIndex = 1; await Settle(); if (!unified.IsVisible || !textView) throw new InvalidOperationException("Version-log regression must begin in the actual Text diff presentation.");
        await SelectLogVersion(0); await Settle(); AssertSingleSource(revisions[0].Get("revision_occurrence_id").Text());
        foreach (var locale in new[] { "ko", "en" }) { SetLanguage(locale); await Settle(); AssertSingleSource(revisions[0].Get("revision_occurrence_id").Text()); await capture("first-version-reading-multi-import-" + locale); }
        sourceView.SelectedIndex = 1; await Settle(); AssertSingleSource(revisions[0].Get("revision_occurrence_id").Text()); await capture("first-version-read-from-text");
        await SelectLogVersion(revisions.Count - 1);
        if (IsWorkbook && (Before.ReadState != "ready" || After.ReadState != "ready" || Before.SheetId != revisions[^2].Get("sheets").Items().First().Get("sheet_id").Text() || After.SheetId != revisions[^1].Get("sheets").Items().First().Get("sheet_id").Text() || Before.CaptureSelection().RequestedSheet != revisions[^2].Get("sheets").Items().First().Get("name").Text())) throw new InvalidOperationException("A fresh predecessor→selected version log choice carried a missing sheet name instead of showing each explicit query source's own sheet.");
        sourceView.SelectedIndex = 1; await Settle(); if (!unified.IsVisible || !textView) throw new InvalidOperationException("Equal-endpoint regression must begin in the actual Text diff presentation.");
        var sameOccurrence = intervalFrom; queryAfter.SelectedItem = queryAfter.Items.OfType<Choice>().Single(item => item.Id == sameOccurrence); await endpointRequest; await Settle(); AssertSingleSource(sameOccurrence);
        foreach (var locale in new[] { "ko", "en" }) { SetLanguage(locale); await Settle(); AssertSingleSource(sameOccurrence); await capture("equal-endpoints-reading-multi-import-" + locale); }
        sourceView.SelectedIndex = 1; await Settle(); AssertSingleSource(sameOccurrence); await capture("equal-endpoints-read-from-text");
        // The real query selectors remain independent of the event source pair.
        await SelectSourcePairForSmoke(0, revisions.Count - 1); comparisonMode.SelectedIndex = 0; await modeRequest; await CheckIntermediateEventForSmoke(); await Settle();
        var representative = changes.FirstOrDefault(item => item.Value.Get("kind").Text() == (IsWorkbook ? "stored_value" : "text_modified") && item.Value.Get(IsWorkbook ? "from_revision_occurrence_id" : "from_occurrence").Text() == revisions[0].Get("revision_occurrence_id").Text() && item.Value.Get(IsWorkbook ? "to_revision_occurrence_id" : "to_occurrence").Text() == revisions[1].Get("revision_occurrence_id").Text()); if (representative is not null) await SelectChange(representative.Value); await Settle();
        var queryA = intervalFrom; var queryB = intervalTo; var count = changes.Count; var sourceA = Before.CaptureSelection(); var sourceB = After.CaptureSelection(); var selected = selectedChange.Get("change_id").Text();
        if (queryBefore.SelectedItem is not Choice selectedA || selectedA.Id != queryA || queryAfter.SelectedItem is not Choice selectedB || selectedB.Id != queryB || !sourcePair.Text.Contains(Copy["withinInterval"], StringComparison.Ordinal) || (changeList.SelectedItem as ChangeChoice)?.Id != selected || changeList.ItemContainerGenerator.ContainerFromItem(changeList.SelectedItem) is not ListBoxItem { IsSelected: true, IsVisible: true } || ScrollViewer.GetHorizontalScrollBarVisibility(changeList) != ScrollBarVisibility.Disabled || !changes.Any(item => item.Location.Contains("→", StringComparison.Ordinal))) throw new InvalidOperationException("Query endpoints, visible native change selection or wrapped physical change rows failed.");
        await capture("history-event");
        await capture("source-first-selected");
        sourceView.SelectedIndex = 1; await Settle();
        var text = new TextRange(unified.Document.ContentStart, unified.Document.ContentEnd).Text;
        if (!unified.IsVisible || comparison.Visibility != Visibility.Hidden || !text.Contains(Copy["textDiffCompact"], StringComparison.Ordinal) || IsWorkbook && !text.Contains(Copy["textSegmentOnly"], StringComparison.Ordinal) || !ReferenceEquals(hostA, Before.Host) || !ReferenceEquals(hostB, After.Host) || Before.CaptureSelection() != sourceA || After.CaptureSelection() != sourceB || intervalFrom != queryA || intervalTo != queryB || changes.Count != count) throw new InvalidOperationException("Native text diff lost its bounded/source semantics, query interval or retained native pane selection.");
        if (!IsWorkbook)
        {
            if (!sourceDiagnostics.IsVisible || text.Contains(reportId, StringComparison.Ordinal)) throw new InvalidOperationException("Document text mode hid source diagnostics or put its technical report hash before the diff by default.");
            sourceDiagnostics.IsChecked = true; sourceDiagnostics.RaiseEvent(new RoutedEventArgs(CheckBox.ClickEvent)); await Settle(); var technical = new TextRange(unified.Document.ContentStart, unified.Document.ContentEnd).Text;
            if (!technical.Contains(reportId, StringComparison.Ordinal) || !technical.Contains(Before.PresentedSourceCaption, StringComparison.Ordinal) || !technical.Contains(Copy["textDiffNotice"], StringComparison.Ordinal)) throw new InvalidOperationException("Native Source details lost the exact fixed report, preview provenance or complete semantic qualifier.");
            sourceDiagnostics.IsChecked = false; sourceDiagnostics.RaiseEvent(new RoutedEventArgs(CheckBox.ClickEvent)); await Settle();
        }
        await capture("text-diff");
        foreach (var language in new[] { "ko", "en" }) { SetLanguage(language); if (selectedChange.Get("change_id").Text() != selected || intervalFrom != queryA || intervalTo != queryB || Before.CaptureSelection() != sourceA || After.CaptureSelection() != sourceB || reportId != fixedReport) throw new InvalidOperationException("Text diff language changes altered evidence identity."); }
        if (IsWorkbook && representative is not null)
        {
            sourceView.SelectedIndex = 0; await Settle(); var origin = (Before.SelectedRow, Before.SelectedColumn); var nativeRows = Before.Cells.ItemsSource;
            await Before.ClickCellForSmoke(Before.FocusedRow + 1, Before.FocusedColumn); await Settle();
            if (AtSelectedChange || (Before.SelectedRow, Before.SelectedColumn) != origin || !ReferenceEquals(nativeRows, Before.Cells.ItemsSource) || !sourceNotice.Text.Contains(Copy["outsideChange"], StringComparison.Ordinal) || !returnChange.IsVisible || !returnChange.IsEnabled || intervalFrom != queryA || intervalTo != queryB || changes.Count != count) throw new InvalidOperationException("A native cell click within the existing viewport retained selected-event identity or changed its query/window.");
            await capture("within-viewport-native-cell-browse"); sourceView.SelectedIndex = 1;
            if (unified.Document.Blocks.OfType<Paragraph>().Any(paragraph => ReferenceEquals(paragraph.Foreground, Brushes.DarkRed) || ReferenceEquals(paragraph.Foreground, Brushes.DarkGreen))) throw new InvalidOperationException("A manual within-viewport cell click retained colored selected-event text authority.");
            await ReturnToChange(); await Settle(); sourceView.SelectedIndex = 0;
            if (!AtSelectedChange || Before.CaptureSelection() != sourceA || After.CaptureSelection() != sourceB || Before.Cells.SelectedCells.Count != 1 || Before.Cells.SelectedCells[0].Item is not GridRow anchor || anchor.Row != sourceA.FocusedRow || Before.SelectedColumn + Before.Cells.SelectedCells[0].Column.DisplayIndex - 1 != sourceA.FocusedColumn || intervalFrom != queryA || intervalTo != queryB || changes.Count != count) throw new InvalidOperationException("Return did not restore the exact native event cell anchor without replacing the wider query.");
            await capture("within-viewport-return-exact-cell"); sourceView.SelectedIndex = 1;
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
    private JsonElement ScopedDocumentPresentationForSmoke(JsonElement change)
    {
        var fields = change.EnumerateObject().ToDictionary(property => property.Name, property => (object?)property.Value);
        fields["report_id"] = reportId; fields["change_id"] = change.Get("change_id").Text().Length > 0 ? change.Get("change_id").Text() : "SYNTHETIC_document_presentation"; fields["from_occurrence"] = Before.RevisionId; fields["to_occurrence"] = After.RevisionId;
        fields["evidence"] = new[] { new { page_id = Before.PageId, revision_occurrence_id = Before.RevisionId }, new { page_id = After.PageId, revision_occurrence_id = After.RevisionId } };
        return JsonSerializer.SerializeToElement(fields);
    }
    internal async Task CheckTypedDiffPresentationForSmoke(Func<string, Task> capture, Func<string, object, Task>? observe = null)
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
            else change = ScopedDocumentPresentationForSmoke(change);
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
            foreach (var pair in new[] { ("a\rb\n", "a\r\nb"), ("a\r\nb", "a\rb\n") })
            {
                Install(J(new { kind = "text_modified", before = pair.Item1, after = pair.Item2 }));
                if (!Colored() || new[] { "⟦CR⟧", "⟦LF⟧", "⟦CRLF⟧", "⟦EOF⟧" }.Any(marker => !Text().Contains(marker, StringComparison.Ordinal))) throw new InvalidOperationException("Native text view conflated distinct per-line terminators with the same concatenated characters.");
            }
            await capture("synthetic-newline-boundary-collision");
            foreach (var source in new[] { "SYNTHETIC boundary\r\n" + new string('x', SourceDiff.CharacterLimit + 20), string.Concat(Enumerable.Repeat("SYNTHETIC line\r\n", SourceDiff.LineLimit + 1)) })
            {
                var after = source.Length > SourceDiff.CharacterLimit ? source.Insert(SourceDiff.CharacterLimit - 4, "inserted near cut boundary\r\n") : "inserted near beginning\n" + source; Install(J(new { kind = "text_modified", before = source, after })); RerenderInspector();
                if (Colored() || !Text().Contains(Copy["boundedDiff"], StringComparison.Ordinal) || !Text().Contains(Copy["before"], StringComparison.Ordinal) || !Text().Contains(Copy["after"], StringComparison.Ordinal) || !detail.Text.Contains(source, StringComparison.Ordinal) || !detail.Text.Contains(after, StringComparison.Ordinal)) throw new InvalidOperationException("Over-budget paired source text produced colored prefix artifacts or lost its full exact evidence reader.");
            }
            UpdateLayout(); await Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle); unified.ScrollToVerticalOffset(320); unified.UpdateLayout();
            var manualTextOffset = unified.VerticalOffset; if (manualTextOffset < 100) throw new InvalidOperationException("The bounded text viewport has no real manual scroll position.");
            var sourceA = Before.CaptureSelection(); var sourceB = After.CaptureSelection(); var diffQuery = CurrentChangeScope; var diffReport = currentReport.GetRawText();
            foreach (var locale in new[] { "ko", "en" })
            {
                SetLanguage(locale); SetBusy(true); SetBusy(false); UpdateLayout(); await Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle);
                if (Math.Abs(unified.VerticalOffset - manualTextOffset) > 1 || sourceA != Before.CaptureSelection() || sourceB != After.CaptureSelection() || diffQuery != CurrentChangeScope || currentReport.GetRawText() != diffReport) throw new InvalidOperationException("Locale or same-identity busy chrome reset the manually scrolled text viewport.");
                await capture("synthetic-retained-text-scroll-" + locale);
            }
            await capture("synthetic-over-budget-neutral-reading");
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
            var structuralRaw = "SYNTHETIC raw structure\r\nends…"; var projected = ComparePane.ReadPreviewObservation(J(new { text = structuralRaw, text_total_length = 65599, text_truncated = true }));
            if (projected.State != SourceTextState.Partial || projected.Text != structuralRaw || projected.Range is not { Valid: true, Total: 65599 } || ComparePane.ReadPreviewObservation(J(new { text = "", text_total_length = 0, text_truncated = false })).State != SourceTextState.Empty) throw new InvalidOperationException("Structural preview presentation markers contaminated the typed raw source observation or erased explicit empty source.");
        }
        else
        {
            var a = CompleteCell(new { address = "C2", value = "SYNTHETIC stored 100", formula = "=SUM(A1:A3)", number_format = "0", cached_result = "present", formula_interpretation = "explicit" });
            var b = CompleteCell(new { address = "C3", value = (string?)null, formula = "=SUM(B1:B3)", number_format = "0", cached_result = "missing", formula_interpretation = "explicit" });
            JsonElement Payload(JsonElement left, JsonElement right) => J(new { before = new { items = new[] { new { before = left } } }, after = new { items = new[] { new { after = right } } } });
            foreach (var kind in new[] { "cache_availability", "stored_value", "cell_observation", "row_correspondence", "sheet_observation", "formatting_range" })
            {
                Install(J(new { kind, association = "inferred", alignment_method = "synthetic_control" }), Payload(a, b));
                if (Colored() || !Text().Contains("=SUM(A1:A3)", StringComparison.Ordinal) || !Text().Contains(Copy["resultMissingShort"], StringComparison.Ordinal) || !Text().Contains("C2", StringComparison.Ordinal) || !Text().Contains("C3", StringComparison.Ordinal)) throw new InvalidOperationException("Unavailable/structural workbook observations became colored deletion or lost exact source fields.");
            }
            await capture("synthetic-missing-cache-neutral");
            Install(J(new { kind = "formula" }), Payload(a, b)); if (!Colored() || !Text().Contains(Copy["resultMissingShort"], StringComparison.Ordinal) || !Text().Contains("=SUM(B1:B3)", StringComparison.Ordinal)) throw new InvalidOperationException("Exact eligible formulas were conflated with missing saved values."); await capture("synthetic-formula-independent-cache");
            var complete = CompleteCell(new { address = "C3", value = "SYNTHETIC 120", formula = "=SUM(B1:B3)", number_format = "0.00", cached_result = "present", formula_interpretation = "explicit" });
            var unresolved = CompleteCell(new { address = "C2", value = "SYNTHETIC 100", formula = "=SUM(A1:A3)", number_format = "0", cached_result = "present", formula_interpretation = "unresolved" });
            foreach (var locale in new[] { "en", "ko" })
            {
                SetLanguage(locale); Install(J(new { kind = "stored_value" }), Payload(unresolved, complete));
                if (Colored() || !Text().Contains(Copy["unresolvedObservation"], StringComparison.Ordinal) || !Text().Contains(Copy["notAssertedObservation"], StringComparison.Ordinal) || !Text().Contains("=SUM(A1:A3)", StringComparison.Ordinal)) throw new InvalidOperationException("A complete companion formula was captioned as an asserted unresolved formula edit.");
                await capture("synthetic-field-kind-before-formula-role-" + locale);
                Install(J(new { kind = "stored_value", association = "needs_review" }), Payload(unresolved, complete));
                if (Colored() || !Text().Contains(Copy["unmatchedSourceObservation"], StringComparison.Ordinal) || Text().Contains(Copy["unresolvedObservation"], StringComparison.Ordinal)) throw new InvalidOperationException("Field-specific formula warnings concealed an unconfirmed source association.");
                Install(J(new { kind = "number_format" }), Payload(a, complete));
                if (Colored() || !Text().Contains(Copy["numberFormatObservation"], StringComparison.Ordinal) || !Text().Contains("0.00", StringComparison.Ordinal)) throw new InvalidOperationException("An actual-format-kind presentation withheld its neutral complete number-format observations.");
                await capture("synthetic-number-format-neutral-observations-" + locale);
            }
            var invalidRangeCell = WithRange(a, "value", new { offset = 0, total_length = 9999, next_offset = (int?)null, state = "complete" });
            foreach (var locale in new[] { "en", "ko" })
            {
                SetLanguage(locale); Install(J(new { kind = "stored_value" }), Payload(invalidRangeCell, complete)); RerenderInspector();
                if (!detailRange.Text.Contains(Copy["invalidSourceRange"], StringComparison.Ordinal) || !detailRange.Text.Contains(Copy["invalidSourceSegment"], StringComparison.Ordinal) || !detail.Text.Contains("SYNTHETIC stored 100", StringComparison.Ordinal) || Colored()) throw new InvalidOperationException("The native inspector echoed contradictory raw continuation metadata as a verified complete source range.");
                await capture("synthetic-invalid-inspector-range-" + locale);
            }
            JsonElement ScopedPayload(JsonElement left, JsonElement right)
            {
                JsonElement Side(string side, JsonElement cell)
                {
                    var item = selectedChange.EnumerateObject().ToDictionary(property => property.Name, property => (object?)property.Value); item["component"] = side; item[side] = cell;
                    return J(new { project_id = projectId, report_id = reportId, items = new[] { item } });
                }
                return J(new { before = Side("before", left), after = Side("after", right) });
            }
            JsonElement WarningCell(string address, int row, string? value, string? formula, string cache, string freshness, string interpretation, string valueType = "string") { var cell = CompleteCell(new { address, row, column = 3, value, formula, number_format = "0", cached_result = cache, cache_freshness = freshness, formula_interpretation = interpretation }).EnumerateObject().ToDictionary(property => property.Name, property => (object?)property.Value); cell["value_type"] = valueType; return J(cell); }
            var warningCases = new[] {
                (Name: "unchanged-missing-result", Kind: "formula", Before: WarningCell("C2", 2, null, "=A1", "missing", "unknown", "explicit"), After: WarningCell("C3", 3, null, "=B1", "missing", "unknown", "explicit"), BeforeKeys: new[] { "resultMissingShort", "freshnessUnknownShort" }, AfterKeys: new[] { "resultMissingShort", "freshnessUnknownShort" }, ColoredFormula: true),
                (Name: "unresolved-one-side", Kind: "formula", Before: WarningCell("C2", 2, null, "=A1", "missing", "unknown", "unresolved"), After: WarningCell("C3", 3, "120", "=B1", "present", "unknown", "explicit"), BeforeKeys: new[] { "formulaUnresolvedShort", "resultMissingShort", "freshnessUnknownShort" }, AfterKeys: new[] { "freshnessUnknownShort" }, ColoredFormula: false),
                (Name: "genuine-empty-versus-missing", Kind: "stored_value", Before: WarningCell("C2", 2, "", null, "not_applicable", "not_applicable", "not_formula"), After: WarningCell("C3", 3, null, null, "missing", "unknown", "not_formula"), BeforeKeys: new[] { "valueEmptyShort" }, AfterKeys: new[] { "resultMissingShort", "freshnessUnknownShort" }, ColoredFormula: false),
                (Name: "observed-blank-versus-unrecorded", Kind: "cell_observation", Before: WarningCell("C2", 2, null, null, "not_applicable", "not_applicable", "not_formula", "blank"), After: WarningCell("C3", 3, null, null, "not_applicable", "not_applicable", "not_formula"), BeforeKeys: new[] { "valueBlankShort" }, AfterKeys: new[] { "valueUnrecordedShort" }, ColoredFormula: false)
            };
            foreach (var preset in new[] { "sourceFirst", "focus" }) foreach (var locale in new[] { "en", "ko" }) foreach (var control in warningCases)
            {
                SetLayout(WorkspaceLayout.Preset(preset)); SetLanguage(locale); sourceView.SelectedIndex = 0;
                Install(J(new { kind = control.Kind, change_id = "SYNTHETIC_original_warning_" + control.Name }), Payload(control.Before, control.After)); detailPayload = ScopedPayload(control.Before, control.After); inspectorMode = "raw"; RenderSourceDiff(); UpdateLayout(); await Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle);
                var expected = new[] { Copy["before"] + " C2: " + string.Join(", ", control.BeforeKeys.Select(key => Copy[key])), Copy["after"] + " C3: " + string.Join(", ", control.AfterKeys.Select(key => Copy[key])) };
                var visible = WorkbookVisibleWarnings(); var warningText = new FormattedText(string.Join(" · ", expected), CultureInfo.CurrentCulture, FlowDirection.LeftToRight, new Typeface(sourceNotice.FontFamily, sourceNotice.FontStyle, sourceNotice.FontWeight, sourceNotice.FontStretch), sourceNotice.FontSize, Brushes.Black, VisualTreeHelper.GetDpi(sourceNotice).PixelsPerDip) { MaxTextWidth = Math.Max(1, sourceNotice.ActualWidth), LineHeight = 16 };
                if (observe is not null) await observe("synthetic-original-warnings-" + control.Name + "-" + preset + "-" + locale, new { provenance = "synthetic scoped cell metadata in real WPF Original source; not engine coverage", warnings = visible, context_height = sourceNotice.ActualHeight, warnings_required_height = warningText.Height, before_rows = Before.GridScroll?.ViewportHeight, after_rows = After.GridScroll?.ViewportHeight, before_address = Before.FocusedAddress, after_address = After.FocusedAddress });
                await capture("synthetic-original-warnings-" + control.Name + "-" + preset + "-" + locale);
                if (!visible.SequenceEqual(expected) || !sourceNotice.Text.StartsWith(string.Join(" · ", expected), StringComparison.Ordinal) || InspectorPane.IsVisible || unified.IsVisible || !comparison.IsVisible || sourceNotice.ActualHeight > 49 || warningText.Height > 48 || Before.GridScroll is not { ViewportHeight: >= 5 } || After.GridScroll is not { ViewportHeight: >= 5 }) throw new InvalidOperationException("Original source hid, clipped or cross-wired exact per-side warnings or lost useful source rows in " + control.Name + "/" + preset + "/" + locale);
                sourceView.SelectedIndex = 1;
                var expectedCaption = control.Name == "observed-blank-versus-unrecorded" ? "valueBlankShort" : "resultMissingShort";
                if (Colored() != control.ColoredFormula || !Text().Contains(Copy[expectedCaption], StringComparison.Ordinal) || control.Name == "observed-blank-versus-unrecorded" && !Text().Contains(Copy["formulaAbsent"], StringComparison.Ordinal)) throw new InvalidOperationException("Text observations conflated a materialized blank, absent formula or unavailable saved result, or changed formula eligibility.");
                if (control.Name == "observed-blank-versus-unrecorded") await capture("synthetic-typed-blank-absent-formula-" + preset + "-" + locale);
                sourceView.SelectedIndex = 0;
                foreach (var state in new[] { "loading", "failed" }) { inspectorMode = state; RenderSourceDiff(); if (WorkbookVisibleWarnings().Count != 0 || sourceNotice.Text.Contains(Copy["resultMissingShort"], StringComparison.Ordinal)) throw new InvalidOperationException("A loading/failed cell read retained stale selected result warnings."); }
                inspectorMode = "raw"; RenderSourceDiff();
            }
            // Superseded/foreign raw metadata cannot supply a warning for the
            // currently focused physical cell; scoped native grid metadata may.
            Install(J(new { kind = "formula", change_id = "SYNTHETIC_foreign_warning" }), Payload(warningCases[0].Before, warningCases[0].After)); detailPayload = ScopedPayload(warningCases[0].Before, warningCases[0].After);
            var goodPayload = detailPayload; var foreign = detailPayload.Get("before").EnumerateObject().ToDictionary(property => property.Name, property => (object?)property.Value); foreign["project_id"] = "SYNTHETIC_foreign_project"; detailPayload = J(new { before = foreign, after = detailPayload.Get("after") }); RenderSourceDiff();
            if (WorkbookVisibleWarnings().Any(value => value.StartsWith(Copy["before"] + " C2: ", StringComparison.Ordinal) && value.Contains(Copy["resultMissingShort"], StringComparison.Ordinal)) || !WorkbookVisibleWarnings().Any(value => value.StartsWith(Copy["after"] + " C3: ", StringComparison.Ordinal) && value.Contains(Copy["resultMissingShort"], StringComparison.Ordinal))) throw new InvalidOperationException("Foreign raw scope cross-wired missing-result warnings between source sides."); detailPayload = goodPayload;
            var savedLoader = detailLoader;
            try
            {
                detailLoader = (_, _) => Task.FromException<JsonElement>(new IOException("Synthetic scoped cell read failure"));
                try { await LoadDetail(0); throw new InvalidOperationException("Synthetic cell read unexpectedly succeeded."); } catch (IOException) { }
                if (inspectorMode != "failed" || WorkbookVisibleWarnings().Count != 0) throw new InvalidOperationException("A failed owned raw read retained selected source warnings.");
                var held = new TaskCompletionSource<JsonElement>(TaskCreationOptions.RunContinuationsAsynchronously); detailLoader = (_, _) => held.Task;
                var superseded = LoadDetail(0);
                if (inspectorMode != "loading" || WorkbookVisibleWarnings().Count != 0) throw new InvalidOperationException("A pending owned raw read retained selected source warnings.");
                var newerPayload = ScopedPayload(WarningCell("C2", 2, "100", null, "not_applicable", "not_applicable", "not_formula"), WarningCell("C3", 3, "120", null, "not_applicable", "not_applicable", "not_formula"));
                detailLoader = (_, _) => Task.FromResult(newerPayload); await LoadDetail(0); held.TrySetResult(goodPayload); await superseded;
                if (detailPayload.GetRawText() != newerPayload.GetRawText() || WorkbookVisibleWarnings().Count != 0) throw new InvalidOperationException("A superseded late cell response reinstalled stale missing-result warnings over the newer scoped read.");
                if (observe is not null) await observe("synthetic-original-warning-owned-read-recovery", new { provenance = "synthetic raw payloads through actual LoadDetail generation/cancellation ownership", failed_read_revokes_warnings = true, pending_read_revokes_warnings = true, late_superseded_response_cannot_replace_newer_payload = true });
            }
            finally { detailLoader = savedLoader; detailPayload = goodPayload; inspectorMode = "raw"; RenderSourceDiff(); }
            SetLayout(WorkspaceLayout.Preset("sourceFirst")); sourceView.SelectedIndex = 1;
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
    internal async Task CheckNoticeGeometryForSmoke(Func<string, Task> capture, Func<string, object, Task> observe)
    {
        // Legal near-limit input in synthetic presentation controls, not an
        // engine OCR/correspondence claim. Canonical report bytes stay untouched.
        var fixedReport = reportId; var report = currentReport; var reportBytes = report.GetRawText(); var layout = Layout; var language = Copy.Language; var priorText = textView;
        var previousChange = selectedChange; var previousBefore = selectedBefore; var previousAfter = selectedAfter; var beforeSource = Before.CaptureSelection(); var afterSource = After.CaptureSelection(); var oldWidth = Width; var oldHeight = Height;
        var reason = string.Concat(Enumerable.Repeat("x\n", 999));
        async Task Settle() { UpdateLayout(); await Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle); }
        void Reason(string value, string status = "human_confirmed", bool directed = false)
        {
            selectedChange = JsonSerializer.SerializeToElement(new { kind = "page_lineage_changed", lineage = new { status, reasons = new[] { value } } });
            if (directed) { var fields = selectedChange.EnumerateObject().ToDictionary(property => property.Name, property => (object?)property.Value); fields["topology"] = new { relation_id = "SYNTHETIC_directed_presentation", kind = "range_lineage", from_page_ids = new[] { Before.PageId }, to_page_ids = new[] { After.PageId }, semantics = "directed_reachability" }; selectedChange = JsonSerializer.SerializeToElement(fields); }
            if (!IsWorkbook) selectedChange = ScopedDocumentPresentationForSmoke(selectedChange);
            selectedBefore = Before.CaptureSelection(); selectedAfter = After.CaptureSelection(); RenderSourceDiff();
        }
        object Geometry() => new { width = ActualWidth, height = ActualHeight, context_height = sourceNotice.ActualHeight, source_height = comparison.ActualHeight, before_height = Before.Host.ActualHeight, after_height = After.Host.ActualHeight, before_grid_height = Before.Cells.ActualHeight, after_grid_height = After.Cells.ActualHeight, before_grid_rows = Before.GridScroll?.ViewportHeight, after_grid_rows = After.GridScroll?.ViewportHeight };
        try
        {
            Width = 1024; Height = 768; sourceView.SelectedIndex = 0;
            foreach (var preset in new[] { "sourceFirst", "focus" })
            {
                SetLayout(WorkspaceLayout.Preset(preset));
                foreach (var locale in new[] { "en", "ko" })
                {
                    SetLanguage(locale); Reason("short human correspondence reason"); await Settle(); var shortGeometry = Geometry(); var shortHeight = comparison.ActualHeight;
                    Reason(reason); await Settle(); var longGeometry = Geometry();
                    await observe("synthetic-multiline-reason-" + preset + "-" + locale, new { provenance = "synthetic legal 1998 UTF16 reason in production WPF presentation; not engine evidence", reason_utf16_length = reason.Length, short_reason = shortGeometry, multiline_reason = longGeometry });
                    await capture("synthetic-multiline-reason-" + preset + "-" + locale);
                    if (!sourceNotice.IsVisible || !sourceNotice.ClipToBounds || sourceNotice.ActualHeight > 49 || sourceNotice.Text.Contains('\n') || sourceNotice.Text.Contains('\r') || !sourceNotice.Text.Contains(Copy["assessment_human_confirmed"], StringComparison.Ordinal) || !selectedLimitsButton.IsVisible || !selectedLimitsButton.IsEnabled || comparison.ActualHeight < Math.Max(200, shortHeight - 33) || InspectorPane.IsVisible) throw new InvalidOperationException("A valid multiline reason consumed source height, overflowed the bounded context, or hid uncertainty/details in " + preset + "/" + locale);
                    if (IsWorkbook && (Before.GridScroll is not { ViewportHeight: >= 5 } || After.GridScroll is not { ViewportHeight: >= 5 } || Before.Cells.ActualHeight < 150 || After.Cells.ActualHeight < 150)) throw new InvalidOperationException("Multiline reason left fewer than five visible native workbook source rows.");
                    var dialog = CreateSelectedLimitsDialog(); var fullText = ((DockPanel)dialog.Content).Children.OfType<TextBox>().Single();
                    if (!fullText.IsReadOnly || fullText.VerticalScrollBarVisibility != ScrollBarVisibility.Auto || !fullText.Text.Contains(reason, StringComparison.Ordinal) || SourceDiffPolicy.SelectedNotices(selectedChange).Single(item => item.Key == "lineageReason").Value != reason) throw new InvalidOperationException("The full exact multiline correspondence reason was not retained in native scrolling details.");
                    dialog.Close();
                }
            }
            foreach (var locale in new[] { "en", "ko" })
            {
                SetLanguage(locale);
                foreach (var opaqueReason in new[] { "inferred", "observed", "human_confirmed", "needs_review" })
                {
                    Reason(opaqueReason); var dialog = CreateSelectedLimitsDialog(); var reader = ((DockPanel)dialog.Content).Children.OfType<TextBox>().Single();
                    var reasonLine = reader.Text.Split(["\r\n", "\n"], StringSplitOptions.None).Single(line => line.StartsWith(Copy["lineageReason"] + ": ", StringComparison.Ordinal));
                    if (!string.Equals(reasonLine, Copy["lineageReason"] + ": " + opaqueReason, StringComparison.Ordinal) || !reader.Text.Contains(Copy["lineageAssessment"] + ": " + Copy["assessment_human_confirmed"], StringComparison.Ordinal)) throw new InvalidOperationException("The production native full reader translated an opaque status-looking reason or failed to translate its typed assessment in " + locale);
                    dialog.Close();
                }
            }
            if (!IsWorkbook)
            {
                foreach (var preset in new[] { "sourceFirst", "focus" }) foreach (var locale in new[] { "en", "ko" })
                {
                    SetLayout(WorkspaceLayout.Preset(preset)); SetLanguage(locale);
                    foreach (var rawReason in new[] { "normalized_text_bigrams", "unique_nonempty_first_column_key", "unique_exact_row_content" })
                    {
                        Reason(rawReason); await Settle();
                        var dialog = CreateSelectedLimitsDialog(); var reader = ((DockPanel)dialog.Content).Children.OfType<TextBox>().Single(); var exactLine = Copy["lineageReason"] + ": " + rawReason;
                        var fullLine = reader.Text.Split(["\r\n", "\n"], StringSplitOptions.None).Single(line => line.StartsWith(Copy["lineageReason"] + ": ", StringComparison.Ordinal));
                        if (!sourceNotice.IsVisible || InspectorPane.IsVisible || sourceNotice.ActualHeight > 49 || !sourceNotice.Text.Contains(exactLine, StringComparison.Ordinal) || sourceNotice.Text.Contains(Copy["reason_" + rawReason], StringComparison.Ordinal) || !sourceNotice.ToolTip.ToString()!.Split('\n').Contains(exactLine, StringComparer.Ordinal) || !string.Equals(fullLine, exactLine, StringComparison.Ordinal) || !reader.Text.Contains(Copy["lineageAssessment"] + ": " + Copy["assessment_human_confirmed"], StringComparison.Ordinal) || selectedChange.Get("lineage").Get("reasons").Items().Single().Text() != rawReason || reportId != fixedReport || currentReport.GetRawText() != reportBytes || Before.CaptureSelection() != beforeSource || After.CaptureSelection() != afterSource) throw new InvalidOperationException("The compact native notice translated an authored code-looking reason or changed its full raw reader/source in " + preset + "/" + locale);
                        dialog.Close();
                    }
                    Reason("normalized_text_bigrams"); await capture("synthetic-authored-code-reason-" + preset + "-" + locale);
                    foreach (var control in new[] { (Status: "inferred", Directed: false), (Status: "human_confirmed", Directed: true) })
                    {
                        Reason("normalized_text_bigrams", control.Status, control.Directed); await Settle();
                        var dialog = CreateSelectedLimitsDialog(); var reader = ((DockPanel)dialog.Content).Children.OfType<TextBox>().Single(); var exactLine = Copy["lineageReason"] + ": normalized_text_bigrams";
                        if (!sourceNotice.Text.Contains(Copy["reason_normalized_text_bigrams"], StringComparison.Ordinal) || sourceNotice.Text.Contains(exactLine, StringComparison.Ordinal) || !reader.Text.Split(["\r\n", "\n"], StringSplitOptions.None).Contains(exactLine, StringComparer.Ordinal) || selectedChange.Get("lineage").Get("reasons").Items().Single().Text() != "normalized_text_bigrams") throw new InvalidOperationException("Typed generated lineage reason presentation lost localization or mutated its raw evidence in " + locale);
                        dialog.Close();
                    }
                    await observe("synthetic-authored-code-reason-" + preset + "-" + locale, new { provenance = "synthetic native presentation controls, not engine mapping facts", authored_status = "human_confirmed", raw_authored_reasons = new[] { "normalized_text_bigrams", "unique_nonempty_first_column_key", "unique_exact_row_content" }, raw_compact_tooltip_and_full_reader_verified = true, inferred_and_directed_generation_controls_localized_without_raw_mutation = true, preset, language = locale });
                }
            }
            // Explicitly qualify the bounded report dialog with a synthetic
            // projection. Full exports use the unchanged fixed-report action.
            var projection = report.EnumerateObject().ToDictionary(property => property.Name, property => (object?)property.Value);
            projection["coverage_gaps"] = new[] { new { feature = "synthetic", reason = "SYNTHETIC shown gap one" }, new { feature = "synthetic", reason = "SYNTHETIC shown gap two" } }; projection["coverage_gap_count"] = 9; projection["coverage_truncated"] = true;
            foreach (var locale in new[] { "en", "ko" })
            {
                SetLanguage(locale); currentReport = JsonSerializer.SerializeToElement(projection); var dialog = CreateReportDetailsDialog(); var panel = ((DockPanel)dialog.Content).Children.OfType<StackPanel>().Single();
                if (panel.Children.OfType<TextBlock>().Single(block => block.Name == "CoverageProjectionCount").Text != string.Format(CultureInfo.CurrentCulture, Copy["coverageShown"], 2, 9) || panel.Children.OfType<TextBlock>().Single(block => block.Name == "CoverageExportPath").Text != Copy["coverageExportPath"] || !actionItems["export"].IsEnabled) throw new InvalidOperationException("The bounded report dialog did not disclose shown/total coverage and a reachable complete-export path in " + locale);
                dialog.Close(); currentReport = report;
            }
        }
        finally { currentReport = report; selectedChange = previousChange; selectedBefore = previousBefore; selectedAfter = previousAfter; Width = oldWidth; Height = oldHeight; SetLanguage(language); SetLayout(layout); sourceView.SelectedIndex = priorText ? 1 : 0; RenderSourceDiff(); await Settle(); }
        if (reportId != fixedReport || currentReport.GetRawText() != reportBytes || Before.CaptureSelection() != beforeSource || After.CaptureSelection() != afterSource) throw new InvalidOperationException("Synthetic notice/report projection controls altered fixed report bytes or actual source selections.");
    }
    internal async Task SelectCell(ComparePane pane, int row, int column)
    {
        if (busy || !IsWorkbook || ComparisonState != "ready" || !pane.AuthorizesCell(row, column)) return;
        pane.FocusCell(row, column);
        var args = new Dictionary<string, object?> { ["revision_occurrence_id"] = pane.RevisionId, ["sheet_id"] = pane.SheetId, ["row"] = row, ["column"] = column, ["text_length"] = 4096 };
        var project = projectId; var report = reportId; ClearDetail(); detailStyle.IsEnabled = true; detailLoader = (offset, cancel) => { var request = new Dictionary<string, object?>(args) { ["text_offset"] = offset, ["component"] = detailStyle.IsChecked == true ? "style" : "cell", ["limit"] = 1 }; if (detailStyle.IsChecked == true && detailCursor.Length > 0) request["cursor"] = detailCursor; return QueryFixed("get_workbook_cell", request, project, report, cancel); }; await LoadDetail(0);
    }
    internal async Task OpenCellSource(ComparePane pane)
    {
        if (!startupReady || !AllowsEvidence || ComparisonState != "ready" || !IsWorkbook || !pane.AuthorizesCell(pane.FocusedRow, pane.FocusedColumn)) return;
        ChangeVisibility(inspector: true); await SelectCell(pane, pane.FocusedRow, pane.FocusedColumn);
    }
    private Task<JsonElement> QueryFixed(string name, Dictionary<string, object?> args, string project, string report, CancellationToken token) { args["project_id"] = project; args["report_id"] = report; args["max_output_tokens"] = 8000; return Bridge.Call("workbookQuery", new { name, args }, token); }
    private void ClearDetail() { ++detailGeneration; cellReads.Cancel(); detailLoader = null; detailPayload = default; documentDetail = default; inspectorMode = "prompt"; detailNext = null; detailOffset = 0; detailCursor = ""; detailItemNext = ""; detailStyle.IsChecked = false; detailStyle.IsEnabled = false; detailRange.Text = ""; detailMetadata.Text = ""; firstDetail.IsEnabled = false; nextDetail.IsEnabled = false; }
    private Task FirstDetail() { detailCursor = ""; return LoadDetail(0); }
    private Task NextDetail() { if (detailNext is { } offset) return LoadDetail(offset); if (detailItemNext.Length > 0) { detailCursor = detailItemNext; return LoadDetail(0); } return Task.CompletedTask; }
    private async Task LoadDetail(int offset)
    {
        if (detailLoader is not { } loader) return; var sequence = ++detailGeneration; var ticket = generation; cellReads.Cancel(); cellReads.Dispose(); cellReads = new(); var token = cellReads.Token; firstDetail.IsEnabled = false; nextDetail.IsEnabled = false; detailPayload = default; documentDetail = default; inspectorMode = "loading"; detailMetadata.Text = ""; detailRange.Text = ""; detail.Text = Copy["loading"]; RenderSourceDiff();
        try { var value = await loader(offset, token); if (!IsCurrent(ticket) || sequence != detailGeneration || token.IsCancellationRequested) return; detailOffset = offset; detailNext = RawSourcePaging.Next(value, offset); detailItemNext = value.Get("next_cursor").Text(); detailPayload = value; inspectorMode = "raw"; RerenderInspector(); detailMetadata.Text = value.Pretty(); firstDetail.IsEnabled = !busy && (offset > 0 || detailCursor.Length > 0); nextDetail.IsEnabled = !busy && (detailNext is not null || detailItemNext.Length > 0); RenderSourceDiff(); EvidenceReadSettled(); }
        catch { if (IsCurrent(ticket) && sequence == detailGeneration && !token.IsCancellationRequested) { inspectorMode = "failed"; detail.Text = Copy["failed"]; firstDetail.IsEnabled = true; RenderSourceDiff(); } throw; }
    }
    private void RerenderInspector()
    {
        if (inspectorMode == "raw" && detailPayload.ValueKind == JsonValueKind.Object) { detail.Text = FormatDetail(detailPayload); detailRange.Text = FormatRanges(detailPayload); return; }
        if (inspectorMode == "event" && documentDetail.ValueKind == JsonValueKind.Object) { detail.Text = Copy["event"] + ": " + VersionLabel(Before.RevisionId) + " → " + VersionLabel(After.RevisionId) + "\n\n" + Copy["before"] + "\n" + documentDetail.Get("before").Text() + "\n\n" + Copy["after"] + "\n" + documentDetail.Get("after").Text(); return; }
        if (inspectorMode == "failed" || ComparisonState == "failed") detail.Text = Copy["failed"];
        else if (inspectorMode == "loading" || ComparisonState == "loading") detail.Text = Copy["loading"];
        else if (ComparisonState == "invalid") detail.Text = Copy["reverse"];
        else if (ComparisonState == "ready" && changes.Count == 0) detail.Text = (singleSource ? SingleSourceGuidance : Copy["noChanges"]) + "\n\n" + Copy["coverage"] + "\n" + currentReport.Get("coverage_gaps").Pretty();
        else if (inspectorMode == "draft") detail.Text = Copy["noReport"];
        else if (inspectorMode == "empty") detail.Text = Copy["chooseProject"];
        else detail.Text = Copy["selectCell"];
    }
    private string FormatDetail(JsonElement value)
    {
        if (WorkbookMetadataPayload(value)) return FormatMetadataDetail(MetadataSideProjection(false), MetadataSideProjection(true));
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
        if (WorkbookMetadataPayload(value)) return FormatMetadataSummary(MetadataSideProjection(false), MetadataSideProjection(true));
        var lines = new List<string> { Copy["textRange"] };
        void Cell(JsonElement cell, string side)
        {
            if (cell.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined) { lines.Add(side + (side.Length > 0 ? " · " : "") + Copy["cellNotMaterialized"]); return; }
            foreach (var field in new[] { "value", "formula", "number_format" })
            {
                var observation = SourceTextObservation.ReadSegment(cell.Get(field), cell.Get("text_continuations").Get(field)); var range = observation.Range!;
                if (range is { Valid: true, State: "missing" }) { lines.Add(side + (side.Length > 0 ? " · " : "") + Copy[field == "value" ? "cached" : field] + ": missing · " + Copy["requestedOffset"] + "=" + range.Offset + " · total=0"); continue; }
                var start = range.Offset?.ToString(CultureInfo.InvariantCulture) ?? "?"; var end = range.Offset is { } offset ? ((long)offset + range.Length).ToString(CultureInfo.InvariantCulture) : "?"; var total = range.Total?.ToString(CultureInfo.InvariantCulture) ?? "?";
                lines.Add(side + (side.Length > 0 ? " · " : "") + Copy[field == "value" ? "cached" : field] + ": [" + start + ", " + end + ") / " + total + " · " + range.State + " · " + Copy[range.Valid ? "validSourceRange" : "invalidSourceRange"] + (!range.Valid ? " · " + Copy["invalidSourceSegment"] : ""));
            }
        }
        if (value.Get("before").ValueKind == JsonValueKind.Object) { Cell(value.Get("before").Get("items").Items().FirstOrDefault().Get("before"), Copy["before"]); Cell(value.Get("after").Get("items").Items().FirstOrDefault().Get("after"), Copy["after"]); }
        else if (value.Get("component").Text() == "style") foreach (var item in value.Get("items").Items()) { var observation = SourceTextObservation.ReadSegment(item.Get("value"), item.Get("text_continuations").Get("value")); var range = observation.Range!; lines.Add(item.Get("key").Text() + ": [" + (range.Offset?.ToString(CultureInfo.InvariantCulture) ?? "?") + ", " + (range.Offset is { } offset ? ((long)offset + range.Length).ToString(CultureInfo.InvariantCulture) : "?") + ") / " + (range.Total?.ToString(CultureInfo.InvariantCulture) ?? "?") + " · " + Copy[range.Valid ? "validSourceRange" : "invalidSourceRange"] + (!range.Valid ? " · " + Copy["invalidSourceSegment"] : "")); }
        else Cell(value.Get("items").Items().FirstOrDefault(), "");
        return string.Join("\n", lines);
    }
    internal IEnumerable<GridSplitter> NativeSplitters()
    {
        IEnumerable<DependencyObject> Visit(DependencyObject parent) { for (var index = 0; index < VisualTreeHelper.GetChildrenCount(parent); index++) { var child = VisualTreeHelper.GetChild(parent, index); yield return child; foreach (var nested in Visit(child)) yield return nested; } }
        return Visit(workspace).OfType<GridSplitter>();
    }
    internal int ActionableChanges => ChangeNavigationReady && changeList.IsEnabled ? changes.Count : 0;
    internal string DetailText => detail.Text;
    internal string StatusForSmoke => status.Text;
    internal async Task<object> CheckCompactHeaderForSmoke()
    {
        var language = Copy.Language; var expected = Layout; var report = reportId; var before = Before.CaptureSelection(); var after = After.CaptureSelection();
        var observations = new List<object>();
        try
        {
            foreach (var locale in new[] { "en", "ko" })
            {
                SetLanguage(locale); UpdateLayout(); await Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle);
                var children = toolbar.Children.OfType<FrameworkElement>().Where(child => child.Visibility != Visibility.Collapsed).ToArray();
                if (toolbar.ActualHeight > children.Max(child => child.DesiredSize.Height) + 1) throw new InvalidOperationException("The compact native header wrapped into another toolbar row in " + locale);
                if (!evidenceMenu.IsVisible || evidenceMenu.Header as string != Copy["evidence"] || evidenceMenu.IsChecked != Layout.Inspector) throw new InvalidOperationException("The native Evidence menu is not discoverable or does not reflect its pane in " + locale);
                evidenceMenu.RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent, evidenceMenu)); UpdateLayout();
                if (Layout.Inspector == expected.Inspector || InspectorPane.IsVisible != Layout.Inspector || evidenceMenu.IsChecked != Layout.Inspector) throw new InvalidOperationException("The native Evidence menu did not toggle the retained inspector in " + locale);
                evidenceMenu.RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent, evidenceMenu)); UpdateLayout();
                if (Layout != expected || reportId != report || Before.CaptureSelection() != before || After.CaptureSelection() != after || evidenceMenu.IsChecked != expected.Inspector) throw new InvalidOperationException("The native Evidence menu changed saved layout dimensions or source selections in " + locale);
                observations.Add(new { language = locale, toolbar_height = toolbar.ActualHeight, single_row_height = children.Max(child => child.DesiredSize.Height), query_bar_height = reportBar.ActualHeight, source_notice_height = sourceNotice.ActualHeight, evidence_menu_reachable = true, evidence_toggle_preserves_source_and_layout = true });
            }
        }
        finally { SetLanguage(language); UpdateLayout(); await Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle); }
        return observations;
    }
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
        if (projectList.Items.Count == 0 && (!libraryPrompt.IsVisible || !firstImport.IsVisible || !firstImport.IsEnabled || startupRetry.IsVisible)) throw new InvalidOperationException("A completed switch to an actually empty workspace did not reveal its first-run Import action.");
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
    internal async Task<object> CheckTemporaryFocusForSmoke()
    {
        var original = Layout; var report = reportId; var reportBytes = currentReport.GetRawText(); var before = Before.CaptureSelection(); var after = After.CaptureSelection(); var hostA = Before.Host; var hostB = After.Host; var rows = Before.Cells.ItemsSource; var image = Before.PageImage.Source;
        var otherFocus = IsWorkbook ? documentFocus : workbookFocus; var otherActive = otherFocus.Active; var otherLayout = Preferences.For(!IsWorkbook).Current; var name = "native_focus_retained"; Preferences.For(IsWorkbook).Named.Remove(name);
        async Task Settle() { UpdateLayout(); await Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle); }
        MenuItem Menu() { var menu = new MenuItem(); BuildLayoutMenu(menu); return menu; }
        void Click(string key) { var item = Menu().Items.OfType<MenuItem>().Single(item => item.Header as string == Copy[key]); item.RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent, item)); }
        var baseline = WorkspaceLayout.Preset("balanced") with { Sidebar = false, InspectorSide = "left", SidebarWidth = 217, InspectorWidth = 327, ChangesHeight = 149, ChangesWidth = 273, ComparisonRatio = .57 };
        try
        {
            SetLayout(baseline); await Settle(); Click("focus"); await Settle();
            if (!ActiveFocus.Active || Layout.Sidebar || Layout.Inspector || Layout.ChangesVisible || SidebarPane.IsVisible || InspectorPane.IsVisible || ChangesPane.IsVisible || !comparison.IsVisible || !reports.IsVisible || !queryBefore.IsVisible) throw new InvalidOperationException("Native temporary Focus did not hide only source-surrounding panels while keeping native sources and query/report controls.");
            var splitter = NativeSplitters().Single(item => item.Tag as string == "resizeComparison"); var presentation = PresentationSource.FromVisual(splitter) ?? throw new InvalidOperationException("Focused native splitter has no presentation source."); splitter.Focus(); var oldRatio = Layout.ComparisonRatio;
            splitter.RaiseEvent(new KeyEventArgs(Keyboard.PrimaryDevice, presentation, Environment.TickCount, Key.Right) { RoutedEvent = Keyboard.KeyDownEvent }); splitter.RaiseEvent(new KeyEventArgs(Keyboard.PrimaryDevice, presentation, Environment.TickCount, Key.Right) { RoutedEvent = Keyboard.KeyUpEvent }); await Settle();
            if (Math.Abs(Layout.ComparisonRatio - oldRatio) <= .001) throw new InvalidOperationException("Focused native keyboard geometry edit did not persist.");
            Click("vertical"); await Settle(); var retained = ActiveFocus.Persisted(Layout);
            if (!ActiveFocus.Active || !Layout.VerticalComparison || Layout.Sidebar || Layout.Inspector || Layout.ChangesVisible || retained.Sidebar != baseline.Sidebar || retained.Inspector != baseline.Inspector || retained.ChangesVisible != baseline.ChangesVisible || AppPreferences.Load(PreferencesPath).For(IsWorkbook).Current != retained) throw new InvalidOperationException("Focus geometry or persistence erased retained panel intent.");
            var dialog = CreateNamedLayoutDialog(); var content = (StackPanel)dialog.Content; var field = content.Children.OfType<TextBox>().Single(); var buttons = content.Children.OfType<StackPanel>().Single();
            dialog.Loaded += (_, _) => dialog.Dispatcher.BeginInvoke(() => { field.Text = name; buttons.Children.OfType<Button>().Single(button => button.Name == "SaveLayout").RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); });
            if (dialog.ShowDialog() != true || !ActiveFocus.Active || Preferences.For(IsWorkbook).Named[name] != retained || AppPreferences.Load(PreferencesPath).For(IsWorkbook).Named[name] != retained) throw new InvalidOperationException("Saving inside Focus stored transient hidden panels or exited Focus.");
            Click("focus"); await Settle(); if (ActiveFocus.Active || Layout != retained) throw new InvalidOperationException("Native Focus off did not restore retained panels and focused geometry edits.");
            Click("focus"); Click("sidebar"); await Settle(); if (ActiveFocus.Active || Layout != (retained with { Sidebar = true })) throw new InvalidOperationException("Opening one panel during Focus did not restore retained geometry and merge only that visibility flag.");
            Click("focus"); Click("review"); await Settle(); if (ActiveFocus.Active || Layout != WorkspaceLayout.Preset("review")) throw new InvalidOperationException("Applying a preset did not establish a new non-Focus baseline.");
            Click("focus"); var saved = Menu().Items.OfType<MenuItem>().Single(item => item.Header as string == Copy["applyLayout"]); var named = saved.Items.OfType<MenuItem>().Single(item => item.Header is TextBlock text && text.Text == name); named.RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent, named)); await Settle();
            if (ActiveFocus.Active || Layout != retained) throw new InvalidOperationException("Applying a saved layout failed to replace the transient Focus baseline.");
            Click("focus"); Click("reset"); await Settle(); if (ActiveFocus.Active || Layout != new WorkspaceLayout()) throw new InvalidOperationException("Reset during Focus failed to establish the source-first baseline.");
            SetLayout(WorkspaceLayout.Preset("focus")); if (ActiveFocus.Active) throw new InvalidOperationException("An independently all-hidden arrangement was mistaken for temporary Focus.");
            if (otherFocus.Active != otherActive || Preferences.For(!IsWorkbook).Current != otherLayout || !ReferenceEquals(hostA, Before.Host) || !ReferenceEquals(hostB, After.Host) || !ReferenceEquals(rows, Before.Cells.ItemsSource) || !ReferenceEquals(image, Before.PageImage.Source) || Before.CaptureSelection() != before || After.CaptureSelection() != after || reportId != report || currentReport.GetRawText() != reportBytes) throw new InvalidOperationException("Temporary Focus changed another workspace, native content, selection or fixed report.");
            return new { focus_geometry_ratio = retained.ComparisonRatio, orientation_retained = retained.VerticalComparison, retained_layout = retained, saved_and_persisted_retained_intent = true, native_menu_toggle_visibility_preset_saved_reset_routes = true, native_hosts_and_source_scope_unchanged = true };
        }
        finally { Preferences.For(IsWorkbook).Named.Remove(name); SetLayout(original); await Settle(); }
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
    internal async Task<object> CheckStartupRecoveryForSmoke(Func<string, Task> capture)
    {
        var language = Copy.Language; var calls = new List<string>(); var before = (await Bridge.Call("projects")).GetRawText();
        try { await InitializeCore(async command => { calls.Add(command); await Bridge.Call(command); if (command == "workbookRecover") throw new IOException("SYNTHETIC startup completion fault after actual recovery calls"); }); throw new InvalidOperationException("The startup recovery failure control succeeded."); } catch (IOException) { }
        foreach (var locale in new[] { "en", "ko" })
        {
            SetLanguage(locale); UpdateLayout(); await Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle);
            if (startupReady || initializing || !startupFailed || busy || importButton.IsEnabled || actionItems.Where(pair => pair.Key != "refresh").Any(pair => pair.Value.IsEnabled) || !actionItems["refresh"].IsEnabled || !startupRetry.IsVisible || !startupRetry.IsEnabled || firstImport.IsVisible) throw new InvalidOperationException("Failed library recovery enabled writers or hid its scoped native retry in " + locale);
            await ImportAndAnalyze("blocked startup writer", []); if ((await Bridge.Call("projects")).GetRawText() != before || operation is not null) throw new InvalidOperationException("A direct import writer bypassed failed startup recovery.");
            await capture("startup-recovery-failed-" + locale);
        }
        startupRetry.RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); await startupRequest; UpdateLayout(); await Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle);
        if (!startupReady || startupFailed || initializing || !firstImport.IsVisible || !firstImport.IsEnabled || startupRetry.IsVisible || !importButton.IsEnabled || (await Bridge.Call("projects")).GetRawText() != before) throw new InvalidOperationException("Native library Retry did not complete real recovery and expose the first-run Import action without mutation.");
        await capture("startup-empty-library-visible-import");
        var opened = false; Exception? failure = null;
        _ = Dispatcher.BeginInvoke(System.Windows.Threading.DispatcherPriority.ApplicationIdle, () =>
        {
            ImportWindow? dialog = null;
            try { dialog = Application.Current.Windows.OfType<ImportWindow>().Single(window => ReferenceEquals(window.Owner, this)); opened = true; if (dialog.Rows.Count != 0) throw new InvalidOperationException("First-run Import did not open a new timeline."); dialog.Close(); }
            catch (Exception error) { failure = error; dialog?.Close(); }
        });
        firstImport.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        if (!opened || failure is not null || (await Bridge.Call("projects")).GetRawText() != before) throw new InvalidOperationException("The visible first-run Import did not open/cancel its actual native empty timeline.", failure);
        SetLanguage(language);
        return new { controlled_failure = "Synthetic completion fault after actual recover and workbookRecover; not an OS-lock assertion", recovery_commands = calls, failed_state_blocks_writer_and_offers_retry = true, native_retry_runs_actual_recovery = true, native_first_run_import_opens_new_timeline_and_cancel_preserves_library = true };
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
            if (status.Text != Copy[Preferences.IsReadOnly ? "preferencesReadOnly" : "ready"]) throw new InvalidOperationException("Restored saved report retained a stale import/progress status after a cancelled or failed new import.");
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
    internal async Task<object> CheckDocumentEventAnchorRaceForSmoke(Func<string, Task> capture, Func<string, object, Task> observe)
    {
        if (IsWorkbook) throw new InvalidOperationException("The event-page anchor race requires actual document sources.");
        var project = projectId; var report = reportId; var reportBytes = currentReport.GetRawText(); var originalA = Before.CaptureSelection(); var originalB = After.CaptureSelection(); var originalFrom = intervalFrom; var originalTo = intervalTo; var originalNet = NetMode; var originalText = textView; var language = Copy.Language; var layout = Layout;
        var originalChange = selectedChange; var originalAnchorA = selectedBefore; var originalAnchorB = selectedAfter; var originalDetail = documentDetail; var originalInspector = inspectorMode; var originalDiagnostics = sourceDiagnostics.IsChecked;
        var observations = new List<object>();
        bool Colored() => unified.Document.Blocks.OfType<Paragraph>().Any(paragraph => ReferenceEquals(paragraph.Foreground, Brushes.DarkRed) || ReferenceEquals(paragraph.Foreground, Brushes.DarkGreen));
        async Task Settle() { UpdateLayout(); await Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle); }
        try
        {
            var revisions = currentReport.Get("revisions").Items(); var beforeRevision = revisions[0]; var afterRevision = revisions[1]; var pages = beforeRevision.Get("pages").Items(); if (pages.Count < 2) throw new InvalidOperationException("The real PDF fixture must have two distinct pages.");
            var canonicalBeforePage = pages[0].Get("page_id").Text(); var canonicalAfterPage = afterRevision.Get("pages").Items()[0].Get("page_id").Text(); var manualPage = pages[1].Get("page_id").Text();
            await SelectSourcePairForSmoke(0, revisions.Count - 1); comparisonMode.SelectedIndex = 0; await modeRequest; SetLayout(WorkspaceLayout.Preset("sourceFirst"));
            var change = changes.FirstOrDefault(item => item.Value.Get("kind").Text() == "text_modified" && item.Value.Get("from_occurrence").Text() == beforeRevision.Get("revision_occurrence_id").Text() && item.Value.Get("to_occurrence").Text() == afterRevision.Get("revision_occurrence_id").Text() && item.Value.Get("evidence").Items().Any(evidence => evidence.Get("page_id").Text() == canonicalBeforePage) && item.Value.Get("evidence").Items().Any(evidence => evidence.Get("page_id").Text() == canonicalAfterPage)) ?? throw new InvalidOperationException("The actual first-page text event is absent from the canonical stored query.");
            var scope = CurrentChangeScope; var rows = changes.ToArray(); var rowBytes = rows.Select(item => item.Value.GetRawText()).ToArray(); var cursor = nextChanges; var queryReads = changeQueryReadsForSmoke; var hostA = Before.Host; var hostB = After.Host;
            foreach (var timing in new[] { (Name: "before-await", After: false, Language: "en"), (Name: "after-await", After: true, Language: "ko") })
            {
                SetLanguage(timing.Language); sourceView.SelectedIndex = 0;
                var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously); var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously); var manualEntered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously); var manualRelease = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
                Task selecting = Task.CompletedTask; Task manual = Task.CompletedTask;
                try
                {
                    if (timing.After) After.PageBeforeInstallForSmoke = async token => { entered.TrySetResult(); await release.Task.WaitAsync(TimeSpan.FromSeconds(20), token); };
                    else Before.PageBeforeInstallForSmoke = async _ => { entered.TrySetResult(); await release.Task.WaitAsync(TimeSpan.FromSeconds(20)); };
                    selecting = SelectChange(change.Value); var ticket = generation; await entered.Task.WaitAsync(TimeSpan.FromSeconds(10)); Before.PageBeforeInstallForSmoke = null; After.PageBeforeInstallForSmoke = null;
                    var userZoom = Math.Min(2, Before.Zoom + .25); Before.Zoom = userZoom;
                    manual = Before.SelectPageForSmoke(manualPage, async token => { manualEntered.TrySetResult(); await manualRelease.Task.WaitAsync(TimeSpan.FromSeconds(20), token); }); await manualEntered.Task.WaitAsync(TimeSpan.FromSeconds(10));
                    release.TrySetResult(); await Settle();
                    if (selecting.IsCompleted || ComparisonState != "loading" || changesReady || Before.ReadState != "loading" || Before.PageImage.Source is not null || documentDetail.ValueKind != JsonValueKind.Undefined) throw new InvalidOperationException("Event selection settled before the latest manual page read in " + timing.Name);
                    manualRelease.TrySetResult(); await Task.WhenAll(selecting, manual); await Settle();
                    void QueryUnchanged()
                    {
                        if (projectId != project || reportId != report || currentReport.GetRawText() != reportBytes || generation != ticket || loadedChangeScope != scope || CurrentChangeScope != scope || !rows.SequenceEqual(changes) || !rowBytes.SequenceEqual(changes.Select(item => item.Value.GetRawText())) || nextChanges != cursor || !ReferenceEquals(changeList.SelectedItem, change) || changeQueryReadsForSmoke != queryReads || !ReferenceEquals(hostA, Before.Host) || !ReferenceEquals(hostB, After.Host)) throw new InvalidOperationException("The real event page race replaced its scoped query/list/cursor, selected identity, report or native hosts.");
                    }
                    QueryUnchanged();
                    if (Before.PageId != manualPage || After.PageId != canonicalAfterPage || selectedBefore?.Page != canonicalBeforePage || selectedAfter?.Page != canonicalAfterPage || selectedChange.GetRawText() != change.Value.GetRawText() || AtSelectedChange || ComparisonState != "ready" || Before.ReadState != "ready" || After.ReadState != "ready" || !sourceNotice.Text.Contains(Copy["outsideChange"], StringComparison.Ordinal) || !returnChange.IsVisible || !returnChange.IsEnabled || Before.Zoom != userZoom || !Before.VerifiedPreviewText.Contains("Second page evidence", StringComparison.Ordinal)) throw new InvalidOperationException("Manual page2 was recaptured as the selected event's immutable page1 anchor in " + timing.Name);
                    await capture("event-anchor-" + timing.Name + "-manual-source"); sourceView.SelectedIndex = 1; await Settle();
                    var text = new TextRange(unified.Document.ContentStart, unified.Document.ContentEnd).Text;
                    if (Colored() || !text.Contains(Copy["pageText"], StringComparison.Ordinal) || text.Contains(Copy["selectedSnippet"], StringComparison.Ordinal)) throw new InvalidOperationException("A manually displayed page received the first-page event's colored excerpts in " + timing.Name);
                    // Independent presentation defense: even an accidentally
                    // recaptured UI anchor must not authorize another page.
                    var intendedA = selectedBefore; var intendedB = selectedAfter; selectedBefore = Before.CaptureSelection(); selectedAfter = After.CaptureSelection(); RenderSourceDiff();
                    if (AtSelectedChange || DocumentEventMatchesSources(selectedChange) || Colored() || !sourceNotice.Text.Contains(Copy["outsideChange"], StringComparison.Ordinal)) throw new InvalidOperationException("Canonical event/evidence page binding trusted a recaptured manual UI anchor.");
                    selectedBefore = intendedA; selectedAfter = intendedB; RenderSourceDiff(); await capture("event-anchor-" + timing.Name + "-manual-neutral-text");
                    var metric = new { timing = timing.Name, language = timing.Language, query_scope = scope, selected_event_id = change.Id, canonical_event = change.Value, intended_before_page = selectedBefore?.Page, intended_after_page = selectedAfter?.Page, manual_before_page = Before.PageId, manual_zoom = Before.Zoom, outside_notice = sourceNotice.Text, colored_event_text_on_manual_page = Colored(), query_read_delta = changeQueryReadsForSmoke - queryReads, loaded_ids = changes.Select(item => item.Id).ToArray(), continuation_cursor = nextChanges, independent_recaptured_anchor_control = "synthetic UI anchor override against the same real canonical event; no engine data mutation" };
                    await observe("event-anchor-" + timing.Name, metric); observations.Add(metric);
                    await ReturnToChange(); await Settle();
                    // Return starts a new owned read, but keeps the query and
                    // exact canonical event while retaining the manual zoom.
                    ticket = generation; QueryUnchanged();
                    if (!AtSelectedChange || !DocumentEventMatchesSources(selectedChange) || Before.PageId != canonicalBeforePage || After.PageId != canonicalAfterPage || selectedChange.GetRawText() != change.Value.GetRawText() || !Colored() || sourceNotice.Text.Contains(Copy["outsideChange"], StringComparison.Ordinal) || Before.Zoom != userZoom) throw new InvalidOperationException("Return did not restore the exact real event pages and eligible excerpts without replacing its query or zoom.");
                    await capture("event-anchor-" + timing.Name + "-return-canonical-text");
                }
                finally { Before.PageBeforeInstallForSmoke = null; After.PageBeforeInstallForSmoke = null; release.TrySetResult(); manualRelease.TrySetResult(); try { await Task.WhenAll(selecting, manual); } catch (OperationCanceledException) { } }
            }
            var oneSided = changes.FirstOrDefault(item => item.Value.Get("kind").Text() is "page_added" or "page_deleted") ?? throw new InvalidOperationException("The real PDF/PPTX history must include a one-sided source event.");
            await SelectChange(oneSided.Value); sourceView.SelectedIndex = 1; await Settle();
            if (!string.Join("\n", unified.Document.Blocks.OfType<Paragraph>().Select(paragraph => new TextRange(paragraph.ContentStart, paragraph.ContentEnd).Text)).Contains(Copy["absentPage"], StringComparison.Ordinal) || !AtSelectedChange || Colored() || Before.ReadState != "absent" && After.ReadState != "absent" || sourceNotice.Text.Contains(Copy["outsideChange"], StringComparison.Ordinal) || !rows.SequenceEqual(changes) || cursor != nextChanges || CurrentChangeScope != scope || changeQueryReadsForSmoke != queryReads) throw new InvalidOperationException("Canonical absent-side event context became manual browsing or a colored text deletion.");
            await capture("event-anchor-actual-one-sided-neutral");
            // Explicit synthetic presentation controls exercise the actual
            // selected missing-page chrome against real report occurrences.
            // They never enter the canonical list or an engine write/query.
            Before.SetEventPage(null); After.SetEventPage(null); await Before.Load(generation, reads.Token); await After.Load(generation, reads.Token);
            var captionControls = new List<object>(); sourceDiagnostics.IsChecked = true;
            foreach (var kind in new[] { "coverage_gap", "visual_region_changed", "text_modified", "page_added", "page_deleted" }) foreach (var locale in new[] { "en", "ko" })
            {
                var fields = oneSided.Value.EnumerateObject().ToDictionary(property => property.Name, property => (object?)property.Value); fields["kind"] = kind; fields["change_id"] = "SYNTHETIC_missing_evidence_" + kind; fields["report_id"] = reportId; fields["from_occurrence"] = Before.RevisionId; fields["to_occurrence"] = After.RevisionId; fields["evidence"] = Array.Empty<object>(); fields["before"] = null; fields["after"] = null;
                selectedChange = JsonSerializer.SerializeToElement(fields); selectedBefore = Before.CaptureSelection(); selectedAfter = After.CaptureSelection(); documentDetail = selectedChange; inspectorMode = "event"; RenderSourceDiff();
                if (Before.PresentedFallback != Copy[SourceDiffPolicy.DocumentMissingPageCaption(kind, false)] || After.PresentedFallback != Copy[SourceDiffPolicy.DocumentMissingPageCaption(kind, true)]) throw new InvalidOperationException("Installing selected missing-page context did not immediately refresh both native fallbacks before a locale change.");
                SetLanguage(locale); sourceView.SelectedIndex = 1; RenderSourceDiff();
                var expectedA = Copy[SourceDiffPolicy.DocumentMissingPageCaption(kind, false)]; var expectedB = Copy[SourceDiffPolicy.DocumentMissingPageCaption(kind, true)]; var paragraphs = unified.Document.Blocks.OfType<Paragraph>().Select(paragraph => new TextRange(paragraph.ContentStart, paragraph.ContentEnd).Text).ToArray();
                if (!AtSelectedChange || Before.LocationCaption != expectedA || After.LocationCaption != expectedB || Before.PresentedFallback != expectedA || After.PresentedFallback != expectedB || !paragraphs[0].Contains(expectedA, StringComparison.Ordinal) || !paragraphs[0].Contains(expectedB, StringComparison.Ordinal) || !paragraphs.Any(text => text.Contains(Copy["before"] + " · " + expectedA, StringComparison.Ordinal)) || !paragraphs.Any(text => text.Contains(Copy["after"] + " · " + expectedB, StringComparison.Ordinal)) || Colored() || !rows.SequenceEqual(changes) || !rowBytes.SequenceEqual(changes.Select(item => item.Value.GetRawText())) || nextChanges != cursor || CurrentChangeScope != scope || changeQueryReadsForSmoke != queryReads || currentReport.GetRawText() != reportBytes) throw new InvalidOperationException("Selected sparse evidence page chrome disagreed across header, diagnostics or native fallback, asserted structural absence without that event kind, or mutated its query.");
                captionControls.Add(new { kind, language = locale, before_location = Before.LocationCaption, after_location = After.LocationCaption, before_native_fallback = Before.PresentedFallback, after_native_fallback = After.PresentedFallback, exact_query_and_report_unchanged = true });
                ClearSelectedChange(); documentDetail = default; RenderSourceDiff();
                if (Before.LocationCaption != Copy["absentPage"] || After.LocationCaption != Copy["absentPage"] || Before.PresentedFallback != Copy["absentPage"] || After.PresentedFallback != Copy["absentPage"]) throw new InvalidOperationException("A missing-page event caption leaked into ordinary source reading after selected context was cleared.");
            }
            await observe("synthetic-selected-missing-page-captions", new { scope = "Synthetic selected presentation controls on real report occurrences and production native page-load/chrome, not engine events", cases = captionControls });
            observations.Add(new { synthetic_selected_missing_page_caption_controls = captionControls });
            return new { report_id = report, actual_canonical_event_id = change.Id, query_scope = scope, cases = observations, data_kind = "Actual two-page PDF canonical event with controlled native read timing; explicit synthetic UI-anchor defense and selected missing-evidence caption controls", return_keeps_exact_pages_query_rows_cursor_and_manual_zoom = true, actual_one_sided_event_id = oneSided.Id, canonical_absent_side_stays_selected_and_neutral = true };
        }
        finally
        {
            Before.PageBeforeInstallForSmoke = null; After.PageBeforeInstallForSmoke = null; documentNet = originalNet; Before.RestoreSelection(originalA); After.RestoreSelection(originalB); intervalFrom = originalFrom; intervalTo = originalTo; UpdateInterval(); await ReloadComparisonCore(true);
            selectedChange = originalChange; selectedBefore = originalAnchorA; selectedAfter = originalAnchorB; documentDetail = originalDetail; inspectorMode = originalInspector; var wasBinding = binding; binding = true; changeList.SelectedItem = changes.FirstOrDefault(item => item.Id == originalChange.Get("change_id").Text()); binding = wasBinding; RerenderInspector(); SetLanguage(language); SetLayout(layout); sourceDiagnostics.IsChecked = originalDiagnostics; sourceView.SelectedIndex = originalText ? 1 : 0; RenderSourceDiff();
        }
    }
    internal async Task<object> CheckSourceOnlyPageSupersessionForSmoke(Func<string, Task> capture)
    {
        if (IsWorkbook || loadedChangeScope != CurrentChangeScope) throw new InvalidOperationException("Page supersession requires an installed document query.");
        var pages = currentReport.Get("revisions").Items().Single(item => item.Get("revision_occurrence_id").Text() == Before.RevisionId).Get("pages").Items(); if (pages.Count < 2) throw new InvalidOperationException("The actual document source must have two distinct pages.");
        var before = Before.CaptureSelection(); var after = After.CaptureSelection(); var scope = loadedChangeScope; var rows = changes.ToArray(); var cursor = nextChanges; var selectedRow = changeList.SelectedItem; var readsBefore = changeQueryReadsForSmoke;
        var oldEntered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously); var oldRelease = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously); var latestEntered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously); var latestRelease = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var afterEntered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously); var afterRelease = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously); var finalEntered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously); var finalRelease = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        Task sourceRead = Task.CompletedTask; Task latest = Task.CompletedTask; Task finalPage = Task.CompletedTask;
        try
        {
            Before.SetEventPage(pages[0].Get("page_id").Text());
            // This controlled old install deliberately ignores cancellation to
            // exercise the normal-return identity-mismatch path, not just OCE.
            Before.PageBeforeInstallForSmoke = async _ => { oldEntered.TrySetResult(); await oldRelease.Task.WaitAsync(TimeSpan.FromSeconds(20)); };
            After.PageBeforeInstallForSmoke = async token => { afterEntered.TrySetResult(); await afterRelease.Task.WaitAsync(TimeSpan.FromSeconds(20), token); };
            sourceRead = ReloadSourceWindow(); await oldEntered.Task.WaitAsync(TimeSpan.FromSeconds(10)); Before.PageBeforeInstallForSmoke = null;
            latest = Before.SelectPageForSmoke(pages[1].Get("page_id").Text(), async token => { latestEntered.TrySetResult(); await latestRelease.Task.WaitAsync(TimeSpan.FromSeconds(20), token); });
            await latestEntered.Task.WaitAsync(TimeSpan.FromSeconds(10)); oldRelease.TrySetResult(); await Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle);
            if (sourceRead.IsCompleted || changesReady || ComparisonState != "loading" || Before.ReadState != "loading" || Before.PageImage.Source is not null || detailPayload.ValueKind != JsonValueKind.Undefined || changeQueryReadsForSmoke != readsBefore) throw new InvalidOperationException("An old normal-return page install prematurely settled or failed the still-pending latest source.");
            latestRelease.TrySetResult(); await latest; await afterEntered.Task.WaitAsync(TimeSpan.FromSeconds(10)); After.PageBeforeInstallForSmoke = null;
            finalPage = Before.SelectPageForSmoke(pages[0].Get("page_id").Text(), async token => { finalEntered.TrySetResult(); await finalRelease.Task.WaitAsync(TimeSpan.FromSeconds(20), token); }); await finalEntered.Task.WaitAsync(TimeSpan.FromSeconds(10)); afterRelease.TrySetResult(); await Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle);
            if (sourceRead.IsCompleted || changesReady || ComparisonState != "loading" || Before.ReadState != "loading" || After.ReadState != "ready") throw new InvalidOperationException("A replacement Before page begun while After was loading was prematurely failed or promoted by the owner source read.");
            finalRelease.TrySetResult(); await Task.WhenAll(sourceRead, finalPage);
            if (ComparisonState != "ready" || Before.ReadState != "ready" || Before.PageId != pages[0].Get("page_id").Text() || Before.VerifiedPreviewText.Length == 0 || !changesReady || loadedChangeScope != scope || !rows.SequenceEqual(changes) || cursor != nextChanges || !ReferenceEquals(selectedRow, changeList.SelectedItem) || changeQueryReadsForSmoke != readsBefore) throw new InvalidOperationException("Latest same-generation page replacement did not settle the source-only read with its retained query continuation.");
            await capture("source-only-normal-return-page-supersession");
            return new { retained_query_scope = scope, old_install_ignored_cancellation = true, later_before_page_started_while_after_loading = true, latest_page = Before.PageId, latest_page_text = Before.VerifiedPreviewText, changes_query_read_delta = changeQueryReadsForSmoke - readsBefore, list_objects_cursor_and_selected_row_retained = true };
        }
        finally
        {
            Before.PageBeforeInstallForSmoke = null; After.PageBeforeInstallForSmoke = null; oldRelease.TrySetResult(); latestRelease.TrySetResult(); afterRelease.TrySetResult(); finalRelease.TrySetResult(); try { await Task.WhenAll(sourceRead, latest, finalPage); } catch (OperationCanceledException) { }
            Before.RestoreSelection(before); After.RestoreSelection(after); await ReloadSourceWindow();
        }
    }
    internal async Task<object> CheckSoleImportedRevisionForSmoke(ImportRow source, Func<string, Task> capture)
    {
        var project = projectId; var report = reportId; var reportBytes = currentReport.GetRawText(); var workbook = IsWorkbook; var layout = Layout; var language = Copy.Language; var originalNet = NetMode; var priorText = textView;
        var observations = new List<object>();
        static IEnumerable<DependencyObject> Visit(DependencyObject parent) { for (var index = 0; index < VisualTreeHelper.GetChildrenCount(parent); index++) { var child = VisualTreeHelper.GetChild(parent, index); yield return child; foreach (var nested in Visit(child)) yield return nested; } }
        async Task Settle() { UpdateLayout(); await Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle); }
        try
        {
            await ImportAndAnalyze("Sole imported " + (workbook ? "workbook" : "document") + " control", new[] { source });
            var soleProject = projectId; var soleReport = reportId; var soleBytes = currentReport.GetRawText(); var versions = currentReport.Get("revisions").Items(); if (versions.Count != 1) throw new InvalidOperationException("Sole-import control did not create an actual one-occurrence fixed report.");
            var occurrence = versions[0].Get("revision_occurrence_id").Text();
            foreach (var preset in new[] { "sourceFirst", "focus" }) foreach (var locale in new[] { "en", "ko" })
            {
                SetLayout(WorkspaceLayout.Preset(preset)); SetLanguage(locale); sourceView.SelectedIndex = 1; await Settle();
                if (!singleSource || textView || unified.Visibility != Visibility.Collapsed || !comparison.IsVisible || comparison.Children.Contains(Before.Host) || !comparison.Children.Contains(After.Host) || After.ReadState != "ready" || sourceView.IsEnabled || sourceView.SelectedIndex != 0 || comparisonMode.IsEnabled || (comparisonMode.SelectedItem as Choice)?.Id != "reading" || queryBefore.Items.Count != 1 || queryAfter.Items.Count != 1 || intervalFrom != occurrence || intervalTo != occurrence || changes.Count != 0 || !sourceNotice.IsVisible || !sourceNotice.Text.Contains(Copy["singleImportedSourceNotice"], StringComparison.Ordinal) || sourceView.ToolTip as string != Copy["singleImportedSourceView"] || !detail.Text.Contains(Copy["singleImportedSourceView"], StringComparison.Ordinal) || detail.Text.Contains(Copy["singleSourceView"], StringComparison.Ordinal) || !actionItems["import"].IsEnabled || actionItems["import"].Header as string != Copy["import"] || reportId != soleReport || projectId != soleProject || currentReport.GetRawText() != soleBytes) throw new InvalidOperationException("Actual sole-import reading gave impossible endpoint guidance, lost its native source or hid the Import route in " + preset + "/" + locale);
                After.CheckReadingChromeForSmoke();
                if (!newComparisonStage.IsVisible || !newComparisonStage.IsEnabled || newComparisonStage.Content as string != Copy["newComparison"] || queryControls.IsVisible || more.IsVisible || previousChange.IsVisible || nextChange.IsVisible || preset == "sourceFirst" && (!soleChanges.IsVisible || !newComparison.IsVisible || !newComparison.IsEnabled || soleExplanation.Text != Copy["soleListExplanation"])) throw new InvalidOperationException("Sole-import source reading hid its persistent empty-list explanation, mounted reading chrome or new-comparison action, or retained irrelevant comparison paging.");
                if (workbook ? !After.Cells.IsVisible || After.Cells.Items.Count != 50 || After.GridScroll is not { ViewportHeight: >= 5 } : !After.PageImage.IsVisible || After.PageImage.Source is null) throw new InvalidOperationException("Actual sole-import reading does not expose its useful native source.");
                await capture("sole-import-" + preset + "-" + locale); observations.Add(new { preset, language = locale, imported_occurrences = 1, source_occurrence = occurrence, guidance = SingleSourceGuidance, persistent_guidance = Copy["singleImportedSourceNotice"], import_action_enabled = actionItems["import"].IsEnabled, comparison_modes_disabled = !comparisonMode.IsEnabled });
            }
            var opened = false; Exception? dialogFailure = null;
            _ = Dispatcher.BeginInvoke(System.Windows.Threading.DispatcherPriority.ApplicationIdle, () =>
            {
                ImportWindow? dialog = null;
                try { dialog = Application.Current.Windows.OfType<ImportWindow>().Single(window => ReferenceEquals(window.Owner, this)); opened = true; if (dialog.Rows.Count != 0 || dialog.Title != Copy["import"]) throw new InvalidOperationException("Import did not open its real new-timeline dialog."); Visit(dialog).OfType<Button>().Single(button => button.IsCancel).RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); }
                catch (Exception error) { dialogFailure = error; dialog?.Close(); }
            });
            newComparisonStage.RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); await Settle();
            if (!opened || dialogFailure is not null || projectId != soleProject || reportId != soleReport || currentReport.GetRawText() != soleBytes) throw new InvalidOperationException("The visible native New comparison route did not open/cancel a new timeline without changing the sole report.", dialogFailure);
            return new { project_id = soleProject, report_id = soleReport, actual_imported_revision_count = 1, cases = observations, visible_native_new_comparison_opens_empty_new_timeline_and_cancel_preserves_report = true };
        }
        finally
        {
            if (workbook) workbookNet = originalNet; else documentNet = originalNet;
            var saved = (await Bridge.Call(workbook ? "workbookProjects" : "projects")).Items().Single(item => item.Get("project_id").Text() == project); await OpenProject(saved); await OpenReport(report); SetLanguage(language); SetLayout(layout); sourceView.SelectedIndex = priorText ? 1 : 0;
            if (currentReport.GetRawText() != reportBytes) throw new InvalidOperationException("Sole-import control changed the original fixed report projection.");
        }
    }
    internal async Task<object> CheckReferencePreviewGeometryForSmoke(IReadOnlyList<ImportRow> sources, Func<string, Task> capture)
    {
        if (IsWorkbook) throw new InvalidOperationException("Reference preview geometry requires document sources.");
        var project = projectId; var report = reportId; var reportBytes = currentReport.GetRawText(); var layout = Layout; var language = Copy.Language; var previousText = textView;
        try
        {
            await ImportAndAnalyze("Real PPTX EMU / supplied PDF point geometry", sources);
            var revision = currentReport.Get("revisions").Items()[0]; var pptxAsset = revision.Get("assets").Items().Single(asset => asset.Get("format").Text() == "pptx").Get("asset_id").Text(); var pdfAsset = revision.Get("assets").Items().Single(asset => asset.Get("format").Text() == "pdf").Get("asset_id").Text();
            var primary = revision.Get("pages").Items().Single(page => page.Get("asset_id").Text() == pptxAsset); var pdf = revision.Get("pages").Items().Single(page => page.Get("asset_id").Text() == pdfAsset);
            // Explicit QA mapping uses the existing production bridge contract;
            // it does not claim Windows automatic PDFKit-raster qualification.
            var decision = await Bridge.Call("bundleMapping", new { project_id = projectId, report_id = reportId, draft_hash = currentReport.Get("draft_hash").Text(), selection = new { revision_occurrence_id = revision.Get("revision_occurrence_id").Text(), source_asset_id = pptxAsset, rendered_asset_id = pdfAsset, source_page_id = primary.Get("page_id").Text(), rendered_page_id = pdf.Get("page_id").Text(), action = "link", reason = "Explicit synthetic-source QA reference for Windows point geometry; not PowerPoint fidelity certification" } });
            await Analyze(); revision = currentReport.Get("revisions").Items()[0]; primary = revision.Get("pages").Items().Single(page => page.Get("asset_id").Text() == pptxAsset); pdf = revision.Get("pages").Items().Single(page => page.Get("asset_id").Text() == pdfAsset);
            if (primary.Get("width").ValueKind != JsonValueKind.Number || !primary.Get("width").TryGetDouble(out var emu) || emu < 12_000_000 || Math.Abs(emu / 12_700 - 960) > .01 || pdf.Get("width").Number() != 720 || primary.Get("appearance").Get("source_page_id").Text() != pdf.Get("page_id").Text() || primary.Get("appearance").Get("asset_id").Text() != pdfAsset) throw new InvalidOperationException("The real PPTX+PDF sources did not preserve OOXML EMUs and independently sized supplied PDF identity.");
            SetLayout(WorkspaceLayout.Preset("sourceFirst")); await SelectSourcePairForSmoke(0, 1); await Before.SelectPageForSmoke(primary.Get("page_id").Text()); Before.Zoom = 1; After.Zoom = 1; sourceView.SelectedIndex = 0; UpdateLayout(); await Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle);
            if (Before.PageImage.Source is not BitmapSource || After.PageImage.Source is not BitmapSource || Before.PageImage.Width != 720 || After.PageImage.Width != 720 || !Before.PresentedSourceCaption.Contains("reference_pdf", StringComparison.Ordinal) || !After.PresentedSourceCaption.Contains("original_pdf", StringComparison.Ordinal)) throw new InvalidOperationException("A supplied reference PDF used its 960-point primary slide width rather than its actual 720-point PDF width at 100%.");
            var linked = Before.CheckPreviewReadabilityForSmoke(); var standalone = After.CheckPreviewReadabilityForSmoke(); await capture("actual-reference-pdf-720-point-width");
            await Before.SelectPageForSmoke(pdf.Get("page_id").Text()); if (Before.PageImage.Width != 720 || Before.PageImage.Source is not BitmapSource) throw new InvalidOperationException("Selecting the same supplied PDF directly changed its physical 720-point scale.");
            await Before.SelectPageForSmoke(primary.Get("page_id").Text()); Before.Zoom = 1.5; SetLanguage("ko"); if (Before.PageImage.Width != 720 || Before.Zoom != 1.5) throw new InvalidOperationException("Reference geometry repair reset the manual zoom during locale rendering."); await capture("actual-reference-pdf-manual-zoom-ko");
            var nonReference = SourcePreviewGeometry.PointWidth(revision, primary, "pptx_converted", 1234); if (Math.Abs(nonReference - 960) > .01) throw new InvalidOperationException("Real primary PPTX EMUs lost their required point conversion outside reference_pdf.");
            var oldRevision = revision.EnumerateObject().Where(property => property.Name != "reference_appearance_policy").ToDictionary(property => property.Name, property => (object?)property.Value); var oldPrimary = primary.EnumerateObject().Where(property => property.Name != "appearance").ToDictionary(property => property.Name, property => (object?)property.Value); var legacyPrimary = JsonSerializer.SerializeToElement(oldPrimary); var legacyRevision = JsonSerializer.SerializeToElement(oldRevision);
            if (SourcePreviewGeometry.PointWidth(legacyRevision, legacyPrimary, "reference_pdf", 1234) != 720 || Math.Abs(SourcePreviewGeometry.PointWidth(legacyRevision, legacyPrimary, "pptx_converted", 1234) - 960) > .01) throw new InvalidOperationException("Legacy reference mapping was ignored or applied to a non-reference raster.");
            var malformed = primary.EnumerateObject().ToDictionary(property => property.Name, property => (object?)property.Value); malformed["appearance"] = new { source_page_id = pdf.Get("page_id").Text(), asset_id = "foreign_asset" };
            if (SourcePreviewGeometry.PointWidth(revision, JsonSerializer.SerializeToElement(malformed), "reference_pdf", 1234) != 1234) throw new InvalidOperationException("A malformed reference geometry trusted a foreign asset or invented primary-page equivalence.");
            malformed["appearance"] = new { source_page_id = "missing_reference_page", asset_id = pdfAsset };
            if (SourcePreviewGeometry.PointWidth(revision, JsonSerializer.SerializeToElement(malformed), "reference_pdf", 1234) != 1234) throw new InvalidOperationException("A missing same-revision reference invented PDF dimensions.");
            return new { project_id = projectId, report_id = reportId, actual_generated_primary_emu_width = emu, actual_pdf_point_width = pdf.Get("width"), explicit_bundle_decision = decision, linked_reference_native = linked, standalone_native = standalone, primary_nonreference_points = nonReference, legacy_mapping_control_uses_actual_revision_data = true, malformed_reference_control_falls_back_to_native_raster_width = true, source_scope = "Real generated PPTX and PDF imported/linked/analyzed through production contracts; legacy/malformed presentation controls explicitly synthetic; no PowerPoint fidelity claim" };
        }
        finally { var original = (await Bridge.Call("projects")).Items().Single(value => value.Get("project_id").Text() == project); await OpenProject(original); await OpenReport(report); SetLayout(layout); SetLanguage(language); sourceView.SelectedIndex = previousText ? 1 : 0; if (currentReport.GetRawText() != reportBytes) throw new InvalidOperationException("Preview geometry QA changed the normal fixed report."); }
    }
    internal async Task<object> CheckPagedSourceNavigationForSmoke(IReadOnlyList<ImportRow> fixtures, Func<Task> corrupt, Func<Task> restore, Func<string, Task> capture, Func<string, object, Task> observe)
    {
        if (!IsWorkbook) throw new InvalidOperationException("Paged source navigation requires the workbook workspace.");
        var originalProject = projectId; var originalReport = reportId; var originalReportBytes = currentReport.GetRawText(); var originalLayout = Layout; var originalNet = NetMode; var originalLanguage = Copy.Language; var originalText = textView;
        var observations = new List<object>();
        static IEnumerable<DependencyObject> Visit(DependencyObject parent) { for (var index = 0; index < VisualTreeHelper.GetChildrenCount(parent); index++) { var child = VisualTreeHelper.GetChild(parent, index); yield return child; foreach (var nested in Visit(child)) yield return nested; } }
        async Task Settle() { UpdateLayout(); await Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle); }
        try
        {
            await ImportAndAnalyze("Actual two-sheet paged navigation control", fixtures); workbookPageLimitForSmoke = 1; SetLayout(WorkspaceLayout.Preset("sourceFirst")); sourceView.SelectedIndex = 0;
            comparisonMode.SelectedIndex = 0; await modeRequest; await SelectSourcePairForSmoke(0, 1);
            var project = projectId; var report = reportId; var reportBytes = currentReport.GetRawText(); var scope = CurrentChangeScope; var firstPage = changes.ToArray(); var firstCursor = nextChanges;
            if (firstPage.Length != 1 || firstCursor.Length == 0) throw new InvalidOperationException("The actual canonical workbook query did not produce a real continuation at the test-only page limit.");
            await LoadMoreChanges(); var continued = changes.Last();
            if (changes.Count != 2 || continued.Id == firstPage[0].Id || nextChanges.Length == 0 || continued.Value.Get("before_address").Text().Length == 0 || continued.Value.Get("after_address").Text().Length == 0) throw new InvalidOperationException("The continued canonical event is missing or does not identify two real physical cells.");
            await SelectChange(continued.Value); await Settle();
            await CheckEventRetryForSmoke(firstPage[0], continued, corrupt, restore, capture, observe);
            var rows = changes.ToArray(); var rawRows = rows.Select(item => item.Value.GetRawText()).ToArray(); var cursor = nextChanges; var selectedRow = changeList.SelectedItem; var eventBytes = selectedChange.GetRawText(); var anchorBefore = selectedBefore; var anchorAfter = selectedAfter; var queryReads = changeQueryReadsForSmoke;
            var listScroll = Visit(changeList).OfType<ScrollViewer>().FirstOrDefault() ?? throw new InvalidOperationException("The native paged change list has no materialized scroll viewer."); var listX = listScroll.HorizontalOffset; var listY = listScroll.VerticalOffset;
            void Retained(string route, bool ready = true)
            {
                if (projectId != project || reportId != report || currentReport.GetRawText() != reportBytes || loadedChangeScope != scope || CurrentChangeScope != scope || !rows.SequenceEqual(changes) || !rawRows.SequenceEqual(changes.Select(item => item.Value.GetRawText())) || nextChanges != cursor || !ReferenceEquals(selectedRow, changeList.SelectedItem) || selectedChange.GetRawText() != eventBytes || selectedBefore != anchorBefore || selectedAfter != anchorAfter || changeQueryReadsForSmoke != queryReads || Math.Abs(listScroll.HorizontalOffset - listX) > 1 || Math.Abs(listScroll.VerticalOffset - listY) > 1 || ready && (!changesReady || ComparisonState != "ready" || !more.IsEnabled)) throw new InvalidOperationException("Source-only " + route + " replaced a loaded continuation, selected row/scroll, event anchor, query scope or change-query count.");
            }
            async Task Browse(string route, Func<Task> action)
            {
                await action(); await Settle(); Retained(route);
                if (AtSelectedChange) throw new InvalidOperationException("Manual " + route + " did not leave the selected physical event context.");
                sourceView.SelectedIndex = 1; if (unified.Document.Blocks.OfType<Paragraph>().Any(paragraph => ReferenceEquals(paragraph.Foreground, Brushes.DarkRed) || ReferenceEquals(paragraph.Foreground, Brushes.DarkGreen))) throw new InvalidOperationException("Manual " + route + " retained paired colored event detail."); sourceView.SelectedIndex = 0;
                var metric = new { route, project_id = project, report_id = report, query_scope = scope, loaded_event_ids = changes.Select(item => item.Id).ToArray(), selected_event_id = selectedChange.Get("change_id").Text(), continuation_cursor = nextChanges, source_before = Before.CaptureSelection(), immutable_event_before = selectedBefore, changes_query_read_delta = changeQueryReadsForSmoke - queryReads, list_x = listScroll.HorizontalOffset, list_y = listScroll.VerticalOffset };
                await observe("paged-" + route, metric); await capture("paged-" + route); observations.Add(metric);
                await ReturnToChange(); await Settle(); Retained(route + " Return"); if (!AtSelectedChange || Before.CaptureSelection() != anchorBefore || After.CaptureSelection() != anchorAfter) throw new InvalidOperationException("Return from " + route + " did not restore the continued event's exact physical sources."); await capture("paged-" + route + "-returned");
            }
            var ownRevision = currentReport.Get("revisions").Items().Single(item => item.Get("revision_occurrence_id").Text() == Before.RevisionId); var anotherSheet = ownRevision.Get("sheets").Items().Single(item => item.Get("sheet_id").Text() != Before.SheetId);
            await Browse("different-native-sheet", () => Before.SelectSheetForSmoke(anotherSheet.Get("sheet_id").Text()));
            await Browse("native-address", () => Before.GoForSmoke("H40"));
            await Browse("native-next-window", Before.NextWindowForSmoke);
            await CheckFailedGridForSmoke(corrupt, restore); Retained("actual corrupt grid and source-only retry"); await ReturnToChange(); Retained("return after source retry");
            var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously); var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously); var oldSource = ReloadSourceOnly(async _ => { entered.TrySetResult(); await release.Task.WaitAsync(TimeSpan.FromSeconds(20)); });
            try { await entered.Task.WaitAsync(TimeSpan.FromSeconds(10)); if (changesReady || Before.AuthorizesCell(Before.FocusedRow, Before.FocusedColumn) || detailPayload.ValueKind != JsonValueKind.Undefined) throw new InvalidOperationException("Pending source-only navigation retained actionable old detail."); await Before.GoForSmoke("H40"); release.TrySetResult(); await oldSource; Retained("superseded source that ignored cancellation"); }
            finally { release.TrySetResult(); await oldSource; }
            await ReturnToChange(); Retained("Return after supersession");
            var appendEntered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously); var appendRelease = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            var pendingAppend = LoadMoreChangesCore(async token => { appendEntered.TrySetResult(); await appendRelease.Task.WaitAsync(TimeSpan.FromSeconds(20), token); });
            try
            {
                await appendEntered.Task.WaitAsync(TimeSpan.FromSeconds(10)); queryReads++;
                await Before.GoForSmoke("H40"); appendRelease.TrySetResult(); try { await pendingAppend; throw new InvalidOperationException("An uninstalled append did not observe source-navigation cancellation."); } catch (OperationCanceledException) { }
                Retained("source navigation while real append reply pending"); await ReturnToChange(); Retained("Return after cancelled append");
            }
            finally { appendRelease.TrySetResult(); try { await pendingAppend; } catch (OperationCanceledException) { } }
            await LoadMoreChanges(); queryReads++; if (changes.Count != rows.Length + 1 || !changes.Take(rows.Length).SequenceEqual(rows) || changes.Select(item => item.Id).Distinct().Count() != changes.Count || nextChanges == cursor || !ReferenceEquals(selectedRow, changeList.SelectedItem)) throw new InvalidOperationException("Resuming More did not use the retained real cursor to append exactly one canonical event without duplicate/replaced prior rows.");
            await ReturnToChange(); if (!AtSelectedChange || selectedChange.GetRawText() != eventBytes) throw new InvalidOperationException("Continued selected event became unreachable after resumed paging.");
            var beforeQueryFailure = changeQueryReadsForSmoke;
            try { await LoadMoreChangesCore(_ => throw new IOException("SYNTHETIC rejection after a real canonical continuation reply")); throw new InvalidOperationException("The query-install fault control unexpectedly succeeded."); } catch (IOException) { }
            if (loadedChangeScope is not null || changesReady || sourceOnlyFailure || ComparisonState != "failed" || detailPayload.ValueKind != JsonValueKind.Undefined || changeQueryReadsForSmoke != beforeQueryFailure + 1) throw new InvalidOperationException("A query failure retained an owned source-only retry scope or authoritative event detail.");
            await RetryComparison(); if (changeQueryReadsForSmoke != beforeQueryFailure + 2 || ComparisonState != "ready" || loadedChangeScope != CurrentChangeScope || changes.Count != 1 || selectedChange.ValueKind != JsonValueKind.Undefined || returnChange.IsVisible) throw new InvalidOperationException("Query-failure Retry did not issue a fresh query or retained a dead event anchor outside its refreshed first page.");
            var beforeUnknownScope = changeQueryReadsForSmoke; FailComparison(); await ReloadSourceWindow(); if (changeQueryReadsForSmoke != beforeUnknownScope + 1 || !changesReady || loadedChangeScope != CurrentChangeScope || ComparisonState != "ready") throw new InvalidOperationException("An unknown query scope was promoted by source-only completion without an actual replacement changes query.");
            await capture("paged-query-failure-explicit-refresh");
            return new { project_id = project, report_id = report, fixture_kind = "real two-sheet synthetic source files imported and analyzed by production engine", test_only_page_limit = 1, production_default_page_limit = 100, first_event_id = firstPage[0].Id, continued_event_id = continued.Id, first_cursor = firstCursor, retained_cursor = cursor, routes = observations, actual_indexed_grid_failure_source_only_retry = true, superseded_source_and_pending_real_append_cannot_replace_list = true, resumed_real_cursor_appends_without_duplicates = true, query_failure_and_unknown_scope_require_new_query = true, report_projection_unchanged = currentReport.GetRawText() == reportBytes };
        }
        finally
        {
            workbookPageLimitForSmoke = null; workbookNet = originalNet;
            var saved = (await Bridge.Call("workbookProjects")).Items().Single(item => item.Get("project_id").Text() == originalProject); await OpenProject(saved); await OpenReport(originalReport); SetLanguage(originalLanguage); SetLayout(originalLayout); sourceView.SelectedIndex = originalText ? 1 : 0;
            if (currentReport.GetRawText() != originalReportBytes) throw new InvalidOperationException("Paged navigation control changed the normal workbook fixed report.");
        }
    }
    private async Task CheckEventRetryForSmoke(ChangeChoice oldRow, ChangeChoice intended, Func<Task> corrupt, Func<Task> restore, Func<string, Task> capture, Func<string, object, Task> observe)
    {
        var scope = CurrentChangeScope; var rows = changes.ToArray(); var rawRows = rows.Select(row => row.Value.GetRawText()).ToArray(); var cursor = nextChanges; var queryReads = changeQueryReadsForSmoke; var reportBytes = currentReport.GetRawText();
        void Owned(bool ready)
        {
            if (CurrentChangeScope != scope || loadedChangeScope != scope || !rows.SequenceEqual(changes) || !rawRows.SequenceEqual(changes.Select(row => row.Value.GetRawText())) || nextChanges != cursor || queryReads != changeQueryReadsForSmoke || currentReport.GetRawText() != reportBytes || ready && (ComparisonState != "ready" || !changesReady || selectedChange.Get("change_id").Text() != intended.Id || !AtSelectedChange || selectedBefore?.FocusedRow != Before.FocusedRow || selectedAfter?.FocusedRow != After.FocusedRow || !SourceDiffPolicy.WorkbookComponent(detailPayload.Get("before"), intended.Value, "before", projectId, reportId, out _))) throw new InvalidOperationException("Event Retry replaced the owned continued query, canonical rows/cursor/report, or failed to restore the intended source/raw anchors.");
        }
        void Failed()
        {
            Owned(false);
            if (!ChangeNavigationReady || !changeList.IsEnabled || !previousChange.IsEnabled || !nextChange.IsEnabled || (nextChanges.Length > 0 && !more.IsEnabled) || ComparisonState != "failed" || changesReady || selectedChange.ValueKind != JsonValueKind.Undefined || selectedBefore is not null || selectedAfter is not null || documentDetail.ValueKind != JsonValueKind.Undefined || detailPayload.ValueKind != JsonValueKind.Undefined || returnChange.IsVisible || eventRetry is not { } pending || pending.Scope != scope || !ReferenceEquals(pending.Row, intended) || !ReferenceEquals(changeList.SelectedItem, intended) || !retryComparison.IsVisible || retryComparison.Content as string != Copy["retryEvent"]) throw new InvalidOperationException("A failed newly selected event retained the previous event identity/details or lost its exact scoped event retry.");
        }
        await SelectChange(oldRow.Value); var actualRawReads = 0;
        try { await SelectChange(intended.Value, afterComponentForSmoke: (side, payload, token) => { actualRawReads++; if (!SourceDiffPolicy.WorkbookComponent(payload, intended.Value, side, projectId, reportId, out _)) throw new InvalidOperationException("The actual raw component did not match its intended event."); throw new IOException("SYNTHETIC native fault after a real scoped event raw-component response"); }); throw new InvalidOperationException("The raw event fault control did not fail."); } catch (IOException) { }
        if (actualRawReads != 1) throw new InvalidOperationException("The raw failure control bypassed the actual component query."); Failed(); await capture("continued-event-raw-failed"); await RetryComparison(); Owned(true); await capture("continued-event-raw-retried");
        var corrupted = false;
        try
        {
            await corrupt(); corrupted = true; var failed = false;
            try { await SelectChange(intended.Value); } catch (Exception error) when (error is BridgeException or IOException) { failed = true; }
            if (!failed) throw new InvalidOperationException("Actual indexed source corruption did not fail event selection."); Failed(); await capture("continued-event-source-failed");
        }
        finally { if (corrupted) await restore(); }
        await RetryComparison(); Owned(true); await capture("continued-event-source-retried");
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously); var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var stale = SelectChange(oldRow.Value, afterComponentForSmoke: async (_, _, _) => { entered.TrySetResult(); await release.Task.WaitAsync(TimeSpan.FromSeconds(20)); throw new IOException("SYNTHETIC stale component completion failure ignoring cancellation"); });
        try
        {
            await entered.Task.WaitAsync(TimeSpan.FromSeconds(10)); if (selectedChange.ValueKind != JsonValueKind.Undefined || selectedBefore is not null || selectedAfter is not null) throw new InvalidOperationException("A pending event load retained the prior event anchors.");
            await ReloadSourceOnly(); release.TrySetResult(); try { await stale; } catch (IOException) { }
            if (eventRetry is not null || ComparisonState != "ready" || !changesReady) throw new InvalidOperationException("A superseded event failure installed stale retry authority over the newer source read.");
            Owned(false); await SelectChange(intended.Value); Owned(true);
        }
        finally { release.TrySetResult(); try { await stale; } catch (IOException) { } }
        async Task FailIntended()
        {
            try { await SelectChange(intended.Value, afterComponentForSmoke: (_, _, _) => throw new IOException("SYNTHETIC repeated target failure after actual scoped raw query")); throw new InvalidOperationException("The event escape control did not fail."); } catch (IOException) { }
        }
        await FailIntended(); Failed(); await MoveChange(-1);
        if (selectedChange.Get("change_id").Text() != oldRow.Id || eventRetry is not null || !changesReady || !AtSelectedChange || changeQueryReadsForSmoke != queryReads) throw new InvalidOperationException("Previous could not escape a failed continued event to its actual preceding canonical row.");
        await MoveChange(1); Owned(true); await FailIntended(); Failed();
        var pendingTarget = eventRetry; var oldCursor = nextChanges; await LoadMoreChanges();
        if (changes.Count != rows.Length + 1 || !rows.SequenceEqual(changes.Take(rows.Length)) || nextChanges.Length == 0 || nextChanges == oldCursor || !ReferenceEquals(eventRetry, pendingTarget) || ComparisonState != "failed" || changesReady || !ChangeNavigationReady || !changeList.IsEnabled || !more.IsEnabled || detailPayload.ValueKind != JsonValueKind.Undefined || selectedChange.ValueKind != JsonValueKind.Undefined || Before.ReadState != "failed" || After.ReadState != "failed" || changeQueryReadsForSmoke != queryReads + 1) throw new InvalidOperationException("Load more during a failed event lost its valid query continuation or revived failed source/event authority.");
        await SelectChange(oldRow.Value);
        if (eventRetry is not null || ComparisonState != "ready" || !AtSelectedChange || selectedChange.Get("change_id").Text() != oldRow.Id || changeQueryReadsForSmoke != queryReads + 1) throw new InvalidOperationException("Another valid scoped row could not escape the persistent failed target after appending a real continuation.");
        await capture("continued-event-alternate-row-escape"); await SelectChange(intended.Value);
        if (eventRetry is not null || !AtSelectedChange || selectedChange.Get("change_id").Text() != intended.Id || nextChanges.Length == 0 || changeQueryReadsForSmoke != queryReads + 1) throw new InvalidOperationException("The intended event was not reachable after failed-event list navigation and explicit continuation.");
        await observe("continued-event-retry", new { query_scope = scope, intended_event = intended.Value, actual_raw_component_read_count_before_controlled_failure = actualRawReads, loaded_event_ids = changes.Select(row => row.Id).ToArray(), cursor, changes_query_read_delta = changeQueryReadsForSmoke - queryReads, source_before = selectedBefore, source_after = selectedAfter, actual_indexed_grid_corruption_restored = true, stale_failure_does_not_install_retry = true, actual_explicit_append_reads = 1, alternate_valid_row_escape = true, previous_next_escape = true, source_authority_revoked_until_successful_selection = true, data_scope = "Real canonical continued event and production raw/grid reads; explicitly controlled UI completion faults and actual indexed grid corruption restored" });
    }
    internal async Task<object> CheckDocumentQueryRoutingForSmoke(Func<string, Task> capture)
    {
        if (IsWorkbook) throw new InvalidOperationException("Document query routing requires the document workspace.");
        var report = reportId; var reportBytes = currentReport.GetRawText(); var originalA = Before.CaptureSelection(); var originalB = After.CaptureSelection(); var originalFrom = intervalFrom; var originalTo = intervalTo; var originalNet = NetMode; var originalText = textView; var layout = Layout; var language = Copy.Language;
        var versions = currentReport.Get("revisions").Items(); var first = versions[0].Get("revision_occurrence_id").Text(); var second = versions[1].Get("revision_occurrence_id").Text();
        async Task<JsonElement> Read(string mode, string from, string to, CancellationToken token = default) => await Bridge.Call("changes", new { project_id = projectId, report_id = reportId, from, to, mode }, token);
        static string Semantics(JsonElement value)
        {
            // Stored provenance is intentionally retained. A range recompute
            // assigns net IDs/manifest URI and directed-range reason strings.
            var fields = value.EnumerateObject().Where(property => property.Name is not ("change_id" or "evidence_uri")).ToDictionary(property => property.Name, property => (object?)property.Value);
            if (value.Get("lineage").ValueKind == JsonValueKind.Object) fields["lineage"] = value.Get("lineage").EnumerateObject().Where(property => property.Name != "reasons").ToDictionary(property => property.Name, property => property.Value);
            return JsonSerializer.Serialize(fields);
        }
        try
        {
            SetLayout(WorkspaceLayout.Preset("sourceFirst")); sourceView.SelectedIndex = 0;
            var history = await Read("history", first, second); var recomputed = await Read("range_net", first, second);
            if (history.Items().Count == 0 || !history.Items().Select(Semantics).Order().SequenceEqual(recomputed.Items().Select(Semantics).Order())) throw new InvalidOperationException("The representative adjacent pair's source observations/assessments differ beyond the explicitly retained identity and lineage-reason provenance.");
            await SelectSourcePairForSmoke(0, 1); comparisonMode.SelectedIndex = 1; await modeRequest;
            if (queryProvenance.Text != Copy["canonicalAdjacent"] || !NetMode || (comparisonMode.SelectedItem as Choice)?.Id != "range_net" || !changes.Select(item => item.Value.GetRawText()).SequenceEqual(history.Items().Select(item => item.GetRawText())) || intervalFrom != first || intervalTo != second) throw new InvalidOperationException("Adjacent Net did not use its exact stored canonical events while retaining the user's one-pair Net question.");
            var selected = changes[0]; await SelectChange(selected.Value);
            if (selectedChange.GetRawText() != selected.Value.GetRawText() || Before.RevisionId != first || After.RevisionId != second || intervalFrom != first || intervalTo != second || !NetMode) throw new InvalidOperationException("A canonical adjacent event lost its exact source/provenance or Net query during native selection.");
            await capture("adjacent-net-stored-canonical-event");
            await SelectSourcePairForSmoke(0, versions.Count - 1); if (!NetMode) { comparisonMode.SelectedIndex = 1; await modeRequest; }
            var from = intervalFrom; var to = intervalTo; var a = Before.CaptureSelection(); var b = After.CaptureSelection(); var calls = new List<string>();
            try
            {
                await ReloadComparisonCore(true, (mode, token) => { token.ThrowIfCancellationRequested(); calls.Add(mode); return Task.FromException<JsonElement>(new BridgeException("ENGINE_VERSION_UNAVAILABLE", "SYNTHETIC archived engine availability fault at the actual native read boundary")); });
                throw new InvalidOperationException("The unavailable-engine negative control unexpectedly succeeded.");
            }
            catch (BridgeException error) when (error.Code == "ENGINE_VERSION_UNAVAILABLE") { }
            if (Before.ReadState != "ready" || After.ReadState != "ready" || Before.PageImage.Source is null || !Before.DiffTextAvailable || !calls.SequenceEqual(new[] { "range_net" }) || !NetMode || ComparisonState != "failed" || changesReady || changes.Count != 0 || (comparisonMode.SelectedItem as Choice)?.Id != "range_net" || intervalFrom != from || intervalTo != to || Before.CaptureSelection() != a || After.CaptureSelection() != b || !storedHistoryButton.IsVisible || !storedHistoryButton.IsEnabled) throw new InvalidOperationException("Unavailable nonadjacent Net silently changed its question, fetched history, retained stale authority or hid its explicit recovery action.");
            foreach (var locale in new[] { "en", "ko" }) { SetLanguage(locale); if (!sourceNotice.Text.Contains(Copy["documentNetUnavailable"], StringComparison.Ordinal) || !storedHistoryButton.IsVisible) throw new InvalidOperationException("Unavailable Net recovery guidance is hidden outside the inspector in " + locale); await capture("synthetic-net-unavailable-explicit-history-" + locale); }
            storedHistoryButton.RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); await storedHistoryRequest;
            if (queryProvenance.Text != Copy["storedInterval"] || NetMode || ComparisonState != "ready" || (comparisonMode.SelectedItem as Choice)?.Id != "history" || intervalFrom != from || intervalTo != to || Before.CaptureSelection() != a || After.CaptureSelection() != b || storedHistoryButton.IsVisible || !changes.Select(item => item.Value.GetRawText()).SequenceEqual((await Read("history", from, to)).Items().Select(item => item.GetRawText()))) throw new InvalidOperationException("Explicit Open stored history did not load the current fixed interval with its unchanged source selections.");
            await capture("explicit-stored-history-recovery");
            if (reportId != report || currentReport.GetRawText() != reportBytes) throw new InvalidOperationException("Query routing or availability recovery changed its immutable report.");
            return new { report_id = report, adjacent = new { from = first, to = second, source_semantics_equal_excluding_explicit_identity_and_lineage_reason_provenance = true, stored_events = history, recomputed_events = recomputed, exact_stored_events_in_native_net = true }, synthetic_unavailable = new { requested_modes = calls, no_automatic_history_fetch_or_mode_flip = true, explicit_native_history_action = true, interval_from = from, interval_to = to } };
        }
        finally { documentRangeUnavailable = false; documentNet = originalNet; Before.RestoreSelection(originalA); After.RestoreSelection(originalB); intervalFrom = originalFrom; intervalTo = originalTo; UpdateInterval(); await ReloadComparisonCore(true); SetLanguage(language); SetLayout(layout); sourceView.SelectedIndex = originalText ? 1 : 0; }
    }
    internal async Task<object> CheckGridEdgesAndClippingForSmoke(Func<string, Task> capture, Func<string, object, Task> observe)
    {
        if (!IsWorkbook || Before.FocusedAddress != "D4") throw new InvalidOperationException("Grid boundary control requires the real XLSX D4 fixture in the visible Before pane.");
        var report = reportId; var reportBytes = currentReport.GetRawText(); var originalA = Before.CaptureSelection(); var originalB = After.CaptureSelection(); var from = intervalFrom; var to = intervalTo; var layout = Layout; var width = Width; var height = Height; var language = Copy.Language; var originalText = textView;
        var edgeObservations = new List<object>(); var clipObservations = new List<object>();
        async Task Settle() { UpdateLayout(); await Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle); }
        try
        {
            Width = 1024; Height = 768; SetLayout(WorkspaceLayout.Preset("sourceFirst")); sourceView.SelectedIndex = 0; await Settle();
            foreach (var edge in new[] { (Address: "XFD1", Row: 1, Column: 16384, Rows: 50, Columns: 1), (Address: "A1048576", Row: 1048576, Column: 1, Rows: 1, Columns: 8), (Address: "XFD1048576", Row: 1048576, Column: 16384, Rows: 1, Columns: 1) })
            {
                await Before.GoForSmoke(edge.Address); await Settle();
                var metrics = new { address = Before.FocusedAddress, read_state = Before.ReadState, row_origin = Before.SelectedRow, column_origin = Before.SelectedColumn, row_count = Before.Cells.Items.Count, source_headers = Before.Cells.Columns.Skip(1).Select(column => column.Header as string).ToArray(), requested_row_limit = 50, requested_column_limit = 8, boundary_shape_rows = edge.Rows, boundary_shape_columns = edge.Columns, strict_bridge_response_scope_validated = Before.AuthorizesCell(edge.Row, edge.Column) };
                await observe("edge-" + edge.Address, metrics); await capture("edge-" + edge.Address);
                if (Before.ReadState != "ready" || ComparisonState != "ready" || Before.FocusedAddress != edge.Address || Before.SelectedRow != edge.Row || Before.SelectedColumn != edge.Column || Before.Cells.Items.Count != edge.Rows || Before.Cells.Columns.Count != edge.Columns + 1 || !Before.Cells.Items.OfType<GridRow>().Select(row => row.Row).SequenceEqual(Enumerable.Range(edge.Row, edge.Rows)) || !Before.Cells.Columns.Skip(1).Select(column => column.Header as string).SequenceEqual(Enumerable.Range(edge.Column, edge.Columns).Select(ComparePane.ColumnName)) || !Before.AuthorizesCell(edge.Row, edge.Column) || Before.AuthorizesCell(1048577, edge.Column) || Before.AuthorizesCell(edge.Row, 16385) || intervalFrom != from || intervalTo != to || reportId != report) throw new InvalidOperationException("A legal tail Go address failed strict scope, bounded physical grid shape or fixed query identity: " + edge.Address);
                edgeObservations.Add(metrics);
            }
            await Before.GoForSmoke("D4"); Before.ShowFormulasForSmoke(false); await Settle();
            const string literal = "stored only; not recalculated";
            if (!Before.TryGetFocusedMaterializedCell(out var raw) || raw.Get("value").Text() != literal || !raw.Get("text_truncated").Flag() || raw.Get("source_lengths").Get("value").Number(-1) != literal.Length || raw.Get("source_lengths").Get("formula").Number() <= raw.Get("formula").Text().Length) throw new InvalidOperationException("The actual D4 fixture no longer distinguishes its complete literal value from its truncated formula preview.");
            foreach (var locale in new[] { "en", "ko" })
            {
                SetLanguage(locale); await Settle(); var metrics = Before.CheckCellClippingForSmoke(literal); var value = JsonSerializer.SerializeToElement(metrics); await observe("narrow-literal-value-" + locale, metrics); await capture("narrow-literal-value-" + locale);
                if (value.Get("active_field").Text() != "value" || value.Get("active_field_truncated").Flag() || !value.Get("cell_text_truncated").Flag() || value.Get("displayed_text").Text() != literal || !value.Get("tooltip").Text().StartsWith(literal + "\n\n", StringComparison.Ordinal)) throw new InvalidOperationException("Native cell clipping translated source or confused a formula-only preview limit with a truncated value.");
                var detailsLayout = Layout; var sourceBefore = Before.CaptureSelection(); var sourceAfter = After.CaptureSelection(); var scopedRows = changes.ToArray(); var scopedCursor = nextChanges; var scopedAnchorA = selectedBefore; var scopedAnchorB = selectedAfter; var scopedEvent = selectedChange; var scopedQueryReads = changeQueryReadsForSmoke;
                await observe("synthetic-cell-details-labels-" + locale, Before.CheckCellDetailLabelsForSmoke());
                var cellDetails = await Before.OpenCellDetailsForSmoke(literal); await Settle();
                if (!InspectorPane.IsVisible || detailPayload.Get("items").Items().Single().Get("value").Text() != literal || Before.CaptureSelection() != sourceBefore || After.CaptureSelection() != sourceAfter || !scopedRows.SequenceEqual(changes) || nextChanges != scopedCursor || selectedBefore != scopedAnchorA || selectedAfter != scopedAnchorB || selectedChange.ValueKind != scopedEvent.ValueKind || scopedEvent.ValueKind != JsonValueKind.Undefined && selectedChange.GetRawText() != scopedEvent.GetRawText() || changeQueryReadsForSmoke != scopedQueryReads || intervalFrom != from || intervalTo != to) throw new InvalidOperationException("The labelled Cell details/source-segment route changed its physical cell, query/list/cursor or event anchors.");
                await observe("narrow-focused-cell-details-" + locale, cellDetails); await capture("narrow-focused-cell-details-" + locale); Before.CloseCellDetailsForSmoke(); SetLayout(detailsLayout); await Settle();
                clipObservations.Add(metrics);
            }
            Before.ShowFormulasForSmoke(true); await Settle(); var formulaMetrics = Before.CheckCellClippingForSmoke(raw.Get("formula").Text()); var formulaValue = JsonSerializer.SerializeToElement(formulaMetrics); await observe("narrow-partial-formula", formulaMetrics); await capture("narrow-partial-formula");
            if (formulaValue.Get("active_field").Text() != "formula" || !formulaValue.Get("active_field_truncated").Flag() || formulaValue.Get("displayed_text").Text() != raw.Get("formula").Text()) throw new InvalidOperationException("The actual partial formula segment lost its separate preview annotation or exact stored text.");
            var rawValue = detailPayload.Get("items").Items().Single().Get("value").Text(); if (rawValue != literal || reportId != report || currentReport.GetRawText() != reportBytes) throw new InvalidOperationException("Clipping or locale changes modified raw source detail or the immutable report.");
            return new { report_id = report, edge_observations = edgeObservations, literal_source = literal, literal_raw_reader = rawValue, value_clipping = clipObservations, formula_clipping = formulaMetrics, source_bytes_and_report_unchanged = true };
        }
        finally { Before.CloseCellDetailsForSmoke(); Before.ShowFormulasForSmoke(false); Before.RestoreSelection(originalA); After.RestoreSelection(originalB); await ReloadComparisonCore(true); await Before.GoForSmoke("D4"); Width = width; Height = height; SetLanguage(language); SetLayout(layout); sourceView.SelectedIndex = originalText ? 1 : 0; await Settle(); }
    }
    internal async Task CheckMissingVersionSheetForSmoke()
    {
        await SelectSourcePairForSmoke(0, currentReport.Get("revisions").Items().Count - 1);
        await Before.SelectRevisionForSmoke(3);
        if (Before.ReadState != "absent" || Before.SheetId.Length != 0 || Before.Cells.Items.Count != 0 || Before.AuthorizesCell(1, 1) || !Before.PresentedFallback.Contains(Copy["missingSelectedSheet"], StringComparison.Ordinal) || !Before.LocationCaption.Contains(Copy["missingSelectedSheet"], StringComparison.Ordinal)) throw new InvalidOperationException("Component-only unmounted revision selector substituted the first available sheet for the previous missing sheet or captioned its absence as metadata.");
        await Before.SelectAvailableSheetForSmoke(); if (Before.ReadState != "ready" || Before.SheetId.Length == 0 || !Before.AuthorizesCell(1, 1)) throw new InvalidOperationException("Explicit available-sheet selection did not load its own source.");
        await SelectSourcePairForSmoke(0, currentReport.Get("revisions").Items().Count - 1);
    }
    private object CheckMetadataProjectionControlForSmoke()
    {
        var saved = unified.Document; var savedDetail = detail.Text; var savedRange = detailRange.Text; var report = currentReport.GetRawText(); var before = Before.CaptureSelection(); var after = After.CaptureSelection();
        try
        {
            var source = JsonSerializer.SerializeToElement(new { name = "SYNTHETIC metadata name\r\n한글 {0}%", merges = new[] { "A1:C1" }, merge_count = 12, metadata_truncated = true, metadata_query = "list_workbook_sheets" });
            var projection = MetadataProjection.Read(source); var flow = new FlowDocument(); unified.Document = flow;
            detail.Text = FormatMetadataDetail(MetadataProjection.Read(default), projection); detailRange.Text = FormatMetadataSummary(MetadataProjection.Read(default), projection);
            if (!detail.Text.Contains(projection.Json, StringComparison.Ordinal) || detail.Text.Contains(Copy["metadataBounded"], StringComparison.Ordinal) || !detailRange.Text.Contains(Copy["after"] + " · " + Copy["metadataBounded"], StringComparison.Ordinal) || !detail.Text.Contains(Copy["observationMissing"], StringComparison.Ordinal)) throw new InvalidOperationException("Inspector metadata mixed a secondary bounded notice into its generated JSON detail body.");
            AppendMetadataProjection(flow, Copy["before"], MetadataProjection.Read(default)); AppendMetadataProjection(flow, Copy["after"], projection); unified.UpdateLayout();
            var paragraphs = flow.Blocks.OfType<Paragraph>().ToArray(); var body = paragraphs.Where(item => item.Tag as string == "metadataJsonProjection").ToArray(); var missing = paragraphs.Where(item => item.Tag as string == "metadataMissing").ToArray(); var bounded = paragraphs.Where(item => item.Tag as string == "metadataBoundedNotice").ToArray();
            if (body.Length != 1 || body[0].Inlines.OfType<Run>().Single().Text != projection.Json || !ReferenceEquals(body[0].Foreground, Brushes.Black) || missing.Length != 1 || missing[0].Inlines.OfType<Run>().Single().Text != Copy["observationMissing"] || !ReferenceEquals(missing[0].Foreground, Brushes.DimGray) || bounded.Length != 1 || bounded[0].Inlines.OfType<Run>().Single().Text != MetadataBoundedNotice() || !ReferenceEquals(bounded[0].Foreground, Brushes.DimGray) || paragraphs.Any(item => item.Inlines.OfType<Run>().Any(run => run.Text.Contains(Copy["observationPresent"], StringComparison.Ordinal) || run.Text.Contains("⟦LF⟧", StringComparison.Ordinal) || run.Text.Contains("⟦EOF⟧", StringComparison.Ordinal))) || JsonSerializer.Deserialize<JsonElement>(body[0].Inlines.OfType<Run>().Single().Text).Get("name").Text() != source.Get("name").Text() || body[0].Inlines.OfType<Run>().Single().Text.Contains("metadata_query", StringComparison.Ordinal) || body[0].Inlines.OfType<Run>().Single().Text.Contains("metadata_truncated", StringComparison.Ordinal) || projection.QueryHint != "list_workbook_sheets") throw new InvalidOperationException("The native typed metadata projection manufactured a missing-side body or mixed its bounded UI note/source terminators into generated JSON.");
            var scalarRevision = JsonSerializer.SerializeToElement(new { sheets = new[] { new { sheet_id = "SYNTHETIC_sheet", name = "SYNTHETIC complete scalar name", merges = new[] { "A1:C1" }, merge_count = 12, row_metadata = Array.Empty<object>(), row_metadata_count = 0, column_metadata = Array.Empty<object>(), column_metadata_count = 0, metadata_truncated = true, metadata_query = "list_workbook_sheets" } } });
            var scalar = SourceDiffPolicy.WorkbookMetadataProjection(scalarRevision, "SYNTHETIC_sheet", "sheet_name"); flow.Blocks.Clear(); AppendMetadataProjection(flow, Copy["after"], scalar); detail.Text = FormatMetadataDetail(scalar, scalar); detailRange.Text = FormatMetadataSummary(scalar, scalar);
            if (scalar.Bounded || flow.Blocks.OfType<Paragraph>().Any(item => item.Tag as string == "metadataBoundedNotice") || detailRange.Text != Copy["metadataObservation"] || !detail.Text.Contains(scalar.Json, StringComparison.Ordinal)) throw new InvalidOperationException("A complete scalar metadata projection inherited an unrelated coarse array truncation flag in native presentation or inspector summary.");
            return new { scope = "Explicit synthetic metadata projection controls through the production native renderer; not engine facts", language = Copy.Language, json_body = body[0].Inlines.OfType<Run>().Single().Text, missing_side_has_no_json_body = true, bounded_notice_separate_dimgray = true, decoded_name_exact = true, scalar_kind_ignores_unrelated_coarse_flag = true };
        }
        finally { unified.Document = saved; detail.Text = savedDetail; detailRange.Text = savedRange; if (currentReport.GetRawText() != report || Before.CaptureSelection() != before || After.CaptureSelection() != after) throw new InvalidOperationException("Metadata projection controls mutated fixed source state."); }
    }
    internal async Task<object> CheckWorkbookMetadataForSmoke(IReadOnlyList<ImportRow> sources, Func<string, Task> capture)
    {
        if (!IsWorkbook) throw new InvalidOperationException("Metadata QA requires workbook sources.");
        var project = projectId; var report = reportId; var bytes = currentReport.GetRawText(); var layout = Layout; var language = Copy.Language; var oldText = textView; var oldNet = workbookNet; var results = new List<object>();
        string Text() => string.Join("\n", unified.Document.Blocks.OfType<Paragraph>().Select(paragraph => new TextRange(paragraph.ContentStart, paragraph.ContentEnd).Text));
        try
        {
            await ImportAndAnalyze("Actual workbook and sheet metadata", sources); await SelectSourcePairForSmoke(0, 1); if (NetMode) await ChangeComparisonMode(false);
            foreach (var locale in new[] { "en", "ko" }) { SetLanguage(locale); results.Add(CheckMetadataProjectionControlForSmoke()); }
            var metadataReport = currentReport.GetRawText(); var rows = changes.ToArray(); var cursor = nextChanges; var scope = CurrentChangeScope; var queryReads = changeQueryReadsForSmoke; SetLayout(WorkspaceLayout.Preset("sourceFirst"));
            foreach (var kind in new[] { "date_system", "calculation_settings", "sheet_name", "merges" })
            {
                var row = changes.Single(item => item.Value.Get("kind").Text() == kind); await SelectChange(row.Value); var anchorA = selectedBefore; var anchorB = selectedAfter;
                foreach (var locale in new[] { "en", "ko" })
                {
                    SetLanguage(locale); sourceView.SelectedIndex = 0; results.Add(Before.CheckMetadataCellDetailsForSmoke(true)); results.Add(After.CheckMetadataCellDetailsForSmoke(true)); sourceView.SelectedIndex = 1; UpdateLayout(); await Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle);
                    var valueA = MetadataSide(false); var valueB = MetadataSide(true); var body = Text(); var rawA = valueA.Pretty(); var rawB = valueB.Pretty();
                    if (!SelectedWorkbookMetadata || !WorkbookMetadataPayload(detailPayload) || !AtSelectedChange || Before.FocusedAddress.Length != 0 || After.FocusedAddress.Length != 0 || !body.Contains(Copy["metadataObservation"], StringComparison.Ordinal) || !body.Contains(Copy["metadataProjection"], StringComparison.Ordinal) || body.Contains(Copy["observationPresent"], StringComparison.Ordinal) || body.Contains("⟦LF⟧", StringComparison.Ordinal) || body.Contains("⟦EOF⟧", StringComparison.Ordinal) || body.Contains(Copy["cellNotMaterialized"], StringComparison.Ordinal) || body.Contains(Copy["invalidSourceSegment"], StringComparison.Ordinal) || !detail.Text.Contains(rawA, StringComparison.Ordinal) || !detail.Text.Contains(rawB, StringComparison.Ordinal) || detailRange.Text != FormatMetadataSummary(MetadataSideProjection(false), MetadataSideProjection(true)) || body.Length == 0 || unified.Document.Blocks.OfType<Paragraph>().Any(item => ReferenceEquals(item.Foreground, Brushes.DarkRed) || ReferenceEquals(item.Foreground, Brushes.DarkGreen))) throw new InvalidOperationException("A real metadata event rendered missing/invalid cell fields or lost its exact neutral metadata in " + kind + "/" + locale);
                    var jsonParagraphs = unified.Document.Blocks.OfType<Paragraph>().Where(paragraph => paragraph.Tag as string == "metadataJsonProjection").ToArray();
                    if (jsonParagraphs.Length != 2 || !string.Equals(jsonParagraphs[0].Inlines.OfType<Run>().Single().Text, rawA, StringComparison.Ordinal) || !string.Equals(jsonParagraphs[1].Inlines.OfType<Run>().Single().Text, rawB, StringComparison.Ordinal)) throw new InvalidOperationException("Generated metadata was split into source lines, annotated as raw source terminators, or rendered more than once.");
                    if (SourceDiffPolicy.WorkbookScoped(kind) && (Before.LocationCaption.Contains(Copy["absentSheet"], StringComparison.Ordinal) || After.LocationCaption.Contains(Copy["absentSheet"], StringComparison.Ordinal) || !row.Location.Contains(Copy["workbookMetadata"], StringComparison.Ordinal))) throw new InvalidOperationException("A workbook-wide metadata event invented an absent sheet.");
                    if (!Before.PresentedFallback.Contains(rawA, StringComparison.Ordinal) || !After.PresentedFallback.Contains(rawB, StringComparison.Ordinal)) throw new InvalidOperationException("Original source did not retain its actual metadata observation.");
                    await capture("actual-metadata-" + kind + "-" + locale); results.Add(new { kind, language = locale, event_id = row.Id, canonical_event = row.Value, before_metadata = valueA, after_metadata = valueB, neutral_metadata_visible = true });
                }
                if (Before.SheetId.Length == 0) await Before.SelectAvailableSheetForSmoke(); await Before.GoForSmoke("B2"); sourceView.SelectedIndex = 0;
                if (SelectedWorkbookMetadata || AtSelectedChange || Before.ReadState != "ready" || Before.FocusedAddress != "B2" || !Before.TryGetFocusedMaterializedCell(out var cell) || cell.Get("value").Text() != "42" || !detail.Text.Contains("42", StringComparison.Ordinal) || detail.Text.Contains(Copy["metadataObservation"], StringComparison.Ordinal) || !sourceNotice.Text.Contains(Copy["outsideChange"], StringComparison.Ordinal)) throw new InvalidOperationException("Manual metadata-to-cell browsing retained event metadata instead of its real physical cell.");
                foreach (var locale in new[] { "en", "ko" }) { SetLanguage(locale); results.Add(Before.CheckMetadataCellDetailsForSmoke(false)); }
                await capture("actual-metadata-" + kind + "-manual-cell"); await ReturnToChange();
                if (!SelectedWorkbookMetadata || selectedBefore != anchorA || selectedAfter != anchorB || !rows.SequenceEqual(changes) || cursor != nextChanges || CurrentChangeScope != scope || changeQueryReadsForSmoke != queryReads || currentReport.GetRawText() != metadataReport) throw new InvalidOperationException("Return from a metadata event's manual cell replaced its exact query, canonical event or metadata anchor.");
            }
            await Before.SelectAvailableSheetForSmoke(); await Before.GoForSmoke("H40");
            foreach (var locale in new[] { "en", "ko" })
            {
                SetLanguage(locale); if (detailRange.Text != Copy["textRange"] + "\n" + Copy["cellNotMaterialized"] || detailRange.Text.Contains(Copy["invalidSourceRange"], StringComparison.Ordinal) || detailPayload.Get("items").Items().Count != 0) throw new InvalidOperationException("A real unmaterialized sparse cell was labelled as three invalid ranges.");
            }
            return new { report_id = reportId, cases = results, real_sparse_cell_range_is_single_unmaterialized_observation = true, query_reads_unchanged_during_metadata_cell_return = true, data_scope = "Real generated XLSX bytes, canonical production metadata events and source/cell queries, native WPF presentation" };
        }
        finally
        {
            workbookNet = oldNet; var original = (await Bridge.Call("workbookProjects")).Items().Single(item => item.Get("project_id").Text() == project); await OpenProject(original); await OpenReport(report); SetLayout(layout); SetLanguage(language); sourceView.SelectedIndex = oldText ? 1 : 0; if (currentReport.GetRawText() != bytes) throw new InvalidOperationException("Metadata qualification changed its original fixed report.");
        }
    }
    internal async Task<object> CheckWorkbookSemanticCaptionsForSmoke(Func<string, Task> capture)
    {
        if (!IsWorkbook) throw new InvalidOperationException("Workbook caption qualification requires actual workbook events.");
        var report = reportId; var reportBytes = currentReport.GetRawText(); var originalNet = NetMode; var from = intervalFrom; var to = intervalTo; var language = Copy.Language; var layout = Layout; var view = textView;
        var observations = new List<object>();
        try
        {
            await SelectSourcePairForSmoke(0, currentReport.Get("revisions").Items().Count - 1); if (NetMode) { comparisonMode.SelectedIndex = 0; await modeRequest; }
            ChangeChoice? Missing() => changes.FirstOrDefault(row => !SourceDiffPolicy.SheetScoped(row.Value.Get("kind").Text()) && row.Value.Get("from_sheet_id").Text().Length > 0 && row.Value.Get("to_sheet_id").Text().Length > 0 && (row.Value.Get("before_address").ValueKind == JsonValueKind.Null ^ row.Value.Get("after_address").ValueKind == JsonValueKind.Null));
            var missing = Missing(); var pages = 0; while (missing is null && nextChanges.Length > 0 && pages++ < 100) { await LoadMoreChanges(); missing = Missing(); }
            if (missing is null) throw new InvalidOperationException("The actual workbook history needs a real cell-scoped event with a null side address.");
            await SelectChange(missing.Value); SetLayout(WorkspaceLayout.Preset("sourceFirst")); sourceView.SelectedIndex = 0;
            var absent = missing.Value.Get("before_address").ValueKind == JsonValueKind.Null ? Before : After; var available = ReferenceEquals(absent, Before) ? After : Before;
            foreach (var locale in new[] { "en", "ko" })
            {
                SetLanguage(locale); UpdateLayout(); await Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle);
                if (!missing.Location.Contains(Copy["cellNotMaterialized"], StringComparison.Ordinal) || missing.Location.Contains(Copy["sheetLevelSource"], StringComparison.Ordinal) || absent.ReadState != "absent" || !absent.LocationCaption.Contains(Copy["cellNotMaterialized"], StringComparison.Ordinal) || absent.PresentedFallback.Contains(Copy["sheetMetadata"], StringComparison.Ordinal) || available.ReadState != "ready" || available.Cells.Items.Count < 1 || !AtSelectedChange) throw new InvalidOperationException("A real unmaterialized cell was labelled as sheet metadata or failed its available opposite grid in " + locale);
                if (detailRange.Text.Contains(Copy["invalidSourceRange"], StringComparison.Ordinal) || detailRange.Text.Split('\n').Count(line => line.EndsWith(Copy["cellNotMaterialized"], StringComparison.Ordinal)) != 1) throw new InvalidOperationException("A real one-sided cell observation was shown as invalid range metadata.");
                await capture("actual-null-cell-side-" + locale); observations.Add(new { language = locale, event_id = missing.Id, canonical_event = missing.Value, row_caption = missing.Caption, missing_side_caption = absent.LocationCaption, opposite_state = available.ReadState });
            }
            // Existing canonical rows stay separate. Only known generated
            // templates are localized, while raw descriptions stay available.
            var known = changes.Where(row => SourceDiffPolicy.WorkbookSummaryKey(row.Value).Length > 0).ToArray(); if (!known.Any(row => row.Value.Get("kind").Text() == "stored_value") || !known.Any(row => row.Value.Get("kind").Text() == "formula")) throw new InvalidOperationException("Known generated workbook summary controls are absent.");
            var raw = known.Select(row => row.Value.GetRawText()).ToArray();
            foreach (var locale in new[] { "en", "ko" })
            {
                SetLanguage(locale);
                foreach (var row in known)
                {
                    var key = SourceDiffPolicy.WorkbookSummaryKey(row.Value); var expected = key == "summaryRowPosition" ? string.Format(CultureInfo.CurrentCulture, Copy[key], SourceDiffPolicy.WorkbookRow(row.Value, false), SourceDiffPolicy.WorkbookRow(row.Value, true)) : Copy[key];
                    if (row.Preview != expected || !row.Tooltip.Contains(row.Value.Get("description").Text(), StringComparison.Ordinal)) throw new InvalidOperationException("A generated summary stayed untranslated or lost the verbatim canonical description.");
                }
                var cache = changes.FirstOrDefault(row => row.Value.Get("kind").Text() == "cache_availability"); if (cache is null) throw new InvalidOperationException("Actual cached-result availability control is absent.");
                await SelectChange(cache.Value); sourceView.SelectedIndex = 0; UpdateLayout(); await Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle);
                var qualifier = new FormattedText(Copy["cacheNotDeletion"], CultureInfo.CurrentCulture, FlowDirection.LeftToRight, new Typeface(sourceNotice.FontFamily, sourceNotice.FontStyle, sourceNotice.FontWeight, sourceNotice.FontStretch), sourceNotice.FontSize, Brushes.Black, VisualTreeHelper.GetDpi(sourceNotice).PixelsPerDip) { MaxTextWidth = Math.Max(1, sourceNotice.ActualWidth), LineHeight = 16 };
                if (!sourceNotice.Text.StartsWith(Copy["cacheNotDeletion"], StringComparison.Ordinal) || qualifier.Height > sourceNotice.ActualHeight || cache.Preview != Copy["summaryCache"] || !known.Select(row => row.Value.GetRawText()).SequenceEqual(raw) || reportId != report || currentReport.GetRawText() != reportBytes) throw new InvalidOperationException("The visible missing-cache negation was truncated or canonical workbook descriptions changed.");
                await capture("actual-localized-cache-qualifier-" + locale);
            }
            return new { report_id = report, actual_null_cell_event = missing.Value, cases = observations, localized_generated_summary_count = known.Length, canonical_descriptions_retained_verbatim = true, missing_cache_qualifier_visible_before_other_notices = true };
        }
        finally
        {
            workbookNet = originalNet; var revisions = currentReport.Get("revisions").Items(); var a = revisions.FindIndex(item => item.Get("revision_occurrence_id").Text() == from); var b = revisions.FindIndex(item => item.Get("revision_occurrence_id").Text() == to); await SelectSourcePairForSmoke(a, b); SetLanguage(language); SetLayout(layout); sourceView.SelectedIndex = view ? 1 : 0;
        }
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
            if (!IsWorkbook)
            {
                var evidence = Enumerable.Range(1, 5).Select(page => new { revision_occurrence_id = before.Revision, page }).Concat(Enumerable.Range(1, 4).Select(page => new { revision_occurrence_id = after.Revision, page }));
                var captionControl = ChangeCaption(JsonSerializer.SerializeToElement(new { kind = "text_modified", from_occurrence = before.Revision, to_occurrence = after.Revision, before = (string?)null, after = "SYNTHETIC caption only", evidence }));
                if (!captionControl.Contains(string.Format(CultureInfo.CurrentCulture, Copy["morePages"], 2), StringComparison.Ordinal) || !captionControl.Contains(string.Format(CultureInfo.CurrentCulture, Copy["morePages"], 1), StringComparison.Ordinal) || !captionControl.Contains(Copy["missing"] + " → SYNTHETIC caption only", StringComparison.Ordinal)) throw new InvalidOperationException("Synthetic bounded page caption concealed the additional page count or an absent observation.");
                foreach (var kind in new[] { "coverage_gap", "visual_region_changed", "text_modified", "page_added", "page_deleted" })
                {
                    var sparse = ChangeCaption(JsonSerializer.SerializeToElement(new { kind, from_occurrence = before.Revision, to_occurrence = after.Revision, before = "SYNTHETIC before", after = "SYNTHETIC after", evidence = Array.Empty<object>() }));
                    var location = sparse.Split('\n')[1]; var absentCount = location.Split(Copy["absentPage"], StringSplitOptions.None).Length - 1; var unknownCount = location.Split(Copy["noEvidencePageListed"], StringSplitOptions.None).Length - 1; var structural = kind is "page_added" or "page_deleted";
                    if (absentCount != (structural ? 1 : 0) || unknownCount != (structural ? 1 : 2)) throw new InvalidOperationException("A native document row caption asserted absent pages from an omitted evidence list rather than structural event semantics.");
                }
                var emptyControl = ChangeCaption(JsonSerializer.SerializeToElement(new { kind = "text_modified", from_occurrence = before.Revision, to_occurrence = after.Revision, before = "", after = " \r\n\t", evidence }));
                if (!emptyControl.Contains(Copy["observationEmpty"] + " → " + Copy["whitespaceText"], StringComparison.Ordinal) || emptyControl.Contains(Copy["missing"], StringComparison.Ordinal)) throw new InvalidOperationException("Synthetic preview caption conflated explicit empty or whitespace source with an absent observation.");
            }
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
        if (queryBefore.IsEnabled || queryAfter.IsEnabled) throw new InvalidOperationException("Busy native query selectors remain interactive.");
        queryAfter.SelectedItem = queryAfter.Items.OfType<Choice>().First(choice => choice.Id != intervalTo); await endpointRequest;
        if ((queryBefore.SelectedItem as Choice)?.Id != intervalFrom || (queryAfter.SelectedItem as Choice)?.Id != intervalTo) throw new InvalidOperationException("A queued busy endpoint selection left unapplied query choices displayed.");
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
        var ownedScope = loadedChangeScope; var rows = changes.ToArray(); var cursor = nextChanges; var selectedRow = changeList.SelectedItem; var anchor = selectedChange; var anchorBefore = selectedBefore; var anchorAfter = selectedAfter; var queryReads = changeQueryReadsForSmoke;
        await corrupt();
        try
        {
            var loading = ReloadSourceWindow();
            if (Before.Cells.Items.Count != 0 || Before.Cells.IsEnabled || Before.AuthorizesCell(Before.SelectedRow, Before.SelectedColumn) || ActionableChanges != 0 || nextDetail.IsEnabled) throw new InvalidOperationException("Old source remained actionable while a new grid scope was loading.");
            try { await loading; throw new InvalidOperationException("Corrupt indexed cell unexpectedly loaded."); } catch (BridgeException) { }
            if (Before.ReadState != "failed" || Before.Cells.Items.Count != 0 || ComparisonState != "failed" || ActionableChanges != 0 || retryComparison.Visibility != Visibility.Visible || !sourceOnlyFailure || loadedChangeScope != ownedScope || !rows.SequenceEqual(changes) || cursor != nextChanges || !ReferenceEquals(selectedRow, changeList.SelectedItem) || changeQueryReadsForSmoke != queryReads || detailPayload.ValueKind != JsonValueKind.Undefined) throw new InvalidOperationException("Failed scoped grid retained stale source authority or discarded/requeried its owned change continuation.");
            await SelectCell(Before, Before.SelectedRow, Before.SelectedColumn); if (detail.Text != Copy["failed"]) throw new InvalidOperationException("Failed grid selection replaced unavailable evidence.");
        }
        finally { await restore(); }
        await RetryComparison(); if (Before.ReadState != "ready" || ComparisonState != "ready" || Before.CaptureSelection() != expectedBefore || After.CaptureSelection() != expectedAfter || intervalFrom != expectedFrom || intervalTo != expectedTo || NetMode != expectedMode || !Before.AuthorizesCell(expectedBefore.Row, expectedBefore.Column) || loadedChangeScope != ownedScope || !rows.SequenceEqual(changes) || cursor != nextChanges || !ReferenceEquals(selectedRow, changeList.SelectedItem) || changeQueryReadsForSmoke != queryReads || selectedChange.GetRawText() != anchor.GetRawText() || selectedBefore != anchorBefore || selectedAfter != anchorAfter) throw new InvalidOperationException("Source-only retry did not recover the exact source window while preserving owned paged query objects, cursor and event anchors without a changes query.");
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
        await ShowVersions(); var closedMenu = versionsButton.ContextMenu ?? throw new InvalidOperationException("The native version menu did not open."); closedMenu.IsOpen = false; await Settle(); if (versionsButton.ContextMenu is not null) throw new InvalidOperationException("Closing the version menu retained stale native menu contents.");
        await ShowVersions(); var staleMenu = versionsButton.ContextMenu ?? throw new InvalidOperationException("The stale-menu control did not open."); var staleVersion = staleMenu.Items.OfType<MenuItem>().First();
        SetLayout(savedLayout); await SelectReport(originalReport); var restoredFrom = intervalFrom; var restoredTo = intervalTo; var restoredGeneration = generation; var restoredSourceA = Before.CaptureSelection(); var restoredSourceB = After.CaptureSelection();
        if (staleMenu.IsOpen || versionsButton.ContextMenu is not null) throw new InvalidOperationException("Changing pinned report did not retire its preceding native version menu.");
        staleVersion.RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent, staleVersion)); await Settle();
        if (reportId != originalReport || generation != restoredGeneration || intervalFrom != restoredFrom || intervalTo != restoredTo || Before.CaptureSelection() != restoredSourceA || After.CaptureSelection() != restoredSourceB) throw new InvalidOperationException("A retired version-menu callback changed the newly pinned report's source/query scope.");
        if (currentReport.Get("revisions").Items().Sum(item => item.Get("pages").Items().Count) != 5) throw new InvalidOperationException("Original MCP document fixture was not restored after the multi-report regression.");
        return new { project_id = project, report_id = olderPin, latest_report_id = latestReport, original_and_final_fixture_report_id = originalReport, fixed_reports = digests, fixed_report_bytes_unchanged = true, reports_list_unchanged = true, retired_versions_menu_closed_and_old_callback_rejected = true, draft_order_before = original, draft_order_after = expected, dirty = true, draft_hash_before = before.Get("draft_hash").Text(), draft_hash_after = after.Get("draft_hash").Text(), mode = "range_net", interval_from = fixedFrom, interval_to = fixedTo, before_selection = beforeSelection, after_selection = afterSelection, before_viewport = new { x = beforePosition.X, y = beforePosition.Y }, after_viewport = new { x = afterPosition.X, y = afterPosition.Y }, restored_before_viewport = restoredBefore, restored_after_viewport = restoredAfter, dialog_route = "three actual native Move down and Save actions; production Analyze twice; native report picker selects an older nonfirst fixed report" };
    }
    internal async Task CheckOrderAndAbsenceForSmoke()
    {
        var versions = currentReport.Get("revisions").Items(); var first = versions.First().Get("revision_occurrence_id").Text(); var last = versions.Last().Get("revision_occurrence_id").Text();
        Before.SetEvidenceRevision(last); After.SetEvidenceRevision(first); await ReloadComparison(); if (ComparisonState != "invalid" || ActionableChanges != 0 || detail.Text != Copy["reverse"] || Before.ReadState != "invalid" || After.ReadState != "invalid" || Before.PresentedFallback != Copy["reverse"] || After.PresentedFallback != Copy["reverse"] || Before.Cells.Items.Count != 0 || After.Cells.Items.Count != 0 || Before.PageImage.Source is not null || After.PageImage.Source is not null) throw new InvalidOperationException("Reverse interval retained source data or false loading instead of explicit invalid guidance.");
        var invalidTicket = generation; var invalidReport = reportId; foreach (var language in new[] { "ko", "en" }) { SetLanguage(language); if (generation != invalidTicket || reportId != invalidReport || Before.ReadState != "invalid" || After.ReadState != "invalid" || Before.PresentedFallback != Copy["reverse"] || After.PresentedFallback != Copy["reverse"]) throw new InvalidOperationException("Invalid interval locale update lost explicit guidance or changed source scope."); }
        Before.SetEvidenceRevision(first); After.SetEvidenceRevision(last); Before.RestoreDefaultSelection(); After.RestoreDefaultSelection(); await ReloadComparison();
        if (IsWorkbook)
        {
            Before.SetEvidenceRevision(first, ""); await Before.Load(generation, reads.Token); if (Before.SheetId.Length != 0 || Before.ReadState != "absent" || Before.Cells.Items.Count != 0 || Before.AuthorizesCell(1, 1) || !Before.LocationCaption.Contains(Copy["absentSheet"], StringComparison.Ordinal)) throw new InvalidOperationException("Absent evidence substituted a real sheet/cell or metadata caption.");
            Before.SetEvidenceRevision(first, "unknown_sheet_id"); await Before.Load(generation, reads.Token); if (Before.SheetId.Length != 0 || Before.ReadState != "absent" || Before.Cells.Items.Count != 0 || !Before.LocationCaption.Contains(Copy["unsupportedSheet"], StringComparison.Ordinal)) throw new InvalidOperationException("Unknown evidence substituted a real sheet/cell or metadata caption.");
            Before.SetEvidenceRevision(first); After.SetEvidenceRevision(last); Before.RestoreDefaultSelection(); After.RestoreDefaultSelection(); await ReloadComparison();
            ChangeChoice? FindAbsent() => changes.FirstOrDefault(c => c.Value.Get("kind").Text() == "sheet_observation" && (c.Value.Get("from_sheet_id").Text().Length == 0 ^ c.Value.Get("to_sheet_id").Text().Length == 0));
            var absent = FindAbsent(); var pages = 0; while (absent is null && nextChanges.Length > 0 && pages++ < 100) { await LoadMoreChanges(); absent = FindAbsent(); }
            if (absent is null) throw new InvalidOperationException("Expected a genuine one-sided sheet event fixture.");
            status.Text = "SYNTHETIC stale source loading banner"; await SelectChange(absent.Value); Before.CheckReadingChromeForSmoke(); After.CheckReadingChromeForSmoke();
            if (status.Text != Copy[Preferences.IsReadOnly ? "preferencesReadOnly" : "ready"]) throw new InvalidOperationException("A terminal absent-side event kept a stale loading banner.");
            var priorText = textView; var priorLanguage = Copy.Language; var metadataReportBytes = currentReport.GetRawText();
            foreach (var locale in new[] { "en", "ko" })
            {
                SetLanguage(locale); sourceView.SelectedIndex = 0; Before.CheckMetadataCellDetailsForSmoke(true); After.CheckMetadataCellDetailsForSmoke(true); sourceView.SelectedIndex = 1; RenderSourceDiff(); var projections = unified.Document.Blocks.OfType<Paragraph>().Where(item => item.Tag as string == "metadataJsonProjection").ToArray(); var missingMetadata = unified.Document.Blocks.OfType<Paragraph>().Where(item => item.Tag as string == "metadataMissing").ToArray();
                var sideA = MetadataSideProjection(false); var sideB = MetadataSideProjection(true); var expected = sideA.Available ? sideA : sideB;
                if (!SelectedWorkbookMetadata || sideA.Available == sideB.Available || projections.Length != 1 || projections[0].Inlines.OfType<Run>().Single().Text != expected.Json || missingMetadata.Length != 1 || missingMetadata[0].Inlines.OfType<Run>().Single().Text != Copy["observationMissing"] || !ReferenceEquals(missingMetadata[0].Foreground, Brushes.DimGray) || detail.Text.Contains(Copy["metadataBounded"], StringComparison.Ordinal) || unified.Document.Blocks.OfType<Paragraph>().Any(item => item.Inlines.OfType<Run>().Any(run => run.Text.Contains(Copy["observationPresent"], StringComparison.Ordinal) || run.Text.Contains("⟦LF⟧", StringComparison.Ordinal) || run.Text.Contains("⟦EOF⟧", StringComparison.Ordinal))) || currentReport.GetRawText() != metadataReportBytes) throw new InvalidOperationException("An actual one-sided sheet metadata event promoted its absent side to a stored text observation or annotated generated JSON source terminators.");
            }
            SetLanguage(priorLanguage); sourceView.SelectedIndex = priorText ? 1 : 0;

            var absentQueryReads = changeQueryReadsForSmoke; var absentRows = changes.ToArray(); var absentCursor = nextChanges; FailComparison(false); status.Text = "SYNTHETIC stale retry banner"; await RetryComparison();
            if (ComparisonState != "ready" || status.Text != Copy[Preferences.IsReadOnly ? "preferencesReadOnly" : "ready"] || !absentRows.SequenceEqual(changes) || absentCursor != nextChanges || absentQueryReads != changeQueryReadsForSmoke) throw new InvalidOperationException("Retry of legitimate absent-side source did not settle ready while retaining its query.");
            if (!absent.Location.Contains(Copy["sheetLevelSource"], StringComparison.Ordinal) || !absent.Location.Contains(Copy["absentSheet"], StringComparison.Ordinal) || absent.Location.Contains(Copy["missing"], StringComparison.Ordinal)) throw new InvalidOperationException("A genuine one-sided sheet event did not distinguish present sheet metadata from its absent sheet side.");
            if (absent.Value.Get("from_sheet_id").Text().Length == 0 && (Before.ReadState != "absent" || Before.SheetId.Length != 0 || Before.Cells.Items.Count != 0)) throw new InvalidOperationException("One-sided before event invented a grid.");
            if (absent.Value.Get("to_sheet_id").Text().Length == 0 && (After.ReadState != "absent" || After.SheetId.Length != 0 || After.Cells.Items.Count != 0)) throw new InvalidOperationException("One-sided after event invented a grid.");
            await SelectSourcePairForSmoke(0, versions.Count - 1);
        }
    }
    internal async Task<string> ReadCellForSmoke(int versionIndex, string cell, string field)
    {
        var revisions = currentReport.Get("revisions").Items(); if (versionIndex + 1 >= revisions.Count) throw new InvalidOperationException("The raw-reader fixture requires a following occurrence to keep its Before pane visible.");
        var occurrence = revisions[versionIndex].Get("revision_occurrence_id").Text(); Before.SetEvidenceRevision(occurrence); After.SetEvidenceRevision(revisions[versionIndex + 1].Get("revision_occurrence_id").Text()); Before.RestoreDefaultSelection(); After.RestoreDefaultSelection(); await ReloadComparison(); await Before.GoForSmoke(cell);
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
    internal void ReloadPreferencesForSmoke() { Preferences = AppPreferences.Load(PreferencesPath); documentFocus.Baseline(Preferences.Document.Current); workbookFocus.Baseline(Preferences.Workbook.Current); Copy.Language = Preferences.Language; ApplyLayout(false); Localize(); }
}
