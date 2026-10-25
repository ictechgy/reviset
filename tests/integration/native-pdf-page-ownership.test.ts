import {nativeLocalizationTestSources,prepareLegacyNativeLocalization} from '../../scripts/native-swift-sources.js';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

test('actual PDFKit navigation cannot detach the displayed page from the selected evidence page', { skip: process.platform !== 'darwin' }, async () => {
  const root = await mkdtemp(join(tmpdir(), 'reviset-pdf-ownership-'));
  try {
  await prepareLegacyNativeLocalization(root);
    const executable = join(root, 'probe');
    const build = spawnSync('swiftc', ['-warnings-as-errors', '-swift-version', '5', '-parse-as-library', '-target', 'arm64-apple-macos14.0', ...nativeLocalizationTestSources,'apps/macos/Bridge.swift', 'apps/macos/Model.swift', 'apps/macos/DocumentView.swift', 'tests/native/PDFPageOwnership.swift', '-o', executable, '-framework', 'SwiftUI', '-framework', 'AppKit', '-framework', 'PDFKit'], { encoding: 'utf8', timeout: 30000 });
    assert.ifError(build.error); assert.equal(build.status, 0, build.stderr);
    const run = spawnSync(executable, [], { cwd: '/', encoding: 'utf8', timeout: 15000, env: { PATH: '/usr/bin:/bin', DOCVER_TEST_USER_DATA: join(root, 'userdata'), ...(process.env.DOCVER_TEST_PDF_CONTROLS_EVIDENCE_OUT ? {DOCVER_TEST_PDF_CONTROLS_EVIDENCE_OUT:process.env.DOCVER_TEST_PDF_CONTROLS_EVIDENCE_OUT}: {}) } });
    assert.ifError(run.error); assert.equal(run.status, 0, run.stdout + run.stderr);
    assert.match(run.stdout, /PASS production PDFKit page ownership/);
    assert.match(run.stdout, /PASS native PDF per-pane zoom controls/);
    const proof=JSON.parse(await readFile(join(root,'userdata/pdf-controls-proof.json'),'utf8')) as Record<string,unknown>;
    assert.equal(proof.native_per_pane_controls_visible_localized_and_performed,true);
    assert.equal(proof.other_pane_manual_zoom_and_viewport_retained,true);
    assert.equal(proof.passive_redraw_and_resize_retain_manual_zoom_and_viewports,true);
    assert.equal(proof.fixed_query_source_report_and_published_model_unchanged,true);
  } finally { await rm(root, { recursive: true, force: true }); }
});
