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
            window.CheckInitializationGateForSmoke(); checks.Add("native_actions_disabled_until_owned_library_initialization_completes"); result["startup_recovery"] = await window.CheckStartupRecoveryForSmoke(async name => { await Tick(window); Screenshot(window, Path.Combine(output, name + ".png")); }); checks.Add("actual_recovery_calls_controlled_startup_failure_blocks_writers_native_retry_restores_empty_library_visible_import_opens_new_timeline_without_mutation");
            var documents = Rows(request.Get("documents"), fixtures, false); var books = Rows(request.Get("workbook"), fixtures, true); var navigationBooks = Rows(request.Get("navigation_workbooks"), fixtures, true);
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
            var protocolControl = Path.Combine(output, "helper-protocol-control.cjs"); await File.WriteAllTextAsync(protocolControl, "process.stdin.resume();process.stdin.on('end',()=>{process.stderr.write('bounded opaque diagnostics {0}% 한글\\n');process.stdout.write('not json');});\n");
            try { await bridge.ProtocolControlForSmoke(protocolControl); throw new InvalidOperationException("Malformed helper control unexpectedly parsed"); } catch (BridgeException error) { Require(error.Code == "HELPER_PROTOCOL", "Malformed helper did not produce typed HELPER_PROTOCOL"); }
            var helperLog = Path.Combine(Path.GetDirectoryName(bridge.Library)!, "logs", "helper-error.log"); Require(File.Exists(helperLog) && new FileInfo(helperLog).Length < 270000 && (await File.ReadAllTextAsync(helperLog)).Contains("bounded opaque diagnostics {0}% 한글", StringComparison.Ordinal), "Bounded helper diagnostics did not preserve opaque stderr"); checks.Add("malformed_helper_typed_protocol_error_and_bounded_local_diagnostics");
            await window.CheckFirstImportForSmoke("Cancelled document draft", documents, true); checks.Add("cancelled_first_document_import_refreshes_saved_draft_without_dead_retry");
            await window.ImportAndAnalyze(request.Get("documents").Get("title").Text(), documents);
            Require(window.ProjectId.Length > 0 && window.ReportId.Length > 0 && window.ReportId != "latest", "Document report was not pinned");
            result["document_project_id"] = window.ProjectId; result["document_report_id"] = window.ReportId;
            result["document_revisions"] = window.Report.Get("revisions").Items().Count;
            var documentProject = window.ProjectId; var documentReport = window.ReportId;
            checks.Add("document_create_analyze_staged_commit_fixed_report");
            result["document_sole_import"] = await window.CheckSoleImportedRevisionForSmoke(documents[0], async name => { await Tick(window); Screenshot(window, Path.Combine(output, "document-git-" + name + ".png")); }, Rows(request.Get("preview_bundle"), fixtures, false)[0], (name, value) => Observe(output, "document-" + name, value)); checks.Add("actual_one_imported_document_occurrence_en_ko_sourcefirst_focus_both_New_comparison_routes_reject_one_entry_and_PPTX_PDF_bundle_before_mutation_cancel_preserves_raw_physical_hosts_ordinary_reopen_allows_one_actual_two_entry_submit_creates_new_fixed_report");
            result["reference_preview_geometry"] = await window.CheckReferencePreviewGeometryForSmoke(Rows(request.Get("preview_bundle"), fixtures, false), async name => { await Tick(window); Screenshot(window, Path.Combine(output, name + ".png")); }); checks.Add("actual_generated_pptx_emu_960_point_primary_supplied_pdf_reference_and_standalone_native_720_point_scale_legacy_mapping_and_invalid_scope_fallback_manual_zoom_retained");
            result["document_query_routing"] = await window.CheckDocumentQueryRoutingForSmoke(async name => { await Tick(window); Screenshot(window, Path.Combine(output, "document-git-" + name + ".png")); }); checks.Add("document_adjacent_net_uses_exact_stored_canonical_pair_and_provenance_nonadjacent_unavailable_keeps_net_until_explicit_scoped_native_history_recovery");
            await window.CheckRetainedImportRecoveryForSmoke(documents); checks.Add("existing_document_report_new_import_actual_process_cancel_and_postcreate_failure_restore_populated_exact_query_selectors_source_pair_and_next_native_endpoint_action");
            await window.CheckGitWorkflowForSmoke(async name => { await Tick(window); Screenshot(window, Path.Combine(output, "document-git-" + name + ".png")); }); checks.Add("document_source_first_native_version_log_v1_read_history_query_event_context_bounded_text_diff_focus_and_retained_hosts");
            result["document_event_anchor_race"] = await window.CheckDocumentEventAnchorRaceForSmoke(async name => { await Tick(window); Screenshot(window, Path.Combine(output, "document-git-" + name + ".png")); }, (name, value) => Observe(output, "document-git-" + name, value)); checks.Add("actual_document_event_page_anchors_are_immutable_before_await_manual_page2_during_before_and_after_reads_stays_neutral_outside_event_return_restores_canonical_pages_query_cursor_rows_identity_and_manual_zoom");
            checks.Add("synthetic_native_selected_missing_evidence_page_header_diagnostics_location_and_fallback_consistent_en_ko_structural_absence_only_on_implied_side_and_normal_reading_after_context_clears");
            result["document_pending_missing_page"] = await window.CheckPendingMissingPageForSmoke(async name => { await Tick(window); Screenshot(window, Path.Combine(output, "document-pending-" + name + ".png")); }); checks.Add("synthetic_scoped_ui_sparse_event_actual_SelectChange_pending_after_preview_holds_before_missing_caption_neutral_en_ko_without_authority_failure_retry_and_manual_page2_cancel_restore_exact_sources_query_and_rows");
            checks.Add("document_actual_text_mode_before_v1_and_equal_native_endpoints_forces_original_reading_picker_and_no_overlay_or_raw_pager");
            result["document_native_preview_scale"] = window.Before.CheckPreviewReadabilityForSmoke(); checks.Add("native_pdf_point_scale_readable_control_labelled_zoom_explicit_fit_and_fixed_height_page_chooser");
            result["document_invalid_fallback_presentation"] = window.Before.CheckInvalidPreviewFallbackForSmoke(); checks.Add("synthetic_document_invalid_preview_metadata_keeps_exact_source_and_visible_invalid_annotation_in_native_fallback_without_authority_or_report_mutation");
            await window.CheckTypedDiffPresentationForSmoke(async name => { await Tick(window); Screenshot(window, Path.Combine(output, "document-git-" + name + ".png")); }); checks.Add("synthetic_native_document_presentation_controls_neutral_appearance_coverage_topology_null_empty_and_selected_inference_limits_visible_in_sourcefirst_focus_without_report_mutation");
            checks.Add("synthetic_native_over_character_and_crlf_line_budget_insertions_show_neutral_bounded_sides_no_colored_prefix_artifacts_full_exact_reader_retained_and_structural_raw_marker_separate");
            checks.Add("synthetic_native_same_source_text_diff_manual_scroll_survives_en_ko_locale_and_immediate_busy_chrome_rebuilds_without_source_or_query_change");
            await window.CheckNoticeGeometryForSmoke(async name => { await Tick(window); Screenshot(window, Path.Combine(output, "document-git-" + name + ".png")); }, (name, value) => Observe(output, "document-git-" + name, value)); checks.Add("synthetic_native_document_valid_1998_utf16_multiline_reason_bounded_geometry_en_ko_sourcefirst_focus_exact_scrolling_reason_and_limited_report_count_export_path");
            checks.Add("native_document_full_selected_limits_reader_preserves_all_four_opaque_status_looking_reasons_exactly_in_en_ko");
            checks.Add("native_document_human_confirmed_code_looking_authored_reasons_remain_exact_in_compact_notice_tooltip_full_reader_en_ko_sourcefirst_focus_inferred_and_directed_machine_reason_controls_localize_without_raw_mutation");
            var revertedFixture = Path.Combine(fixtures, "v3-reverted.pdf"); Require(File.Exists(revertedFixture), "Missing byte-identical reverted PDF fixture.");
            var beforeRevertedLayout = window.Layout;
            await window.ImportAndAnalyze("Reverted 100→120→100", new[] { new ImportRow { Label = "100", Paths = [Path.Combine(fixtures, "v1.pdf")] }, new ImportRow { Label = "120", Paths = [Path.Combine(fixtures, "v2.pdf")] }, new ImportRow { Label = "100 restored", Paths = [revertedFixture] } });
            await window.CheckRevertedHistoryForSmoke(async name => { await Tick(window); Screenshot(window, Path.Combine(output, "document-git-" + name + ".png")); }); checks.Add("real_pdf_100_120_100_endpoint_identity_zero_net_and_two_intermediate_observations_preserve_wide_query_and_exact_source_pair");
            await window.OpenProject((await bridge.Call("projects")).Items().First(p => p.Get("project_id").Text() == documentProject)); await window.OpenReport(documentReport); window.SetLayout(beforeRevertedLayout);
            result["document_lost_reply_recovery"] = await window.CheckLostAnalysisReplyForSmoke(); checks.Add("document_real_staged_reply_lost_cancel_then_same_session_reanalyze_retires_orphan_preserves_fixed_report");
            await window.CheckProjectTransitionAuthorityForSmoke(async () => (await IndexControl(bridge, output, new { operation = "counts" })).GetRawText()); checks.Add("held_real_candidate_reports_and_failed_transition_revoke_previous_writer_target_without_new_runs_or_reports");
            await window.CheckIndependentProjectRefreshForSmoke(); checks.Add("document_project_list_refresh_survives_same_workspace_mode_and_source_generation_changes");
            await window.CheckModesForSmoke(false); checks.Add("document_native_net_history_modes_preserve_explicit_interval_and_event_pair");
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
            var guardedOldPageRead = window.Guard(() => oldPageRead);
            Task newestPage;
            try
            {
                await supersededStarted.Task.WaitAsync(TimeSpan.FromSeconds(10)); newestPage = window.Before.SelectPageForSmoke(documentPages[0].Get("page_id").Text()); window.SetLanguage("ko"); window.SetLanguage("en");
                Require(window.Before.ReadState == "loading" && window.Before.VerifiedPreviewText.Length == 0, "Superseding page locale transition reused retired payload");
            }
            finally { releaseSuperseded.TrySetResult(); }
            try { await oldPageRead; throw new InvalidOperationException("Superseded page request did not cancel"); } catch (OperationCanceledException) { }
            await guardedOldPageRead; await newestPage; Require(window.Before.ReadState == "ready" && window.Before.VerifiedPreviewText.Contains("Revenue 100", StringComparison.Ordinal) && window.Before.PageId == documentPages[0].Get("page_id").Text() && window.StatusForSmoke == window.Copy[window.Preferences.IsReadOnly ? "preferencesReadOnly" : "ready"], "Older page cancellation invalidated the newest verified request or presented a false import-cancelled banner"); checks.Add("guarded_superseded_actual_page_read_remains_quiet_latest_verified_page_settles_ready_without_import_cancelled_banner");
            result["document_source_only_page_supersession"] = await window.CheckSourceOnlyPageSupersessionForSmoke(async name => { await Tick(window); Screenshot(window, Path.Combine(output, "document-git-" + name + ".png")); }); checks.Add("actual_document_source_only_read_follows_latest_same_generation_page_after_old_install_ignores_cancellation_and_returns_normally_without_query_refresh_or_premature_authority");
            await CheckLayout(window, checks, output, "document"); window.CheckChangeCaptionLanguageForSmoke(); checks.Add("document_existing_native_change_captions_locally_translate_preserving_row_selection_mode_interval_and_source"); checks.Add("synthetic_native_sparse_document_row_captions_omit_absence_assertion_except_structural_event_implied_side_en_ko");
            result["document_temporary_focus"] = await window.CheckTemporaryFocusForSmoke(); checks.Add("document_native_temporary_focus_toggle_retains_custom_geometry_panel_intent_saves_retained_layout_and_visibility_preset_saved_reset_routes_preserve_hosts_sources_other_workspace");
            var documentAssets = await AssetHashes(bridge.Library);
            window.SetLanguage("ko"); await Tick(window); Screenshot(window, Path.Combine(output, "document-ko.png")); window.SetLanguage("en"); await Tick(window); Screenshot(window, Path.Combine(output, "document-en.png"));
            result["document_native_reorder"] = await window.CheckReorderForSmoke(async fixedReport => (await IndexControl(bridge, output, new { operation = "report_digest", project_id = documentProject, report_id = fixedReport })).Get("sha256").Text()); checks.Add("production_native_reorder_three_distinct_reports_preserves_older_nonfirst_pin_event_scope_net_interval_zoom_manual_viewports_and_all_fixed_report_bytes");
            checks.Add("native_versions_menu_close_and_report_pin_change_retire_old_menu_stale_callback_cannot_change_new_report_query_or_source_scope");
            await window.ExportForSmoke(Path.Combine(output, "document-export")); checks.Add("document_pinned_export");
            Require(Equal(documentAssets, await AssetHashes(bridge.Library)), "Source assets changed during UI/layout/export"); checks.Add("document_source_assets_preserved");
            await window.CheckWorkspaceListForSmoke(); checks.Add("held_workspace_project_refresh_rejects_stale_native_row_before_scope_commit_and_recovers_membership");
            var staleGeneration = window.Generation; var superseded = window.ReloadSourceWindow(); await window.SwitchWorkspace(true);
            try { await superseded; } catch (OperationCanceledException) { }
            Require(window.Generation > staleGeneration && window.IsWorkbook && window.ReportId.Length == 0, "A stale document source-only read mutated workbook state"); checks.Add("superseded_document_source_only_read_cannot_promote_foreign_workbook_scope");
            var firstStage = Path.Combine(bridge.Library, "workbook-staging-v1"); Require(!Directory.Exists(firstStage) && !File.Exists(firstStage), "First workbook staging control requires its isolated empty profile");
            try { await window.CheckFirstImportForSmoke("Failed workbook draft", books, false, () => File.WriteAllText(firstStage, "synthetic first import failure")); } finally { File.Delete(firstStage); } checks.Add("failed_first_workbook_import_refreshes_saved_draft_without_dead_retry");
            await window.ImportAndAnalyze(request.Get("workbook").Get("title").Text(), books);
            Require(window.ProjectId.StartsWith("wprj_", StringComparison.Ordinal) && window.ReportId.StartsWith("wreport_", StringComparison.Ordinal), "Workbook report was not pinned");
            result["workbook_project_id"] = window.ProjectId; result["workbook_report_id"] = window.ReportId; result["workbook_revisions"] = window.Report.Get("revisions").Items().Count;
            result["workbook_sole_import"] = await window.CheckSoleImportedRevisionForSmoke(books[0], async name => { await Tick(window); Screenshot(window, Path.Combine(output, "workbook-git-" + name + ".png")); }, observe: (name, value) => Observe(output, "workbook-" + name, value)); checks.Add("actual_one_imported_workbook_occurrence_en_ko_sourcefirst_focus_both_New_comparison_routes_reject_one_entry_before_mutation_cancel_preserves_raw_physical_hosts_ordinary_reopen_allows_one_actual_two_entry_submit_creates_new_fixed_report");
            JsonElement navigationBackup = default;
            async Task CorruptNavigation() { navigationBackup = await IndexControl(bridge, output, new { operation = "corrupt", report_id = window.ReportId, revision = window.Before.RevisionId, sheet = window.Before.SheetId, row = window.Before.SelectedRow, column = window.Before.SelectedColumn }); }
            async Task RestoreNavigation() { if (navigationBackup.ValueKind != JsonValueKind.Undefined) await IndexControl(bridge, output, new { operation = "restore", backup = navigationBackup }); }
            result["workbook_committed_initial_focus_recovery"] = await window.CheckCommittedInitialFocusRecoveryForSmoke(navigationBooks, async name => { await Tick(window); Screenshot(window, Path.Combine(output, name + ".png")); }, (name, value) => Observe(output, name, value)); checks.Add("source30_actual_import_and_analyze_committed_report_initial_event_component_failure_visible_exact_retry_preserves_successful_query_raw_sources_native_hosts_and_new_report_without_mutation_restore");
            result["workbook_paged_source_navigation"] = await window.CheckPagedSourceNavigationForSmoke(navigationBooks, CorruptNavigation, RestoreNavigation, async name => { await Tick(window); Screenshot(window, Path.Combine(output, "workbook-navigation-" + name + ".png")); }, (name, value) => Observe(output, "workbook-navigation-" + name, value)); checks.Add("actual_two_sheet_canonical_continuation_event_native_sheet_address_next_window_browse_and_return_preserve_loaded_objects_cursor_selected_row_scroll_query_mode_report_scope_and_event_anchors_without_changes_reads");
            checks.Add("source28_production_fresh_report_and_endpoint_query_first_eligible_physical_event_focus_manual_B9_mode_change_paging_locale_layout_refresh_retain_exact_physical_source_raw_continuation_hosts_and_viewports_without_reacquisition");
            checks.Add("actual_paged_source_corruption_retry_preserves_owned_query_pending_append_cancellation_resumes_real_cursor_unknown_or_failed_query_requires_requery_and_old_source_completion_cannot_promote_authority");
            checks.Add("actual_continued_event_raw_and_indexed_source_failures_retry_exact_intended_event_without_query_reread_rows_cursor_loss_old_anchors_or_stale_failure_authority");
            checks.Add("actual_failed_continued_event_retains_scoped_change_list_previous_next_and_load_more_navigation_alternate_valid_event_escapes_without_retrying_failed_target_or_reviving_failed_source_authority");
            result["workbook_metadata_presentation"] = await window.CheckWorkbookMetadataForSmoke(Rows(request.Get("metadata_workbooks"), fixtures, true), async name => { await Tick(window); Screenshot(window, Path.Combine(output, "workbook-metadata-" + name + ".png")); }); checks.Add("actual_workbook_date_system_calculation_settings_and_sheet_name_merges_neutral_metadata_en_ko_manual_physical_cell_browse_and_return_preserve_exact_query_report_and_event_context");
            checks.Add("actual_four_metadata_event_generated_json_is_single_neutral_projection_without_stored_text_or_source_terminator_labels_and_synthetic_bounded_kind_specific_scalar_note_and_missing_body_controls_en_ko");
            checks.Add("actual_four_metadata_kinds_expanded_cell_details_hide_nonphysical_value_formula_rows_disable_window_arrows_keep_Go_exit_restore_real_B2_fields_and_synthetic_query_hint_bounds_outside_json_body_en_ko");
            await window.CheckRetainedImportRecoveryForSmoke(books); checks.Add("existing_workbook_report_new_import_actual_process_cancel_and_postcreate_failure_restore_populated_exact_query_selectors_physical_pair_and_next_native_endpoint_action");
            await window.CheckGitWorkflowForSmoke(async name => { await Tick(window); Screenshot(window, Path.Combine(output, "workbook-git-" + name + ".png")); }); checks.Add("workbook_source_first_native_version_log_v1_read_history_query_event_context_stored_formula_address_text_diff_focus_and_retained_hosts");
            checks.Add("workbook_actual_text_mode_before_v1_and_equal_native_endpoints_forces_original_reading_picker_five_source_rows_and_no_overlay_or_raw_pager");
            checks.Add("actual_native_cell_click_inside_unchanged_viewport_revokes_event_context_and_colored_text_return_restores_exact_cell_anchor_without_changing_query");
            await window.CheckTypedDiffPresentationForSmoke(async name => { await Tick(window); Screenshot(window, Path.Combine(output, "workbook-git-" + name + ".png")); }, (name, value) => Observe(output, "workbook-git-" + name, value)); checks.Add("synthetic_native_workbook_presentation_controls_missing_cache_null_observation_and_topology_neutral_exact_formula_diff_independent_of_cache_without_report_mutation");
            checks.Add("synthetic_native_original_source_scoped_per_side_unchanged_missing_results_unresolved_and_genuine_empty_warnings_prioritized_en_ko_sourcefirst_focus_five_rows_and_stale_scope_rejection");
            checks.Add("synthetic_native_current_materialized_observed_blank_distinct_from_unrecorded_null_and_genuine_empty_string_with_exact_per_side_flags_in_en_ko_sourcefirst_focus");
            await window.CheckNoticeGeometryForSmoke(async name => { await Tick(window); Screenshot(window, Path.Combine(output, "workbook-git-" + name + ".png")); }, (name, value) => Observe(output, "workbook-git-" + name, value)); checks.Add("synthetic_native_workbook_valid_1998_utf16_multiline_reason_bounded_geometry_en_ko_sourcefirst_focus_five_source_rows_exact_scrolling_reason_and_limited_report_count_export_path");
            checks.Add("native_workbook_full_selected_limits_reader_preserves_all_four_opaque_status_looking_reasons_exactly_in_en_ko");
            checks.Add("workbook_create_analyze_staged_commit_fixed_report"); result["workbook_lost_reply_recovery"] = await window.CheckLostAnalysisReplyForSmoke(); checks.Add("workbook_real_staged_reply_lost_cancel_then_same_session_reanalyze_retires_orphan_preserves_fixed_report"); await window.CheckMissingVersionSheetForSmoke(); checks.Add("component_only_unmounted_revision_selector_preserves_missing_sheet_absence_until_available_sheet_selection"); await window.CheckIndependentProjectRefreshForSmoke(); checks.Add("workbook_project_list_refresh_survives_same_workspace_mode_and_source_generation_changes"); await window.CheckModesForSmoke(true); checks.Add("workbook_native_history_includes_temporary_row_net_excludes_and_interval_remains_fixed"); await SaveConfig(window, Path.Combine(output, "workbook-mcp.json")); checks.Add("actual_workbook_mcp_configuration");
            await window.CheckIntermediateEventForSmoke(); checks.Add("workbook_intermediate_event_exact_source_pair_preserves_list_interval");
            Require(window.Before.Cells.Items.Count == 50 && window.After.Cells.Items.Count == 50, "Native sparse grid viewport was not populated"); checks.Add("native_virtualized_sparse_grid");
            await window.Before.GoForSmoke("B2"); Require(window.Before.SelectedRow == 2 && window.Before.SelectedColumn == 2, "Grid address navigation failed"); checks.Add("grid_physical_address_and_raw_cell_detail");
            await window.CheckOrderAndAbsenceForSmoke(); checks.Add("workbook_reverse_missing_unknown_and_actual_one_sided_event");
            checks.Add("actual_one_sided_sheet_metadata_absence_is_secondary_no_generated_body_on_missing_side_en_ko");
            checks.Add("actual_one_sided_sheet_expanded_cell_details_hide_nonphysical_value_formula_rows_disable_ineffective_window_arrows_and_keep_Go_exit_en_ko");
            result["workbook_semantic_captions"] = await window.CheckWorkbookSemanticCaptionsForSmoke(async name => { await Tick(window); Screenshot(window, Path.Combine(output, "workbook-git-" + name + ".png")); }); checks.Add("actual_workbook_cell_scoped_null_side_is_unmaterialized_not_sheet_metadata_opposite_grid_healthy_en_ko_known_generated_summaries_localized_raw_description_retained_cache_negation_visible");
            checks.Add("actual_sparse_missing_cell_and_one_sided_cell_raw_ranges_show_one_unmaterialized_observation_not_invalid_field_ranges");
            var expectedLong = request.Get("expected_long_sources");
            Require(await window.ReadCellForSmoke(3, "B3", "value") == expectedLong.Get("csv_b3").Text(), "Native raw Unicode source continuation failed exact reconstruction");
            Require(await window.ReadCellForSmoke(3, "C3", "value") == expectedLong.Get("csv_c3").Text(), "Native formula-looking CSV source was changed or truncated");
            Require(await window.ReadCellForSmoke(1, "D4", "formula") == expectedLong.Get("xlsx_d4_formula").Text(), "Native raw formula continuation failed exact reconstruction"); checks.Add("native_long_unicode_value_and_formula_exact_utf16_continuation_first_next");
            foreach (var marker in new[] { ("B4", "—"), ("C4", "…"), ("D4", "ends…") }) { Require(await window.ReadCellForSmoke(3, marker.Item1, "value") == marker.Item2, "Literal marker source changed in the raw reader"); window.Before.CheckLiteralMarkerForSmoke(marker.Item2); }
            await window.ReadCellForSmoke(3, "B3", "value"); window.Before.CheckTruncationForSmoke(); checks.Add("literal_grid_markers_are_source_normal_and_sparse_truncation_annotations_are_distinct");
            await window.ReadCellForSmoke(1, "D4", "formula");
            result["source32_single_cell_ownership"] = await window.CheckSingleCellOwnershipForSmoke((name, value) => Observe(output, name, value)); checks.Add("source32_actual_single_cell_same_generation_foreign_reply_rejected_before_display_owned_First_retry_exact_fixed_query_physical_hosts_en_ko_immutable_pending_component_and_actual_style_response");
            result["source34_equal_source_reader_reload"] = await window.CheckEqualSourceReaderReloadForSmoke((name, value) => Observe(output, name, value)); checks.Add("source34_equal_source_actual_owned_nonzero_cell_continuation_body_payload_ranges_pagers_and_hosts_retained_through_programmatic_same_query_reload_en_ko_no_mounted_mode_claim");
            result["workbook_edge_and_cell_clipping"] = await window.CheckGridEdgesAndClippingForSmoke(async name => { await Tick(window); Screenshot(window, Path.Combine(output, "workbook-grid-" + name + ".png")); }, (name, value) => Observe(output, "workbook-grid-" + name, value)); checks.Add("native_go_XFD1_A1048576_XFD1048576_keeps_strict_requested_50_by_8_scope_with_valid_bounded_tail_shape_and_1024px_en_ko_exact_literal_value_clipping_formula_only_partial_annotation");
            checks.Add("synthetic_native_cell_details_field_labels_distinguish_complete_empty_string_empty_partial_fragment_and_independent_formula_truncation_en_ko_disabled_navigation_cannot_reenable_source_route");
            result["source31_paired_raw_mode_continuation"] = await window.CheckPairedRawModeContinuationForSmoke((name, value) => Observe(output, name, value), async name => { await Tick(window); Screenshot(window, Path.Combine(output, name + ".png")); }); checks.Add("source31_actual_event_derived_moved_physical_pair_nonzero_raw_continuation_retained_both_modes_en_ko_neutral_old_event_retired_native_viewports_and_exact_query_failure_retry_fixed_cell_First_Next_unavailable_side");
            result["source36_query_failure_retention"] = await window.CheckQueryFailureRetentionForSmoke((name, value) => Observe(output, name, value)); checks.Add("source36_actual_native_arrow_no_detail_manual_grid_scroll_method_query_failure_and_owned_raw_pagination_failure_exact_scoped_Retry_preserve_selectors_grid_raw_scope_hosts_rows_both_scroll_axes_and_source_query_counts");
            result["source28_raw_mode_continuation"] = await window.CheckSource28RawModeContinuationForSmoke((name, value) => Observe(output, name, value)); checks.Add("source28_actual_long_D4_raw_formula_first_next_UTF16_continuation_reader_and_native_grid_viewports_preserved_across_both_query_modes_without_physical_reacquisition");
            result["source27_native_presentation"] = await window.CheckSource27PresentationForSmoke(async name => { await Tick(window); Screenshot(window, Path.Combine(output, name + ".png")); }, (name, value) => Observe(output, name, value)); checks.Add("source30_native_physical_headers_scope_matched_Evidence_action_captions_single_Evidence_raw_reader_available_window_geometry_exact_narrow_dock_Evidence_close_saved_layout_query_hosts_source_en_ko_wide_coverage_explicit");
            checks.Add("source34_actual_native_header_OnClick_preserves_physical_row_order_without_sort_state_and_repeated_cell_focus_reuses_two_styles_with_native_resize_parts");
            JsonElement backup = default;
            async Task Corrupt() { backup = await IndexControl(bridge, output, new { operation = "corrupt", report_id = window.ReportId, revision = window.Before.RevisionId, sheet = window.Before.SheetId, row = window.Before.SelectedRow, column = window.Before.SelectedColumn }); }
            async Task Restore() { if (backup.ValueKind != JsonValueKind.Undefined) await IndexControl(bridge, output, new { operation = "restore", backup }); }
            await window.Before.GoForSmoke("D4");
            result["failed_raw_continuation"] = await window.CheckFailedDetailForSmoke(Corrupt, Restore, (name, value) => Observe(output, name, value)); checks.Add("failed_raw_continuation_removes_authority_and_scoped_first_retry");
            await window.SelectSourcePairForSmoke(0, 2); await window.CheckIntermediateEventForSmoke(); await window.Before.GoForSmoke("B2");
            await window.CheckFailedGridForSmoke(Corrupt, Restore); checks.Add("failed_B2_grid_clears_authority_and_retries_exact_event_pair_window_and_separate_interval");
            await window.SelectSourcePairForSmoke(0, 1); await window.Before.GoForSmoke("B2");
            await window.CheckAnalysisCancellationForSmoke(); checks.Add("actual_analysis_during_pending_read_busy_evidence_blocked_cancel_restores_scope");
            await window.CheckPostCommitAdmissionForSmoke(); checks.Add("post_commit_refresh_retains_single_writer_rejects_nested_analysis_import_and_owns_cancel");
            var priorReport = window.ReportId; var stageFolder = Path.Combine(bridge.Library, "workbook-staging-v1"); var stageBackup = stageFolder + ".smoke-preserved"; var hadStageFolder = Directory.Exists(stageFolder); if (hadStageFolder) Directory.Move(stageFolder, stageBackup);
            try { await File.WriteAllTextAsync(stageFolder, "Synthetic staging failure control"); try { await window.AnalyzeForSmoke(); throw new InvalidOperationException("Blocked staging path unexpectedly completed analysis."); } catch (BridgeException) { } Require(window.ReportId == priorReport && window.ComparisonState == "ready" && window.DetailText != window.Copy["loading"], "Failed analysis did not restore the prior fixed comparison"); } finally { if (File.Exists(stageFolder)) File.Delete(stageFolder); if (hadStageFolder) Directory.Move(stageBackup, stageFolder); }
            checks.Add("actual_analysis_failure_restores_exact_fixed_comparison");
            await CheckLayout(window, checks, output, "workbook"); window.CheckChangeCaptionLanguageForSmoke(); checks.Add("workbook_existing_native_change_captions_locally_translate_preserving_row_selection_mode_interval_and_source");
            result["workbook_temporary_focus"] = await window.CheckTemporaryFocusForSmoke(); checks.Add("workbook_native_temporary_focus_toggle_retains_custom_geometry_panel_intent_saves_retained_layout_and_visibility_preset_saved_reset_routes_preserve_hosts_sources_other_workspace");
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
        else { await Tick(window); foreach (var pane in new[] { window.Before, window.After }) { pane.GridScroll?.ScrollToVerticalOffset(6); pane.GridScroll?.ScrollToHorizontalOffset(80); } await Tick(window); foreach (var pane in new[] { window.Before, window.After }) Require(pane.GridScroll?.HorizontalOffset > 0 && pane.GridScroll.VerticalOffset > 0, "Frozen-coordinate control requires actual nonzero horizontal and vertical manual scrolling."); }
        var before = window.Before.Host; var after = window.After.Host; var sidebar = window.SidebarPane; var inspector = window.InspectorPane; var changePane = window.ChangesPane;
        var report = window.ReportId; var beforeVersion = window.Before.RevisionId; var afterVersion = window.After.RevisionId; var page = window.Before.PageId; var row = window.Before.SelectedRow; var column = window.Before.SelectedColumn; var zoom = window.Before.PageImage.LayoutTransform.Value;
        var nativeRows = window.Before.Cells.ItemsSource; var sourceImage = window.Before.PageImage.Source;
        var layouts = new[]
        {
            (Name: "source-first", Layout: WorkspaceLayout.Preset("sourceFirst")),
            (Name: "focus", Layout: WorkspaceLayout.Preset("focus")),
            (Name: "review", Layout: WorkspaceLayout.Preset("review")),
            (Name: "changes-left", Layout: WorkspaceLayout.Preset("balanced") with { Changes = "left", Sidebar = false, Inspector = false }),
            (Name: "changes-right", Layout: WorkspaceLayout.Preset("balanced") with { Changes = "right", Sidebar = false, Inspector = false }),
            (Name: "vertical", Layout: WorkspaceLayout.Preset("focus") with { VerticalComparison = true }),
            (Name: "balanced", Layout: WorkspaceLayout.Preset("balanced"))
        };
        foreach (var preset in layouts)
        {
            var positions = new[] { window.Before, window.After }.Select(pane => { var scroll = window.IsWorkbook ? pane.GridScroll! : pane.PageScroll; return (scroll.HorizontalOffset, scroll.VerticalOffset); }).ToArray();
            window.SetLayout(preset.Layout); await Tick(window);
            Require(ReferenceEquals(before, window.Before.Host) && ReferenceEquals(after, window.After.Host) && ReferenceEquals(sidebar, window.SidebarPane) && ReferenceEquals(inspector, window.InspectorPane) && ReferenceEquals(changePane, window.ChangesPane), "Layout recreated a retained pane");
            Require(window.ReportId == report && window.Before.RevisionId == beforeVersion && window.After.RevisionId == afterVersion && window.Before.PageId == page && window.Before.SelectedRow == row && window.Before.SelectedColumn == column, "Layout changed report/version/page/grid state");
            Require(ReferenceEquals(nativeRows, window.Before.Cells.ItemsSource) && ReferenceEquals(sourceImage, window.Before.PageImage.Source) && window.Before.PageImage.LayoutTransform.Value == zoom, "Layout recreated native content or lost zoom");
            for (var index = 0; index < 2; index++) { var pane = index == 0 ? window.Before : window.After; var scroll = window.IsWorkbook ? pane.GridScroll! : pane.PageScroll; Require(Math.Abs(scroll.HorizontalOffset - Math.Min(positions[index].HorizontalOffset, scroll.ScrollableWidth)) <= 1 && Math.Abs(scroll.VerticalOffset - Math.Min(positions[index].VerticalOffset, scroll.ScrollableHeight)) <= 1, "Native viewport changed beyond its measured scrollable clamp"); }
            if (preset.Name is "focus" or "changes-left" or "changes-right" or "vertical" || window.IsWorkbook && preset.Name is "review" or "balanced") Screenshot(window, Path.Combine(output, name + "-layout-" + preset.Name + ".png"));
            if (!window.IsWorkbook) Require(window.Before.Zoom == 1.5, "Layout reset user zoom");
            else
            {
                Task Observe(string side, object geometry) => File.WriteAllTextAsync(Path.Combine(output, name + "-frozen-observed-" + preset.Name + "-" + side + ".json"), JsonSerializer.Serialize(geometry, new JsonSerializerOptions { WriteIndented = true }));
                var coordinates = new { before = await window.Before.CheckFrozenCoordinatesForSmoke(geometry => Observe("before", geometry)), after = await window.After.CheckFrozenCoordinatesForSmoke(geometry => Observe("after", geometry)) };
                await File.WriteAllTextAsync(Path.Combine(output, name + "-frozen-coordinates-" + preset.Name + ".json"), JsonSerializer.Serialize(coordinates, new JsonSerializerOptions { WriteIndented = true }));
            }
        }
        checks.Add(name + "_actual_focus_left_right_vertical_native_layout_captures_preserve_report_hosts_source_and_viewport");
        if (window.IsWorkbook) checks.Add("native_frozen_row_numbers_remain_visible_correct_after_manual_xy_scroll_all_layouts_and_physical_stored_cell_queries");
        var customized = window.Layout with { Changes = "right", InspectorSide = "left", VerticalComparison = true, Sidebar = false, ComparisonRatio = .62 };
        window.SetLayout(customized); window.Preferences.For(window.IsWorkbook).Named["smoke saved"] = window.Layout; window.SavePreferences(); var expected = window.Layout;
        window.SetLayout(new()); window.Preferences.For(window.IsWorkbook).Current = window.Preferences.For(window.IsWorkbook).Named["smoke saved"]; window.ApplyLayout(); window.ReloadPreferencesForSmoke();
        Require(window.Layout == expected && window.Preferences.For(window.IsWorkbook).Named.ContainsKey("smoke saved"), "Saved layout did not reload");
        Require(window.ReportId == report && window.Before.PageId == page && window.Before.SelectedRow == row, "Preference reload changed source scope");
        checks.Add(name + "_all_presets_retained_native_pane_and_state"); checks.Add(name + "_custom_docking_named_save_apply_reload"); window.CheckLayoutDialogForSmoke(); checks.Add(name + "_production_named_layout_save_cancel_apply_and_exclusive_language_menus");
        var preferred = window.Layout; var wide = window.Width; window.Width = 1000; await Tick(window); Require(window.Layout == preferred, "Narrow layout overwrote user preferred dimensions"); window.Width = wide; await Tick(window); Require(window.Layout == preferred, "Widening failed to retain preferred dimensions"); checks.Add(name + "_narrow_window_preserves_preferred_layout");
        window.SetLayout(WorkspaceLayout.Preset("balanced")); await Tick(window); Screenshot(window, Path.Combine(output, name + "-balanced.png"));
        foreach (var splitter in window.NativeSplitters()) Require(!string.IsNullOrWhiteSpace(AutomationProperties.GetName(splitter)), "An active native splitter lacks an accessibility name");
        var ratio = window.Layout.ComparisonRatio; var divider = window.NativeSplitters().First(s => s.Tag as string == "resizeComparison"); var presentation = PresentationSource.FromVisual(divider) ?? throw new InvalidOperationException("Native splitter is not attached"); divider.Focus();
        object DividerGeometry() { var parent = (Grid)divider.Parent; return new { arranged_before = parent.ColumnDefinitions[0].ActualWidth, arranged_after = parent.ColumnDefinitions[2].ActualWidth, definition_before = parent.ColumnDefinitions[0].Width.ToString(), definition_after = parent.ColumnDefinitions[2].Width.ToString(), saved_ratio = window.Layout.ComparisonRatio }; }
        var keyboardBefore = DividerGeometry(); divider.RaiseEvent(new KeyEventArgs(Keyboard.PrimaryDevice, presentation, Environment.TickCount, Key.Right) { RoutedEvent = Keyboard.KeyDownEvent }); divider.RaiseEvent(new KeyEventArgs(Keyboard.PrimaryDevice, presentation, Environment.TickCount, Key.Right) { RoutedEvent = Keyboard.KeyUpEvent }); await Tick(window); await File.WriteAllTextAsync(Path.Combine(output, name + "-keyboard-resize.json"), JsonSerializer.Serialize(new { before = keyboardBefore, after = DividerGeometry() }, new JsonSerializerOptions { WriteIndented = true }));
        Require(Math.Abs(window.Layout.ComparisonRatio - ratio) > .001, "Native keyboard splitter resize did not persist"); Require(AppPreferences.Load(window.PreferencesPath).For(window.IsWorkbook).Current.ComparisonRatio == window.Layout.ComparisonRatio, "Keyboard splitter ratio was not saved"); checks.Add(name + "_named_native_splitters_and_keyboard_resize_persistence");
        window.SetLayout(WorkspaceLayout.Preset("balanced")); var oldWidth = window.Width; var oldHeight = window.Height; window.Width = 1024; window.Height = 768; await Tick(window);
        await window.CheckNarrowSidebarForSmoke(); await Tick(window); checks.Add(name + "_narrow_native_layout_menu_sidebar_toggle_and_existing_project_access");
        var compactHeader = await window.CheckCompactHeaderForSmoke(); await Tick(window);
        checks.Add(name + "_narrow_en_ko_single_row_toolbar_and_native_evidence_menu_toggle_preserve_source_and_saved_dimensions");
        object Measurements() => new { actual_window_width = window.ActualWidth, actual_window_height = window.ActualHeight, before_width = window.Before.Host.ActualWidth, before_height = window.Before.Host.ActualHeight, before_grid_height = window.Before.Cells.ActualHeight, before_grid_visible_rows = window.Before.GridScroll?.ViewportHeight, after_width = window.After.Host.ActualWidth, after_height = window.After.Host.ActualHeight, after_grid_height = window.After.Cells.ActualHeight, after_grid_visible_rows = window.After.GridScroll?.ViewportHeight };
        var narrow = Measurements();
        // Preserve the actual failing geometry and pixels before asserting. A
        // runtime failure must leave evidence, not only the previous wide view.
        await File.WriteAllTextAsync(Path.Combine(output, name + "-narrow-viewport-observed.json"), JsonSerializer.Serialize(new { narrow, compact_header = compactHeader }, new JsonSerializerOptions { WriteIndented = true }));
        Screenshot(window, Path.Combine(output, name + "-1024x768.png"));
        if (window.IsWorkbook)
        {
            Require(window.Before.Cells.ActualHeight >= 150 && window.After.Cells.ActualHeight >= 150, "Balanced 1024x768 native grids have insufficient visible height");
            Require(window.Before.GridScroll?.ViewportHeight >= 5 && window.After.GridScroll?.ViewportHeight >= 5, "Balanced 1024x768 native grids do not show at least five source rows");
            Require(window.Before.Cells.ActualWidth >= 180 && window.After.Cells.ActualWidth >= 180, "Balanced source panes do not retain useful native grid width");
        }
        window.Width = oldWidth; window.Height = oldHeight; await Tick(window); await File.WriteAllTextAsync(Path.Combine(output, name + "-viewport-measurements.json"), JsonSerializer.Serialize(new { narrow, available_wide = Measurements() }, new JsonSerializerOptions { WriteIndented = true }));
        var savedLayout = window.Layout; var heightBefore = window.Height; var actualWidth = window.ActualWidth;
        var preferredHeight = Math.Clamp(window.WorkspaceHeightForSmoke - 260, 150, 400); window.SetLayout(window.Layout with { Changes = "bottom", ChangesVisible = true, Inspector = false, ChangesHeight = preferredHeight }); await Tick(window);
        var layoutIntent = window.Layout; var preferenceBytes = await File.ReadAllBytesAsync(window.PreferencesPath); var tallHeight = window.ChangesPane.ActualHeight; var heightSourceA = window.Before.CaptureSelection(); var heightSourceB = window.After.CaptureSelection();
        // CheckNarrowSidebarForSmoke intentionally opens the fixed report again.
        // The height-only contract begins here, after that source installation.
        var heightHostA = window.Before.Host; var heightHostB = window.After.Host; var heightRowsA = window.Before.Cells.ItemsSource; var heightRowsB = window.After.Cells.ItemsSource; var heightImageA = window.Before.PageImage.Source; var heightImageB = window.After.PageImage.Source; var heightRawA = window.Before.RawIdentityForSmoke; var heightRawB = window.After.RawIdentityForSmoke; var heightQuery = window.QueryIdentityForSmoke;
        Dictionary<string, bool> HeightRetention() => new()
        {
            ["before_physical_selection"] = heightSourceA == window.Before.CaptureSelection(), ["after_physical_selection"] = heightSourceB == window.After.CaptureSelection(),
            ["before_native_host"] = ReferenceEquals(heightHostA, window.Before.Host), ["after_native_host"] = ReferenceEquals(heightHostB, window.After.Host),
            ["before_native_rows"] = ReferenceEquals(heightRowsA, window.Before.Cells.ItemsSource), ["after_native_rows"] = ReferenceEquals(heightRowsB, window.After.Cells.ItemsSource),
            ["before_native_image"] = ReferenceEquals(heightImageA, window.Before.PageImage.Source), ["after_native_image"] = ReferenceEquals(heightImageB, window.After.PageImage.Source),
            ["before_exact_raw_scope"] = heightRawA == window.Before.RawIdentityForSmoke, ["after_exact_raw_scope"] = heightRawB == window.After.RawIdentityForSmoke, ["fixed_query_and_raw_detail"] = heightQuery == window.QueryIdentityForSmoke
        };
        object HeightPlacement() => new { requested_window_width = window.Width, actual_window_width = window.ActualWidth, requested_window_height = window.Height, actual_window_height = window.ActualHeight, workspace_width = window.WorkspaceWidthForSmoke, workspace_height = window.WorkspaceHeightForSmoke, temporary_evidence_bottom_dock = window.EvidenceBottomDockForSmoke, inspector_visible = window.InspectorPane.IsVisible, changes_height = window.ChangesPane.ActualHeight, expected_preferred_bottom_changes_height = window.EffectiveChangesHeightForSmoke, before_height = window.Before.Host.ActualHeight, after_height = window.After.Host.ActualHeight };
        var tallPlacement = HeightPlacement(); window.Height = 640; await Tick(window); var shortHeight = window.ChangesPane.ActualHeight; var shortPlacement = HeightPlacement(); var shortRetention = HeightRetention(); window.Height = heightBefore; await Tick(window); var restoredPlacement = HeightPlacement();
        var restoredPreferenceBytes = await File.ReadAllBytesAsync(window.PreferencesPath); var restoredRetention = HeightRetention();
        await File.WriteAllTextAsync(Path.Combine(output, name + "-height-restore-observed.json"), JsonSerializer.Serialize(new { scope = "Preferred bottom Changes height with Evidence closed; the temporary responsive Evidence row has its own geometry contract", preferred_height = preferredHeight, layout_intent = layoutIntent, tall = tallPlacement, short_window = shortPlacement, restored = restoredPlacement, preference_bytes_unchanged = preferenceBytes.SequenceEqual(restoredPreferenceBytes), source_selections_unchanged = heightSourceA == window.Before.CaptureSelection() && heightSourceB == window.After.CaptureSelection(), stage_local_baseline = new { before = heightSourceA, after = heightSourceB, raw_before = heightRawA, raw_after = heightRawB, query = heightQuery }, short_retention = shortRetention, restored_retention = restoredRetention, native_hosts_and_content_retained = restoredRetention.Values.All(value => value) }, new JsonSerializerOptions { WriteIndented = true }));
        Require(!window.InspectorPane.IsVisible && !window.EvidenceBottomDockForSmoke && !layoutIntent.Inspector, "Pure preferred Changes-height qualification accidentally used the temporary responsive Evidence row");
        foreach (var field in shortRetention) Require(field.Value, "Height-only shrink changed " + field.Key);
        foreach (var field in restoredRetention) Require(field.Value, "Height-only expansion changed " + field.Key);
        Require(window.Layout == layoutIntent && preferenceBytes.SequenceEqual(restoredPreferenceBytes), "Height-only temporary clamp changed persisted preferred layout intent");
        Require(Math.Abs(window.ActualWidth - actualWidth) <= 1 && Math.Abs(window.ChangesPane.ActualHeight - window.EffectiveChangesHeightForSmoke) <= 2 && Math.Abs(window.ChangesPane.ActualHeight - tallHeight) <= 2 && window.ChangesPane.ActualHeight > shortHeight + 5, "Height-only expansion did not restore the effective preferred bottom changes height");
        Require(window.Before.Host.ActualHeight >= 100 && window.After.Host.ActualHeight >= 100 && window.Layout.ComparisonRatio == layoutIntent.ComparisonRatio, "Height-only resize lost comparison geometry or source visibility");
        await File.WriteAllTextAsync(Path.Combine(output, name + "-height-restore.json"), JsonSerializer.Serialize(new { preferred_height = preferredHeight, actual_width = window.ActualWidth, actual_window_height = window.ActualHeight, initial_effective_height = tallHeight, short_height = shortHeight, restored_height = window.ChangesPane.ActualHeight, effective_expected_height = window.EffectiveChangesHeightForSmoke, preference_bytes_unchanged = true })); window.SetLayout(savedLayout); await Tick(window); checks.Add(name + "_height_only_shrink_expand_restores_bottom_changes_without_rewriting_preferred_bytes");
        if (window.IsWorkbook && window.ActualHeight >= 900) Require(window.Before.GridScroll?.ViewportHeight >= 9 && window.After.GridScroll?.ViewportHeight >= 9, "Wide native grids do not show nine source rows"); checks.Add(name + "_source_viewport_visible_at_1024x768_and_available_wide_bounds");
    }
    private static async Task Tick(MainWindow window) { window.UpdateLayout(); await window.Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle); }
    private static Task Observe(string output, string name, object value) => File.WriteAllTextAsync(Path.Combine(output, name + ".json"), JsonSerializer.Serialize(value, new JsonSerializerOptions { WriteIndented = true }));
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
        await File.WriteAllTextAsync(script, "const fs=require('node:fs');const {DatabaseSync}=require('node:sqlite');const q=JSON.parse(fs.readFileSync(0,'utf8'));const db=new DatabaseSync(require('node:path').join(process.argv[2],'docver.sqlite'));try{if(q.operation==='counts'){process.stdout.write(JSON.stringify({runs:db.prepare('SELECT project_id,status,count(*) AS total FROM runs GROUP BY project_id,status ORDER BY project_id,status').all(),workbook_runs:db.prepare('SELECT project_id,status,count(*) AS total FROM workbook_runs_v1 GROUP BY project_id,status ORDER BY project_id,status').all(),reports:db.prepare('SELECT project_id,count(*) AS total FROM reports GROUP BY project_id ORDER BY project_id').all(),workbook_reports:db.prepare('SELECT project_id,count(*) AS total FROM workbook_reports_v1 GROUP BY project_id ORDER BY project_id').all()}));}else if(q.operation==='report_digest'){const r=db.prepare('SELECT body FROM reports WHERE id=? AND project_id=?').get(q.report_id,q.project_id);if(!r)throw Error('Missing owned fixed document report');process.stdout.write(JSON.stringify({sha256:require('node:crypto').createHash('sha256').update(String(r.body)).digest('hex')}));}else if(q.operation==='corrupt'){const r=db.prepare('SELECT rowid,body,body_sha FROM workbook_cells_v1 WHERE report_id=? AND revision_occurrence_id=? AND sheet_id=? AND row=? AND col=?').get(q.report_id,q.revision,q.sheet,q.row,q.column);if(!r)throw Error('Missing owned indexed control');db.prepare('UPDATE workbook_cells_v1 SET body=? WHERE rowid=?').run('corrupt synthetic control',r.rowid);process.stdout.write(JSON.stringify(r));}else{const r=q.backup;db.prepare('UPDATE workbook_cells_v1 SET body=?,body_sha=? WHERE rowid=?').run(r.body,r.body_sha,r.rowid);process.stdout.write('{}');}}finally{db.close();}\n");
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
