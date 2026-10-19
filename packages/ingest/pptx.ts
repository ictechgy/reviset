import { unzipSync } from 'fflate';
import { XMLParser, XMLValidator } from 'fast-xml-parser';
import { posix } from 'node:path';
import { MAX_PPTX_EXPANDED_BYTES,MAX_PPTX_PART_BYTES,box, byteHash, DocverError, id, normalize, type ElementData, type PageData } from '../schema/index.js';

const MAX_UNCOMPRESSED=MAX_PPTX_EXPANDED_BYTES;
const MAX_XML_DEPTH=100;
const parserOptions={ignoreAttributes:false, removeNSPrefix:false, transformTagName:(name:string)=>name.split(':').at(-1)!, textNodeName:'#text',
  trimValues:false, parseTagValue:false, parseAttributeValue:false, processEntities:false,maxNestedTags:MAX_XML_DEPTH};
const parser=new XMLParser(parserOptions),orderedParser=new XMLParser({...parserOptions,preserveOrder:true,cdataPropName:'#cdata'});
export const PPTX_TEXT_POLICY='drawingml-ordered-paragraphs-v3-unicode';
const arr=(v:any):any[] => v == null ? [] : Array.isArray(v) ? v : [v];
// OPC XML parts use UTF-8 or BOM-marked UTF-16 (XML1.0 §4.3.3).
// A malformed byte sequence must never silently change the observed source.
function decodeXml(bytes:Uint8Array):string {
  const encoding=bytes[0]===0xff&&bytes[1]===0xfe?'utf-16le':bytes[0]===0xfe&&bytes[1]===0xff?'utf-16be':'utf-8';
  let source:string;
  try{source=new TextDecoder(encoding,{fatal:true}).decode(bytes);}
  catch{throw new DocverError('INVALID_XML','Invalid OOXML character encoding');}
  if(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\ufffe\uffff]/u.test(source))throw new DocverError('INVALID_XML','Forbidden XML character');
  if(source.startsWith('<?xml')&&/[ \t\r\n]/.test(source[5]??'')){
    const end=source.indexOf('?>');
    if(end<0)throw new DocverError('INVALID_XML','Unterminated XML declaration');
    const declared=source.slice(0,end).match(/\bencoding[ \t\r\n]*=[ \t\r\n]*(['"])([^'"]*)\1/)?.[2].toUpperCase();
    if(declared&&declared!=='UTF-8'&&declared!=='UTF-16')throw new DocverError('XML_ENCODING_UNSUPPORTED','OOXML encoding must be UTF-8 or UTF-16');
    if(declared&&((declared==='UTF-8')!==(encoding==='utf-8')))throw new DocverError('INVALID_XML','OOXML encoding declaration does not match its bytes');
  }
  return source;
}
function xmlCharacter(cp:number):boolean {
  return cp===0x9||cp===0xa||cp===0xd||cp>=0x20&&cp<=0xd7ff||cp>=0xe000&&cp<=0xfffd||cp>=0x10000&&cp<=0x10ffff;
}
function checkXmlReferences(source:string){
  for(const match of source.matchAll(/&#(?:x([0-9a-fA-F]+)|([0-9]+));/g)){
    const cp=match[1]===undefined?Number(match[2]):parseInt(match[1],16);
    if(!xmlCharacter(cp))throw new DocverError('INVALID_XML','Forbidden XML character reference');
  }
}

function checkXmlMarkup(source:string){
  let cursor=0,depth=0;
  while(cursor<source.length){
    const open=source.indexOf('<',cursor);checkXmlReferences(source.slice(cursor,open<0?source.length:open));if(open<0)break;
    let delimiter:string|undefined,contentStart=open;
    if(source.startsWith('<!--',open)){delimiter='-->';contentStart=open+4;}
    else if(source.startsWith('<![CDATA[',open)){delimiter=']]>';contentStart=open+9;}
    else if(source.startsWith('<?',open)){delimiter='?>';contentStart=open+2;}
    if(delimiter){const end=source.indexOf(delimiter,contentStart);if(end<0)throw new DocverError('INVALID_XML','Unterminated XML data');cursor=end+delimiter.length;continue;}
    if(source.startsWith('<!',open)){
      const declaration=source.slice(open,open+9).toUpperCase();
      if(declaration.startsWith('<!DOCTYPE')||declaration.startsWith('<!ENTITY'))throw new DocverError('XML_DTD','DTD/entity declarations are unsupported');
      throw new DocverError('INVALID_XML','Unsupported XML declaration');
    }
    let end=open+1,quote='';
    for(;end<source.length;end++){
      const char=source[end];
      // XMLValidator accepts raw '<' in quoted attributes; XML1.0 does not.
      // Never rescan that value as a comment, PI, CDATA or another tag.
      if(char==='<')throw new DocverError('INVALID_XML','Invalid XML attribute or tag');
      if(quote){if(char===quote)quote='';}
      else if(char==='"'||char==="'")quote=char;
      else if(char==='>')break;
    }
    if(end===source.length||quote)throw new DocverError('INVALID_XML','Unterminated XML tag');
    checkXmlReferences(source.slice(open,end+1));
    if(source[open+1]==='/')depth--;else if(source[end-1]!=='/')depth++;
    if(depth<0)throw new DocverError('INVALID_XML','Unbalanced XML tags');
    if(depth>MAX_XML_DEPTH)throw new DocverError('XML_DEPTH','XML nesting exceeds limit');
    cursor=end+1;
  }
  if(depth!==0)throw new DocverError('INVALID_XML','Unbalanced XML tags');
}
// Decode predefined entities only, after parsing. DTDs and custom entities are rejected.
function decoded(text:string):string {
  return text.replace(/&(amp|lt|gt|quot|apos|#x[0-9a-f]+|#[0-9]+);/gi,(match,k:string)=>{
    if(k[0]!=='#')return {amp:'&',lt:'<',gt:'>',quot:'"',apos:"'"}[k]??match;
    const n=k.slice(1),cp=n[0].toLowerCase()==='x'?parseInt(n.slice(1),16):Number(n);if(!xmlCharacter(cp))throw new DocverError('INVALID_XML','Invalid XML Unicode scalar');return String.fromCodePoint(cp);
  });
}
export function extractPptx(bytes:Uint8Array, assetId:string):PageData[] {
  const paragraphs=new WeakMap<object,string[]>();
  const shapes=new WeakMap<object,[string,any][]>();
  const inlineText=(ordered:any[],depth=0):string[]=>{
    if(depth>MAX_XML_DEPTH)throw new DocverError('XML_DEPTH','XML nesting exceeds limit');
    return ordered.flatMap(part=>Object.entries(part).flatMap(([tag,children])=>{
    if(tag==='t')return arr(children).flatMap(child=>typeof child?.['#text']==='string'?[decoded(child['#text'])]:
      arr(child?.['#cdata']).flatMap(value=>typeof value?.['#text']==='string'?[value['#text']]:[]));
    if(tag==='br')return ['\n'];
    return Array.isArray(children)?inlineText(children,depth+1):[];
  }));};
  // The normal object tree groups repeated tag names, losing r/fld/r order.
  // Correlate by occurrence within each parent, and retain only paragraph text.
  const bindParagraphs=(plain:any,ordered:any[],depth=0)=>{
    if(depth>MAX_XML_DEPTH)throw new DocverError('XML_DEPTH','XML nesting exceeds limit');
    const positions=new Map<string,number>();
    const drawingChildren:[string,any][]=[];
    for(const part of ordered)for(const [tag,children]of Object.entries(part)){
      if(!Array.isArray(children))continue;
      const index=positions.get(tag)??0;positions.set(tag,index+1);
      const child=arr(plain?.[tag])[index];
      if(['sp','pic','graphicFrame','cxnSp','grpSp'].includes(tag)){
        if(child===undefined)throw new DocverError('PPTX_TEXT_ORDER','DrawingML shape order is unavailable');
        drawingChildren.push([tag,child]);
      }
      if(!child||typeof child!=='object')continue;
      if(tag==='p')paragraphs.set(child,inlineText(children));else bindParagraphs(child,children,depth+1);
    }
    if(drawingChildren.length)shapes.set(plain,drawingChildren);
  };
  const bodyText=(body:any)=>arr(body?.p).map(p=>{
    if(!p||typeof p!=='object')return '';
    const runs=paragraphs.get(p);
    if(!runs)throw new DocverError('PPTX_TEXT_ORDER','DrawingML paragraph order is unavailable');
    return runs.join('');
  }).join('\n');
  let total=0;
  let zip:Record<string,Uint8Array>;
  try { zip=unzipSync(bytes,{filter:entry=> {
    total+=entry.originalSize;
    if (total>MAX_UNCOMPRESSED || entry.originalSize>MAX_PPTX_PART_BYTES) throw new DocverError('ZIP_LIMIT','Uncompressed package exceeds limit');
    if (entry.name.startsWith('/') || entry.name.split('/').includes('..')) throw new DocverError('ZIP_PATH','Unsafe ZIP part');
    return true;
  }}); } catch(e) { if(e instanceof DocverError) throw e; throw new DocverError('INVALID_PPTX','Invalid ZIP package'); }
  function xml(path:string):any {
    if (!zip[path]) throw new DocverError('MISSING_PART',`Missing OOXML part: ${path}`);
    const source=decodeXml(zip[path]);
    checkXmlMarkup(source);
    if(XMLValidator.validate(source)!==true) throw new DocverError('INVALID_XML','Malformed OOXML');
    try{const parsed=parser.parse(source);bindParagraphs(parsed,orderedParser.parse(source));return parsed;}
    catch(error){
      if(error instanceof DocverError)throw error;
      if(error instanceof Error&&error.message==='Maximum nested tags exceeded')throw new DocverError('XML_DEPTH','XML nesting exceeds limit');
      throw new DocverError('INVALID_XML','OOXML parsing failed');
    }
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
      for(const [kind,nodes] of shapes.get(tree)??Object.entries(tree)) {
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
          const table=shape.graphic?.graphicData?.tbl;
          if(kind==='graphicFrame'&&table){
            const columns=arr(table.tblGrid?.gridCol).map(c=>Number(c['@_w'])),rows=arr(table.tr),totalW=columns.reduce((a,b)=>a+b,0),totalH=rows.reduce((a,r)=>a+Number(r['@_h']),0);
            const tableId=id('table',[assetId,path,elements.length]);let yy=0;
            for(const [ri,row] of rows.entries()){
              let xx=0;
              const cells=arr(row.tc),compactRow=cells.length<columns.length;let column=0;
              for(const cell of cells){const ci=column;
                const cellText=bodyText(cell.txBody),cw=columns[ci]??0;
                const colSpan=Math.max(1,Number(cell['@_gridSpan']??1)),rowSpan=Math.max(1,Number(cell['@_rowSpan']??1));
                const spanWidth=columns.slice(ci,ci+colSpan).reduce((a,b)=>a+b,0),spanHeight=rows.slice(ri,ri+rowSpan).reduce((a,r)=>a+Number(r['@_h']),0);
                const cellBox=totalW>0&&totalH>0?box(bbox[0]+bbox[2]*xx/totalW,bbox[1]+bbox[3]*yy/totalH,bbox[2]*spanWidth/totalW,bbox[3]*spanHeight/totalH):bbox;
                if(cellText&&!['1','true'].includes(String(cell['@_hMerge']))&&!['1','true'].includes(String(cell['@_vMerge'])))elements.push({observation_id:id('obs',[assetId,path,elements.length]),kind:'table_cell',text:cellText,normalized_text:normalize(cellText),bbox:cellBox,reading_order:elements.length,availability:'available',method:'ooxml_table_cell',source_ref:path+'#table/'+ri+'/'+ci,provenance:'observed',table:{table_id:tableId,row:ri,column:ci,row_span:rowSpan,column_span:colSpan,origin:'ooxml_table',assessment:'observed'}});
                xx+=compactRow?spanWidth:cw;column+=compactRow?colSpan:1;
                if(cell['@_gridSpan']||cell['@_rowSpan']||cell['@_hMerge']||cell['@_vMerge'])gaps.push({feature:'table_geometry',reason:'merged_cell_geometry_requires_review'});
              }
              yy+=Number(row['@_h']);
            }
            continue;
          }
          const text=bodyText(shape.txBody);
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
    if(noteRel) { const note=xml(target(path,noteRel)); notes=arr(note.notes?.cSld?.spTree?.sp).filter(s=>s.nvSpPr?.nvPr?.ph?.['@_type']==='body').map(s=>bodyText(s.txBody)).join('\n'); }
    return { page_id:id('pg',[assetId,index]),asset_id:assetId,page:index+1,width,height,coordinate_system:'ooxml_emu_top_left',source_transform:[1/width,0,0,1/height,0,0],
      hidden:slide['@_show']==='0'||slide['@_show']==='false',text:elements.filter(e=>e.kind==='text'||e.kind==='table_cell').map(e=>e.text).join('\n'), elements, notes,
      capabilities:{text:'available',notes:'available',hidden_slides:'available',animation:'unsupported',structure:'available',preview:'unavailable'},
      coverage_gaps:[...gaps,{feature:'preview',reason:'pptx_conversion_not_run'},{feature:'animation',reason:'animation_diff_unsupported'}] };
  });
}
