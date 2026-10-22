import { crc32, inflateRawSync } from 'node:zlib';
import { DocverError, MAX_PPTX_EXPANDED_BYTES, MAX_PPTX_PART_BYTES } from '../schema/index.js';

export interface OfficeZipEntry {
  name: string;
  size: number;
  compressed: number;
  compression: number;
  crc: number;
  offset: number;
  start: number;
  end: number;
  recordEnd: number;
}

const invalid = (message: string): never => { throw new DocverError('INVALID_PPTX', message); };
const limit = (): never => { throw new DocverError('ZIP_LIMIT', 'Office package exceeds extraction limits'); };

// Validate metadata before allocating output. In particular, stored members
// cannot use a forged expanded size to bypass admission, and all readers use
// the same local/central-header interpretation before sending bytes to Office.
export function officeZipDirectory(bytes: Uint8Array): OfficeZipEntry[] {
  if (bytes.length < 22) invalid('Invalid Office ZIP package');
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const u16 = (offset: number) => view.getUint16(offset, true);
  const u32 = (offset: number) => view.getUint32(offset, true);
  const lower = Math.max(0, bytes.length - 65_557);
  let eocd = bytes.length - 22;
  while (eocd >= lower && (u32(eocd) !== 0x06054b50 || eocd + 22 + u16(eocd + 20) !== bytes.length)) eocd--;
  if (eocd < lower) invalid('Invalid ZIP directory');
  if (u16(eocd + 4) || u16(eocd + 6) || u16(eocd + 8) !== u16(eocd + 10)) invalid('Multi-disk Office ZIP is unsupported');
  const count = u16(eocd + 10), length = u32(eocd + 12), directory = u32(eocd + 16);
  if (count === 0xffff || length === 0xffffffff || directory === 0xffffffff) invalid('ZIP64 Office package is unsupported');
  if (directory + length !== eocd) invalid('ZIP directory bounds disagree');
  const entries: OfficeZipEntry[] = [], names = new Set<string>();
  const decoder = new TextDecoder('utf-8', { fatal: true });
  let cursor = directory, expanded = 0;
  for (let index = 0; index < count; index++) {
    if (cursor + 46 > eocd || u32(cursor) !== 0x02014b50) invalid('Malformed ZIP central directory');
    const flags = u16(cursor + 8), compression = u16(cursor + 10), crc = u32(cursor + 16);
    const compressed = u32(cursor + 20), size = u32(cursor + 24), nameLength = u16(cursor + 28);
    const extraLength = u16(cursor + 30), commentLength = u16(cursor + 32), disk = u16(cursor + 34);
    const mode = u32(cursor + 38) >>> 16, offset = u32(cursor + 42), next = cursor + 46 + nameLength + extraLength + commentLength;
    if (next > eocd || !nameLength || disk || [offset, compressed, size].includes(0xffffffff)) invalid('Unsupported ZIP member metadata');
    if (flags & ~(8 | 2048 | 2 | 4) || ![0, 8].includes(compression)) invalid('Encrypted or unsupported ZIP member');
    if ((mode & 0xf000) && ![0x8000, 0x4000].includes(mode & 0xf000)) invalid('Special ZIP members are unsupported');
    let name: string;
    try { name = decoder.decode(bytes.subarray(cursor + 46, cursor + 46 + nameLength)); }
    catch { invalid('ZIP names must be UTF-8'); }
    if (name!.includes('\\') || name!.startsWith('/') || /^[A-Za-z]:/.test(name!) || /[\u0000-\u001f\u007f]/.test(name!) || name!.split('/').some(piece => piece === '.' || piece === '..') || name!.includes('//') || name!.length > 1024) {
      throw new DocverError('ZIP_PATH', 'Unsafe Office ZIP part');
    }
    const identity = name!.normalize('NFC').toLowerCase();
    if (names.has(identity)) invalid('Duplicate or aliased Office ZIP part');
    names.add(identity);
    if (size > MAX_PPTX_PART_BYTES || (expanded += size) > MAX_PPTX_EXPANDED_BYTES) limit();
    if (offset + 30 > directory || u32(offset) !== 0x04034b50) invalid('Invalid ZIP local header');
    const localNameLength = u16(offset + 26), start = offset + 30 + localNameLength + u16(offset + 28), end = start + compressed;
    if (u16(offset + 6) !== flags || u16(offset + 8) !== compression || localNameLength !== nameLength || start > directory || end > directory || !bytes.subarray(offset + 30, offset + 30 + nameLength).every((byte, i) => byte === bytes[cursor + 46 + i])) invalid('ZIP local header disagrees with directory');
    if (!(flags & 8) && (u32(offset + 14) !== crc || u32(offset + 18) !== compressed || u32(offset + 22) !== size)) invalid('ZIP local sizes disagree with directory');
    if (compression === 0 && compressed !== size) invalid('Stored ZIP size disagrees with payload size');
    let recordEnd = end;
    if (flags & 8) {
      if (end + 12 > directory) invalid('Missing ZIP data descriptor');
      // An unsigned descriptor's CRC can itself equal the optional signature.
      const candidates = u32(end) === 0x08074b50 ? [end + 4, end] : [end];
      const descriptor = candidates.find(position => position + 12 <= directory && u32(position) === crc && u32(position + 4) === compressed && u32(position + 8) === size);
      if (descriptor === undefined) invalid('ZIP data descriptor disagrees with directory');
      recordEnd = descriptor! + 12;
      for (const [position, expected] of [[14, crc], [18, compressed], [22, size]]) {
        if (u32(offset + position) !== 0 && u32(offset + position) !== expected) invalid('ZIP streamed local size disagrees with directory');
      }
    }
    entries.push({ name: name!, size, compressed, compression, crc, offset, start, end, recordEnd });
    cursor = next;
  }
  if (cursor !== eocd) invalid('Unexpected ZIP directory bytes');
  const ordered = [...entries].sort((a, b) => a.offset - b.offset);
  for (let index = 1; index < ordered.length; index++) {
    if (ordered[index].offset < ordered[index - 1].recordEnd) invalid('Overlapping ZIP members');
  }
  return entries;
}

export function readOfficeZipPart(bytes: Uint8Array, entry: OfficeZipEntry): Uint8Array {
  let content: Uint8Array;
  try {
    content = entry.compression === 0 ? bytes.subarray(entry.start, entry.end)
      : inflateRawSync(bytes.subarray(entry.start, entry.end), { maxOutputLength: Math.max(1, entry.size + 1) });
  } catch { invalid('Corrupt or oversized compressed Office ZIP part'); }
  if (content!.length !== entry.size || crc32(content!) !== entry.crc) invalid('Office ZIP part size or CRC mismatch');
  return content!;
}

export function readOfficeZip(bytes: Uint8Array): Record<string, Uint8Array> {
  const result: Record<string, Uint8Array> = Object.create(null);
  for (const entry of officeZipDirectory(bytes)) result[entry.name] = readOfficeZipPart(bytes, entry);
  return result;
}
