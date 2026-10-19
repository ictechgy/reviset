import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {execFileSync} from 'node:child_process';

test('actual native SwiftUI split initializes at140 and remembers four divider changes through hide/reopen',{skip:process.platform!=='darwin',timeout:35_000},async()=>{
  const root=await mkdtemp(join(tmpdir(),'docver-workspace-geometry-'));
  try {
    const binary=join(root,'probe');
    execFileSync('swiftc',['-swift-version','5','-warnings-as-errors','-O','-parse-as-library','-target','arm64-apple-macos14.0','apps/macos/WorkspaceSplit.swift','tests/native/WorkspaceGeometry.swift','-o',binary,'-framework','SwiftUI','-framework','AppKit'],{timeout:25_000,stdio:'pipe'});
    const output=execFileSync(binary,[],{timeout:8000,encoding:'utf8',env:{...process.env,DOCVER_TEST_USER_DATA:root}});
    assert.match(output,/PASS native actual embedded default140 \+4 divider\/hide\/reopen cycles/);
  }finally{await rm(root,{recursive:true,force:true});}
});
