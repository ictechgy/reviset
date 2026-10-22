import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, rm, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DesktopService, DESKTOP_PROJECTS_TABLE } from '../../packages/desktop/service.js';
import { WorkbookService } from '../../packages/workbook/service.js';
import { Store } from '../../packages/storage/index.js';
import { Report, SCHEMA_VERSION, ENGINE_VERSION, SCHEMA_HASH } from '../../packages/schema/index.js';

function transactionIsReusable(store: Store) {
  assert.equal(store.db.isTransaction, false);
  store.db.exec('BEGIN IMMEDIATE');
  assert.equal(store.db.isTransaction, true);
  store.db.exec('ROLLBACK');
}

async function documentFixture() {
  const root = await mkdtemp(join(tmpdir(), 'reviset-draft-rollback-'));
  const source = join(root, 'source.pdf'); await writeFile(source, 'synthetic source; parsing is unnecessary for draft order');
  const service = new DesktopService(join(root, 'library'));
  const draft = await service.create('Rollback boundary', [{label:'v1',files:[source]},{label:'v2',files:[source]}]);
  return { service, draft, close: async () => { service.close(); await rm(root,{recursive:true,force:true}); } };
}

async function workbookFixture() {
  const root = await mkdtemp(join(tmpdir(), 'reviset-workbook-rollback-'));
  const source = join(root, 'source.csv'); await writeFile(source, 'id,value\na,1\n');
  const store = new Store(join(root, 'library')), service = new WorkbookService(store);
  const draft = await service.create('Rollback boundary', [{label:'v1',path:source}]);
  const stage = await service.run(draft.project_id);
  return { store, service, draft, stage, close: async () => { store.close(); await rm(root,{recursive:true,force:true}); } };
}

for (const mode of ['ROLLBACK','ABORT'] as const) {
  test(`desktop reorder preserves SQLite ${mode} cause, original draft and reusable transaction`, async () => {
    const f = await documentFixture();
    try {
      const original = f.service.project(f.draft.project_id);
      f.service.store.db.exec(`CREATE TRIGGER reject_draft BEFORE UPDATE ON ${DESKTOP_PROJECTS_TABLE} BEGIN SELECT RAISE(${mode},'original draft rejection'); END;`);
      assert.throws(() => f.service.reorder(f.draft.project_id,[1,0]), /original draft rejection/);
      assert.deepEqual(f.service.project(f.draft.project_id), original);
      transactionIsReusable(f.service.store);
      f.service.store.db.exec('DROP TRIGGER reject_draft');
      assert.deepEqual(f.service.reorder(f.draft.project_id,[1,0]).revisions.map(r=>r.label),['v2','v1']);
      transactionIsReusable(f.service.store);
    } finally { await f.close(); }
  });

  test(`workbook commit preserves SQLite ${mode} cause and rolls back all partially written indexes`, async () => {
    const f = await workbookFixture();
    try {
      // The report is already inserted when metadata is written. ABORT leaves
      // that insertion in the active transaction until the service rolls back.
      f.store.db.exec(`CREATE TRIGGER reject_metadata BEFORE INSERT ON workbook_metadata_v1 BEGIN SELECT RAISE(${mode},'original workbook rejection'); END;`);
      await assert.rejects(f.service.commit(f.draft.project_id,f.stage), /original workbook rejection/);
      for (const table of ['workbook_reports_v1','workbook_metadata_v1','workbook_cells_v1','workbook_changes_v1']) {
        assert.equal(f.store.db.prepare(`SELECT count(*) AS n FROM ${table}`).get()!.n,0,table);
      }
      assert.equal(f.service.runStatus(f.draft.project_id,f.stage.analysis_run_id).status,'staged');
      assert.ok((await readFile(join(f.store.root,'workbook-staging-v1',f.stage.staged_name))).length>0);
      transactionIsReusable(f.store);
      f.store.db.exec('DROP TRIGGER reject_metadata');
      assert.equal((await f.service.commit(f.draft.project_id,f.stage)).status,'complete');
      assert.equal(f.service.runStatus(f.draft.project_id,f.stage.analysis_run_id).status,'success');
      assert.equal(f.service.reports(f.draft.project_id).length,1);
      transactionIsReusable(f.store);
    } finally { await f.close(); }
  });
}

test('desktop application validation failure closes its transaction without changing the draft', async () => {
  const f = await documentFixture();
  try {
    const original = f.service.project(f.draft.project_id);
    assert.throws(() => f.service.reorder(f.draft.project_id,[0,0]), {code:'INVALID_ORDER'});
    assert.deepEqual(f.service.project(f.draft.project_id),original);
    transactionIsReusable(f.service.store);
  } finally { await f.close(); }
});

test('Store finishRun onCommit failure rolls back the report, run status and callback writes with the same cause', async () => {
  const root = await mkdtemp(join(tmpdir(),'reviset-oncommit-rollback-')), store = new Store(root);
  try {
    const report = Report.parse({schema_version:SCHEMA_VERSION,engine_version:ENGINE_VERSION,schema_hash:SCHEMA_HASH,project_id:'project_rollback',report_id:'report_rollback',timeline_revision_id:'timeline',mapping_revision_id:'mapping',observation_environment:{},revisions:[],matches:[],candidates:[],mapping_decisions:[],lineages:[],changes:[],coverage_gaps:[]});
    const run = store.beginRun(report.project_id,'Original title'), cause = new Error('onCommit rejected this write');
    assert.throws(() => store.finishRun(run,report,'success',() => {
      assert.equal(store.db.isTransaction,true);
      assert.equal(store.reports(report.project_id).length,1);
      assert.equal(store.db.prepare('SELECT status FROM runs WHERE id=?').get(run)?.status,'success');
      store.db.prepare('UPDATE projects SET title=? WHERE id=?').run('Uncommitted title',report.project_id);
      throw cause;
    }), error => error === cause);
    assert.equal(store.reports(report.project_id).length,0);
    assert.equal(store.db.prepare('SELECT status,report_id FROM runs WHERE id=?').get(run)?.status,'running');
    assert.equal(store.db.prepare('SELECT report_id FROM runs WHERE id=?').get(run)?.report_id,null);
    assert.equal(store.db.prepare('SELECT title FROM projects WHERE id=?').get(report.project_id)?.title,'Original title');
    transactionIsReusable(store);
    store.finishRun(run,report);
    assert.deepEqual(store.report(report.project_id,report.report_id),report);
  } finally { store.close(); await rm(root,{recursive:true,force:true}); }
});

for (const boundary of ['desktop','workbook'] as const) {
  test(`${boundary} keeps the original SQLite cause and rollback failure together`, async () => {
    const document = boundary==='desktop' ? await documentFixture() : null;
    const workbook = boundary==='workbook' ? await workbookFixture() : null;
    const store = document?.service.store ?? workbook!.store;
    const exec = store.db.exec, rollbackFailure = new Error('injected rollback I/O failure');
    try {
      exec.call(store.db, boundary==='desktop'
        ? `CREATE TRIGGER reject_write BEFORE UPDATE ON ${DESKTOP_PROJECTS_TABLE} BEGIN SELECT RAISE(ABORT,'primary write rejection'); END;`
        : "CREATE TRIGGER reject_write BEFORE INSERT ON workbook_metadata_v1 BEGIN SELECT RAISE(ABORT,'primary write rejection'); END;");
      store.db.exec = function(sql: string) { if (sql==='ROLLBACK') throw rollbackFailure; return exec.call(this,sql); };
      const check = (error: unknown) => {
        assert.ok(error instanceof AggregateError);
        assert.equal(error.errors.length,2);
        assert.match(error.errors[0].message,/primary write rejection/);
        assert.equal(error.errors[1],rollbackFailure);
        assert.equal(error.cause,error.errors[0]);
        return true;
      };
      if (document) assert.throws(() => document.service.reorder(document.draft.project_id,[1,0]),check);
      else await assert.rejects(workbook!.service.commit(workbook!.draft.project_id,workbook!.stage),check);
      assert.equal(store.db.isTransaction,true,'failed rollback cannot pretend the transaction was closed');
    } finally {
      store.db.exec = exec;
      if (store.db.isTransaction) store.db.exec('ROLLBACK');
      transactionIsReusable(store);
      if (document) await document.close(); else await workbook!.close();
    }
  });
}
