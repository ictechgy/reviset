import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, mkdir, chmod, rm, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { DesktopService } from '../../packages/desktop/service.js';
import { Report, SCHEMA_VERSION, ENGINE_VERSION, SCHEMA_HASH, hash, byteHash } from '../../packages/schema/index.js';
import { Store } from '../../packages/storage/index.js';

test('store revalidates mutable reports and preserves the cause of an automatic SQLite rollback', async () => {
  const root=await mkdtemp(join(tmpdir(),'reviset-store-rollback-')),store=new Store(root);
  try{
    const report=Report.parse({schema_version:SCHEMA_VERSION,engine_version:ENGINE_VERSION,schema_hash:SCHEMA_HASH,project_id:'project_rollback',report_id:'report_rollback',timeline_revision_id:'timeline',mapping_revision_id:'mapping',observation_environment:{},revisions:[],matches:[],candidates:[],mapping_decisions:[],lineages:[],changes:[],coverage_gaps:[]});
    const run=store.beginRun(report.project_id,'Rollback boundary');
    (report as any).schema_version='invalid';
    assert.throws(()=>store.finishRun(run,report));
    assert.equal(store.reports(report.project_id).length,0);
    report.schema_version=SCHEMA_VERSION;
    store.db.exec("CREATE TRIGGER reject_report BEFORE INSERT ON reports BEGIN SELECT RAISE(ROLLBACK,'original storage rejection'); END;");
    assert.throws(()=>store.finishRun(run,report),/original storage rejection/);
    assert.equal(store.reports(report.project_id).length,0);
    assert.equal(store.db.prepare('SELECT status FROM runs WHERE id=?').get(run)?.status,'running');
    store.db.exec('DROP TRIGGER reject_report');
    store.finishRun(run,report);
    assert.deepEqual(store.report(report.project_id,report.report_id),report);
  }finally{store.close();await rm(root,{recursive:true,force:true});}
});

test('document commit remains successful after stage cleanup fails and run status reconciles the fixed snapshot', async () => {
  const root = await mkdtemp(join(tmpdir(), 'reviset-commit-boundary-'));
  const library = join(root, 'library'), folder = join(library, 'staging-v4');
  const service = new DesktopService(library);
  const call = (action: string, args: unknown, success = true) => {
    const result = spawnSync(process.execPath, ['--import', 'tsx', resolve('apps/bridge/main.ts'), '--root', library], { input: JSON.stringify({ action, args }), encoding: 'utf8', timeout: 10000 });
    assert.ifError(result.error);
    assert.equal(result.status, success ? 0 : 1, result.stdout + result.stderr);
    const response = JSON.parse(result.stdout); assert.equal(response.ok, success);
    return success ? response.value : response.error;
  };
  try {
    const source = join(root, 'source.pdf'); await writeFile(source, 'synthetic original');
    const project = await service.create('Commit boundary', [{ label: 'v1', files: [source] }]);
    const other = await service.create('Other project', [{ label: 'v1', files: [source] }]);
    const report = (report_id: string) => Report.parse({ schema_version: SCHEMA_VERSION, engine_version: ENGINE_VERSION, schema_hash: SCHEMA_HASH, project_id: project.project_id, report_id, timeline_revision_id: 'timeline', mapping_revision_id: 'mapping', observation_environment: { fixture: 'commit-boundary' }, revisions: [], matches: [], candidates: [], mapping_decisions: [], lineages: [], changes: [], coverage_gaps: [] });
    const prior = report('report_prior');
    service.commit(project.project_id, { report: prior, analysis_run_id: service.store.beginRun(project.project_id, project.title), draft_hash: hash(service.manifest(project.project_id)) });
    const oldBody = service.store.db.prepare('SELECT body FROM reports WHERE id=?').get(prior.report_id)?.body;
    const next = report('report_next'), run = service.store.beginRun(project.project_id, project.title);
    const bytes = Buffer.from(JSON.stringify(next)); await mkdir(folder); await writeFile(join(folder, run + '.json'), bytes);
    const stage = { analysis_run_id: run, report_id: next.report_id, staged_name: run + '.json', sha256: byteHash(bytes), draft_hash: hash(service.manifest(project.project_id)), project_id: project.project_id, schema_version: SCHEMA_VERSION, engine_version: ENGINE_VERSION };
    const scope = { project_id: project.project_id, analysis_run_id: run };
    assert.equal(call('runStatus', scope).status, 'running');
    assert.equal(call('runStatus', { ...scope, project_id: other.project_id }, false).code, 'RUN_SCOPE');
    assert.equal(call('commit', { project_id: project.project_id, result: { ...stage, sha256: '0'.repeat(64) } }, false).code, 'STAGED_HASH');
    assert.equal(call('runStatus', scope).status, 'running');
    await chmod(folder, 0o500);
    const committed = call('commit', { project_id: project.project_id, result: stage });
    assert.deepEqual(committed, { report_id: next.report_id, status: 'complete', cleanup_pending: true });
    const status = call('runStatus', scope);
    assert.equal(status.status, 'success'); assert.equal(status.report_id, next.report_id); assert.equal(status.cleanup_pending, true);
    assert.equal(service.project(project.project_id).last_report_id, next.report_id);
    assert.equal(service.store.db.prepare('SELECT body FROM reports WHERE id=?').get(prior.report_id)?.body, oldBody);
    assert.deepEqual(await readFile(join(folder, run + '.json')), bytes);
    assert.equal(call('commit', { project_id: project.project_id, result: stage }, false).code, 'INVALID_RUN');
    await chmod(folder, 0o700); call('recover', { run_id: run });
    const cleaned = call('runStatus', scope);
    assert.equal(cleaned.status, 'success'); assert.equal(cleaned.report_id, next.report_id); assert.equal(cleaned.cleanup_pending, false);
    const active = service.store.beginRun(project.project_id, project.title);
    call('recover', { run_id: active });
    assert.equal(call('runStatus', { ...scope, analysis_run_id: active }).status, 'interrupted');
  } finally {
    service.close(); await chmod(folder, 0o700).catch(() => {}); await rm(root, { recursive: true, force: true });
  }
});
