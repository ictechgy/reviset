using System.IO;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
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
            await window.CheckOrderAndAbsenceForSmoke(); checks.Add("document_reversed_interval_is_invalid_not_empty"); await window.CheckIntermediateEventForSmoke();
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
            var documentPages = window.Report.Get("revisions").Items()[0].Get("pages").Items(); Require(documentPages.Count >= 2, "Distinct two-page control fixture is required");
            await window.Before.SelectPageForSmoke(documentPages[0].Get("page_id").Text()); Require(window.Before.VerifiedPreviewText.Contains("Revenue 100", StringComparison.Ordinal), "Page A source control is missing");
            var pageTicket = window.Generation; var pageReport = window.ReportId; var pendingStarted = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously); var releasePage = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            var pendingPage = window.Before.SelectPageForSmoke(documentPages[1].Get("page_id").Text(), async ownedToken => { pendingStarted.TrySetResult(); await releasePage.Task.WaitAsync(TimeSpan.FromSeconds(20), ownedToken); });
            try
            {
                await pendingStarted.Task.WaitAsync(TimeSpan.FromSeconds(10));
                foreach (var language in new[] { "ko", "en" }) { window.SetLanguage(language); Require(window.Before.ReadState == "loading" && window.Before.PageImage.Source is null && window.Before.VerifiedPreviewText.Length == 0 && window.Before.PresentedSourceCaption.Length == 0 && window.Before.PresentedFallback == window.Copy["loading"] && window.Generation == pageTicket && window.ReportId == pageReport && window.Before.PageId == documentPages[1].Get("page_id").Text(), "Pending page B locale update reused page A text/image/provenance"); }
            }
            finally { releasePage.TrySetResult(); }
            await pendingPage; Require(window.Before.ReadState == "ready" && window.Before.VerifiedPreviewText.Contains("Second page evidence 1 / 100", StringComparison.Ordinal) && !window.Before.VerifiedPreviewText.Contains("Revenue 100", StringComparison.Ordinal), "Verified replacement page did not bind distinct page B source");
            await window.Before.SelectPageForSmoke(documentPages[0].Get("page_id").Text()); checks.Add("distinct_pending_page_language_transition_never_reuses_previous_text_image_or_provenance");
            var supersededStarted = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously); var releaseSuperseded = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            var oldPageRead = window.Before.SelectPageForSmoke(documentPages[1].Get("page_id").Text(), async ownedToken => { supersededStarted.TrySetResult(); await releaseSuperseded.Task.WaitAsync(TimeSpan.FromSeconds(20), ownedToken); });
            Task newestPage;
            try
            {
                await supersededStarted.Task.WaitAsync(TimeSpan.FromSeconds(10)); newestPage = window.Before.SelectPageForSmoke(documentPages[0].Get("page_id").Text()); window.SetLanguage("ko"); window.SetLanguage("en");
                Require(window.Before.ReadState == "loading" && window.Before.VerifiedPreviewText.Length == 0, "Superseding page locale transition reused retired payload");
            }
            finally { releaseSuperseded.TrySetResult(); }
            try { await oldPageRead; throw new InvalidOperationException("Superseded page request did not cancel"); } catch (OperationCanceledException) { }
            await newestPage; Require(window.Before.ReadState == "ready" && window.Before.VerifiedPreviewText.Contains("Revenue 100", StringComparison.Ordinal) && window.Before.PageId == documentPages[0].Get("page_id").Text(), "Older page cancellation invalidated the newest verified request"); checks.Add("older_page_cancellation_cannot_fail_or_cancel_newest_same_scope_page_request");
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
            await window.CheckOrderAndAbsenceForSmoke(); checks.Add("workbook_reverse_missing_unknown_and_actual_one_sided_event");
            var expectedLong = request.Get("expected_long_sources");
            Require(await window.ReadCellForSmoke(3, "B3", "value") == expectedLong.Get("csv_b3").Text(), "Native raw Unicode source continuation failed exact reconstruction");
            Require(await window.ReadCellForSmoke(3, "C3", "value") == expectedLong.Get("csv_c3").Text(), "Native formula-looking CSV source was changed or truncated");
            Require(await window.ReadCellForSmoke(1, "D4", "formula") == expectedLong.Get("xlsx_d4_formula").Text(), "Native raw formula continuation failed exact reconstruction"); checks.Add("native_long_unicode_value_and_formula_exact_utf16_continuation_first_next");
            JsonElement backup = default;
            async Task Corrupt() { backup = await IndexControl(bridge, output, new { operation = "corrupt", report_id = window.ReportId, revision = window.Before.RevisionId, sheet = window.Before.SheetId, row = window.Before.SelectedRow, column = window.Before.SelectedColumn }); }
            async Task Restore() { if (backup.ValueKind != JsonValueKind.Undefined) await IndexControl(bridge, output, new { operation = "restore", backup }); }
            await window.CheckFailedDetailForSmoke(Corrupt, Restore); checks.Add("failed_raw_continuation_removes_authority_and_scoped_first_retry");
            await window.CheckFailedGridForSmoke(Corrupt, Restore); checks.Add("failed_grid_clears_cells_selection_changes_inspector_and_exact_retry");
            await window.SelectSourcePairForSmoke(0, 1); await window.Before.GoForSmoke("B2");
            await window.CheckAnalysisCancellationForSmoke(); checks.Add("actual_analysis_during_pending_read_busy_evidence_blocked_cancel_restores_scope");
            await window.CheckPostCommitAdmissionForSmoke(); checks.Add("post_commit_refresh_retains_single_writer_rejects_nested_analysis_import_and_owns_cancel");
            var priorReport = window.ReportId; var stageFolder = Path.Combine(bridge.Library, "workbook-staging-v1"); var stageBackup = stageFolder + ".smoke-preserved"; var hadStageFolder = Directory.Exists(stageFolder); if (hadStageFolder) Directory.Move(stageFolder, stageBackup);
            try { await File.WriteAllTextAsync(stageFolder, "Synthetic staging failure control"); try { await window.AnalyzeForSmoke(); throw new InvalidOperationException("Blocked staging path unexpectedly completed analysis."); } catch (BridgeException) { } Require(window.ReportId == priorReport && window.ComparisonState == "ready" && window.DetailText != window.Copy["loading"], "Failed analysis did not restore the prior fixed comparison"); } finally { if (File.Exists(stageFolder)) File.Delete(stageFolder); if (hadStageFolder) Directory.Move(stageBackup, stageFolder); }
            checks.Add("actual_analysis_failure_restores_exact_fixed_comparison");
            await CheckLayout(window, checks, output, "workbook");
            await window.Before.GoForSmoke("B2"); window.CheckLoadedLanguageForSmoke(); checks.Add("loaded_source_detail_locally_relabels_en_ko_preserving_payload_selection_generation"); var workbookAssets = await AssetHashes(bridge.Library); window.SetLanguage("ko"); await Tick(window); Screenshot(window, Path.Combine(output, "workbook-ko.png")); window.SetLanguage("en"); await Tick(window); Screenshot(window, Path.Combine(output, "workbook-en.png"));
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
        if (!window.IsWorkbook) { window.Before.Zoom = 1.5; window.After.Zoom = 1.5; await Tick(window); window.Before.PageScroll.ScrollToVerticalOffset(20); window.Before.PageScroll.ScrollToHorizontalOffset(15); window.After.PageScroll.ScrollToVerticalOffset(18); window.After.PageScroll.ScrollToHorizontalOffset(12); await Tick(window); }
        else { await Tick(window); foreach (var pane in new[] { window.Before, window.After }) { pane.GridScroll?.ScrollToVerticalOffset(6); pane.GridScroll?.ScrollToHorizontalOffset(80); } await Tick(window); }
        var before = window.Before.Host; var after = window.After.Host; var sidebar = window.SidebarPane; var inspector = window.InspectorPane; var changePane = window.ChangesPane;
        var report = window.ReportId; var beforeVersion = window.Before.RevisionId; var afterVersion = window.After.RevisionId; var page = window.Before.PageId; var row = window.Before.SelectedRow; var column = window.Before.SelectedColumn; var zoom = window.Before.PageImage.LayoutTransform.Value;
        var nativeRows = window.Before.Cells.ItemsSource; var sourceImage = window.Before.PageImage.Source;
        foreach (var preset in new[] { "focus", "review", "balanced" })
        {
            var positions = new[] { window.Before, window.After }.Select(pane => { var scroll = window.IsWorkbook ? pane.GridScroll! : pane.PageScroll; return (scroll.HorizontalOffset, scroll.VerticalOffset); }).ToArray();
            window.SetLayout(WorkspaceLayout.Preset(preset)); await Tick(window);
            Require(ReferenceEquals(before, window.Before.Host) && ReferenceEquals(after, window.After.Host) && ReferenceEquals(sidebar, window.SidebarPane) && ReferenceEquals(inspector, window.InspectorPane) && ReferenceEquals(changePane, window.ChangesPane), "Layout recreated a retained pane");
            Require(window.ReportId == report && window.Before.RevisionId == beforeVersion && window.After.RevisionId == afterVersion && window.Before.PageId == page && window.Before.SelectedRow == row && window.Before.SelectedColumn == column, "Layout changed report/version/page/grid state");
            Require(ReferenceEquals(nativeRows, window.Before.Cells.ItemsSource) && ReferenceEquals(sourceImage, window.Before.PageImage.Source) && window.Before.PageImage.LayoutTransform.Value == zoom, "Layout recreated native content or lost zoom");
            for (var index = 0; index < 2; index++) { var pane = index == 0 ? window.Before : window.After; var scroll = window.IsWorkbook ? pane.GridScroll! : pane.PageScroll; Require(Math.Abs(scroll.HorizontalOffset - Math.Min(positions[index].HorizontalOffset, scroll.ScrollableWidth)) <= 1 && Math.Abs(scroll.VerticalOffset - Math.Min(positions[index].VerticalOffset, scroll.ScrollableHeight)) <= 1, "Native viewport changed beyond its measured scrollable clamp"); }
            if (!window.IsWorkbook) Require(window.Before.Zoom == 1.5, "Layout reset user zoom");
        }
        var customized = window.Layout with { Changes = "right", InspectorSide = "left", VerticalComparison = true, Sidebar = false, ComparisonRatio = .62 };
        window.SetLayout(customized); window.Preferences.For(window.IsWorkbook).Named["smoke saved"] = window.Layout; window.SavePreferences(); var expected = window.Layout;
        window.SetLayout(new()); window.Preferences.For(window.IsWorkbook).Current = window.Preferences.For(window.IsWorkbook).Named["smoke saved"]; window.ApplyLayout(); window.ReloadPreferencesForSmoke();
        Require(window.Layout == expected && window.Preferences.For(window.IsWorkbook).Named.ContainsKey("smoke saved"), "Saved layout did not reload");
        Require(window.ReportId == report && window.Before.PageId == page && window.Before.SelectedRow == row, "Preference reload changed source scope");
        checks.Add(name + "_all_presets_retained_native_pane_and_state"); checks.Add(name + "_custom_docking_named_save_apply_reload");
        var preferred = window.Layout; var wide = window.Width; window.Width = 1000; await Tick(window); Require(window.Layout == preferred, "Narrow layout overwrote user preferred dimensions"); window.Width = wide; await Tick(window); Require(window.Layout == preferred, "Widening failed to retain preferred dimensions"); checks.Add(name + "_narrow_window_preserves_preferred_layout");
        window.SetLayout(WorkspaceLayout.Preset("balanced")); await Tick(window); Screenshot(window, Path.Combine(output, name + "-balanced.png"));
        foreach (var splitter in window.NativeSplitters()) Require(!string.IsNullOrWhiteSpace(AutomationProperties.GetName(splitter)), "An active native splitter lacks an accessibility name");
        var ratio = window.Layout.ComparisonRatio; var divider = window.NativeSplitters().First(s => s.Tag as string == "resizeComparison"); var presentation = PresentationSource.FromVisual(divider) ?? throw new InvalidOperationException("Native splitter is not attached"); divider.Focus();
        object DividerGeometry() { var parent = (Grid)divider.Parent; return new { arranged_before = parent.ColumnDefinitions[0].ActualWidth, arranged_after = parent.ColumnDefinitions[2].ActualWidth, definition_before = parent.ColumnDefinitions[0].Width.ToString(), definition_after = parent.ColumnDefinitions[2].Width.ToString(), saved_ratio = window.Layout.ComparisonRatio }; }
        var keyboardBefore = DividerGeometry(); divider.RaiseEvent(new KeyEventArgs(Keyboard.PrimaryDevice, presentation, Environment.TickCount, Key.Right) { RoutedEvent = Keyboard.KeyDownEvent }); divider.RaiseEvent(new KeyEventArgs(Keyboard.PrimaryDevice, presentation, Environment.TickCount, Key.Right) { RoutedEvent = Keyboard.KeyUpEvent }); await Tick(window); await File.WriteAllTextAsync(Path.Combine(output, name + "-keyboard-resize.json"), JsonSerializer.Serialize(new { before = keyboardBefore, after = DividerGeometry() }, new JsonSerializerOptions { WriteIndented = true }));
        Require(Math.Abs(window.Layout.ComparisonRatio - ratio) > .001, "Native keyboard splitter resize did not persist"); Require(AppPreferences.Load(window.PreferencesPath).For(window.IsWorkbook).Current.ComparisonRatio == window.Layout.ComparisonRatio, "Keyboard splitter ratio was not saved"); checks.Add(name + "_named_native_splitters_and_keyboard_resize_persistence");
        window.SetLayout(WorkspaceLayout.Preset("balanced")); var oldWidth = window.Width; var oldHeight = window.Height; window.Width = 1024; window.Height = 768; await Tick(window);
        if (window.IsWorkbook)
        {
            Require(window.Before.Cells.ActualHeight >= 150 && window.After.Cells.ActualHeight >= 150, "Balanced 1024x768 native grids have insufficient visible height");
            Require(window.Before.GridScroll?.ViewportHeight >= 5 && window.After.GridScroll?.ViewportHeight >= 5, "Balanced 1024x768 native grids do not show at least five source rows");
            Require(window.Before.Cells.ActualWidth >= 180 && window.After.Cells.ActualWidth >= 180, "Balanced source panes do not retain useful native grid width");
        }
        object Measurements() => new { actual_window_width = window.ActualWidth, actual_window_height = window.ActualHeight, before_width = window.Before.Host.ActualWidth, before_height = window.Before.Host.ActualHeight, before_grid_height = window.Before.Cells.ActualHeight, before_grid_visible_rows = window.Before.GridScroll?.ViewportHeight, after_width = window.After.Host.ActualWidth, after_height = window.After.Host.ActualHeight, after_grid_height = window.After.Cells.ActualHeight, after_grid_visible_rows = window.After.GridScroll?.ViewportHeight };
        var narrow = Measurements(); Screenshot(window, Path.Combine(output, name + "-1024x768.png")); window.Width = oldWidth; window.Height = oldHeight; await Tick(window); await File.WriteAllTextAsync(Path.Combine(output, name + "-viewport-measurements.json"), JsonSerializer.Serialize(new { narrow, available_wide = Measurements() }, new JsonSerializerOptions { WriteIndented = true }));
        if (window.IsWorkbook && window.ActualHeight >= 900) Require(window.Before.GridScroll?.ViewportHeight >= 9 && window.After.GridScroll?.ViewportHeight >= 9, "Wide native grids do not show nine source rows"); checks.Add(name + "_source_viewport_visible_at_1024x768_and_available_wide_bounds");
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
    private static async Task<JsonElement> IndexControl(BridgeClient bridge, string output, object request)
    {
        // Synthetic smoke-profile integrity failure, not a production bridge action.
        // Restore the exact original row after each negative check before MCP/export.
        var script = Path.Combine(output, "owned-index-control.cjs");
        await File.WriteAllTextAsync(script, "const fs=require('node:fs');const {DatabaseSync}=require('node:sqlite');const q=JSON.parse(fs.readFileSync(0,'utf8'));const db=new DatabaseSync(require('node:path').join(process.argv[2],'docver.sqlite'));try{if(q.operation==='corrupt'){const r=db.prepare('SELECT rowid,body,body_sha FROM workbook_cells_v1 WHERE report_id=? AND revision_occurrence_id=? AND sheet_id=? AND row=? AND col=?').get(q.report_id,q.revision,q.sheet,q.row,q.column);if(!r)throw Error('Missing owned indexed control');db.prepare('UPDATE workbook_cells_v1 SET body=? WHERE rowid=?').run('corrupt synthetic control',r.rowid);process.stdout.write(JSON.stringify(r));}else{const r=q.backup;db.prepare('UPDATE workbook_cells_v1 SET body=?,body_sha=? WHERE rowid=?').run(r.body,r.body_sha,r.rowid);process.stdout.write('{}');}}finally{db.close();}\n");
        using var job = new ProcessJob(); var start = bridge.StartInfo(script); start.ArgumentList.Add(bridge.Library); using var process = new Process { StartInfo = start }; Require(process.Start(), "Index integrity control failed to start"); job.Assign(process);
        await process.StandardInput.WriteAsync(JsonSerializer.Serialize(request)); process.StandardInput.Close(); var stdout = process.StandardOutput.ReadToEndAsync(); var stderr = process.StandardError.ReadToEndAsync(); await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(10)); var text = await stdout; var errors = await stderr; Require(process.ExitCode == 0, "Index integrity control failed: " + errors); using var parsed = JsonDocument.Parse(text); return parsed.RootElement.Clone();
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
