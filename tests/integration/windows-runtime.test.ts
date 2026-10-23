import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,readFile,writeFile,symlink,rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {readRegularFile} from '../../packages/runtime/regular-file.js';
import {runTool,officeExecutable,visionExecutable} from '../../packages/runtime/tools.js';
import {nativeHelperLaunch} from '../../packages/runtime/native-isolation.js';
import {convertPptxDetailed,isolatedOfficeVersion} from '../../packages/render/index.js';
import {onlyOfficeSidecarConfigured} from '../../packages/render/onlyoffice-sidecar.js';

test('portable input reader accepts exact Unicode bytes and rejects links/directories',async()=>{
  const folder=await mkdtemp(join(tmpdir(),'reviset-platform-input-'));
  try{
    const path=join(folder,'한글 $ (control).pdf'),bytes=Buffer.from('opaque {0} 한글 😀\0');await writeFile(path,bytes);
    assert.deepEqual(await readRegularFile(path),bytes);
    const link=join(folder,'link.pdf');await symlink(path,link,'file');
    await assert.rejects(readRegularFile(link),{code:'INPUT_NOT_REGULAR'});
    const dir=join(folder,'dir.pdf');await mkdir(dir);await assert.rejects(readRegularFile(dir),{code:'INPUT_NOT_REGULAR'});
    if(process.platform==='win32'){
      const junction=join(folder,'junction.pdf');await symlink(dir,junction,'junction');await assert.rejects(readRegularFile(junction),{code:'INPUT_NOT_REGULAR'});
      await assert.rejects(readRegularFile('\\\\.\\pipe\\reviset-forbidden'),{code:'INPUT_NOT_REGULAR'});
    }
  }finally{await rm(folder,{recursive:true,force:true});}
});

test('POSIX owned processor timeout terminates its actual child process tree',{skip:process.platform==='win32'},async()=>{
  const folder=await mkdtemp(join(tmpdir(),'reviset-process-tree-'));let descendant=0;
  try{
    const pidFile=join(folder,'descendant.pid');
    const script="const {spawn}=require('node:child_process');const fs=require('node:fs');const child=spawn(process.execPath,['-e','setInterval(()=>{},1000)'],{stdio:'inherit'});fs.writeFileSync(process.argv[1],String(child.pid));setInterval(()=>{},1000);";
    await assert.rejects(runTool(process.execPath,['-e',script,pidFile],{timeout:2000,maxBytes:8192}),{code:'TOOL_TIMEOUT'});
    descendant=Number(await readFile(pidFile,'utf8'));assert.ok(descendant>1);
    let alive=true;
    for(let i=0;i<100&&alive;i++){
      try{process.kill(descendant,0);await new Promise(ok=>setTimeout(ok,20));}catch(error){assert.equal((error as NodeJS.ErrnoException).code,'ESRCH');alive=false;}
    }
    assert.equal(alive,false,'owned descendant must be terminated, not orphaned');
  }finally{if(descendant)try{process.kill(descendant,'SIGKILL');}catch{/* already terminated */}await rm(folder,{recursive:true,force:true});}
});

test('Windows never discovers or launches macOS-only helpers or unconfined Office',{skip:process.platform!=='win32'},async()=>{
  assert.equal(officeExecutable(),undefined);assert.equal(visionExecutable(),undefined);
  await assert.rejects(runTool(process.execPath,['--version']),{code:'TOOL_PLATFORM_UNSUPPORTED'});
  await assert.rejects(nativeHelperLaunch(process.execPath,tmpdir()),{code:'OCR_UNAVAILABLE'});
  await assert.rejects(convertPptxDetailed('untrusted.pptx',process.execPath),{code:'CONVERTER_UNAVAILABLE'});
  await assert.rejects(isolatedOfficeVersion(process.execPath),{code:'CONVERTER_UNAVAILABLE'});
  assert.equal(await onlyOfficeSidecarConfigured(tmpdir()),false);
});
