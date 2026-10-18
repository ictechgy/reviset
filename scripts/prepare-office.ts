import { existsSync } from 'node:fs';
import { mkdir,readFile,writeFile,mkdtemp,rm } from 'node:fs/promises';
import { resolve,join } from 'node:path';
import { execFileSync,spawnSync } from 'node:child_process';
import { byteHash } from '../packages/schema/index.js';

// Official TDF redirect response Digest: SHA-256, checked against the signed vendor app.
export const officePin={version:'26.8.1',team:'7P5S3ZLCN7',sha256:'ca074e0b13571efb30a31fc531c5f95e997030637325e5d5de92d67aefdf0dfc',url:'https://download.documentfoundation.org/libreoffice/stable/26.8.1/mac/aarch64/LibreOffice_26.8.1_MacOS_aarch64.dmg'};
const folder=resolve('dist/tools'),app=join(folder,'LibreOffice.app'),dmg=join(folder,'LibreOffice_26.8.1_MacOS_aarch64.dmg');
function verify(){
  execFileSync('/usr/bin/codesign',['--verify','--deep','--strict',app]);
  const result=spawnSync('/usr/bin/codesign',['-dv','--verbose=4',app],{encoding:'utf8'});
  if(result.status!==0||!result.stderr.includes('TeamIdentifier='+officePin.team))throw new Error('Unexpected LibreOffice signing team');
  const version=execFileSync(join(app,'Contents/MacOS/soffice'),['--version'],{encoding:'utf8'}).trim();if(!version.startsWith('LibreOffice '+officePin.version+'.'))throw new Error('Unexpected LibreOffice version');return version;
}
await mkdir(folder,{recursive:true});
if(!existsSync(app)){
  if(!existsSync(dmg))execFileSync('/usr/bin/curl',['-fL','--retry','2','--max-time','300',officePin.url,'-o',dmg],{stdio:'inherit'});
  if(byteHash(await readFile(dmg))!==officePin.sha256)throw new Error('LibreOffice DMG hash mismatch');
  const mount=await mkdtemp(join(folder,'mount-'));let attached=false;
  try{execFileSync('/usr/bin/hdiutil',['attach','-readonly','-nobrowse','-mountpoint',mount,dmg],{stdio:'inherit'});attached=true;execFileSync('/usr/bin/ditto',[join(mount,'LibreOffice.app'),app]);}
  finally{if(attached)execFileSync('/usr/sbin/diskutil',['eject',mount],{stdio:'inherit'});await rm(mount,{recursive:true,force:true});}
}
const version=verify();await writeFile(join(folder,'libreoffice-provenance.json'),JSON.stringify({...officePin,actual_version:version},null,2)+'\n');
console.log(JSON.stringify({app,version,signature:'TDF vendor signature verified',pin:officePin.sha256}));
