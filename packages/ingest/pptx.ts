import { readOfficeZip } from '../runtime/office-zip.js';
import { XMLParser } from 'fast-xml-parser';
import {MAX_XML_DEPTH,readXml,xmlCharacter} from '../xml/index.js';
import { posix } from 'node:path';
import { box, byteHash, DocverError, id, normalize, type ElementData, type PageData } from '../schema/index.js';

const parserOptions={ignoreAttributes:false, removeNSPrefix:false, transformTagName:(name:string)=>name.split(':').at(-1)!, textNodeName:'#text',
  trimValues:false, parseTagValue:false, parseAttributeValue:false, processEntities:false,maxNestedTags:MAX_XML_DEPTH};
const parser=new XMLParser(parserOptions),orderedParser=new XMLParser({...parserOptions,preserveOrder:true,cdataPropName:'#cdata'});
export const PPTX_TEXT_POLICY='drawingml-ordered-paragraphs-v4-shared-xml';
export const PPTX_EXTRACTION_BUDGET_POLICY='unique-slides-cumulative-xml-text-elements-v1';
export const PPTX_EXTRACTION_LIMITS=Object.freeze({slides:1000,xmlPartBytes:8*1024*1024,xmlBytes:128*1024*1024,xmlNodes:2_000_000,
  pageElements:25_000,elements:500_000,pageText:2_000_000,text:20_000_000,pageNotes:500_000,notes:5_000_000,parsedText:32_000_000});
type PptxDocumentResource='xmlBytes'|'xmlNodes'|'elements'|'text'|'notes'|'parsedText';
export class PptxExtractionBudget {
  private used={xmlBytes:0,xmlNodes:0,elements:0,text:0,notes:0,parsedText:0};
  reserve(resource:PptxDocumentResource,amount:number){
    if(!Number.isSafeInteger(amount)||amount<0||this.used[resource]+amount>PPTX_EXTRACTION_LIMITS[resource]){
      const code=resource==='xmlBytes'||resource==='xmlNodes'?'PPTX_PARSE_LIMIT':resource==='elements'?'PPTX_ELEMENT_LIMIT':resource==='notes'?'PPTX_NOTES_LIMIT':'PPTX_TEXT_LIMIT';
      throw new DocverError(code,'PPTX exceeds the cumulative '+resource+' extraction budget');
    }
    this.used[resource]+=amount;
  }
}
const arr=(v:any):any[] => v == null ? [] : Array.isArray(v) ? v : [v];
// Decode predefined entities only, after parsing. DTDs and custom entities are rejected.
function decoded(text:string):string {
  return text.replace(/&(amp|lt|gt|quot|apos|#x[0-9a-f]+|#[0-9]+);/gi,(match,k:string)=>{
    if(k[0]!=='#')return {amp:'&',lt:'<',gt:'>',quot:'"',apos:"'"}[k]??match;
    const n=k.slice(1),cp=n[0].toLowerCase()==='x'?parseInt(n.slice(1),16):Number(n);if(!xmlCharacter(cp))throw new DocverError('INVALID_XML','Invalid XML Unicode scalar');return String.fromCodePoint(cp);
  });
}
export function extractPptx(bytes:Uint8Array, assetId:string):PageData[] {
  const budget=new PptxExtractionBudget();
  const mediaHashes=new Map<string,string>();
  const paragraphs=new WeakMap<object,string[]>();
  const shapes=new WeakMap<object,[string,any][]>();
  const inlineText=(ordered:any[],depth=0):string[]=>{
    if(depth>MAX_XML_DEPTH)throw new DocverError('XML_DEPTH','XML nesting exceeds limit');
    return ordered.flatMap(part=>Object.entries(part).flatMap(([tag,children])=>{
    if(tag==='t')return arr(children).flatMap(child=>{
      const text=typeof child?.['#text']==='string'?[child['#text']]:arr(child?.['#cdata']).flatMap(value=>typeof value?.['#text']==='string'?[value['#text']]:[]);
      for(const value of text)budget.reserve('parsedText',value.length);
      return typeof child?.['#text']==='string'?text.map(decoded):text;
    });
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
  const bodyText=(body:any,reserve?:(length:number)=>void)=>{
    const runs=arr(body?.p).map(p=>{if(!p||typeof p!=='object')return [];const values=paragraphs.get(p);if(!values)throw new DocverError('PPTX_TEXT_ORDER','DrawingML paragraph order is unavailable');return values;});
    reserve?.(runs.reduce((length,paragraph)=>length+paragraph.reduce((n,value)=>n+value.length,0),Math.max(0,runs.length-1)));
    return runs.map(paragraph=>paragraph.join('')).join('\n');
  };
  const zip=readOfficeZip(bytes);
  function xml(path:string):any {
    if (!zip[path]) throw new DocverError('MISSING_PART',`Missing OOXML part: ${path}`);
    // Reserve both XML trees' source work before validation or parser allocation.
    if(zip[path].length>PPTX_EXTRACTION_LIMITS.xmlPartBytes)throw new DocverError('PPTX_PARSE_LIMIT','OOXML exceeds the per-part parsing byte budget');
    budget.reserve('xmlBytes',zip[path].length);
    const source=readXml(zip[path]);
    for(let cursor=source.indexOf('<');cursor>=0;cursor=source.indexOf('<',cursor+1))budget.reserve('xmlNodes',1);
    try{const parsed=parser.parse(source);bindParagraphs(parsed,orderedParser.parse(source));return parsed;}
    catch(error){
      if(error instanceof DocverError)throw error;
      if(error instanceof Error&&error.message==='Maximum nested tags exceeded')throw new DocverError('XML_DEPTH','XML nesting exceeds limit');
      throw new DocverError('INVALID_XML','OOXML parsing failed');
    }
  }
  function rels(part:string):any[] {
    const p=posix.join(posix.dirname(part),'_rels',posix.basename(part)+'.rels');
    const relationships=zip[p] ? arr(xml(p).Relationships?.Relationship) : [],ids=new Set<string>();
    for(const relationship of relationships){const key=relationship?.['@_Id'];if(typeof key!=='string'||!key||ids.has(key))throw new DocverError('INVALID_PPTX_RELATIONSHIP','OOXML relationship IDs must be present and unique');ids.add(key);}
    return relationships;
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
  if(![width,height].every(n=>Number.isFinite(n)&&n>0)) throw new DocverError('PAGE_SIZE','Invalid slide dimensions');
  const entries=arr(presentation.sldIdLst?.sldId);
  if(entries.length>PPTX_EXTRACTION_LIMITS.slides)throw new DocverError('PAGE_LIMIT','PPTX exceeds 1000 slides');
  const links=new Map(rels(main).map(r=>[r['@_Id'],r])),slideIds=new Set<string>(),relationshipIds=new Set<string>(),targets=new Set<string>();
  // Validate the entire slide list before touching any slide payload. Repeated
  // references cannot multiply one compressed part into an unbounded page tree.
  const paths=entries.map(entry=>{
    const slideId=entry?.['@_id'],relationshipId=entry?.['@_r:id'];
    if(typeof slideId!=='string'||!/^\d+$/.test(slideId)||Number(slideId)<256||Number(slideId)>2147483647||typeof relationshipId!=='string'||!relationshipId)throw new DocverError('INVALID_PPTX_SLIDE_REFERENCE','Slide IDs and relationship IDs must be present and valid');
    const identity=String(Number(slideId)),relationship=links.get(relationshipId);
    if(slideIds.has(identity)||relationshipIds.has(relationshipId)||!String(relationship?.['@_Type']).endsWith('/slide'))throw new DocverError('INVALID_PPTX_SLIDE_REFERENCE','Slide IDs and relationships must be unique slide references');
    const path=target(main,relationship),targetId=path.normalize('NFC').toLowerCase();
    if(targets.has(targetId))throw new DocverError('INVALID_PPTX_SLIDE_REFERENCE','Slide targets must be unique');
    slideIds.add(identity);relationshipIds.add(relationshipId);targets.add(targetId);return path;
  });
  return paths.map((path,index)=> {
    const slide=xml(path).sld, slideRels=rels(path),slideLinks=new Map(slideRels.map(r=>[r['@_Id'],r])), elements:ElementData[]=[];
    if(!slide)throw new DocverError('INVALID_PPTX','Slide part is missing its slide root');
    let pageText=0,pageElements=0;
    const reserveText=(length:number)=>{if((pageText+=length)>PPTX_EXTRACTION_LIMITS.pageText)throw new DocverError('PPTX_TEXT_LIMIT','PPTX source text exceeds the page extraction budget');budget.reserve('text',length);};
    const reserveElement=()=>{if(++pageElements>PPTX_EXTRACTION_LIMITS.pageElements)throw new DocverError('PPTX_ELEMENT_LIMIT','PPTX elements exceed the page extraction budget');budget.reserve('elements',1);};
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
            const columns=arr(table.tblGrid?.gridCol).map(c=>Number(c['@_w'])),rows=arr(table.tr),columnOffsets=[0],rowOffsets=[0];
            for(const width of columns)columnOffsets.push(columnOffsets.at(-1)!+width);
            for(const row of rows)rowOffsets.push(rowOffsets.at(-1)!+Number(row['@_h']));
            const totalW=columnOffsets.at(-1)!,totalH=rowOffsets.at(-1)!;
            const tableId=id('table',[assetId,path,elements.length]);let yy=0;
            for(const [ri,row] of rows.entries()){
              let xx=0;
              const cells=arr(row.tc),compactRow=cells.length<columns.length;let column=0;
              for(const cell of cells){const ci=column;
                reserveElement();const cellText=bodyText(cell.txBody,reserveText),cw=columns[ci]??0;
                const colSpan=Math.max(1,Number(cell['@_gridSpan']??1)),rowSpan=Math.max(1,Number(cell['@_rowSpan']??1));
                const spanWidth=(columnOffsets[Math.min(columns.length,ci+colSpan)]??columnOffsets.at(-1)!)-(columnOffsets[ci]??columnOffsets.at(-1)!),spanHeight=rowOffsets[Math.min(rows.length,ri+rowSpan)]-rowOffsets[ri];
                const cellBox=totalW>0&&totalH>0?box(bbox[0]+bbox[2]*xx/totalW,bbox[1]+bbox[3]*yy/totalH,bbox[2]*spanWidth/totalW,bbox[3]*spanHeight/totalH):bbox;
                if(cellText&&!['1','true'].includes(String(cell['@_hMerge']))&&!['1','true'].includes(String(cell['@_vMerge'])))elements.push({observation_id:id('obs',[assetId,path,elements.length]),kind:'table_cell',text:cellText,normalized_text:normalize(cellText),bbox:cellBox,reading_order:elements.length,availability:'available',method:'ooxml_table_cell',source_ref:path+'#table/'+ri+'/'+ci,provenance:'observed',table:{table_id:tableId,row:ri,column:ci,row_span:rowSpan,column_span:colSpan,origin:'ooxml_table',assessment:'observed'}});
                xx+=compactRow?spanWidth:cw;column+=compactRow?colSpan:1;
                if(cell['@_gridSpan']||cell['@_rowSpan']||cell['@_hMerge']||cell['@_vMerge'])gaps.push({feature:'table_geometry',reason:'merged_cell_geometry_requires_review'});
              }
              yy+=Number(row['@_h']);
            }
            continue;
          }
          reserveElement();const text=bodyText(shape.txBody,reserveText);
          const element:ElementData={observation_id:id('obs',[assetId,path,elements.length]), kind:kind==='pic'?'image':text?'text':kind==='graphicFrame'?'unsupported':'shape',
            text, normalized_text:normalize(text),bbox,reading_order:elements.length,availability:kind==='graphicFrame'?'unsupported':'available',
            method:'ooxml_text',source_ref:path+'#'+String(shape.nvSpPr?.cNvPr?.['@_id']??elements.length),provenance:'observed'};
          if(kind==='pic') {
            const embed=shape.blipFill?.blip?.['@_r:embed'];
            const rel=slideLinks.get(embed);
            if(rel&&rel['@_TargetMode']!=='External') { const mediaPath=target(path,rel),media=zip[mediaPath];if(media){let hash=mediaHashes.get(mediaPath);if(!hash){hash=byteHash(media);mediaHashes.set(mediaPath,hash);}element.media_hash=hash;} }
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
    if(noteRel) { const note=xml(target(path,noteRel)),parts:string[]=[];let length=0;for(const shape of arr(note.notes?.cSld?.spTree?.sp))if(shape.nvSpPr?.nvPr?.ph?.['@_type']==='body'){const text=bodyText(shape.txBody,characters=>{const amount=characters+(parts.length?1:0);length+=amount;if(length>PPTX_EXTRACTION_LIMITS.pageNotes)throw new DocverError('PPTX_NOTES_LIMIT','PPTX speaker notes exceed the page extraction budget');budget.reserve('notes',amount);});parts.push(text);}notes=parts.join('\n'); }
    const textElements=elements.filter(e=>e.kind==='text'||e.kind==='table_cell');reserveText(Math.max(0,textElements.length-1));
    return { page_id:id('pg',[assetId,index]),asset_id:assetId,page:index+1,width,height,coordinate_system:'ooxml_emu_top_left',source_transform:[1/width,0,0,1/height,0,0],
      hidden:slide['@_show']==='0'||slide['@_show']==='false',text:textElements.map(e=>e.text).join('\n'), elements, notes,
      capabilities:{text:'available',notes:'available',hidden_slides:'available',animation:'unsupported',structure:'available',preview:'unavailable'},
      coverage_gaps:[...gaps,{feature:'preview',reason:'pptx_conversion_not_run'},{feature:'animation',reason:'animation_diff_unsupported'}] };
  });
}
