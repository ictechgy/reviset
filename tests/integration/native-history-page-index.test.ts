import {nativeLocalizationTestSources,prepareLegacyNativeLocalization} from '../../scripts/native-swift-sources.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,readFile,rm,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {execFileSync} from 'node:child_process';

test('native history index preserves primary-page lineage labels, occurrence identity and split/merge order',{skip:process.platform!=='darwin',timeout:35_000},async()=>{
  const root=await mkdtemp(join(tmpdir(),'docver-history-index-'));
  try {
  await prepareLegacyNativeLocalization(root);
    // Compile the production projection without the unrelated SwiftUI screens.
    const views=await readFile('apps/macos/Views.swift','utf8');
    const graphStart=views.indexOf('struct HistoryGraphView:View {');
    const helperStart=views.indexOf('    struct PageIndex {',graphStart);
    const helperEnd=views.indexOf('    @EnvironmentObject var model:AppModel',helperStart);
    assert.ok(graphStart>=0 && helperStart>graphStart && helperEnd>helperStart,'HistoryGraphView page index must be present');
    const projection=join(root,'HistoryPageProjection.swift'),binary=join(root,'probe');
    await writeFile(projection,'import Foundation\n'+views.slice(helperStart,helperEnd));
    execFileSync('swiftc',['-swift-version','5','-warnings-as-errors','-parse-as-library','-target','arm64-apple-macos14.0',...nativeLocalizationTestSources,'apps/macos/Bridge.swift','apps/macos/Model.swift',projection,'tests/native/HistoryPageIndex.swift','-o',binary,'-framework','SwiftUI','-framework','AppKit'],{timeout:25_000,stdio:'pipe'});
    const output=execFileSync(binary,[],{timeout:5000,encoding:'utf8',env:{...process.env,DOCVER_TEST_USER_DATA:root}});
    assert.match(output,/PASS native history page index parity/);
  }finally{await rm(root,{recursive:true,force:true});}
});
