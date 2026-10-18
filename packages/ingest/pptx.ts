import { unzipSync } from 'fflate';
import { XMLParser, XMLValidator } from 'fast-xml-parser';
import { posix } from 'node:path';
import { box, byteHash, DocverError, id, normalize, type ElementData, type PageData } from '../schema/index.js';

const MAX_UNCOMPRESSED=100*1024*1024;
const parser=new XMLParser({ignoreAttributes:false, removeNSPrefix:false, transformTagName:(name:string)=>name.split(':').at(-1)!, textNodeName:'#text',
  trimValues:false, parseTagValue:false, parseAttributeValue:false, processEntities:false});
const arr=(v:any):any[] => v == null ? [] : Array.isArray(v) ? v : [v];
function texts(node:any):string[] {
  if (!node || typeof node!=='object') return [];
  return Object.entries(node).flatMap(([key,v])=> key==='t' ? arr(v).map(t=>typeof t==='object'?String(t['#text']??''):String(t)) : texts(v));
}
// Decode predefined entities only, after parsing. DTDs and custom entities are rejected.
function decoded(text:string):string {
  return text.replace(/&(amp|lt|gt|quot|apos);/g,(_,k)=>({amp:'&',lt:'<',gt:'>',quot:'"',apos:"'"}[k as string]!))
    .replace(/&#(x[0-9a-f]+|[0-9]+);/gi,(_,n)=>{ const cp=n[0].toLowerCase()==='x'?parseInt(n.slice(1),16):Number(n); return cp<=0x10ffff?String.fromCodePoint(cp):'�'; });
}
export function extractPptx(bytes:Uint8Array, assetId:string):PageData[] {
  let total=0;
  let zip:Record<string,Uint8Array>;
  try { zip=unzipSync(bytes,{filter:entry=> {
    total+=entry.originalSize;
    if (total>MAX_UNCOMPRESSED || entry.originalSize>20*1024*1024) throw new DocverError('ZIP_LIMIT','Uncompressed package exceeds limit');
    if (entry.name.startsWith('/') || entry.name.split('/').includes('..')) throw new DocverError('ZIP_PATH','Unsafe ZIP part');
    return true;
  }}); } catch(e) { if(e instanceof DocverError) throw e; throw new DocverError('INVALID_PPTX','Invalid ZIP package'); }
  function xml(path:string):any {
    if (!zip[path]) throw new DocverError('MISSING_PART',`Missing OOXML part: ${path}`);
    const source=new TextDecoder().decode(zip[path]);
    if (/<!DOCTYPE|<!ENTITY/i.test(source)) throw new DocverError('XML_DTD','DTD/entity declarations are unsupported');
    let depth=0;
    for(const tag of source.matchAll(/<\/?[A-Za-z_][^>]*>/g)) {
      if(tag[0].startsWith('</')) depth--; else if(!tag[0].endsWith('/>')) depth++;
      if(depth>100) throw new DocverError('XML_DEPTH','XML nesting exceeds limit');
    }
    if(XMLValidator.validate(source)!==true) throw new DocverError('INVALID_XML','Malformed OOXML');
    return parser.parse(source);
  }
  function rels(part:string):any[] {
    const p=posix.join(posix.dirname(part),'_rels',posix.basename(part)+'.rels');
    return zip[p] ? arr(xml(p).Relationships?.Relationship) : [];
  }
  function target(part:string, rel:any):string {
    if(!rel || rel['@_TargetMode']==='External') throw new DocverError('EXTERNAL_RELATIONSHIP','External relationship is not fetched');
    const value=String(rel['@_Target']);
    if(/^[a-z]+:/i.test(value)) throw new DocverError('EXTERNAL_RELATIONSHIP','URI relationship is not fetched');
    const p=posix.normalize(value.startsWith('/')?value.slice(1):posix.join(posix.dirname(part),value));
    if(p.startsWith('../')) throw new DocverError('RELATIONSHIP_PATH','Relationship leaves package');
    return p;
  }
  const root='_rels/.rels';
  const mainRel=zip[root]?arr(xml(root).Relationships?.Relationship).find(r=>String(r['@_Type']).endsWith('/officeDocument')):null;
  const main=mainRel?target('',mainRel):'ppt/presentation.xml';
  const presentation=xml(main).presentation;
  if(!presentation) throw new DocverError('INVALID_PPTX','Missing presentation');
  const width=Number(presentation.sldSz?.['@_cx']), height=Number(presentation.sldSz?.['@_cy']);
  if(!(width>0&&height>0)) throw new DocverError('PAGE_SIZE','Invalid slide dimensions');
  const links=rels(main);
  return arr(presentation.sldIdLst?.sldId).map((entry,index)=> {
    const path=target(main,links.find(r=>r['@_Id']===entry['@_id'] || r['@_Id']===entry['@_r:id']));
    const slide=xml(path).sld, slideRels=rels(path), elements:ElementData[]=[];
    const gaps:PageData['coverage_gaps']=[];
    function walk(tree:any, grouped=false) {
      if(!tree) return;
      for(const [kind,nodes] of Object.entries(tree)) {
        if(kind==='grpSp') { gaps.push({feature:'group_geometry',reason:'unsupported_group_transform'}); for(const n of arr(nodes)) walk(n,true); }
        if(!['sp','pic','graphicFrame','cxnSp'].includes(kind)) continue;
        for(const node of arr(nodes)) {
          const shape=node as any;
          const transform=shape.spPr?.xfrm??shape.xfrm;
          const off=transform?.off, ext=transform?.ext;
          const known=off&&ext&&!grouped;
          if(!known) gaps.push({feature:'geometry',reason:'layout_inheritance_or_group_transform_unsupported'});
          if(transform?.['@_rot']) gaps.push({feature:'geometry',reason:'rotated_shape_bbox_is_approximate'});
          const bbox=known?box(Number(off['@_x'])/width,Number(off['@_y'])/height,Number(ext['@_cx'])/width,Number(ext['@_cy'])/height):box(0,0,1,1);
          const text=arr(shape.txBody?.p).map(p=>texts(p).map(decoded).join('')).join('\n');
          const element:ElementData={observation_id:id('obs',[assetId,path,elements.length]), kind:kind==='pic'?'image':text?'text':kind==='graphicFrame'?'unsupported':'shape',
            text, normalized_text:normalize(text),bbox,reading_order:elements.length,availability:kind==='graphicFrame'?'unsupported':'available',
            method:'ooxml_text',source_ref:path+'#'+String(shape.nvSpPr?.cNvPr?.['@_id']??elements.length),provenance:'observed'};
          if(kind==='pic') {
            const embed=shape.blipFill?.blip?.['@_r:embed'];
            const rel=slideRels.find(r=>r['@_Id']===embed);
            if(rel&&rel['@_TargetMode']!=='External') { const media=zip[target(path,rel)]; if(media) element.media_hash=byteHash(media); }
          }
          if(kind==='graphicFrame') gaps.push({feature:'table_chart',reason:'semantic_extraction_unsupported'});
          elements.push(element);
        }
      }
    }
    walk(slide.cSld?.spTree);
    const noteRel=slideRels.find(r=>String(r['@_Type']).endsWith('/notesSlide'));
    // Notes placeholders for slide number/header/footer are not speaker notes.
    let notes='';
    if(noteRel) { const note=xml(target(path,noteRel)); notes=arr(note.notes?.cSld?.spTree?.sp).filter(s=>s.nvSpPr?.nvPr?.ph?.['@_type']==='body').map(s=>texts(s.txBody).map(decoded).join('')).join('\n'); }
    return { page_id:id('pg',[assetId,index]),asset_id:assetId,page:index+1,width,height,coordinate_system:'ooxml_emu_top_left',source_transform:[1/width,0,0,1/height,0,0],
      hidden:slide['@_show']==='0'||slide['@_show']==='false',text:elements.filter(e=>e.kind==='text').map(e=>e.text).join('\n'), elements, notes,
      capabilities:{text:'available',notes:'available',hidden_slides:'available',animation:'unsupported',structure:'available',preview:'unavailable'},
      coverage_gaps:[...gaps,{feature:'preview',reason:'pptx_conversion_not_run'},{feature:'animation',reason:'animation_diff_unsupported'}] };
  });
}
