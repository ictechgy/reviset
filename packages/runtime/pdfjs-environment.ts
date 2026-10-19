import {createRequire} from 'node:module';
import {dirname,join} from 'node:path';
import {fileSha256} from './file-hash.js';
const require=createRequire(import.meta.url);
let identity:Promise<string>|undefined;
// Read-only in packaged apps. Both patched and upstream workers have distinct
// snapshot identities; an unpatched worker simply cannot prove embedded origin.
export function pdfWorkerEnvironment():Promise<string>{
  return identity??=fileSha256(join(dirname(require.resolve('pdfjs-dist/package.json')),'legacy/build/pdf.worker.mjs'));
}
