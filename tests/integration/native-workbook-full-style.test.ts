import {nativeLocalizationTestSources,prepareLegacyNativeLocalization} from '../../scripts/native-swift-sources.js';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,writeFile,copyFile,symlink,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {execFileSync} from 'node:child_process';
import {build} from 'esbuild';
import {Store} from '../../packages/storage/index.js';
import {WorkbookService} from '../../packages/workbook/service.js';
import {WorkbookQueryService} from '../../packages/workbook/query.js';
import {xlsxFixture,excelDefaultStyles} from '../workbook-fixtures.js';

test('native full style reader separates property cursors and text continuations on a fixed physical source', {skip:process.platform!=='darwin'||process.arch!=='arm64',timeout:65000},async()=>{
  const root=await mkdtemp(join(tmpdir(),'reviset-workbook-style-'));
  try {
    const contents=join(root,'Probe.app/Contents'),exe=join(contents,'MacOS/Probe'),library=join(root,'isolated-library');
    for(const path of ['MacOS','Helpers','Resources/backend'])await mkdir(join(contents,path),{recursive:true});
    await mkdir(library);
    await prepareLegacyNativeLocalization(join(contents,'Resources'));
    await writeFile(join(contents,'Info.plist'),'<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>Probe</string><key>CFBundleIdentifier</key><string>org.reviset.style-probe</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>');
    await symlink(process.execPath,join(contents,'Helpers/node'));
    execFileSync('swiftc',['-warnings-as-errors','-swift-version','5','-parse-as-library','-target','arm64-apple-macos14.0',...nativeLocalizationTestSources,'apps/macos/Bridge.swift','apps/macos/Model.swift','apps/macos/WorkbookView.swift','tests/native/WorkbookFullStyle.swift','-o',exe,'-framework','SwiftUI','-framework','AppKit'],{timeout:45000,stdio:'pipe'});
    const actualLibrary=join(root,'actual-library'),store=new Store(actualLibrary),service=new WorkbookService(store);
    try {
      const inputs=[];
      for(const [index,font]of ['Calibri','Arial'].entries()) {
        const path=join(root,index+'.xlsx');await writeFile(path,xlsxFixture('<sheetData><row r="1"><c r="A1"><v>1</v></c></row></sheetData>',{styles:excelDefaultStyles.replace('Calibri',font)}));inputs.push({path,label:font});
      }
      const draft=await service.create('Independent font source',inputs),stage=await service.run(draft.project_id);await service.commit(draft.project_id,stage);
      const report=service.report(draft.project_id,stage.report_id),query=new WorkbookQueryService(service,new Set([draft.project_id]));
      assert.ok(report.changes.some(change=>change.kind==='style'&&change.before_address==='A1'));
      const source:Record<string,unknown>={project:draft.project_id,report:report.report_id};
      for(const [index,revision]of report.revisions.entries()) {
        const sheet=revision.sheets[0],args={project_id:draft.project_id,report_id:report.report_id,revision_occurrence_id:revision.revision_occurrence_id,sheet_id:sheet.sheet_id,row:1,column:1,max_output_tokens:8000};
        const preview=await query.query('get_workbook_cell',args),full=await query.query('get_workbook_cell',{...args,component:'style',limit:200,text_length:4096});
        assert.equal(full.items[8].key,'font.name.@val');assert.equal(full.items[8].value,index===0?'Calibri':'Arial');
        source[index===0?'old':'new']={occurrence:revision.revision_occurrence_id,sheet:sheet.sheet_id,style:Object.fromEntries(full.items.map((item:any)=>[item.key,item.value]))};
        source.total=full.total;source.font_key=full.items[8].key;source[index===0?'old_preview':'new_preview']=preview.items[0].style;
      }
      assert.deepEqual(source.old_preview,source.new_preview,'font change must reproduce indistinguishable four-property previews');
      await writeFile(join(actualLibrary,'style-source.json'),JSON.stringify(source));
    }finally{store.close();}
    await build({entryPoints:['apps/bridge/main.ts'],outfile:join(contents,'Resources/backend/bridge.mjs'),bundle:true,format:'esm',platform:'node',packages:'external',target:'node24'});
    await symlink(resolve('node_modules'),join(contents,'Resources/backend/node_modules'));
    const evidence=process.env.DOCVER_TEST_STYLE_EVIDENCE_OUT;
    const actual=execFileSync(exe,[],{encoding:'utf8',timeout:18000,env:{PATH:'/usr/bin:/bin',DOCVER_TEST_USER_DATA:actualLibrary,DOCVER_TEST_STYLE_REAL:'1',...(evidence?{DOCVER_TEST_STYLE_EVIDENCE_OUT:join(evidence,'actual-xlsx')}:{})}});
    assert.match(actual,/PASS actual XLSX full style:/);
    await copyFile(resolve('tests/native/workbook-style-fixture.mjs'),join(contents,'Resources/backend/bridge.mjs'));
    const output=execFileSync(exe,[],{encoding:'utf8',timeout:18000,env:{PATH:'/usr/bin:/bin',DOCVER_TEST_USER_DATA:library,...(process.env.DOCVER_TEST_STYLE_EVIDENCE_OUT?{DOCVER_TEST_STYLE_EVIDENCE_OUT:process.env.DOCVER_TEST_STYLE_EVIDENCE_OUT}:{})}});
    assert.match(output,/PASS native full style:/);
  } finally {await rm(root,{recursive:true,force:true});}
});
