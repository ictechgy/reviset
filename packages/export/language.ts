import {DocverError} from '../schema/index.js';
export type ExportLanguage='en'|'ko';
export function exportLanguage(value:unknown,fallback:ExportLanguage='ko'):ExportLanguage {
  if(value===undefined)return fallback;
  if(value!=='en'&&value!=='ko')throw new DocverError('INVALID_EXPORT_LANGUAGE','Export language must be en or ko');
  return value;
}
