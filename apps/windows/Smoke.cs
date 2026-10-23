using System.IO;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace Reviset.Windows;

// Runs only with a new isolated profile beneath the explicitly supplied output
// directory. Exercises the real window, production bridge and bundled runtime.
// This is programmatic WPF control QA, not OS mouse or accessibility automation.
internal static class Smoke
{
    internal static async Task<bool> Run(MainWindow window, BridgeClient bridge, string output, string? fixtures)
    {
        Directory.CreateDirectory(output);
        var checks = new List<string>(); var result = new Dictionary<string, object?> { ["passed"] = false, ["library"] = bridge.Library, ["interaction_scope"] = "Production WPF window/model/actions and RenderTargetBitmap; no OS mouse/keyboard or screen-reader automation", ["checks"] = checks };
        var started = DateTimeOffset.UtcNow; result["started_at"] = started;
        try
        {
            if (fixtures is null) throw new ArgumentException("--fixtures is required for --smoke");
            using var manifest = JsonDocument.Parse(await File.ReadAllTextAsync(Path.Combine(fixtures, "windows-smoke.json")));
            var request = manifest.RootElement;
            await window.Initialize();
            var documents = Rows(request.Get("documents"), fixtures, false); var books = Rows(request.Get("workbook"), fixtures, true);
            var formats = documents.SelectMany(r => r.Paths).Concat(books.SelectMany(r => r.Paths)).Select(p => Path.GetExtension(p).ToLowerInvariant()).Distinct().OrderBy(v => v).ToArray();
            foreach (var extension in new[] { ".pdf", ".pptx", ".xlsx", ".csv", ".ods" }) Require(formats.Contains(extension), "Missing required fixture format " + extension);
            result["fixture_formats"] = formats;
            result["process_job"] = await CheckJob(bridge, output); checks.Add("host_job_terminates_actual_parent_and_descendant");
            using (var runningCancel = new CancellationTokenSource())
            {
                var startedPid = 0;
                try { await bridge.Call("projects", token: runningCancel.Token, startedForSmoke: pid => { startedPid = pid; runningCancel.Cancel(); }); throw new InvalidOperationException("Started helper cancellation succeeded unexpectedly"); } catch (OperationCanceledException) { }
                Require(startedPid > 0, "Running cancellation never started the actual bundled helper"); result["cancelled_helper_pid"] = startedPid;
                try { using var stopped = Process.GetProcessById(startedPid); Require(stopped.HasExited, "Cancelled helper remained alive"); } catch (ArgumentException) { }
                Require((await bridge.Call("projects")).ValueKind == JsonValueKind.Array, "Running cancellation poisoned the next request"); checks.Add("started_engine_process_cancellation_and_next_request");
            }
            await window.ImportAndAnalyze(request.Get("documents").Get("title").Text(), documents);
            Require(window.ProjectId.Length > 0 && window.ReportId.Length > 0 && window.ReportId != "latest", "Document report was not pinned");
            result["document_project_id"] = window.ProjectId; result["document_report_id"] = window.ReportId;
            result["document_revisions"] = window.Report.Get("revisions").Items().Count;
            var documentProject = window.ProjectId; var documentReport = window.ReportId;
            checks.Add("document_create_analyze_staged_commit_fixed_report");
            await window.CheckIntermediateEventForSmoke(); checks.Add("document_intermediate_event_exact_source_pair_preserves_list_interval");
            await SaveConfig(window, Path.Combine(output, "document-mcp.json")); checks.Add("actual_document_mcp_configuration");
            var previews = new List<object>();
            foreach (var revision in window.Report.Get("revisions").Items())
            {
                var firstPage = revision.Get("pages").Items().FirstOrDefault(); if (firstPage.ValueKind == JsonValueKind.Undefined) continue;
                var preview = await bridge.Call("pagePreview", new { project_id = documentProject, report_id = documentReport, page_id = firstPage.Get("page_id").Text(), max_width = 600 });
                Require(preview.Get("report_id").Text() == documentReport && preview.Get("page_id").Text() == firstPage.Get("page_id").Text(), "Page scope mismatch");
                var hasImage = preview.Get("png_base64").Text().Length > 0;
                Require(hasImage || preview.Get("text").Text().Length > 0, "No raster or honest source text fallback");
                previews.Add(new { source = preview.Get("source").Text(), raster = hasImage, unavailable_reason = preview.Get("unavailable_reason").Text() });
            }
            result["document_previews"] = previews; Require(previews.Count >= 2, "Expected multiple document previews"); checks.Add("document_pdf_and_pptx_previews_or_explicit_fallback");
            await CheckLayout(window, checks, output, "document");
            var documentAssets = await AssetHashes(bridge.Library);
            window.SetLanguage("ko"); await Tick(window); Screenshot(window, Path.Combine(output, "document-ko.png")); window.SetLanguage("en"); await Tick(window); Screenshot(window, Path.Combine(output, "document-en.png"));
            await window.ExportForSmoke(Path.Combine(output, "document-export")); checks.Add("document_pinned_export");
            Require(Equal(documentAssets, await AssetHashes(bridge.Library)), "Source assets changed during UI/layout/export"); checks.Add("document_source_assets_preserved");
            var staleGeneration = window.Generation; var superseded = window.ReloadComparison(); await window.SwitchWorkspace(true);
            try { await superseded; } catch (OperationCanceledException) { }
            Require(window.Generation > staleGeneration && window.IsWorkbook && window.ReportId.Length == 0, "A stale document read mutated workbook state"); checks.Add("superseded_document_read_scope");
            await window.ImportAndAnalyze(request.Get("workbook").Get("title").Text(), books);
            Require(window.ProjectId.StartsWith("wprj_", StringComparison.Ordinal) && window.ReportId.StartsWith("wreport_", StringComparison.Ordinal), "Workbook report was not pinned");
            result["workbook_project_id"] = window.ProjectId; result["workbook_report_id"] = window.ReportId; result["workbook_revisions"] = window.Report.Get("revisions").Items().Count;
            checks.Add("workbook_create_analyze_staged_commit_fixed_report"); await SaveConfig(window, Path.Combine(output, "workbook-mcp.json")); checks.Add("actual_workbook_mcp_configuration");
            await window.CheckIntermediateEventForSmoke(); checks.Add("workbook_intermediate_event_exact_source_pair_preserves_list_interval");
            Require(window.Before.Cells.Items.Count == 50 && window.After.Cells.Items.Count == 50, "Native sparse grid viewport was not populated"); checks.Add("native_virtualized_sparse_grid");
            await window.Before.GoForSmoke("B2"); Require(window.Before.SelectedRow == 2 && window.Before.SelectedColumn == 2, "Grid address navigation failed"); checks.Add("grid_physical_address_and_raw_cell_detail");
            await CheckLayout(window, checks, output, "workbook");
            var workbookAssets = await AssetHashes(bridge.Library); window.SetLanguage("ko"); await Tick(window); Screenshot(window, Path.Combine(output, "workbook-ko.png")); window.SetLanguage("en"); await Tick(window); Screenshot(window, Path.Combine(output, "workbook-en.png"));
            await window.ExportForSmoke(Path.Combine(output, "workbook-export")); Require(Equal(workbookAssets, await AssetHashes(bridge.Library)), "Workbook assets changed during UI/layout/export"); checks.Add("workbook_source_assets_and_pinned_export");
            var workbookLayout = window.Layout; var documentLayout = window.Preferences.Document.Current;
            await window.SwitchWorkspace(false); Require(window.Layout == documentLayout, "Document layout was overwritten by workbook preferences");
            var project = (await bridge.Call("projects")).Items().First(p => p.Get("project_id").Text() == documentProject); await window.OpenProject(project); await window.OpenReport(documentReport);
            Require(window.ReportId == documentReport && !window.IsWorkbook, "Reopening fixed document report failed"); checks.Add("workspace_independent_layout_and_fixed_report_reopen");
            Require(window.Preferences.Workbook.Current == workbookLayout, "Switching document changed workbook layout");
            var beforeScope = window.ReportId; using (var cancelled = new CancellationTokenSource()) { cancelled.Cancel(); try { await bridge.Call("projects", token: cancelled.Token); throw new InvalidOperationException("Cancelled engine request succeeded"); } catch (OperationCanceledException) { } }
            Require(window.ReportId == beforeScope && (await bridge.Call("projects")).ValueKind == JsonValueKind.Array, "Cancellation poisoned subsequent engine requests"); checks.Add("cancellation_scope_and_subsequent_request");
            var buildInfo = Path.Combine(bridge.BundleRoot, "build-info.json"); if (File.Exists(buildInfo)) result["build_info"] = JsonSerializer.Deserialize<JsonElement>(await File.ReadAllTextAsync(buildInfo));
            result["passed"] = true;
        }
        catch (Exception error) { result["error"] = error.ToString(); }
        result["completed_at"] = DateTimeOffset.UtcNow; result["seconds"] = (DateTimeOffset.UtcNow - started).TotalSeconds;
        await File.WriteAllTextAsync(Path.Combine(output, "result.json"), JsonSerializer.Serialize(result, new JsonSerializerOptions { WriteIndented = true }));
        return result["passed"] is true;
    }
    private static List<ImportRow> Rows(JsonElement section, string fixtures, bool workbook)
    {
        var root = Path.GetFullPath(fixtures) + Path.DirectorySeparatorChar;
        string PathInFixture(string input)
        {
            var path = Path.GetFullPath(Path.Combine(root, input));
            if (!path.StartsWith(root, StringComparison.OrdinalIgnoreCase) || !File.Exists(path)) throw new IOException("Smoke fixture must be an existing file within --fixtures: " + input);
            return path;
        }
        var rows = section.Get("revisions").Items().Select(v => new ImportRow { Label = v.Get("label").Text(), Paths = workbook ? [PathInFixture(v.Get("path").Text())] : v.Get("files").Items().Select(v => PathInFixture(v.Text())).ToArray() }).ToList();
        Require(rows.Count >= 2 && rows.All(r => r.Paths.Length > 0 && r.Label.Length > 0), "Smoke needs multiple labelled revisions"); return rows;
    }
    private static async Task SaveConfig(MainWindow window, string path) { var config = await window.McpConfig(); using var parsed = JsonDocument.Parse(config.Text()); await File.WriteAllTextAsync(path, config.Text()); }
    private static async Task CheckLayout(MainWindow window, List<string> checks, string output, string name)
    {
        if (!window.IsWorkbook) { window.Before.Zoom = 1.5; await Tick(window); window.Before.PageScroll.ScrollToVerticalOffset(20); window.Before.PageScroll.ScrollToHorizontalOffset(15); await Tick(window); }
        var before = window.Before.Host; var after = window.After.Host; var sidebar = window.SidebarPane; var inspector = window.InspectorPane; var changePane = window.ChangesPane;
        var report = window.ReportId; var beforeVersion = window.Before.RevisionId; var afterVersion = window.After.RevisionId; var page = window.Before.PageId; var row = window.Before.SelectedRow; var column = window.Before.SelectedColumn; var zoom = window.Before.PageImage.LayoutTransform.Value;
        var nativeRows = window.Before.Cells.ItemsSource; var sourceImage = window.Before.PageImage.Source;
        foreach (var preset in new[] { "focus", "review", "balanced" })
        {
            window.SetLayout(WorkspaceLayout.Preset(preset)); await Tick(window);
            Require(ReferenceEquals(before, window.Before.Host) && ReferenceEquals(after, window.After.Host) && ReferenceEquals(sidebar, window.SidebarPane) && ReferenceEquals(inspector, window.InspectorPane) && ReferenceEquals(changePane, window.ChangesPane), "Layout recreated a retained pane");
            Require(window.ReportId == report && window.Before.RevisionId == beforeVersion && window.After.RevisionId == afterVersion && window.Before.PageId == page && window.Before.SelectedRow == row && window.Before.SelectedColumn == column, "Layout changed report/version/page/grid state");
            Require(ReferenceEquals(nativeRows, window.Before.Cells.ItemsSource) && ReferenceEquals(sourceImage, window.Before.PageImage.Source) && window.Before.PageImage.LayoutTransform.Value == zoom, "Layout recreated native content or lost zoom");
            if (!window.IsWorkbook) { Require(window.Before.Zoom == 1.5, "Layout reset user zoom"); Require(window.Before.PageScroll.HorizontalOffset >= 0 && window.Before.PageScroll.VerticalOffset >= 0, "Invalid native scroll viewport"); }
        }
        var customized = window.Layout with { Changes = "right", InspectorSide = "left", VerticalComparison = true, Sidebar = false, ComparisonRatio = .62 };
        window.SetLayout(customized); window.Preferences.For(window.IsWorkbook).Named["smoke saved"] = window.Layout; window.SavePreferences(); var expected = window.Layout;
        window.SetLayout(new()); window.Preferences.For(window.IsWorkbook).Current = window.Preferences.For(window.IsWorkbook).Named["smoke saved"]; window.ApplyLayout(); window.ReloadPreferencesForSmoke();
        Require(window.Layout == expected && window.Preferences.For(window.IsWorkbook).Named.ContainsKey("smoke saved"), "Saved layout did not reload");
        Require(window.ReportId == report && window.Before.PageId == page && window.Before.SelectedRow == row, "Preference reload changed source scope");
        checks.Add(name + "_all_presets_retained_native_pane_and_state"); checks.Add(name + "_custom_docking_named_save_apply_reload");
        var preferred = window.Layout; var wide = window.Width; window.Width = 1000; await Tick(window); Require(window.Layout == preferred, "Narrow layout overwrote user preferred dimensions"); window.Width = wide; await Tick(window); Require(window.Layout == preferred, "Widening failed to retain preferred dimensions"); checks.Add(name + "_narrow_window_preserves_preferred_layout");
        window.SetLayout(WorkspaceLayout.Preset("balanced")); await Tick(window); Screenshot(window, Path.Combine(output, name + "-balanced.png"));
    }
    private static async Task Tick(MainWindow window) { window.UpdateLayout(); await window.Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle); }
    private static async Task<object> CheckJob(BridgeClient bridge, string output)
    {
        var script = Path.Combine(output, "job-lifetime-control.cjs");
        await File.WriteAllTextAsync(script, "const {spawn}=require('node:child_process');process.stdin.once('data',()=>{const child=spawn(process.execPath,['-e','setInterval(()=>{},1000)'],{stdio:'ignore',shell:false});process.stdout.write(JSON.stringify({parent:process.pid,child:child.pid})+'\\n');setInterval(()=>{},1000);});process.stdin.resume();\n");
        var job = new ProcessJob(); using var parent = new Process { StartInfo = bridge.StartInfo(script) }; Process? child = null;
        try
        {
            Require(parent.Start(), "Job control could not start bundled Node"); job.Assign(parent);
            await parent.StandardInput.WriteLineAsync("begin"); parent.StandardInput.Close();
            var line = await parent.StandardOutput.ReadLineAsync().WaitAsync(TimeSpan.FromSeconds(10)); using var parsed = JsonDocument.Parse(line ?? "{}"); var parentPid = parsed.RootElement.Get("parent").Number(); var childPid = parsed.RootElement.Get("child").Number();
            Require(parentPid == parent.Id && childPid > 0, "Job control did not report its actual descendant"); child = Process.GetProcessById(childPid); Require(!child.HasExited, "Job control descendant did not remain running");
            job.Dispose(); await Task.WhenAll(parent.WaitForExitAsync(), child.WaitForExitAsync()).WaitAsync(TimeSpan.FromSeconds(5));
            Require(parent.HasExited && child.HasExited, "Closing the host job did not terminate the complete tree"); return new { parent_pid = parentPid, child_pid = childPid, parent_exited = parent.HasExited, child_exited = child.HasExited, assignment = "fixed trusted Node control waits for stdin until job assignment; no breakaway flag" };
        }
        finally { job.Dispose(); child?.Dispose(); }
    }
    private static void Screenshot(MainWindow window, string path)
    {
        var bitmap = new RenderTargetBitmap((int)Math.Ceiling(window.ActualWidth), (int)Math.Ceiling(window.ActualHeight), 96, 96, PixelFormats.Pbgra32); bitmap.Render(window); var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap)); using var stream = File.Create(path); encoder.Save(stream);
    }
    private static async Task<Dictionary<string, string>> AssetHashes(string library)
    {
        var result = new Dictionary<string, string>(); var folder = Path.Combine(library, "assets"); if (!Directory.Exists(folder)) return result;
        foreach (var path in Directory.EnumerateFiles(folder)) { await using var stream = File.OpenRead(path); result[Path.GetFileName(path)] = Convert.ToHexString(await SHA256.HashDataAsync(stream)); } return result;
    }
    private static bool Equal(Dictionary<string, string> a, Dictionary<string, string> b) => a.Count == b.Count && a.All(pair => b.TryGetValue(pair.Key, out var value) && value == pair.Value);
    private static void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
}
