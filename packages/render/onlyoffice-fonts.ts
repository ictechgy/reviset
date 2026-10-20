import {isAbsolute,resolve,join} from 'node:path';
import {homedir} from 'node:os';
import {DocverError} from '../schema/index.js';

export const onlyOfficeFontRoots=()=>['/System/Library/Fonts','/System/Library/AssetsV2','/Library/Fonts','/Library/Apple/System/Library/Fonts',join(homedir(),'Library/Fonts')];

// This is a data file emitted by the local font indexer, not an executable
// extension. Parse each assignment as JSON; never eval or import its JavaScript.
export function parseOnlyOfficeFonts(bytes:Uint8Array):{files:string[]}{
  if(bytes.length>1024*1024)throw new DocverError('SIDECAR_FONTS','Font metadata exceeds its limit');
  const source=Buffer.from(bytes).toString('utf8').replace(/^\uFEFF/u,''),values=new Map<string,unknown>();
  let at=0;
  while(at<source.length){
    while(at<source.length&&/\s/u.test(source[at]))at++;
    if(at===source.length)break;
    const header=/^window\["([A-Za-z_0-9]+)"\]\s*=\s*/u.exec(source.slice(at));
    if(!header||values.has(header[1]))throw new DocverError('SIDECAR_FONTS','Unsupported font metadata assignment');
    at+=header[0].length;const start=at;let depth=0,quoted=false,escaped=false;
    for(;at<source.length;at++){
      const c=source[at];
      if(quoted){if(escaped)escaped=false;else if(c==='\\')escaped=true;else if(c==='"')quoted=false;continue;}
      if(c==='"')quoted=true;
      else if(c==='['||c==='{')depth++;
      else if(c===']'||c==='}')depth--;
      else if(c===';'&&depth===0)break;
      if(depth<0||depth>8)throw new DocverError('SIDECAR_FONTS','Unsupported font metadata nesting');
    }
    if(at===source.length||quoted||depth!==0)throw new DocverError('SIDECAR_FONTS','Incomplete font metadata');
    try{values.set(header[1],JSON.parse(source.slice(start,at)));}catch{throw new DocverError('SIDECAR_FONTS','Font metadata must contain only JSON values');}
    at++;
  }
  const keys=['__all_fonts_js_version__','__fonts_files','__fonts_infos','__fonts_ranges','g_fonts_selection_bin'];
  if(values.size!==keys.length||keys.some(k=>!values.has(k))||values.get(keys[0])!==2)throw new DocverError('SIDECAR_FONTS','Unsupported font metadata version');
  const files=values.get(keys[1]),infos=values.get(keys[2]),ranges=values.get(keys[3]),selection=values.get(keys[4]);
  const roots=onlyOfficeFontRoots();
  if(!Array.isArray(files)||!files.length||files.length>10000||files.some(p=>typeof p!=='string'||p.length>4096||/[\u0000-\u001f\u007f]/u.test(p)||!isAbsolute(p)||resolve(p)!==p||!roots.some(root=>p.startsWith(root+'/'))))throw new DocverError('SIDECAR_FONTS','Font metadata references an unsupported location');
  if(!Array.isArray(infos)||infos.length>10000||infos.some(row=>!Array.isArray(row)||row.length!==9||typeof row[0]!=='string'||row[0].length>1000||row.slice(1).some(n=>!Number.isInteger(n)||n< -1||n>10000000)))throw new DocverError('SIDECAR_FONTS','Unsupported font selection records');
  if(!Array.isArray(ranges)||ranges.length>200000||ranges.some(n=>!Number.isInteger(n)||n<0||n>0xffffffff)||typeof selection!=='string'||selection.length>1024*1024||!/^[A-Za-z0-9+/]*={0,2}$/u.test(selection))throw new DocverError('SIDECAR_FONTS','Unsupported font selection data');
  return {files};
}
