using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using System.Security.Cryptography;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using Microsoft.Win32;

namespace Reviset.Windows;

internal sealed class ImportRow : INotifyPropertyChanged
{
    private string label = "";
    public string Label { get => label; set { label = value; PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Label))); } }
    public string[] Paths { get; init; } = [];
    public int OriginalIndex { get; init; }
    public string Files => string.Join(" + ", Paths.Select(Path.GetFileName));
    public event PropertyChangedEventHandler? PropertyChanged;
}

internal sealed class ImportWindow : Window
{
    public ObservableCollection<ImportRow> Rows { get; } = [];
    public string ProjectTitle => title.Text.Trim();
    private readonly TextBox title = new() { MaxLength = 200, Margin = new Thickness(0, 4, 0, 12) };
    private readonly DataGrid table = new() { AutoGenerateColumns = false, CanUserAddRows = false, CanUserDeleteRows = false, SelectionMode = DataGridSelectionMode.Single, Margin = new Thickness(0, 8, 0, 8) };
    private readonly Copy copy;
    private readonly bool workbook;
    private readonly bool reorder;
    public ImportWindow(Copy copy, bool workbook, IEnumerable<JsonElement>? existing = null)
    {
        this.copy = copy; this.workbook = workbook; reorder = existing is not null;
        Title = copy[reorder ? "reorder" : "import"]; Width = 790; Height = 550; MinWidth = 620; MinHeight = 420; WindowStartupLocation = WindowStartupLocation.CenterOwner;
        var root = new DockPanel { Margin = new Thickness(20) }; Content = root;
        var top = new StackPanel(); DockPanel.SetDock(top, Dock.Top); root.Children.Add(top);
        top.Children.Add(new TextBlock { Text = copy[reorder ? "reorderHint" : workbook ? "workbookHint" : "documentHint"], TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 12) });
        if (!reorder) { top.Children.Add(new TextBlock { Text = copy["title"] }); top.Children.Add(title); }
        var bottom = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right }; DockPanel.SetDock(bottom, Dock.Bottom); root.Children.Add(bottom);
        var cancel = Button(copy["cancel"], () => DialogResult = false); cancel.IsCancel = true; bottom.Children.Add(cancel);
        bottom.Children.Add(Button(copy[reorder ? "save" : "start"], () =>
        {
            table.CommitEdit(DataGridEditingUnit.Cell, true); table.CommitEdit(DataGridEditingUnit.Row, true);
            if (Rows.Count is < 1 or > 100 || Rows.Any(r => string.IsNullOrWhiteSpace(r.Label) || r.Label.Trim().Length > 200) || (!reorder && (ProjectTitle.Length is < 1 or > 200))) { MessageBox.Show(this, copy["title"] + " / " + copy["label"] + " (1–200)", copy["error"]); return; }
            DialogResult = true;
        }));
        var commands = new StackPanel { Orientation = Orientation.Horizontal }; DockPanel.SetDock(commands, Dock.Top); root.Children.Add(commands);
        if (!reorder) commands.Children.Add(Button(copy["add"], Add));
        commands.Children.Add(Button(copy["up"], () => Move(-1))); commands.Children.Add(Button(copy["down"], () => Move(1)));
        if (!reorder) commands.Children.Add(Button(copy["remove"], () => { if (table.SelectedItem is ImportRow row) Rows.Remove(row); }));
        table.Columns.Add(new DataGridTextColumn { Header = copy["label"], Binding = new Binding(nameof(ImportRow.Label)) { UpdateSourceTrigger = UpdateSourceTrigger.PropertyChanged }, Width = new DataGridLength(1, DataGridLengthUnitType.Star), IsReadOnly = reorder });
        table.Columns.Add(new DataGridTextColumn { Header = copy["files"], Binding = new Binding(nameof(ImportRow.Files)), Width = new DataGridLength(2, DataGridLengthUnitType.Star), IsReadOnly = true });
        table.ItemsSource = Rows; root.Children.Add(table);
        if (existing is not null) foreach (var item in existing.Select((value, index) => (value, index))) Rows.Add(new() { Label = item.value.Get("label").Text(), Paths = item.value.Get("files").Items().Select(v => v.ValueKind == JsonValueKind.Object ? v.Get("name").Text() : v.Text()).ToArray(), OriginalIndex = item.index });
    }
    private void Add()
    {
        if (Rows.Count >= 100) return;
        var dialog = new OpenFileDialog { Multiselect = !workbook, Filter = workbook ? "Spreadsheets|*.xlsx;*.ods;*.csv" : "Documents|*.pdf;*.pptx", CheckFileExists = true, DereferenceLinks = true };
        if (dialog.ShowDialog(this) != true) return;
        var paths = dialog.FileNames;
        var extensions = paths.Select(p => Path.GetExtension(p).ToLowerInvariant()).ToArray();
        if (workbook ? paths.Length != 1 || !extensions.All(e => e is ".xlsx" or ".ods" or ".csv") : paths.Length is < 1 or > 2 || !extensions.All(e => e is ".pdf" or ".pptx") || extensions.Distinct().Count() != extensions.Length) { MessageBox.Show(this, copy[workbook ? "workbookHint" : "documentHint"], copy["error"]); return; }
        Rows.Add(new() { Label = Path.GetFileNameWithoutExtension(paths[0]), Paths = paths }); table.SelectedIndex = Rows.Count - 1;
        if (string.IsNullOrWhiteSpace(title.Text)) title.Text = Path.GetFileNameWithoutExtension(paths[0]);
    }
    private void Move(int delta) { var index = table.SelectedIndex; if (index < 0 || index + delta < 0 || index + delta >= Rows.Count) return; Rows.Move(index, index + delta); table.SelectedIndex = index + delta; }
    private static Button Button(string title, Action action) { var button = new Button { Content = title, Margin = new Thickness(0, 5, 8, 5), Padding = new Thickness(12, 6, 12, 6) }; button.Click += (_, _) => action(); return button; }

    public static async Task<string> Identity(string path, CancellationToken token)
    {
        // No shell, macro, formula or source document program is launched.
        var info = new FileInfo(path);
        if ((info.Attributes & FileAttributes.ReparsePoint) != 0) throw new IOException("Select a regular source file, not a symbolic link or reparse point.");
        await using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 1024 * 1024, FileOptions.Asynchronous | FileOptions.SequentialScan);
        if (stream.Length > 1024L * 1024 * 1024) throw new IOException("Source exceeds 1 GiB.");
        return Convert.ToHexString(await SHA256.HashDataAsync(stream, token)).ToLowerInvariant();
    }
}
