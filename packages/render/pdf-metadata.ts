// The pinned Impress exporter writes a classic xref table. Use its offsets and
// direct dictionary entries; never search or rewrite drawing/image/font streams.
type Token={start:number;end:number;text:string};
function dictionary(source:string):Map<string,Token>{
  let at=0;
  const whitespace=()=>{while(at<source.length){if(/\s/.test(source[at]))at++;else if(source[at]==='%'){while(at<source.length&&!/[\r\n]/.test(source[at]))at++;}else break;}};
  function value(depth=0):Token{
    if(depth>64)throw new Error('Metadata nesting');whitespace();const start=at;
    if(source.startsWith('<<',at)){at+=2;while(true){whitespace();if(source.startsWith('>>',at)){at+=2;break;}if(at>=source.length)throw new Error('Dictionary');value(depth+1);}}
    else if(source[at]==='['){at++;while(true){whitespace();if(source[at]===']'){at++;break;}if(at>=source.length)throw new Error('Array');value(depth+1);}}
    else if(source[at]==='('){let nesting=1;at++;while(nesting&&at<source.length){const c=source[at++];if(c==='\\'){if(source[at]==='\r'&&source[at+1]==='\n')at+=2;else at++;}else if(c==='(')nesting++;else if(c===')')nesting--;}if(nesting)throw new Error('String');}
    else if(source[at]==='<'){at++;while(at<source.length&&source[at]!=='>')at++;if(source[at++]!=='>')throw new Error('Hex string');}
    else {if(source[at]==='/')at++;while(at<source.length&&!/[\s()[\]<>/%]/.test(source[at]))at++;if(at===start)throw new Error('Token');
      if(/^\d+$/.test(source.slice(start,at))){const reference=/^\s+\d+\s+R\b/.exec(source.slice(at));if(reference)at+=reference[0].length;}}
    return {start,end:at,text:source.slice(start,at)};
  }
  whitespace();if(!source.startsWith('<<',at))throw new Error('Direct dictionary required');at+=2;
  const entries=new Map<string,Token>();
  while(true){whitespace();if(source.startsWith('>>',at))break;const key=value();if(!/^\/[^\s]+$/.test(key.text))throw new Error('Dictionary key');if(entries.has(key.text))throw new Error('Duplicate key');entries.set(key.text,value());}
  return entries;
}
export function normalizeConvertedPdf(bytes:Buffer):Buffer{
  const source=bytes.toString('latin1'),footer=/startxref\s+(\d+)\s+%%EOF\s*$/.exec(source);
  if(!footer)return bytes;
  const xref=Number(footer[1]),table=/^xref\s+([\s\S]*?)\btrailer\s*/.exec(source.slice(xref));
  if(!table)return bytes; // Unknown exporter syntax is preserved byte-for-byte.
  try{
    const fields=table[1].trim().split(/\s+/),objects=new Map<string,number>();let cursor=0;
    while(cursor<fields.length){const first=Number(fields[cursor++]),count=Number(fields[cursor++]);if(!Number.isInteger(first)||!Number.isInteger(count)||count<0||count>1_000_000)throw new Error('xref');
      for(let n=0;n<count;n++){const offset=Number(fields[cursor++]),generation=fields[cursor++],state=fields[cursor++];if(!Number.isInteger(offset)||!/^\d+$/.test(generation??'')||!['n','f'].includes(state))throw new Error('xref row');if(state==='n'){if(offset<=0||offset>=xref)throw new Error('xref offset');objects.set(`${first+n} ${Number(generation)} R`,offset);}}}
    const edits:{start:number;end:number;text:string}[]=[],trailerStart=xref+table[0].length,trailer=dictionary(source.slice(trailerStart));
    const queue=(base:number,t:Token,text:string)=>{if(text.length!==t.text.length)throw new Error('Metadata width');edits.push({start:base+t.start,end:base+t.end,text});};
    const id=trailer.get('/ID');if(id&&/^\[\s*<[a-f0-9]+>\s*<[a-f0-9]+>\s*\]$/i.test(id.text))queue(trailerStart,id,id.text.replace(/<[a-f0-9]+>/gi,t=>'<'+ '0'.repeat(t.length-2)+'>'));
    const checksum=trailer.get('/DocChecksum');if(checksum&&/^\/[a-f0-9]+$/i.test(checksum.text))queue(trailerStart,checksum,'/'+ '0'.repeat(checksum.text.length-1));
    const objectAt=(reference:string)=>{const offset=objects.get(reference);if(!offset)throw new Error('Object reference');const limit=Math.min(xref,...[...objects.values()].filter(n=>n>offset)),object=source.slice(offset,limit),header=/^\d+\s+\d+\s+obj\s*/.exec(object);if(!header)throw new Error('Object header');return {base:offset+header[0].length,limit,body:object.slice(header[0].length)};};
    // Only a catalog-referenced, unfiltered XML metadata stream is eligible.
    const root=trailer.get('/Root');if(root){const catalog=objectAt(root.text),metadata=dictionary(catalog.body).get('/Metadata');if(metadata){const object=objectAt(metadata.text),entries=dictionary(object.body),length=Number(entries.get('/Length')?.text),stream=/^<<[\s\S]*?>>\s*stream\r?\n/.exec(object.body);
      if(entries.get('/Type')?.text==='/Metadata'&&entries.get('/Subtype')?.text==='/XML'&&!entries.has('/Filter')&&Number.isInteger(length)&&length>=0&&stream&&object.base+stream[0].length+length<=object.limit){
        const start=object.base+stream[0].length,xml=source.slice(start,start+length);if(/^<\?xpacket\b/.test(xml)&&xml.includes('</x:xmpmeta>')){
          const normalized=xml.replace(/(<xmp:(?:CreateDate|ModifyDate|MetadataDate)>)(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?=[^<]*<\/xmp:)/g,'$11970-01-01T00:00:00').replace(/(<dc:date>\s*<rdf:Seq>\s*<rdf:li>)(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?=[^<]*<\/rdf:li>)/g,'$11970-01-01T00:00:00');
          queue(start,{start:0,end:length,text:xml},normalized);
        }
      }
    }}
    const info=trailer.get('/Info'),offset=info?objects.get(info.text):undefined;
    if(offset){const limit=Math.min(xref,...[...objects.values()].filter(n=>n>offset)),object=source.slice(offset,limit),header=/^\d+\s+\d+\s+obj\s*/.exec(object);if(!header)throw new Error('Info object');
      const base=offset+header[0].length,entries=dictionary(source.slice(base,limit));
      for(const key of ['/CreationDate','/ModDate']){const token=entries.get(key);if(token&&/^\(D:\d{14}[^()]*\)$/.test(token.text))queue(base,token,token.text.replace(/D:\d{14}/,'D:19700101000000'));}}
    const result=Buffer.from(bytes);for(const edit of edits)result.write(edit.text,edit.start,edit.end-edit.start,'latin1');return result;
  }catch{return bytes;}
}
