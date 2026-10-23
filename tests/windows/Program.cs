using System.Text.Json;
using Reviset.Windows;

var folder = Path.Combine(Path.GetTempPath(), "reviset-preferences-" + Guid.NewGuid().ToString("N")); Directory.CreateDirectory(folder);
var path = Path.Combine(folder, "preferences.json"); var checks = new List<string>();
void Require(bool condition, string name) { if (!condition) throw new InvalidOperationException(name); checks.Add(name); }
try
{
    var preferences = AppPreferences.Load(path); Require(preferences.Document.Current == new WorkspaceLayout(), "missing preferences use bounded defaults");
    preferences.Document.Current = WorkspaceLayout.Preset("review") with { InspectorSide = "left", VerticalComparison = true, ComparisonRatio = .72 };
    preferences.Workbook.Current = WorkspaceLayout.Preset("focus"); preferences.Document.Named["review 100% {0} 한글 العربية"] = preferences.Document.Current; preferences.Save(path);
    var loaded = AppPreferences.Load(path); Require(loaded.Document.Current == preferences.Document.Current && loaded.Workbook.Current == preferences.Workbook.Current, "independent document and workbook layouts persist"); Require(loaded.Document.Named.Keys.Single() == "review 100% {0} 한글 العربية", "authored preset names remain opaque");
    var bounded = new WorkspaceLayout { SidebarWidth = double.NaN, InspectorWidth = double.PositiveInfinity, ChangesHeight = -9, ComparisonRatio = 50, Changes = "execute", InspectorSide = "invalid" }.Bounded();
    Require(double.IsFinite(bounded.SidebarWidth) && bounded.InspectorWidth == 290 && bounded.ChangesHeight == 100 && bounded.ComparisonRatio == .8 && bounded.Changes == "bottom" && bounded.InspectorSide == "right", "nonfinite extremes and unsupported dock positions bounded");
    await File.WriteAllTextAsync(path, "{\"Version\":99,\"future\":\"preserve me\"}"); var futureBytes = await File.ReadAllBytesAsync(path); var future = AppPreferences.Load(path); future.Language = "ko"; future.Save(path); var afterFuture = await File.ReadAllBytesAsync(path); Require(future.IsReadOnly && futureBytes.SequenceEqual(afterFuture), "future schema retained without overwrite");
    await File.WriteAllTextAsync(path, "{\"Version\":1,\"Document\":null,\"Workbook\":{\"Current\":null,\"Named\":null}}"); var nulls = AppPreferences.Load(path); Require(nulls.Document.Current == new WorkspaceLayout() && nulls.Workbook.Named.Count == 0, "null nested settings recovered");
    await File.WriteAllTextAsync(path, "bad json"); Require(AppPreferences.Load(path).Language == "en", "corrupt JSON recovered");
    var tooMany = new AppPreferences(); for (var index = 0; index < 30; index++) tooMany.Document.Named[index.ToString()] = new(); tooMany.Save(path); Require(AppPreferences.Load(path).Document.Named.Count == 12, "named presets bounded at twelve");
    await File.WriteAllTextAsync(path, new string('x', 65537)); Require(AppPreferences.Load(path).Document.Current == new WorkspaceLayout(), "oversized settings recovered");
    Console.WriteLine(JsonSerializer.Serialize(new { passed = true, checks }, new JsonSerializerOptions { WriteIndented = true }));
}
finally { Directory.Delete(folder, true); }
