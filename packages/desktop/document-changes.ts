import {createHash} from 'node:crypto';
import {z} from 'zod';
import {QueryService} from '../query/index.js';
import {DocverError,hash,textChunk,type ChangeData} from '../schema/index.js';

const key=z.string().regex(/^[a-zA-Z0-9_-]{1,160}$/);
const selection=z.object({project_id:key,report_id:key.refine(v=>v!=='latest','Native changes require a fixed report'),from:key,to:key,mode:z.enum(['adjacent','range_net','history']),kind:z.string().max(60).optional(),text:z.string().max(500).optional()}).strict();
export const nativeChangePageSchema=selection.extend({cursor:z.string().max(2048).optional(),limit:z.number().int().min(1).max(100).default(100)});
export const nativeChangeDetailSchema=selection.extend({query_id:z.string().regex(/^[a-f0-9]{64}$/),change_id:key,detail_offset:z.number().int().nonnegative().default(0)});
// UTF-16 offsets match JavaScript, Swift's utf16 and .NET strings. The JSON
// envelope expands escaped characters but remains below 4 MiB per response.
export const NATIVE_CHANGE_DETAIL_CHARS=128*1024;
export const NATIVE_CHANGE_MAX_DETAIL_CHARS=128*1024*1024;
const PREVIEW=180;
export const NATIVE_CHANGE_PAGE_BYTES=1024*1024;
function scope(raw:z.infer<typeof selection>){return selection.parse(raw);}
function rows(query:QueryService,args:z.infer<typeof selection>){
  const {text,kind,...fixed}=args;
  const needle=text?.toLowerCase();
  return query.changeReferences(fixed).filter(c=>(!kind||c.kind===kind)&&(!needle||((c.before??'')+' '+(c.after??'')).toLowerCase().includes(needle)));
}
function summary(c:ChangeData){
  // A list row is explicitly a preview. All source identities and unabridged
  // observations are fetched for the selected event before evidence is shown.
  const anchors=[c.evidence.find(e=>e.revision_occurrence_id===c.from_occurrence),c.evidence.find(e=>e.revision_occurrence_id===c.to_occurrence)].filter((e):e is ChangeData['evidence'][number]=>!!e);
  const evidence=[...new Set([...anchors,...c.evidence.slice(0,8)])].slice(0,8).map(({quote,...e})=>({...e,quote:textChunk(quote,0,PREVIEW),method:textChunk(e.method,0,120)}));
  return {schema_version:c.schema_version,report_id:c.report_id,change_id:c.change_id,entity_id:c.entity_id,from_revision:c.from_revision,to_revision:c.to_revision,from_occurrence:c.from_occurrence,to_occurrence:c.to_occurrence,kind:c.kind,before:c.before===null?null:textChunk(c.before,0,PREVIEW),after:c.after===null?null:textChunk(c.after,0,PREVIEW),before_length:c.before?.length??null,after_length:c.after?.length??null,evidence,evidence_count:c.evidence.length,lineage:{status:c.lineage.status,score:c.lineage.score,reasons:[]},coverage_gaps:c.coverage_gaps.slice(0,3).map(g=>({feature:textChunk(g.feature,0,120),reason:textChunk(g.reason,0,180)})),coverage_gap_count:c.coverage_gaps.length,evidence_uri:textChunk(c.evidence_uri,0,1024),appearance_assessment:c.appearance_assessment,text_assessment:c.text_assessment,text_scope:c.text_scope,region_pairing_assessment:c.region_pairing_assessment,summary_preview:true,detail_required:true};
}
export function nativeChangePage(query:QueryService,raw:unknown){
  const parsed=nativeChangePageSchema.parse(raw),{cursor,limit,...rest}=parsed,args=scope(rest),query_id=hash(['native-document-changes-v1',args]);
  const all=rows(query,args);let offset=0;
  if(cursor){let value:any;try{value=JSON.parse(Buffer.from(cursor,'base64url').toString('utf8'));}catch{throw new DocverError('DOCUMENT_CURSOR_SCOPE','Invalid document continuation');}
    if(value===null||typeof value!=='object'||Array.isArray(value)||value.query_id!==query_id||!Number.isSafeInteger(value.offset)||value.offset<0||value.offset>all.length)throw new DocverError('DOCUMENT_CURSOR_SCOPE','Continuation does not match the fixed document selection');offset=value.offset;}
  const items:ReturnType<typeof summary>[]=[];let end=offset,bytes=4096;
  while(end<all.length&&items.length<limit){const item=summary(all[end]),size=Buffer.byteLength(JSON.stringify(item));if(bytes+size>NATIVE_CHANGE_PAGE_BYTES){if(!items.length)throw new DocverError('DOCUMENT_CHANGE_LIMIT','A document summary exceeds the native response limit; use bounded MCP tools or export');break;}items.push(item);bytes+=size;end++;}
  const next_cursor=end<all.length?Buffer.from(JSON.stringify({query_id,offset:end})).toString('base64url'):null;
  return {project_id:args.project_id,report_id:args.report_id,query_id,items,next_cursor,total_count:all.length,summary_preview:true};
}
export function nativeChangeDetail(query:QueryService,raw:unknown){
  const {query_id,change_id,detail_offset,...rest}=nativeChangeDetailSchema.parse(raw),args=scope(rest),expected=hash(['native-document-changes-v1',args]);
  if(query_id!==expected)throw new DocverError('DOCUMENT_CHANGE_SCOPE','Detail does not match the fixed document query');
  const change=rows(query,args).find(c=>c.change_id===change_id);
  if(!change)throw new DocverError('DOCUMENT_CHANGE_SCOPE','Selected change is outside the fixed document query');
  const serialized=JSON.stringify(change);
  if(serialized.length>NATIVE_CHANGE_MAX_DETAIL_CHARS)throw new DocverError('DOCUMENT_CHANGE_LIMIT','Selected change exceeds the native detail limit; use the bounded MCP reading tools or export to read its components');
  if(detail_offset>serialized.length||(detail_offset>0&&/[\uDC00-\uDFFF]/.test(serialized[detail_offset])))throw new DocverError('DOCUMENT_CHANGE_SCOPE','Invalid selected-change text continuation');
  const json_chunk=textChunk(serialized,detail_offset,NATIVE_CHANGE_DETAIL_CHARS),next=detail_offset+json_chunk.length;
  return {project_id:args.project_id,report_id:args.report_id,query_id,change_id,detail_offset,json_length:serialized.length,content_sha256:createHash('sha256').update(serialized).digest('hex'),json_chunk,next_detail_offset:next<serialized.length?next:null};
}
