import {mkdir,readFile,writeFile} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {byteHash,hash} from '../packages/schema/index.js';

if(process.platform!=='darwin'||process.arch!=='arm64')throw new Error('Renderer guard requires macOS arm64.');
await mkdir('dist/native',{recursive:true});
const source='apps/helpers/RendererGuard.c',binary='dist/native/DocverRendererGuard',metadata='dist/native/renderer-guard.json';
const fingerprint=hash([byteHash(await readFile(source)),byteHash(await readFile('scripts/build-renderer-guard.ts')),execFileSync('/usr/bin/clang',['--version'],{encoding:'utf8'}),execFileSync('/usr/bin/xcrun',['--show-sdk-version'],{encoding:'utf8'})]);
let reusable=false;
try{const prior=JSON.parse(await readFile(metadata,'utf8'));reusable=prior.fingerprint===fingerprint&&prior.binary_sha256===byteHash(await readFile(binary));}catch{/* First build or changed source. */}
if(!reusable){
  execFileSync('/usr/bin/clang',['-O2','-Wall','-Wextra','-Werror','-target','arm64-apple-macos14.0',source,'-o',binary],{stdio:'inherit'});
  execFileSync('/usr/bin/codesign',['--force','--sign','-',binary],{stdio:'inherit'});
  await writeFile(metadata,JSON.stringify({fingerprint,binary_sha256:byteHash(await readFile(binary))},null,2)+'\n');
}
