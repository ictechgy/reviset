import { z } from 'zod';
import { Store } from '../storage/index.js';
import { SCHEMA_VERSION,ENGINE_VERSION, canonical, hash, id,comparisonText,textChunk, DocverError, Gap, Change, type ChangeData, type ReportData } from '../schema/index.js';
import { matchPages } from '../matching/index.js';
import { diffRevisions } from '../diff/index.js';
import { diffRevisions as legacyNativeDiff } from '../diff/legacy-native-1.js';
const internalId=z.string().regex(/^[a-zA-Z0-9_-]{1,160}$/);
const paging={cursor:z.string().max(2048).optional(),limit:z.number().int().min(1).max(200).default(50),max_output_tokens:z.number().int().min(256).max(8000).default(4000)};
const scope={project_id:internalId,report_id:internalId};
const base=z.object({...scope,...paging}).strict();
export const querySchemas={
  list_projects:z.object(paging).strict(),
  list_reports:z.object({project_id:internalId,...paging}).strict(),
  get_report:base,
  list_revisions:base,
  list_pages:base.extend({revision_id:internalId}),
  get_page:base.extend({revision_id:internalId,page_id:internalId}),
  get_element:base.extend({observation_id:internalId,text_offset:z.number().int().nonnegative().default(0),text_length:z.number().int().min(1).max(1000).default(500),span_offset:z.number().int().nonnegative().default(0),span_limit:z.number().int().min(0).max(20).default(0),appearance_evidence_offset:z.number().int().nonnegative().default(0),appearance_evidence_limit:z.number().int().min(0).max(10).default(0),ocr_alternative_index:z.number().int().min(0).max(2).default(0),ocr_alternative_offset:z.number().int().nonnegative().default(0),ocr_alternative_length:z.number().int().min(1).max(1000).default(256)}),
  list_changes:base.extend({from:internalId.optional(),to:internalId.optional(),mode:z.enum(['adjacent','range_net','history']).default('history'),kind:z.string().max(60).optional(),change_id:internalId.optional(),entity_id:internalId.optional(),text:z.string().max(500).optional()}),
  get_entity_history:base.extend({entity_id:internalId}),
  get_evidence:base.extend({change_id:internalId.optional(),observation_id:internalId.optional(),text_offset:z.number().int().nonnegative().default(0),text_length:z.number().int().min(1).max(1000).default(500)})
};
export type QueryName=keyof typeof querySchemas;
export const Envelope=z.object({schema_version:z.literal(SCHEMA_VERSION),report_id:z.string().nullable(),items:z.array(z.record(z.string(),z.unknown())),
  next_cursor:z.string().nullable(),coverage_gaps:z.array(Gap),truncated:z.boolean(),omitted_fields:z.array(z.string()),token_estimation:z.string()});
export type QueryResult=z.infer<typeof Envelope>;
const resource=(r:ReportData,kind:string,key?:string)=>`docver://projects/${r.project_id}/reports/${r.report_id}/${kind}${key?'/'+key:''}`;
export class QueryService {
  constructor(readonly store:Store,readonly allowedProjects:Set<string>,private readonly loadSnapshot?:(projectId:string,reportId:string)=>ReportData) {}
  snapshot(projectId:string,reportId:string):ReportData {
    if(!this.allowedProjects.has(projectId))throw new DocverError('PROJECT_SCOPE','Project is outside the configured scope');
    return this.loadSnapshot?this.loadSnapshot(projectId,reportId):this.store.report(projectId,reportId);
  }
  changeSet(raw:unknown):ChangeData[] {
    const args=querySchemas.list_changes.parse(raw);const report=this.snapshot(args.project_id,args.report_id);
    return this.rows('list_changes',args,report).map(c=>Change.parse(c));
  }
  query(name:QueryName,raw:unknown):QueryResult {
    const args:any=querySchemas[name].parse(raw);
    if(args.project_id&&!this.allowedProjects.has(args.project_id)) throw new DocverError('PROJECT_SCOPE','Project is outside the configured scope');
    const report:ReportData|undefined=args.report_id?this.snapshot(args.project_id,args.report_id):undefined;
    let rows:Record<string,unknown>[]=[];
    if(name==='list_projects') rows=this.store.projects().filter(p=>this.allowedProjects.has(p.project_id));
    else if(name==='list_reports') rows=this.store.reports(args.project_id);
    else if(report) rows=this.rows(name,args,report);
    return this.paginate(name,args,report,rows);
  }
  private rows(name:QueryName,args:any,r:ReportData):Record<string,unknown>[] {
    const revision=()=> {
      const rev=r.revisions.find(v=>v.revision_occurrence_id===args.revision_id)??r.revisions.find(v=>v.revision_id===args.revision_id);
      if(!rev) throw new DocverError('REVISION_NOT_FOUND','Revision is outside this report');return rev;
    };
    const pageFor=(pageId:string)=>r.revisions.flatMap(v=>v.pages.map(p=>({v,p}))).find(({p})=>p.page_id===pageId);
    const element=()=> {
      for(const v of r.revisions) for(const p of v.pages) {const e=p.elements.find(e=>e.observation_id===args.observation_id);if(e)return {v,p,e};}
      throw new DocverError('OBSERVATION_NOT_FOUND','Observation is outside this report');
    };
    switch(name) {
      case 'get_report': return [{schema_version:r.schema_version,report_id:r.report_id,project_id:r.project_id,engine_version:r.engine_version,schema_hash:r.schema_hash,timeline_revision_id:r.timeline_revision_id,mapping_revision_id:r.mapping_revision_id,
        observation_environment:r.observation_environment,revision_count:r.revisions.length,change_count:r.changes.length,unresolved_candidates:r.candidates.filter(c=>c.status==='needs_review').length,resource_uri:resource(r,'manifest')}];
      case 'list_revisions':return r.revisions.map(({pages,...v})=>({...v,page_count:pages.length,coverage_gaps:undefined}));
      case 'list_pages':return revision().pages.map(page=>{const {elements,notes,text,visible_text,unresolved_text,suppressed_text,ocr_text,ocr_unresolved_text,...p}=page;return {...p,text_excerpt:textChunk(comparisonText(page),0,160),element_count:elements.length,resource_uri:resource(r,`revisions/${revision().revision_occurrence_id}/pages`,p.page_id)};});
      case 'get_page': {
        const p=revision().pages.find(p=>p.page_id===args.page_id);if(!p)throw new DocverError('PAGE_NOT_FOUND','Page is outside this revision');
        // One item per element allows even a large page to be traversed without a monolithic payload.
        return p.elements.length?p.elements.map(e=>({page_id:p.page_id,page:p.page,capabilities:p.capabilities,...e,ocr:e.ocr?{...e.ocr,alternatives:e.ocr.alternatives.map(a=>({confidence:a.confidence,text_length:a.text.length,truncated:a.truncated}))}:undefined,visibility_spans:undefined,visibility_evidence:undefined,visibility_span_count:e.visibility_spans?.length??0,visibility_evidence_count:e.visibility_evidence?.length??0,resource_uri:resource(r,'evidence',e.observation_id)})):
          [{page_id:p.page_id,page:p.page,capabilities:p.capabilities,coverage_gaps:p.coverage_gaps,elements:[],text:''}];
      }
      case 'get_element': {
        const {v,p,e}=element();const text=textChunk(e.text,args.text_offset,args.text_length);
        const spans=e.visibility_spans??[],appearance=e.visibility_evidence??[],chunk=spans.slice(args.span_offset,args.span_offset+args.span_limit),evidence=appearance.slice(args.appearance_evidence_offset,args.appearance_evidence_offset+args.appearance_evidence_limit);
        const alternative=e.ocr?.alternatives[args.ocr_alternative_index],alternativeText=alternative?textChunk(alternative.text,args.ocr_alternative_offset,args.ocr_alternative_length):undefined;
        return [{...e,text,normalized_text:undefined,ocr:e.ocr?{...e.ocr,alternatives:e.ocr.alternatives.map(a=>({confidence:a.confidence,text_length:a.text.length,truncated:a.truncated}))}:undefined,ocr_alternative:alternative?{index:args.ocr_alternative_index,confidence:alternative.confidence,text:alternativeText,text_length:alternative.text.length,text_offset:args.ocr_alternative_offset,next_text_offset:args.ocr_alternative_offset+alternativeText!.length<alternative.text.length?args.ocr_alternative_offset+alternativeText!.length:null}:undefined,visibility_spans:args.span_limit?chunk:undefined,visibility_evidence:args.appearance_evidence_limit?evidence:undefined,visibility_span_count:spans.length,visibility_evidence_count:appearance.length,span_offset:args.span_offset,next_span_offset:args.span_offset+chunk.length<spans.length?args.span_offset+chunk.length:null,appearance_evidence_offset:args.appearance_evidence_offset,next_appearance_evidence_offset:args.appearance_evidence_offset+evidence.length<appearance.length?args.appearance_evidence_offset+evidence.length:null,text_offset:args.text_offset,next_text_offset:args.text_offset+text.length<e.text.length?args.text_offset+text.length:null,
          revision_id:v.revision_id,page_id:p.page_id,page:p.page,resource_uri:resource(r,'evidence',e.observation_id)}];
      }
      case 'list_changes': {
        let changes=r.changes;
        if(args.mode==='range_net') {
          if(!args.from||!args.to)throw new DocverError('RANGE_REQUIRED','range_net requires from and to occurrence IDs');
          const resolveRev=(key:string)=>r.revisions.find(v=>v.revision_occurrence_id===key)??r.revisions.find(v=>v.revision_id===key);
          const a=resolveRev(args.from),b=resolveRev(args.to);if(!a||!b)throw new DocverError('REVISION_NOT_FOUND','Range endpoints are outside this report');
          const aIndex=r.revisions.indexOf(a),bIndex=r.revisions.indexOf(b);if(aIndex>=bIndex)throw new DocverError('RANGE_ORDER','from must precede to');
          const entity=(p:string)=>r.lineages.find(l=>l.page_ids.includes(p))?.entity_id??'';
          const primary=(v:typeof a)=>v.assets.some(s=>s.format==='pptx')?{...v,pages:v.pages.filter(p=>v.assets.find(s=>s.asset_id===p.asset_id)?.format==='pptx')}:v;
          const left=primary(a),right=primary(b);
          const matches=left.pages.flatMap(p=>right.pages.filter(q=>entity(p.page_id)===entity(q.page_id)).map(q=>({from_page_id:p.page_id,to_page_id:q.page_id,score:Math.min(1,...r.matches.filter(m=>r.lineages.find(l=>l.entity_id===entity(p.page_id))?.page_ids.includes(m.from_page_id)).map(m=>m.score)),status:r.lineages.find(l=>l.entity_id===entity(p.page_id))?.status??'inferred',reasons:['snapshot_lineage_range_net']})));
          const diff=r.engine_version===ENGINE_VERSION?diffRevisions:r.engine_version==='0.1.0-native.1'?legacyNativeDiff:undefined;
          if(!diff)throw new DocverError('ENGINE_VERSION_UNAVAILABLE','Historical range computation requires its archived engine; stored history/export remains readable, and reanalysis creates a new report');
          changes=diff(left,right,matches,matchPages(left.pages,right.pages).candidates,entity).map((c,i)=>({...c,schema_version:r.schema_version,report_id:r.report_id,change_id:id('net',[r.report_id,args.from,args.to,i,c]),evidence_uri:resource(r,'manifest')}));
        } else {
          const revIndex=(key:string)=>r.revisions.findIndex(v=>v.revision_occurrence_id===key||v.revision_id===key);
          const start=args.from?revIndex(args.from):0,end=args.to?revIndex(args.to):r.revisions.length-1;
          if(start<0||end<0)throw new DocverError('REVISION_NOT_FOUND','Range endpoints are outside this report');
          if(start>end)throw new DocverError('RANGE_ORDER','from must precede to');
          if(args.mode==='adjacent'&&args.from&&args.to&&end!==start+1)throw new DocverError('NOT_ADJACENT','Endpoints must be adjacent');
          changes=changes.filter(c=>revIndex(c.from_occurrence)>=start&&revIndex(c.to_occurrence)<=end);
        }
        return changes.filter(c=>(!args.change_id||c.change_id===args.change_id)&&(!args.kind||c.kind===args.kind)&&(!args.entity_id||c.entity_id===args.entity_id)&&(!args.text||((c.before??'')+' '+(c.after??'')).includes(args.text)));
      }
      case 'get_entity_history': {
        const lineage=r.lineages.find(l=>l.entity_id===args.entity_id);if(!lineage)throw new DocverError('ENTITY_NOT_FOUND','Entity is outside this report');
        return lineage.page_ids.map(pageId=> {const {v,p}=pageFor(pageId)!;return {entity_id:lineage.entity_id,status:lineage.status,revision_id:v.revision_id,revision_occurrence_id:v.revision_occurrence_id,page_id:pageId,page:p.page,text:p.text,
          changes:r.changes.filter(c=>c.entity_id===lineage.entity_id&&c.to_occurrence===v.revision_occurrence_id).map(c=>({change_id:c.change_id,kind:c.kind})),resource_uri:resource(r,`revisions/${v.revision_occurrence_id}/pages`,pageId)};});
      }
      case 'get_evidence': {
        if(Boolean(args.change_id)===Boolean(args.observation_id))throw new DocverError('EVIDENCE_TARGET','Supply exactly one change_id or observation_id');
        if(args.change_id) {const c=r.changes.find(c=>c.change_id===args.change_id);if(!c)throw new DocverError('CHANGE_NOT_FOUND','Change is outside this report');
          return c.evidence.map(e=>{const quote=textChunk(e.quote,args.text_offset,args.text_length);return {...e,quote,text_offset:args.text_offset,next_text_offset:args.text_offset+quote.length<e.quote.length?args.text_offset+quote.length:null};});}
        const {v,p,e}=element(),quote=textChunk(e.text,args.text_offset,args.text_length);
        return [{revision_id:v.revision_id,revision_occurrence_id:v.revision_occurrence_id,asset_id:p.asset_id,page_id:p.page_id,page:p.page,observation_id:e.observation_id,bbox:e.bbox,quote,method:e.method,provenance:e.provenance,ocr:e.ocr?{confidence:e.ocr.confidence,numeric_consensus:e.ocr.numeric_consensus,ambiguous:e.ocr.ambiguous,confidence_scope:e.ocr.confidence_scope,alternative_count:e.ocr.alternatives.length}:undefined,
          text_offset:args.text_offset,next_text_offset:args.text_offset+quote.length<e.text.length?args.text_offset+quote.length:null}];
      }
      default:throw new DocverError('UNKNOWN_QUERY','Unsupported query');
    }
  }
  private paginate(name:string,args:any,r:ReportData|undefined,rows:Record<string,unknown>[]):QueryResult {
    const reportId=r?.report_id??null;
    const {cursor,limit,max_output_tokens,...filters}=args;
    const queryHash=hash([name,{...filters,...(reportId?{report_id:reportId}:{})},reportId]);let offset=0;
    if(cursor) {
      let data:any;try{data=JSON.parse(Buffer.from(cursor,'base64url').toString());}catch{throw new DocverError('INVALID_CURSOR','Invalid cursor');}
      if(data.report_id!==reportId)throw new DocverError('CURSOR_REPORT_MISMATCH','Cursor belongs to another report');
      if(data.query_hash!==queryHash)throw new DocverError('CURSOR_QUERY_MISMATCH','Cursor belongs to another query');
      if(!Number.isSafeInteger(data.offset)||data.offset<0||data.offset>rows.length)throw new DocverError('INVALID_CURSOR','Invalid cursor position');offset=data.offset;
    }
    const result:QueryResult={schema_version:SCHEMA_VERSION,report_id:reportId,items:[],next_cursor:null,coverage_gaps:[],truncated:false,omitted_fields:[],token_estimation:'conservative_utf8_bytes_upper_estimate; model tokenizer varies'};
    // One UTF-8 byte per estimated token, capped again at 32 KiB. Includes envelope and cursor.
    const budget=Math.min(max_output_tokens,32768);
    const size=()=>Buffer.byteLength(JSON.stringify(result));
    const makeCursor=(n:number)=>Buffer.from(canonical({report_id:reportId,query_hash:queryHash,offset:n})).toString('base64url');
    let position=offset;
    while(position<rows.length&&result.items.length<limit) {
      const item=JSON.parse(JSON.stringify(rows[position]));
      result.items.push(item);result.next_cursor=position+1<rows.length?makeCursor(position+1):null;
      if(size()>budget) {
        result.items.pop();
        if(!result.items.length) {
          const keys=['change_id','entity_id','observation_id','page_id','revision_id','kind','resource_uri','evidence_uri'];
          const summary:Record<string,unknown>=Object.fromEntries(keys.filter(k=>item[k]!==undefined).map(k=>[k,item[k]]));
          summary.truncated=true;summary.omitted_fields=Object.keys(item).filter(k=>!keys.includes(k));
          if(item.observation_id)summary.retrieval='get_element with text_offset/text_length';
          else if(item.change_id)summary.retrieval='get_evidence with change_id and text_offset/text_length';
          result.items.push(summary);result.omitted_fields.push('oversized_item_fields');result.truncated=true;position++;
        }
        break;
      }
      position++;
    }
    result.next_cursor=position<rows.length?makeCursor(position):null;
    result.truncated=result.truncated||result.next_cursor!==null;
    if(r?.coverage_gaps.length) {
      result.coverage_gaps=r.coverage_gaps.slice(0,3);if(r.coverage_gaps.length>3)result.omitted_fields.push('additional_coverage_gaps');
      if(size()>budget){result.coverage_gaps=[];result.omitted_fields.push('coverage_gaps');}
    }
    result.truncated=result.truncated||result.omitted_fields.length>0;
    // Envelope flags/coverage metadata can grow after an item initially fits.
    // Return a shorter page instead of failing an otherwise valid 8KiB query.
    while(size()>budget&&result.items.length>1){result.items.pop();position--;result.next_cursor=makeCursor(position);result.truncated=true;}
    if(size()>budget&&result.items.length===1){const item=result.items[0],keys=['change_id','entity_id','observation_id','page_id','revision_id','kind','resource_uri','evidence_uri'];
      result.items[0]={...Object.fromEntries(keys.filter(k=>item[k]!==undefined).map(k=>[k,item[k]])),truncated:true,omitted_fields:Object.keys(item).filter(k=>!keys.includes(k)),retrieval:item.change_id?'get_evidence with change_id and text_offset/text_length':'get_element with observation_id and text_offset/text_length'};result.truncated=true;result.omitted_fields.push('oversized_item_fields');}
    if(size()>budget)throw new DocverError('OUTPUT_BUDGET_TOO_SMALL','Increase max_output_tokens to fit the response envelope; minimum practical budget is 1024');
    return Envelope.parse(result);
  }
}
