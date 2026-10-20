import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {execFileSync} from 'node:child_process';

test('superseded native range requests terminate only their own child and preserve unrelated calls',{skip:process.platform!=='darwin',timeout:30_000},async()=>{
  const root=await mkdtemp(join(tmpdir(),'docver-query-cancel-'));
  try {
    const binary=join(root,'probe');
    execFileSync('swiftc',['-swift-version','5','-O','-parse-as-library','apps/macos/Bridge.swift','tests/native/QueryCancellation.swift','-o',binary],{timeout:20_000,stdio:'pipe'});
    const output=execFileSync(binary,[join(root,'app'),process.execPath,resolve('tests/native/query-fixture.mjs')],{timeout:7000,encoding:'utf8'});
    assert.match(output,/PASS 7:/);
  } finally {await rm(root,{recursive:true,force:true});}
});
