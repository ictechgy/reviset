using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Reviset.Windows;

internal sealed record WorkspaceLayout
{
    public bool Sidebar { get; init; }
    public bool Inspector { get; init; }
    public bool ChangesVisible { get; init; } = true;
    public string Changes { get; init; } = "left";
    public string InspectorSide { get; init; } = "right";
    public bool VerticalComparison { get; init; }
    public double SidebarWidth { get; init; } = 225;
    public double InspectorWidth { get; init; } = 290;
    public double ChangesHeight { get; init; } = 135;
    public double ChangesWidth { get; init; } = 250;
    public double ComparisonRatio { get; init; } = .5;
    public static WorkspaceLayout Preset(string name) => name switch
    {
        "sourceFirst" => new(),
        "focus" => new() { Sidebar = false, Inspector = false, ChangesVisible = false },
        "review" => new() { Sidebar = false, Inspector = true, Changes = "left", ChangesWidth = 300, InspectorWidth = 340 },
        "balanced" => new() { Sidebar = true, Inspector = true, Changes = "bottom", ChangesWidth = 290 },
        _ => new()
    };
    public WorkspaceLayout Bounded() => this with
    {
        Changes = Changes is "bottom" or "left" or "right" ? Changes : "bottom",
        InspectorSide = InspectorSide is "left" or "right" ? InspectorSide : "right",
        SidebarWidth = Bound(SidebarWidth, 150, 480, 225), InspectorWidth = Bound(InspectorWidth, 200, 600, 290),
        ChangesHeight = Bound(ChangesHeight, 100, 500, 210), ChangesWidth = Bound(ChangesWidth, 160, 600, 290), ComparisonRatio = Bound(ComparisonRatio, .2, .8, .5)
    };
    private static double Bound(double value, double low, double high, double fallback) => double.IsFinite(value) ? Math.Clamp(value, low, high) : fallback;
}

internal sealed class WorkspacePreferences
{
    public WorkspaceLayout Current { get; set; } = new();
    public Dictionary<string, WorkspaceLayout> Named { get; set; } = new(StringComparer.Ordinal);
}

internal sealed class AppPreferences
{
    public int Version { get; set; } = 1;
    [JsonIgnore] public bool IsReadOnly { get; private set; }
    public string Language { get; set; } = "en";
    public WorkspacePreferences Document { get; set; } = new();
    public WorkspacePreferences Workbook { get; set; } = new();
    public WorkspacePreferences For(bool workbook) => workbook ? Workbook : Document;
    public static AppPreferences Load(string path)
    {
        try
        {
            if (!File.Exists(path)) return new();
            if (new FileInfo(path).Length > 65536) return new() { IsReadOnly = true };
            var bytes = File.ReadAllBytes(path);
            if (bytes.Length > 65536) return new() { IsReadOnly = true };
            using var document = JsonDocument.Parse(bytes, new JsonDocumentOptions { MaxDepth = 16 });
            // Probe the schema envelope before decoding any version-specific fields.
            // Future schemas may change the type of every currently known field.
            if (document.RootElement.ValueKind != JsonValueKind.Object || !document.RootElement.TryGetProperty("Version", out var version) || version.ValueKind != JsonValueKind.Number || !version.TryGetInt32(out var number) || number != 1) return new() { IsReadOnly = true };
            var prefs = JsonSerializer.Deserialize<AppPreferences>(bytes, new JsonSerializerOptions { MaxDepth = 16 });
            if (prefs is null) return new();
            if (prefs.Version != 1) return new() { IsReadOnly = true };
            prefs.Language = prefs.Language == "ko" ? "ko" : "en";
            prefs.Document = Clean(prefs.Document); prefs.Workbook = Clean(prefs.Workbook); return prefs;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException or ArgumentException) { return new() { IsReadOnly = true }; }
    }
    private static WorkspacePreferences Clean(WorkspacePreferences? value)
    {
        var clean = new WorkspacePreferences { Current = value?.Current?.Bounded() ?? new() };
        if (value?.Named is not null) foreach (var item in value.Named.Take(12))
            if (item.Key.Length is > 0 and <= 48 && item.Key.Trim() == item.Key && !item.Key.Any(char.IsControl) && item.Value is not null) clean.Named[item.Key] = item.Value.Bounded();
        return clean;
    }
    public void Save(string path)
    {
        if (IsReadOnly) return;
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try { File.WriteAllText(temp, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true })); File.Move(temp, path, true); }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }
}
