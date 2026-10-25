import {nativeLocalizationTestSources,prepareLegacyNativeLocalization} from '../../scripts/native-swift-sources.js';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,writeFile,readFile,copyFile,symlink,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {execFileSync} from 'node:child_process';

test('native workbook retries preserve scope and withhold mismatched cell evidence', {skip:process.platform!=='darwin'||process.arch!=='arm64',timeout:60000},async()=>{
  const root=await mkdtemp(join(tmpdir(),'docver-workbook-reads-'));
  try {
  await prepareLegacyNativeLocalization(join(root,'Probe.app/Contents/Resources'));
    const contents=join(root,'Probe.app/Contents'),exe=join(contents,'MacOS/Probe');
    for(const folder of ['MacOS','Helpers','Resources/backend','userdata']) await mkdir(join(contents,folder),{recursive:true});
    await writeFile(join(contents,'Info.plist'),'<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>Probe</string><key>CFBundleIdentifier</key><string>org.docver.workbook-reads</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>');
    await symlink(process.execPath,join(contents,'Helpers/node'));
    await copyFile(resolve('tests/native/workbook-read-fixture.mjs'),join(contents,'Resources/backend/bridge.mjs'));
    const userData=join(contents,'userdata');
    execFileSync('swiftc',['-warnings-as-errors','-swift-version','5','-parse-as-library','-target','arm64-apple-macos14.0',...nativeLocalizationTestSources,'apps/macos/Bridge.swift','apps/macos/Model.swift','apps/macos/WorkbookView.swift','tests/native/WorkbookReads.swift','-o',exe,'-framework','SwiftUI','-framework','AppKit'],{timeout:45000,stdio:'pipe'});
    const stdout=execFileSync(exe,[],{encoding:'utf8',timeout:18000,env:{PATH:'/usr/bin:/bin',DOCVER_TEST_USER_DATA:userData,...(process.env.DOCVER_TEST_WORKBOOK_PAGED_SELECTION_EVIDENCE_OUT?{DOCVER_TEST_WORKBOOK_PAGED_SELECTION_EVIDENCE_OUT:process.env.DOCVER_TEST_WORKBOOK_PAGED_SELECTION_EVIDENCE_OUT}:{}),...(process.env.DOCVER_TEST_WORKBOOK_MODE_INTERVAL_EVIDENCE_OUT?{DOCVER_TEST_WORKBOOK_MODE_INTERVAL_EVIDENCE_OUT:process.env.DOCVER_TEST_WORKBOOK_MODE_INTERVAL_EVIDENCE_OUT}:{})}});
    assert.match(stdout,/PASS native workbook reads:/);
    assert.match(stdout,/PASS native workbook paged selection:/);
    const proof=JSON.parse(await readFile(join(userData,'paged-selection-proof.json'),'utf8')) as Record<string,unknown>;
    assert.equal(proof.first_success_selects_first_eligible_valid_revision_and_address,true);
    assert.equal(proof.same_scope_next_previous_refresh_keep_selected_off_page_event_and_source,true);
    assert.equal(proof.off_page_return_retains_list_cursor_and_query,true);
    assert.equal(proof.visible_mutated_event_and_unqualified_list_replacement_rejected,true);
    assert.equal(proof.comparison_method_failure_retry_preserves_physical_sources_without_autoselection,true);
    assert.match(stdout,/PASS native workbook method interval:/);
    const method=JSON.parse(await readFile(join(userData,'method-interval-proof.json'),'utf8')) as Record<string,unknown>;
    for(const key of ['selected_intermediate_source_preserved_across_method_toggles','manual_browse_preserved_across_method_toggles','failed_method_then_default_retry_does_not_reselect','range_net_limit_fallback_keeps_sources_and_wide_interval','method_actions_issue_only_list_requests','distinct_before_after_exact_utf16_verified','explicit_new_version_query_still_auto_selects']) assert.equal(method[key],true,key);
  } finally { await rm(root,{recursive:true,force:true}); }
});
