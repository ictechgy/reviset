import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

test('actual PDFKit navigation cannot detach the displayed page from the selected evidence page', { skip: process.platform !== 'darwin' }, async () => {
  const root = await mkdtemp(join(tmpdir(), 'reviset-pdf-ownership-'));
  try {
    const executable = join(root, 'probe');
    const build = spawnSync('swiftc', ['-warnings-as-errors', '-swift-version', '5', '-parse-as-library', '-target', 'arm64-apple-macos14.0', 'apps/macos/Bridge.swift', 'apps/macos/Model.swift', 'apps/macos/DocumentView.swift', 'tests/native/PDFPageOwnership.swift', '-o', executable, '-framework', 'SwiftUI', '-framework', 'AppKit', '-framework', 'PDFKit'], { encoding: 'utf8', timeout: 30000 });
    assert.ifError(build.error); assert.equal(build.status, 0, build.stderr);
    const run = spawnSync(executable, [], { cwd: '/', encoding: 'utf8', timeout: 15000, env: { PATH: '/usr/bin:/bin', DOCVER_TEST_USER_DATA: join(root, 'userdata') } });
    assert.ifError(run.error); assert.equal(run.status, 0, run.stdout + run.stderr);
    assert.match(run.stdout, /PASS production PDFKit page ownership/);
  } finally { await rm(root, { recursive: true, force: true }); }
});
