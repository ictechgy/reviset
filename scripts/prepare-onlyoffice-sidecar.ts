import {readFile,writeFile,mkdir,realpath,stat} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {parseArgs} from 'node:util';
import {byteHash} from '../packages/schema/index.js';
import {parseOnlyOfficeFonts} from '../packages/render/onlyoffice-fonts.js';
import {runTool,visionInfo} from '../packages/runtime/tools.js';

// Provision only generated metadata for a private build on this Mac. The vendor
// app and all font programs remain external; no linked font-indexer is shipped.
const {values}=parseArgs({options:{app:{type:'string'},fonts:{type:'string'}}});
if(!values.app||!values.fonts)throw new Error('Provide --app and --fonts for the local signed renderer and generated metadata.');
const app=await realpath(values.app),fonts=await realpath(values.fonts),output=resolve('dist/onlyoffice-sidecar');
const requirement='=anchor apple generic and certificate leaf[subject.OU] = "2WH24U26GJ"';
await runTool('/usr/bin/codesign',['--verify','--deep','--strict','-R',requirement,app],{timeout:30_000,maxBytes:65536,inheritEnv:false,env:{PATH:'/usr/bin:/bin'}});
const version=(await runTool('/usr/bin/plutil',['-extract','CFBundleVersion','raw',join(app,'Contents/Info.plist')],{timeout:5000,maxBytes:1024,inheritEnv:false,env:{PATH:'/usr/bin:/bin'}})).trim();
const releaseVersion=(await runTool('/usr/bin/plutil',['-extract','CFBundleShortVersionString','raw',join(app,'Contents/Info.plist')],{timeout:5000,maxBytes:1024,inheritEnv:false,env:{PATH:'/usr/bin:/bin'}})).trim();
const files:Record<string,{sha256:string;bytes:number}>={};
const copied:Record<string,Buffer>={};
for(const name of ['AllFonts.js','font_selection.bin']){
  const path=join(fonts,name);if((await stat(path)).size>1024*1024)throw new Error('Font metadata limit');
  const bytes=await readFile(path);if(name==='AllFonts.js')parseOnlyOfficeFonts(bytes);
  files[name]={sha256:byteHash(bytes),bytes:bytes.length};copied[name]=bytes;
}
const info=await visionInfo();if(!info)throw new Error('The current native font inventory is required.');
const config={version:1,app_path:app,bundle_version:version,release_version:releaseVersion,team_id:'2WH24U26GJ',converter_sha256:byteHash(await readFile(join(app,'Contents/Resources/converter/x2t'))),code_resources_sha256:byteHash(await readFile(join(app,'Contents/_CodeSignature/CodeResources'))),font_inventory_sha256:info.font_inventory_sha256,files};
await mkdir(output,{recursive:true,mode:0o700});await mkdir(join(output,'fonts'),{recursive:true,mode:0o700});
for(const [name,bytes]of Object.entries(copied))await writeFile(join(output,'fonts',name),bytes,{mode:0o600});
await writeFile(join(output,'provider.json'),JSON.stringify(config,null,2)+'\n',{mode:0o600});
console.log(JSON.stringify({output,vendor_bundled:false,font_programs_copied:false,host_bound:true,bundle_version:version}));
