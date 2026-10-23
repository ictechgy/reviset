import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, mkdir, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {execFileSync} from 'node:child_process';
import {buildLocalizationResources, readLocalizationCatalog, validateLocalizationCatalog, validateLocalizationKeys, validateSourceLocalizationKeys} from '../../scripts/localization.js';

test('localization catalog rejects missing languages, placeholders, duplicate keys and unresolved source keys', async () => {
  assert.throws(() => validateLocalizationCatalog({'test.label': {en: 'Hello'}}), /en and ko/u);
  assert.throws(() => validateLocalizationCatalog({'Hello, {0}': {en: 'Hello', ko: '안녕'}}), /semantic/u);
  assert.throws(() => validateLocalizationCatalog({'test.label': {en: '{0}', ko: '{1}'}}), /contiguous/u);
  assert.throws(() => validateLocalizationCatalog({'test.label': {en: '{0}', ko: '없음'}}), /placeholder sets differ/u);
  assert.throws(() => validateLocalizationCatalog({'test.label': {en: '{name}', ko: '{name}'}}), /invalid numbered placeholder/u);
  assert.throws(() => validateLocalizationCatalog({'test.label': {en: '{{0}}', ko: '{0}'}}), /nested placeholder braces/u);
  assert.throws(() => validateLocalizationCatalog({'test.label': {en: '{0', ko: '{0'}}), /unmatched/u);
  assert.doesNotThrow(() => validateLocalizationCatalog({'test.camelCase': {en: 'Hello', ko: '안녕'}}));
  const catalog = validateLocalizationCatalog({'test.label': {en: '{0} {1}', ko: '{1} {0}'}});
  assert.doesNotThrow(() => validateLocalizationKeys(catalog, ['test.label']));
  assert.throws(() => validateLocalizationKeys(catalog, ['test.missing']), /Missing localization key/u);
  const root = await mkdtemp(join(tmpdir(), 'reviset-localization-validation-'));
  try {
    await writeFile(join(root, 'A.json'), JSON.stringify({'test.label': {en: 'Hello', ko: '안녕'}}));
    await writeFile(join(root, 'B.json'), JSON.stringify({'test.label': {en: 'Other', ko: '다름'}}));
    await assert.rejects(readLocalizationCatalog(root), /duplicate localization key/u);
    await rm(join(root, 'B.json'));
    await writeFile(join(root, 'A.json'), '{"test.label":{"en":"First","en":"Second","ko":"안녕"}}');
    await assert.rejects(readLocalizationCatalog(root), /duplicate JSON property en/u);
    await writeFile(join(root, 'A.json'), '{"test.label":{"en":"First","ko":"안녕"},"test.label":{"en":"Second","ko":"다름"}}');
    await assert.rejects(readLocalizationCatalog(root), /duplicate JSON property test.label/u);
    await writeFile(join(root, 'Probe.swift'), 'let label = L("test.missing")');
    await assert.rejects(validateSourceLocalizationKeys(catalog, root), /Probe.swift: Missing localization key/u);
    await writeFile(join(root, 'Probe.swift'), 'let label = UIMessage.plural("test.count", 2)');
    await assert.rejects(validateSourceLocalizationKeys(catalog, root), /test.count.one/u);
    const sourceCatalog = validateLocalizationCatalog({...catalog, 'test.inner': {en: 'Inner', ko: '안쪽'}, 'test.count.one': {en: '{0} item', ko: '{0}개'}, 'test.count.other': {en: '{0} items', ko: '{0}개'}});
    await writeFile(join(root, 'Probe.swift'), String.raw`
// L("test.missing")
/* nested /* UIMessage("test.missing") */ comments */
let opaque = #"L("test.missing")"#
let valid = L("test.label", .verbatim("comma, )"), .message(UIMessage("test.inner")))
let interpolated = "value \(L("test.inner"))"
let multiline = L(
  "test.label",
  .verbatim("nested \(value["key"])"),
  .verbatim(#"raw comma, ) and \" quote"#)
)
let count = UIMessage.plural("test.count", 2)
`);
    await assert.doesNotReject(validateSourceLocalizationKeys(sourceCatalog, root));
    await writeFile(join(root, 'Probe.swift'), 'let label = L("test.label", .verbatim("only one"))');
    await assert.rejects(validateSourceLocalizationKeys(sourceCatalog, root), /expected 2 argument\(s\), got 1/u);
    await writeFile(join(root, 'Probe.swift'), String.raw`let interpolated = "value \(L("test.inner", .count(2)))"`);
    await assert.rejects(validateSourceLocalizationKeys(sourceCatalog, root), /test.inner: expected 0 argument\(s\), got 1/u);
  } finally { await rm(root, {recursive: true, force: true}); }
});

test('native localization preserves raw data, chooses plural forms, falls back and rerenders typed state', {skip: process.platform !== 'darwin', timeout: 45000}, async () => {
  const root = await mkdtemp(join(tmpdir(), 'reviset-native-localization-'));
  try {
    const contents = join(root, 'LocalizationProbe.app/Contents');
    const resources = join(contents, 'Resources');
    const executable = join(contents, 'MacOS/LocalizationProbe');
    const domains = join(root, 'catalog');
    await mkdir(join(contents, 'MacOS'), {recursive: true});
    await mkdir(domains);
    await writeFile(join(contents, 'Info.plist'), '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>LocalizationProbe</string><key>CFBundleIdentifier</key><string>org.reviset.localization-checks</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleDevelopmentRegion</key><string>en</string><key>CFBundleLocalizations</key><array><string>en</string><string>ko</string></array></dict></plist>');
    const common = JSON.parse(await readFile(resolve('apps/macos/Localization/Common.json'), 'utf8')) as Record<string, {en: string; ko: string}>;
    const fixture = {
      ...common,
      'test.greeting': {en: 'Hello, {0}', ko: '안녕하세요, {0}'},
      'test.items.one': {en: '{0} item', ko: '{0}개'},
      'test.items.other': {en: '{0} items', ko: '{0}개'},
      'test.wrap': {en: '[{0}]', ko: '[{0}]'},
      'test.nested': {en: '{0} / {1}', ko: '{0} / {1}'},
      'test.percent': {en: '%@ %% {0}', ko: '%@ %% {0}'},
      'test.escape': {en: 'Quoted "value" \\ path\nnext\ttab', ko: '인용 "값" \\ 경로\n다음\t탭'},
      'test.fallback': {en: 'English fallback', ko: '한국어 대체'},
    };
    await writeFile(join(domains, 'Test.json'), JSON.stringify(fixture));
    await buildLocalizationResources(resources, {catalogDirectory: domains, sourceDirectory: null});
    const koreanTable = join(resources, 'ko.lproj/Reviset.strings');
    await writeFile(koreanTable, (await readFile(koreanTable, 'utf8')).split('\n').filter(line => !line.startsWith('"test.fallback"')).join('\n'));
    execFileSync('swiftc', ['-warnings-as-errors', '-swift-version', '5', '-parse-as-library', '-target', 'arm64-apple-macos14.0', 'apps/macos/Localization.swift', 'tests/native/LocalizationChecks.swift', '-o', executable], {timeout: 25000, stdio: 'pipe'});
    const stdout = execFileSync(executable, [join(root, 'LocalizationProbe.app')], {encoding: 'utf8', timeout: 12000, env: {PATH: '/usr/bin:/bin'}});
    assert.match(stdout, /PASS localization:/u);
  } finally { await rm(root, {recursive: true, force: true}); }
});
