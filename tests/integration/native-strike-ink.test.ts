import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';

test('native raster strikes require ink independent of a glyph crossbar', {skip:process.platform!=='darwin'}, async()=>{
  const folder=await mkdtemp(join(tmpdir(),'reviset-strike-ink-'));
  try {
    const binary=join(folder,'checks');
    execFileSync('/usr/bin/swiftc',['-warnings-as-errors','-swift-version','5','-O','-parse-as-library','-D','DOCVER_TEST','apps/helpers/Vision.swift','apps/helpers/Reconsideration.swift','tests/native/StrikeChecks.swift','-o',binary],{timeout:120_000});
    assert.match(execFileSync(binary,[],{encoding:'utf8',timeout:10_000}),/PASS 10 native strike ink separation controls/);
  } finally { await rm(folder,{recursive:true,force:true}); }
});
