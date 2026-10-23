using System.Text.Json;
using Reviset.Windows;

var folder = Path.Combine(Path.GetTempPath(), "reviset-preferences-" + Guid.NewGuid().ToString("N")); Directory.CreateDirectory(folder);
var path = Path.Combine(folder, "preferences.json"); var checks = new List<string>();
void Require(bool condition, string name) { if (!condition) throw new InvalidOperationException(name); checks.Add(name); }
try
{
    var preferences = AppPreferences.Load(path); Require(preferences.Document.Current == new WorkspaceLayout(), "missing preferences use bounded defaults");
    preferences.Document.Current = WorkspaceLayout.Preset("review") with { InspectorSide = "left", VerticalComparison = true, ComparisonRatio = .72 };
    preferences.Workbook.Current = WorkspaceLayout.Preset("focus"); preferences.Document.Named["review__100%_{0}_한글_العربية"] = preferences.Document.Current; preferences.Save(path);
    var loaded = AppPreferences.Load(path); Require(loaded.Document.Current == preferences.Document.Current && loaded.Workbook.Current == preferences.Workbook.Current, "independent document and workbook layouts persist"); Require(loaded.Document.Named.Keys.Single() == "review__100%_{0}_한글_العربية", "authored preset names remain opaque");
    var bounded = new WorkspaceLayout { SidebarWidth = double.NaN, InspectorWidth = double.PositiveInfinity, ChangesHeight = -9, ComparisonRatio = 50, Changes = "execute", InspectorSide = "invalid" }.Bounded();
    Require(double.IsFinite(bounded.SidebarWidth) && bounded.InspectorWidth == 290 && bounded.ChangesHeight == 100 && bounded.ComparisonRatio == .8 && bounded.Changes == "bottom" && bounded.InspectorSide == "right", "nonfinite extremes and unsupported dock positions bounded");
    await File.WriteAllTextAsync(path, "{\"Version\":99,\"future\":\"preserve me\"}"); var futureBytes = await File.ReadAllBytesAsync(path); var future = AppPreferences.Load(path); future.Language = "ko"; future.Save(path); var afterFuture = await File.ReadAllBytesAsync(path); Require(future.IsReadOnly && futureBytes.SequenceEqual(afterFuture), "future schema retained without overwrite");
    foreach (var shape in new[] { "{\"Version\":2,\"Document\":[],\"Workbook\":false,\"Language\":{}}", "{\"Version\":\"next\",\"Document\":12}" }) { await File.WriteAllTextAsync(path, shape); var next = AppPreferences.Load(path); next.Save(path); Require(next.IsReadOnly && await File.ReadAllTextAsync(path) == shape, "future schema with changed known field types retained"); }
    var deepFuture = "{\"Version\":2,\"Document\":" + new string('[', 20) + "0" + new string(']', 20) + "}"; await File.WriteAllTextAsync(path, deepFuture); var deep = AppPreferences.Load(path); deep.Save(path); Require(deep.IsReadOnly && await File.ReadAllTextAsync(path) == deepFuture, "deep valid future schema retained read-only before bounded decode");
    foreach (var marker in new[]
    {
        (Name: "missing", Json: "{\"Document\":{},\"opaque\":\"한글 {0}%\"}"),
        (Name: "null", Json: "{\"Version\":null,\"Document\":{}}"),
        (Name: "boolean", Json: "{\"Version\":true,\"Document\":{}}"),
        (Name: "numeric string", Json: "{\"Version\":\"1\",\"Document\":{}}"),
        (Name: "noninteger", Json: "{\"Version\":1.5,\"Document\":{}}"),
        (Name: "null envelope", Json: "null")
    })
    {
        await File.WriteAllTextAsync(path, marker.Json); var original = await File.ReadAllBytesAsync(path); var unknown = AppPreferences.Load(path); unknown.Language = "ko"; unknown.Document.Named["session only"] = new(); unknown.Save(path); var preserved = await File.ReadAllBytesAsync(path);
        Require(unknown.IsReadOnly && original.SequenceEqual(preserved), marker.Name + " schema marker preserves existing preference bytes read-only");
    }
    await File.WriteAllTextAsync(path, "{\"Version\":1,\"Document\":null,\"Workbook\":{\"Current\":null,\"Named\":null}}"); var nulls = AppPreferences.Load(path); Require(nulls.Document.Current == new WorkspaceLayout() && nulls.Workbook.Named.Count == 0, "null nested settings recovered");
    await File.WriteAllTextAsync(path, "bad json"); Require(AppPreferences.Load(path).Language == "en", "corrupt JSON recovered");
    var tooMany = new AppPreferences(); for (var index = 0; index < 30; index++) tooMany.Document.Named[index.ToString()] = new(); tooMany.Save(path); Require(AppPreferences.Load(path).Document.Named.Count == 12, "named presets bounded at twelve");
    var oversized = new string('x', 65537); await File.WriteAllTextAsync(path, oversized); var large = AppPreferences.Load(path); large.Save(path); Require(large.IsReadOnly && await File.ReadAllTextAsync(path) == oversized, "oversized settings preserved read-only");
    var part = JsonSerializer.SerializeToElement(new { before = new { text_continuations = new { value = new { next_offset = 4095 }, formula = new { next_offset = 4094 } } }, after = new { text_continuations = new { value = new { next_offset = 2048 } } } }); Require(RawSourcePaging.Next(part, 0) == 2048 && RawSourcePaging.Next(part, 4095) is null, "paired continuation advances by actual minimum UTF16 offset");
    var descriptor = JsonSerializer.SerializeToElement(new { project_id = "wprj_owned", analysis_run_id = "wrun_owned", report_id = "wreport_fixed" });
    foreach (var lost in new[] { "exception", "invalid_ack", "cancel" })
    {
        var calls = new List<string>(); var recovered = await AnalysisCommit.Save("wprj_owned", true, descriptor, CancellationToken.None, (action, args, cancel) => { calls.Add(action); if (action == "workbookCommit") { if (lost == "invalid_ack") return Task.FromResult(JsonSerializer.SerializeToElement(new { report_id = "wrong", status = "complete" })); throw lost == "cancel" ? new OperationCanceledException() : new IOException("lost acknowledgement"); } return Task.FromResult(JsonSerializer.SerializeToElement(new { project_id = "wprj_owned", analysis_run_id = "wrun_owned", report_id = "wreport_fixed", status = "success" })); }); Require(recovered.Get("report_id").Text() == "wreport_fixed" && calls.SequenceEqual(new[] { "workbookCommit", "workbookRunStatus" }), "durable exact-run recovery after " + lost);
    }
    var discarded = false; try { await AnalysisCommit.Save("wprj_owned", true, descriptor, CancellationToken.None, (action, args, cancel) => { if (action == "workbookCommit") throw new IOException("failed"); if (action == "workbookDiscard") { var owned = JsonSerializer.SerializeToElement(args); discarded = owned.Get("project_id").Text() == "wprj_owned" && owned.Get("analysis_run_id").Text() == "wrun_owned"; } return Task.FromResult(JsonSerializer.SerializeToElement(new { project_id = "wprj_owned", analysis_run_id = "wrun_owned", status = "staged" })); }); } catch (IOException) { } Require(discarded, "failed commit discards only exact owned uncommitted workbook stage");
    var peerDiscarded = false; try { await AnalysisCommit.Save("wprj_owned", true, descriptor, CancellationToken.None, (action, args, cancel) => { if (action == "workbookCommit") throw new IOException("failed"); if (action == "workbookDiscard") peerDiscarded = true; return Task.FromResult(JsonSerializer.SerializeToElement(new { project_id = "wprj_peer", analysis_run_id = "wrun_peer", status = "staged" })); }); } catch (AggregateException) { } Require(!peerDiscarded, "mismatched peer status never authorizes discard");
    Console.WriteLine(JsonSerializer.Serialize(new { passed = true, checks }, new JsonSerializerOptions { WriteIndented = true }));
}
finally { Directory.Delete(folder, true); }
