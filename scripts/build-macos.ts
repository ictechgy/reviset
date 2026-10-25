import { build } from 'esbuild';
import { mkdir,cp,writeFile,rm,readFile,stat,appendFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { resolve,join } from 'node:path';
import { generateFixtures } from './generate-fixtures.js';
import {preparePdfjs} from './prepare-pdfjs.js';
import {optionalSidecarBuild} from './onlyoffice-build-policy.js';
import {generateWorkbookDemo} from './generate-workbook-demo.js';
import {buildLocalizationResources} from './localization.js';
import {nativeSwiftSources} from './native-swift-sources.js';
import {appBuildName} from './app-build-name.js';
if(process.platform!=='darwin'||process.arch!=='arm64')throw new Error('This local build currently targets macOS arm64.');
const appName=appBuildName(process.env);
const optionalSidecar=optionalSidecarBuild(appName,process.env.REVISET_OPTIONAL_SIDECAR??process.env.DOCVER_OPTIONAL_SIDECAR);
if(optionalSidecar)for(const path of ['provider.json','fonts/AllFonts.js','fonts/font_selection.bin'])await stat(join('dist/onlyoffice-sidecar',path));
const app=resolve('release',appName),contents=join(app,'Contents'),resources=join(contents,'Resources');
await import('./build-native-helpers.js');await import('./build-renderer-guard.js');await import('./prepare-office.js');
// Only this generated bundle is replaced; never reuse stale runtimes or dependencies.
await rm(app,{recursive:true,force:true});
await buildLocalizationResources(resources);
await mkdir(join(contents,'MacOS'),{recursive:true});await mkdir(join(resources,'backend'),{recursive:true});await mkdir(join(contents,'Helpers'),{recursive:true});
await build({entryPoints:{bridge:'apps/bridge/main.ts',mcp:'apps/mcp/main.ts','office-input':'apps/helpers/OfficeInput.ts'},outdir:join(resources,'backend'),bundle:true,format:'esm',platform:'node',packages:'external',outExtension:{'.js':'.mjs'},target:'node24'});
await cp('package.json',join(resources,'package.json'));
await cp('package-lock.json',join(resources,'package-lock.json'));
execFileSync('npm',['ci','--omit=dev','--ignore-scripts','--no-audit','--no-fund','--prefix',resources],{stdio:'inherit'});
const pdfjs=await preparePdfjs(join(resources,'node_modules/pdfjs-dist'));
await cp('scripts/prepare-pdfjs.ts',join(resources,'pdfjs-source-change.ts'));
const linked=execFileSync('otool',['-L',process.execPath],{encoding:'utf8'}).split('\n').slice(1).map(line=>line.trim().split(' (')[0]).filter(Boolean);
if(linked.some(path=>!path.startsWith('/usr/lib/')&&!path.startsWith('/System/Library/')))throw new Error('Node links a non-system dylib; choose a self-contained runtime before packaging.');
await cp(process.execPath,join(contents,'Helpers/node'));
await cp('dist/native/DocverVision',join(contents,'Helpers/DocverVision'));
await cp('dist/native/DocverRendererGuard',join(contents,'Helpers/DocverRendererGuard'));
if(optionalSidecar){
  const destination=join(resources,'onlyoffice-sidecar');await mkdir(join(destination,'fonts'),{recursive:true});
  await cp('dist/onlyoffice-sidecar/provider.json',join(destination,'provider.json'));
  for(const name of ['AllFonts.js','font_selection.bin'])await cp(join('dist/onlyoffice-sidecar/fonts',name),join(destination,'fonts',name));
}
execFileSync('/usr/bin/ditto',['dist/tools/LibreOffice.app',join(contents,'Helpers/LibreOffice.app')]);
await cp('dist/tools/libreoffice-provenance.json',join(resources,'libreoffice-provenance.json'));
let sourceHead='unknown',sourceDirty=true;try{sourceHead=execFileSync('git',['rev-parse','HEAD'],{encoding:'utf8'}).trim();sourceDirty=!!execFileSync('git',['status','--porcelain'],{encoding:'utf8'}).trim();}catch{/* source archives can be built without Git */}
await writeFile(join(resources,'build-info.json'),JSON.stringify({source_head:sourceHead,source_dirty:sourceDirty,version:'0.5.0',pdfjs,native_helper:JSON.parse(await readFile('dist/native/build.json','utf8')),renderer_guard:JSON.parse(await readFile('dist/native/renderer-guard.json','utf8')),optional_sidecar:optionalSidecar?{policy:'host-bound-external-onlyoffice-v1',provider:JSON.parse(await readFile(join(resources,'onlyoffice-sidecar/provider.json'),'utf8'))}:null},null,2));
await writeFile(join(resources,'THIRD-PARTY-NOTICES.txt'),'LibreOffice 26.8.1.1 by The Document Foundation is bundled unchanged under its vendor license notices. Full licenses: Helpers/LibreOffice.app/Contents/Resources/LICENSE.html and related vendor files. Corresponding source: https://download.documentfoundation.org/libreoffice/src/26.8.1/ . Apple system fonts/frameworks are read from the host and are not redistributed. PDF.js6.4.299 legacy/build/pdf.worker.mjs is modified by Reviset to expose the embedded-font-program origin flag and two finite actual font metrics; the reproducible source change and fingerprints are in Resources/pdfjs-source-change.ts and build-info.json. PDF.js license: Resources/node_modules/pdfjs-dist/LICENSE. No fontExtraProperties data export is enabled. Node and npm dependency licenses remain in their respective bundled package directories. This is a local private build, not a public distribution approval.\n');
if(optionalSidecar)await appendFile(join(resources,'THIRD-PARTY-NOTICES.txt'),'The optional ONLYOFFICE viewer calls a separately installed, pinned vendor app. The vendor app, its libraries, and the font indexer are not bundled. Only generated JSON-assignment font selection metadata is included; it contains host font paths and is bound to this Mac font inventory. Font program files are not copied. This optional private configuration is not a portable or public distribution qualification.\n');
await generateFixtures(resolve('tests/fixtures/generated'));await mkdir(join(resources,'demo'),{recursive:true});await cp('tests/fixtures/generated/lifecycle-five',join(resources,'demo/lifecycle-five'),{recursive:true});
await generateWorkbookDemo(join(resources,'demo/workbooks'));
await rm('dist/native-icon.iconset',{recursive:true,force:true});
await mkdir('dist/native-icon.iconset',{recursive:true});await cp('assets/branding/reviset-icon.png','dist/native-icon.png');
for(const size of [16,32,128,256,512])for(const scale of [1,2])execFileSync('sips',['-z',String(size*scale),String(size*scale),'dist/native-icon.png','--out',`dist/native-icon.iconset/icon_${size}x${size}${scale===2?'@2x':''}.png`],{stdio:'ignore'});
execFileSync('iconutil',['-c','icns','dist/native-icon.iconset','-o',join(resources,'Reviset.icns')]);
await writeFile(join(contents,'Info.plist'),`<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleDevelopmentRegion</key><string>en</string><key>CFBundleLocalizations</key><array><string>en</string><string>ko</string></array><key>CFBundleName</key><string>Reviset</string><key>CFBundleDisplayName</key><string>Reviset</string><key>CFBundleIdentifier</key><string>org.docver.native</string><key>CFBundleExecutable</key><string>Reviset</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>0.5.0</string><key>CFBundleVersion</key><string>1</string><key>CFBundleIconFile</key><string>Reviset.icns</string><key>LSMinimumSystemVersion</key><string>14.0</string><key>NSHighResolutionCapable</key><true/><key>NSPrincipalClass</key><string>NSApplication</string><key>LSApplicationCategoryType</key><string>public.app-category.productivity</string></dict></plist>`);
execFileSync('swiftc',['-swift-version','5','-O','-parse-as-library','-target','arm64-apple-macos14.0',...nativeSwiftSources,'-o',join(contents,'MacOS/Reviset'),'-framework','SwiftUI','-framework','AppKit','-framework','PDFKit'],{stdio:'inherit'});
execFileSync('codesign',['--force','--sign','-',join(contents,'Helpers/node')],{stdio:'inherit'});
// Preserve TDF's already-verified nested vendor signature; sign the containing app only.
execFileSync('codesign',['--force','--sign','-',app],{stdio:'inherit'});
execFileSync('codesign',['--verify','--deep','--strict',app],{stdio:'inherit'});
console.log(JSON.stringify({app,ui:'SwiftUI/AppKit/PDFKit',runtime:process.version,architecture:process.arch,signature:'local ad-hoc; not notarized'}));
