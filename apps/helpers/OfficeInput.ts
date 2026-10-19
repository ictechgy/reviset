import {readFile,writeFile,rename,realpath} from 'node:fs/promises';
import {join,isAbsolute} from 'node:path';
import {materializeOfficeInsets,officeInputPolicy} from '../../packages/render/pptx-default-insets.js';
import {byteHash,OfficeInputPreparation,DocverError} from '../../packages/schema/index.js';
import {z} from 'zod';
try{
  let input=Buffer.alloc(0);for await(const chunk of process.stdin){if(input.length+chunk.length>8192)throw new Error('Input limit');input=Buffer.concat([input,chunk]);}
  const query=z.object({folder:z.string().min(1),source_sha256:z.string().regex(/^[a-f0-9]{64}$/)}).strict().parse(JSON.parse(input.toString('utf8')));
  if(!isAbsolute(query.folder)||await realpath(query.folder)!==query.folder)throw new Error('Noncanonical job path');
  const source=await readFile(join(query.folder,'input.pptx')),sourceHash=byteHash(source);if(sourceHash!==query.source_sha256)throw new Error('Input identity');
  const prepared=materializeOfficeInsets(source),metadata=OfficeInputPreparation.parse({policy:officeInputPolicy,source_sha256:sourceHash,input_sha256:byteHash(prepared.bytes),changed_properties:prepared.changed_properties,unsupported_parts:prepared.unsupported_parts,skip_reason:prepared.skip_reason});
  if(prepared.changed_properties){const staging=join(query.folder,'render-input.tmp');await writeFile(staging,prepared.bytes,{flag:'wx',mode:0o600});await rename(staging,join(query.folder,'render-input.pptx'));}
  process.stdout.write(JSON.stringify({status:'ok',metadata}));
}catch(error){
  const code=error instanceof DocverError&&['ZIP_LIMIT','ZIP_PATH'].includes(error.code)?error.code:'OFFICE_INPUT_FAILED';
  process.stdout.write(JSON.stringify({status:'error',code}));
}
