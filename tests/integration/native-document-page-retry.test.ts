import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,writeFile,symlink,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {execFileSync} from 'node:child_process';
import {nativeLocalizationTestSources,prepareLegacyNativeLocalization} from '../../scripts/native-swift-sources.js';

test('native single-page Retry repeats the same fixed source while retaining the other PDF host', {skip:process.platform!=='darwin'},async()=>{
  const root=await mkdtemp(join(tmpdir(),'reviset-page-retry-'));
  try {
    const contents=join(root,'Probe.app/Contents'),resources=join(contents,'Resources'),executable=join(contents,'MacOS/Probe');
    for(const folder of ['MacOS','Helpers','Resources/backend'])await mkdir(join(contents,folder),{recursive:true});
    await prepareLegacyNativeLocalization(resources);
    await writeFile(join(contents,'Info.plist'),'<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>Probe</string><key>CFBundleIdentifier</key><string>org.reviset.page-retry</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>');
    await symlink(process.execPath,join(contents,'Helpers/node'));
    await writeFile(join(resources,'backend/bridge.mjs'),`import{readFileSync,writeFileSync}from'node:fs';import{join}from'node:path';const {action,args}=JSON.parse(readFileSync(0,'utf8')),root=process.argv[process.argv.indexOf('--root')+1];if(action!=='page')throw Error('Unexpected action');let events=[];try{events=JSON.parse(readFileSync(join(root,'attempts.json'),'utf8'))}catch{}const fail=args.page_id==='left'&&!events.some(e=>e.page_id==='left');events.push(args);writeFileSync(join(root,'attempts.json'),JSON.stringify(events));console.log(JSON.stringify({protocol_version:'0.1.0',schema_version:'0.4.0',ok:!fail,...(fail?{error:{code:'CONTROLLED_TRANSIENT',message:'Controlled first-read failure'}}:{value:{page:{page_id:args.page_id,page:1,width:400,height:500,elements:[]},source:{kind:'pdf',origin:'original',path:join(root,'source.pdf')}}})}));`);
    execFileSync('swiftc',['-warnings-as-errors','-swift-version','5','-parse-as-library','-target','arm64-apple-macos14.0',...nativeLocalizationTestSources,'apps/macos/Bridge.swift','apps/macos/Model.swift','apps/macos/DocumentView.swift','tests/native/DocumentPageRetry.swift','-o',executable,'-framework','SwiftUI','-framework','AppKit','-framework','PDFKit'],{timeout:30000,stdio:'pipe'});
    const output=execFileSync(executable,[],{encoding:'utf8',timeout:12000,env:{PATH:'/usr/bin:/bin',DOCVER_TEST_USER_DATA:join(root,'userdata')}});
    assert.match(output,/PASS native document page Retry preserves both fixed sources/);
  }finally{await rm(root,{recursive:true,force:true});}
});
