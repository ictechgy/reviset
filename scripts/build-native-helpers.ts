import { mkdir,readFile,writeFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { byteHash,hash } from '../packages/schema/index.js';
await mkdir('dist/native',{recursive:true});
const fingerprint=hash([byteHash(await readFile('apps/helpers/Vision.swift')),byteHash(await readFile('apps/helpers/Reconsideration.swift')),byteHash(await readFile('scripts/build-native-helpers.ts')),execFileSync('swiftc',['--version'],{encoding:'utf8'}),execFileSync('xcrun',['--show-sdk-version'],{encoding:'utf8'})]);
let reusable=false;try{const previous=JSON.parse(await readFile('dist/native/build.json','utf8'));reusable=previous.fingerprint===fingerprint&&previous.binary_sha256===byteHash(await readFile('dist/native/DocverVision'));}catch{/* first/changed build */}
if(!reusable){
  execFileSync('swiftc',['-swift-version','5','-O','-parse-as-library','-target','arm64-apple-macos14.0','apps/helpers/Vision.swift','apps/helpers/Reconsideration.swift','-o','dist/native/DocverVision','-framework','Vision','-framework','AppKit','-framework','PDFKit','-framework','CryptoKit'],{stdio:'inherit'});
  execFileSync('codesign',['--force','--sign','-','dist/native/DocverVision'],{stdio:'inherit'});
  await writeFile('dist/native/build.json',JSON.stringify({fingerprint,binary_sha256:byteHash(await readFile('dist/native/DocverVision'))},null,2));
}
const info=JSON.parse(execFileSync('dist/native/DocverVision',['--info'],{encoding:'utf8'}));
console.log(JSON.stringify({helper:'DocverVision',version:info.version,languages:info.languages,document_structure:info.document_structure,font_inventory_sha256:info.font_inventory_sha256}));
