import {mkdir, readFile, readdir, writeFile} from 'node:fs/promises';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

export type LocalizationLanguage = 'en' | 'ko';
export type LocalizationCatalog = Record<string, Record<LocalizationLanguage, string>>;
const languages: readonly LocalizationLanguage[] = ['en', 'ko'];
const sourceRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../apps/macos');
const defaultCatalogDirectory = join(sourceRoot, 'Localization');
const semanticKey = /^[a-z][a-zA-Z0-9]*(?:[._][a-zA-Z0-9]+)+$/u;

function placeholders(value: string, key: string, language: string): number[] {
  const indices = new Set<number>();
  for (const token of value.matchAll(/\{([^{}]*)\}/gu)) {
    if (!/^(?:0|[1-9][0-9]*)$/u.test(token[1]!)) throw new Error(`${key}/${language}: invalid numbered placeholder ${token[0]}`);
    const index = Number(token[1]);
    if (!Number.isSafeInteger(index)) throw new Error(`${key}/${language}: placeholder index is too large`);
    indices.add(index);
  }
  if (/[{}]/u.test(value.replace(/\{(?:0|[1-9][0-9]*)\}/gu, ''))) throw new Error(`${key}/${language}: unmatched or nested placeholder braces`);
  const ordered = [...indices].sort((a, b) => a - b);
  if (ordered.some((value, index) => value !== index)) throw new Error(`${key}/${language}: placeholders must be contiguous from {0}`);
  return ordered;
}

export function validateLocalizationCatalog(value: unknown): LocalizationCatalog {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Localization catalog must be an object');
  const catalog: LocalizationCatalog = Object.create(null) as LocalizationCatalog;
  for (const [key, entry] of Object.entries(value)) {
    if (!semanticKey.test(key)) throw new Error(`Invalid semantic localization key: ${key}`);
    if (!entry || typeof entry !== 'object' || Array.isArray(entry)) throw new Error(`${key}: translations must be an object`);
    const translations = entry as Record<string, unknown>;
    if (Object.keys(translations).sort().join(',') !== [...languages].sort().join(',')) throw new Error(`${key}: exactly en and ko translations are required`);
    for (const language of languages) {
      if (typeof translations[language] !== 'string' || !translations[language].length) throw new Error(`${key}/${language}: a nonempty translation is required`);
    }
    const en = translations.en as string, ko = translations.ko as string;
    if (placeholders(en, key, 'en').join(',') !== placeholders(ko, key, 'ko').join(',')) throw new Error(`${key}: placeholder sets differ between en and ko`);
    catalog[key] = {en, ko};
  }
  return catalog;
}

// JSON.parse discards duplicate properties, so reject them before parsing each domain.
// At object boundaries this scanner distinguishes property names from string values.
function rejectDuplicateJSONProperties(text: string, file: string): void {
  const objectKeys: Array<Set<string> | null> = [];
  let expectingKey = false;
  for (let index = 0; index < text.length; index++) {
    const character = text[index];
    if (character === '"') {
      let end = index + 1;
      while (end < text.length) {
        if (text[end] === '\\') { end += 2; continue; }
        if (text[end] === '"') break;
        end++;
      }
      const decoded = JSON.parse(text.slice(index, end + 1)) as string;
      const current = objectKeys.at(-1);
      if (expectingKey && current) {
        if (current.has(decoded)) throw new Error(`${file}: duplicate JSON property ${decoded}`);
        current.add(decoded);
      }
      expectingKey = false;
      index = end;
    } else if (character === '{') {
      objectKeys.push(new Set()); expectingKey = true;
    } else if (character === '[') {
      objectKeys.push(null); expectingKey = false;
    } else if (character === '}' || character === ']') {
      objectKeys.pop(); expectingKey = false;
    } else if (character === ',') {
      expectingKey = objectKeys.at(-1) !== null;
    } else if (character === ':') {
      expectingKey = false;
    }
  }
}

export async function readLocalizationCatalog(catalogDirectory = defaultCatalogDirectory): Promise<LocalizationCatalog> {
  const files = (await readdir(catalogDirectory)).filter(file => file.endsWith('.json')).sort();
  if (!files.length) throw new Error('No localization catalog domains found');
  const combined: LocalizationCatalog = Object.create(null) as LocalizationCatalog;
  for (const file of files) {
    const text = await readFile(join(catalogDirectory, file), 'utf8');
    rejectDuplicateJSONProperties(text, file);
    const catalog = validateLocalizationCatalog(JSON.parse(text));
    for (const [key, entry] of Object.entries(catalog)) {
      if (Object.hasOwn(combined, key)) throw new Error(`${file}: duplicate localization key ${key}`);
      combined[key] = entry;
    }
  }
  return combined;
}

export function validateLocalizationKeys(catalog: LocalizationCatalog, keys: Iterable<string>): void {
  for (const key of keys) if (!Object.hasOwn(catalog, key)) throw new Error(`Missing localization key: ${key}`);
}

function swiftCommentEnd(text: string, start: number): number | null {
  if (text.startsWith('//', start)) {
    const end = text.indexOf('\n', start + 2);
    return end < 0 ? text.length : end;
  }
  if (!text.startsWith('/*', start)) return null;
  let depth = 1, cursor = start + 2;
  while (cursor < text.length && depth) {
    if (text.startsWith('/*', cursor)) { depth++; cursor += 2; }
    else if (text.startsWith('*/', cursor)) { depth--; cursor += 2; }
    else cursor++;
  }
  return cursor;
}

// Skip a complete Swift string, including raw/multiline delimiters and nested interpolation.
function swiftStringEnd(text: string, start: number, onInterpolation?: (start: number, end: number) => void): number | null {
  let quote = start;
  while (text[quote] === '#') quote++;
  if (text[quote] !== '"') return null;
  const hashes = text.slice(start, quote);
  const quotes = text.startsWith('"""', quote) ? '"""' : '"';
  const closing = quotes + hashes, escape = '\\' + hashes;
  let cursor = quote + quotes.length;
  while (cursor < text.length) {
    if (text.startsWith(closing, cursor)) return cursor + closing.length;
    if (text.startsWith(escape, cursor)) {
      cursor += escape.length;
      if (text[cursor] === '(') {
        cursor++;
        const interpolationStart = cursor;
        let depth = 1;
        while (cursor < text.length && depth) {
          const commentEnd = swiftCommentEnd(text, cursor);
          if (commentEnd !== null) { cursor = commentEnd; continue; }
          const stringEnd = swiftStringEnd(text, cursor);
          if (stringEnd !== null) { cursor = stringEnd; continue; }
          if (text[cursor] === '(') depth++;
          if (text[cursor] === ')') depth--;
          cursor++;
        }
        onInterpolation?.(interpolationStart, cursor - 1);
      } else cursor++;
    } else cursor++;
  }
  return cursor;
}

function swiftLocalizationCalls(text: string): Array<{name: string; key: string; opening: number}> {
  const calls: Array<{name: string; key: string; opening: number}> = [];
  const walk = (start: number, end: number): void => {
    let cursor = start;
    while (cursor < end) {
      const commentEnd = swiftCommentEnd(text, cursor);
      if (commentEnd !== null) { cursor = commentEnd; continue; }
      const stringEnd = swiftStringEnd(text, cursor, walk);
      if (stringEnd !== null) { cursor = stringEnd; continue; }
      if (!/[a-zA-Z0-9_]/u.test(text[cursor - 1] ?? '')) {
        const match = /^(L|LC|UIMessage(?:\.plural)?)\(\s*"([^"\\]*)"/u.exec(text.slice(cursor));
        if (match) calls.push({name: match[1]!, key: match[2]!, opening: cursor + match[1]!.length});
      }
      cursor++;
    }
  };
  walk(0, text.length);
  return calls;
}

function withoutSwiftComments(text: string): string {
  let result = '', cursor = 0;
  while (cursor < text.length) {
    const commentEnd = swiftCommentEnd(text, cursor);
    if (commentEnd !== null) {
      result += text.slice(cursor, commentEnd).replace(/[^\n]/gu, ' ');
      cursor = commentEnd;
      continue;
    }
    const stringEnd = swiftStringEnd(text, cursor);
    if (stringEnd !== null) { result += text.slice(cursor, stringEnd); cursor = stringEnd; continue; }
    result += text[cursor]; cursor++;
  }
  return result;
}

function swiftCallArgumentCount(text: string, opening: number): number {
  let depth = 1, commas = 0, cursor = opening + 1;
  while (cursor < text.length && depth) {
    const commentEnd = swiftCommentEnd(text, cursor);
    if (commentEnd !== null) { cursor = commentEnd; continue; }
    const stringEnd = swiftStringEnd(text, cursor);
    if (stringEnd !== null) { cursor = stringEnd; continue; }
    if ('([{'.includes(text[cursor]!)) depth++;
    if (')]}'.includes(text[cursor]!)) depth--;
    if (text[cursor] === ',' && depth === 1) commas++;
    cursor++;
  }
  if (depth) throw new Error('Unterminated localization call');
  return text.slice(opening + 1, cursor - 1).trim() ? commas + 1 : 0;
}

export async function validateSourceLocalizationKeys(catalog: LocalizationCatalog, sourceDirectory = sourceRoot): Promise<void> {
  for (const file of (await readdir(sourceDirectory)).filter(file => file.endsWith('.swift')).sort()) {
    const text = withoutSwiftComments(await readFile(join(sourceDirectory, file), 'utf8'));
    for (const call of swiftLocalizationCalls(text)) {
      const plural = call.name === 'LC' || call.name === 'UIMessage.plural';
      const keys = plural ? [`${call.key}.one`, `${call.key}.other`] : [call.key];
      try {
        validateLocalizationKeys(catalog, keys);
        const argumentCount = swiftCallArgumentCount(text, call.opening);
        const expected = plural ? 2 : 1 + placeholders(catalog[keys[0]!]!.en, keys[0]!, 'en').length;
        if (argumentCount !== expected) throw new Error(`${call.key}: expected ${expected - 1} argument(s), got ${argumentCount - 1}`);
      } catch (error) { throw new Error(`${file}: ${(error as Error).message}`); }
    }
  }
}

function stringsEscape(value: string): string {
  return value.replace(/\\/gu, '\\\\').replace(/"/gu, '\\"').replace(/\n/gu, '\\n').replace(/\r/gu, '\\r').replace(/\t/gu, '\\t')
    .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/gu, character => `\\U${character.charCodeAt(0).toString(16).padStart(4, '0')}`);
}

export async function buildLocalizationResources(resourcesDirectory: string, options: {catalogDirectory?: string; sourceDirectory?: string | null} = {}): Promise<LocalizationCatalog> {
  const catalog = await readLocalizationCatalog(options.catalogDirectory);
  if (options.sourceDirectory !== null) await validateSourceLocalizationKeys(catalog, options.sourceDirectory);
  for (const language of languages) {
    const directory = join(resourcesDirectory, `${language}.lproj`);
    await mkdir(directory, {recursive: true});
    const rows = Object.keys(catalog).sort().map(key => `"${stringsEscape(key)}" = "${stringsEscape(catalog[key]![language])}";`);
    await writeFile(join(directory, 'Reviset.strings'), `/* Generated from apps/macos/Localization/*.json. */\n${rows.join('\n')}\n`, 'utf8');
  }
  return catalog;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const command = process.argv[2] ?? 'validate';
  if (command === 'validate') {
    const catalog = await readLocalizationCatalog();
    await validateSourceLocalizationKeys(catalog);
    console.log(JSON.stringify({localization: 'valid', languages, keys: Object.keys(catalog).length}));
  } else if (command === 'build' && process.argv[3]) {
    const catalog = await buildLocalizationResources(resolve(process.argv[3]));
    console.log(JSON.stringify({localization: 'built', languages, keys: Object.keys(catalog).length}));
  } else throw new Error('Usage: tsx scripts/localization.ts validate | build <bundle-resources-directory>');
}
