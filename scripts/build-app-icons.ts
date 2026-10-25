import {createCanvas,loadImage} from '@napi-rs/canvas';
import {mkdir,readFile,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';

// Package the selected artwork in a fixed native icon silhouette. Keep the
// original raster master intact; the mask removes backdrop/alpha edge debris
// without changing the displaced-layer mark inside the tile.
const directory=resolve('assets/branding');
const source=await loadImage(await readFile(resolve(directory,'reviset-icon-source.png')));
if(source.width!==1254||source.height!==1254)throw new Error('Unexpected icon master dimensions. Recheck the packaging crop before replacing the master.');
const canvas=createCanvas(1024,1024),context=canvas.getContext('2d');
context.beginPath();context.roundRect(56,56,912,912,205);context.clip();
context.fillStyle='#f5f1e9';context.fillRect(0,0,1024,1024);
context.imageSmoothingEnabled=true;context.imageSmoothingQuality='high';
context.drawImage(source,114,96,1024,1024,56,56,912,912);
await mkdir(directory,{recursive:true});
await writeFile(resolve(directory,'reviset-icon.png'),canvas.toBuffer('image/png'));

// PNG-compressed ICO frames are supported by the target Windows/WPF runtime.
const sizes=[16,24,32,48,64,128,256];
const frames=sizes.map(size=>{
  const frame=createCanvas(size,size),ctx=frame.getContext('2d');
  ctx.imageSmoothingEnabled=true;ctx.imageSmoothingQuality='high';
  ctx.drawImage(canvas,0,0,size,size);return frame.toBuffer('image/png');
});
const header=Buffer.alloc(6+16*frames.length);header.writeUInt16LE(1,2);header.writeUInt16LE(frames.length,4);
let offset=header.length;
for(let index=0;index<frames.length;index++){
  const entry=6+16*index,size=sizes[index],frame=frames[index];
  header[entry]=size===256?0:size;header[entry+1]=size===256?0:size;
  header.writeUInt16LE(1,entry+4);header.writeUInt16LE(32,entry+6);
  header.writeUInt32LE(frame.length,entry+8);header.writeUInt32LE(offset,entry+12);offset+=frame.length;
}
await writeFile(resolve(directory,'reviset.ico'),Buffer.concat([header,...frames]));
console.log(JSON.stringify({png:resolve(directory,'reviset-icon.png'),ico:resolve(directory,'reviset.ico'),sizes}));
