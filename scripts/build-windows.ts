import {build} from 'esbuild';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {mkdir,rm,cp,writeFile,readFile} from 'node:fs/promises';
import {dirname,join,resolve} from 'node:path';
import {preparePdfjs} from './prepare-pdfjs.js';

// Use a Windows runner so npm installs the target's native canvas binary and
// the published WPF application can be executed before distributing the zip.
if(process.platform!=='win32'||process.arch!=='x64')throw new Error('Build Windows x64 packages on Windows x64. Cross-compilation alone does not qualify native dependencies.');
const destination=resolve('release/Reviset-Windows-x64');
const nodeVersion='24.22.1';
const nodeURL=`https://nodejs.org/dist/v${nodeVersion}/win-x64/node.exe`;
const nodeSHA256='d702daa815eabbff763c7d3808e235cf031cf2ca70211b56847bc72f51e240e5';
const response=await fetch(nodeURL,{signal:AbortSignal.timeout(120_000)});
if(!response.ok)throw new Error('Official Node runtime download failed: '+response.status);
const runtime=Buffer.from(await response.arrayBuffer());
if(createHash('sha256').update(runtime).digest('hex')!==nodeSHA256)throw new Error('Official Windows Node runtime SHA-256 mismatch');
await rm(destination,{recursive:true,force:true});await mkdir(destination,{recursive:true});
execFileSync('dotnet',['publish','apps/windows/Reviset.Windows.csproj','-c','Release','-r','win-x64','--self-contained','true','-o',destination,'-p:PublishSingleFile=false','-p:ContinuousIntegrationBuild=true'],{stdio:'inherit'});
await mkdir(join(destination,'runtime'),{recursive:true});await writeFile(join(destination,'runtime/node.exe'),runtime);
await mkdir(join(destination,'backend'),{recursive:true});
await build({entryPoints:{bridge:'apps/bridge/main.ts',mcp:'apps/mcp/main.ts'},outdir:join(destination,'backend'),bundle:true,format:'esm',platform:'node',packages:'external',outExtension:{'.js':'.mjs'},target:'node24'});
await cp('package.json',join(destination,'package.json'));await cp('package-lock.json',join(destination,'package-lock.json'));
const npmCLI=process.env.npm_execpath??join(dirname(process.execPath),'node_modules/npm/bin/npm-cli.js');
execFileSync(process.execPath,[npmCLI,'ci','--omit=dev','--ignore-scripts','--no-audit','--no-fund','--prefix',destination],{stdio:'inherit'});
const pdfjs=await preparePdfjs(join(destination,'node_modules/pdfjs-dist'));
await cp('scripts/prepare-pdfjs.ts',join(destination,'pdfjs-source-change.ts'));
let sourceHead='unknown',sourceDirty=true;
try{sourceHead=execFileSync('git',['rev-parse','HEAD'],{encoding:'utf8'}).trim();sourceDirty=!!execFileSync('git',['status','--porcelain'],{encoding:'utf8'}).trim();}catch{/* source archives retain explicit unknown provenance */}
await writeFile(join(destination,'build-info.json'),JSON.stringify({source_head:sourceHead,source_dirty:sourceDirty,platform:'win32',architecture:'x64',native_ui:'WPF',node:{version:nodeVersion,url:nodeURL,sha256:nodeSHA256},pdfjs,capabilities:{pdf_text_and_appearance:true,pptx_structure:true,workbook_formats:['xlsx','ods','csv'],apple_vision_ocr:false,confined_office_renderer:false}},null,2)+'\n');
await writeFile(join(destination,'THIRD-PARTY-NOTICES.txt'),'Reviset uses Microsoft .NET/WPF (MIT; runtime notices accompany these files), Node.js (licenses at https://github.com/nodejs/node/blob/v24.22.1/LICENSE), and the npm packages whose licenses remain in node_modules. PDF.js is modified by the adjacent pdfjs-source-change.ts, with fingerprints in build-info.json. No Office suite or fonts are bundled. This portable build is not Authenticode signed.\n');
await cp('docs/WINDOWS.md',join(destination,'WINDOWS.md'));
// Ensure package provenance is readable before the caller archives it.
JSON.parse(await readFile(join(destination,'build-info.json'),'utf8'));
console.log(JSON.stringify({destination,native_ui:'WPF',source_head:sourceHead,source_dirty:sourceDirty,node_sha256:nodeSHA256}));
