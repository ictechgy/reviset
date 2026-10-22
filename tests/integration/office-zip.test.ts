import { test } from 'node:test';
import assert from 'node:assert/strict';
import { zipSync, strToU8, Zip, ZipPassThrough, ZipDeflate } from 'fflate';
import { officeZipDirectory, readOfficeZip } from '../../packages/runtime/office-zip.js';
import { extractPptx } from '../../packages/ingest/pptx.js';
import { validateRenderPackage } from '../../packages/render/index.js';
import { MAX_PPTX_PART_BYTES } from '../../packages/schema/index.js';

const parts = {
  'ppt/presentation.xml': strToU8('<p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><p:sldIdLst><p:sldId id="256" r:id="r1"/></p:sldIdLst><p:sldSz cx="960" cy="540"/></p:presentation>'),
  'ppt/_rels/presentation.xml.rels': strToU8('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="r1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide1.xml"/></Relationships>'),
  'ppt/slides/slide1.xml': strToU8('<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld><p:spTree/></p:cSld></p:sld>'),
};
function metadata(bytes: Uint8Array) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength), eocd = bytes.length - 22;
  return { view, central: view.getUint32(eocd + 16, true), eocd };
}
function rejected(bytes: Uint8Array, code = 'INVALID_PPTX') {
  for (const consume of [readOfficeZip, (value: Uint8Array) => extractPptx(value, 'sha256:fixture'), validateRenderPackage]) {
    assert.throws(() => consume(bytes), { code });
  }
}

test('PPTX readers reject forged stored/deflate sizes and CRC before extraction or Office admission', () => {
  for (const level of [0, 6] as const) {
    const source = zipSync(parts, { level });
    assert.equal(extractPptx(source, 'sha256:fixture').length, 1);
    validateRenderPackage(source);
    for (const bothHeaders of [false, true]) {
      const bytes = source.slice(), { view, central } = metadata(bytes), local = view.getUint32(central + 42, true);
      view.setUint32(central + 24, 1, true);
      if (bothHeaders) view.setUint32(local + 22, 1, true);
      rejected(bytes);
    }
    const corrupt = source.slice(), { view, central } = metadata(corrupt), local = view.getUint32(central + 42, true);
    const wrong = (view.getUint32(central + 16, true) ^ 1) >>> 0;
    view.setUint32(central + 16, wrong, true); view.setUint32(local + 14, wrong, true);
    rejected(corrupt);
  }
});

test('ZIP admission rejects aliases, special files, path traversal, overlap, and oversized metadata', () => {
  rejected(zipSync({ ...parts, 'PPT/SLIDES/slide1.xml': parts['ppt/slides/slide1.xml'] }));
  rejected(zipSync({ '../outside': strToU8('x') }), 'ZIP_PATH');
  rejected(zipSync({ 'unsafe\\part': strToU8('x') }), 'ZIP_PATH');
  const source = zipSync(parts, { level: 0 });
  const huge = source.slice(), hugeMeta = metadata(huge);
  hugeMeta.view.setUint32(hugeMeta.central + 24, MAX_PPTX_PART_BYTES + 1, true);
  rejected(huge, 'ZIP_LIMIT');
  const special = source.slice(), specialMeta = metadata(special);
  specialMeta.view.setUint32(specialMeta.central + 38, 0xa0000000, true);
  rejected(special);
  const overlap = source.slice(), overlapMeta = metadata(overlap);
  const second = overlapMeta.central + 46 + overlapMeta.view.getUint16(overlapMeta.central + 28, true) + overlapMeta.view.getUint16(overlapMeta.central + 30, true) + overlapMeta.view.getUint16(overlapMeta.central + 32, true);
  overlapMeta.view.setUint32(second + 42, 0, true);
  rejected(overlap);
});

function streamed(compressed: boolean): Uint8Array {
  const chunks: Uint8Array[] = [];
  const zip = new Zip((error, bytes) => { if (error) throw error; chunks.push(bytes); });
  for (const [name, content] of Object.entries(parts)) {
    const entry = compressed ? new ZipDeflate(name) : new ZipPassThrough(name);
    zip.add(entry); entry.push(content, true);
  }
  zip.end();
  return Buffer.concat(chunks);
}
test('valid streamed ZIP descriptors retain original bytes; contradictory descriptors are rejected', () => {
  for (const compressed of [false, true]) {
    const bytes = streamed(compressed), entries = officeZipDirectory(bytes), decoded = readOfficeZip(bytes);
    for (const [name, content] of Object.entries(parts)) assert.deepEqual(Buffer.from(decoded[name]), Buffer.from(content));
    assert.equal(extractPptx(bytes, 'sha256:fixture').length, 1); validateRenderPackage(bytes);
    const corrupt = bytes.slice(), view = new DataView(corrupt.buffer, corrupt.byteOffset, corrupt.byteLength);
    view.setUint32(entries[0].end + 8, 1, true);
    rejected(corrupt);
  }
  assert.equal(readOfficeZip(zipSync({ empty: new Uint8Array() })).empty.length, 0);
});
