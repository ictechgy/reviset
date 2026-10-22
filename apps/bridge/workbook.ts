import { z } from 'zod';
import { Store } from '../../packages/storage/index.js';
import { DocverError } from '../../packages/schema/index.js';
import { WorkbookService } from '../../packages/workbook/service.js';
import { WorkbookQueryService, boundedWorkbookCell } from '../../packages/workbook/query.js';

const key = z.string().regex(/^[a-zA-Z0-9_-]{1,160}$/), scope = { project_id: key, report_id: key };
export async function handleWorkbookAction(store: Store, action: string, input: unknown): Promise<unknown> {
  const service = new WorkbookService(store), args = input ?? {};
  switch (action) {
    case 'workbookProjects': return service.projects();
    case 'workbookCreate': { const a = z.object({ title: z.string(), revisions: z.array(z.unknown()) }).parse(args); return service.create(a.title, a.revisions); }
    case 'workbookAnalyze': {
      const a = z.object({ project_id: key }).parse(args), controller = new AbortController(), cancel = () => controller.abort(), parent = process.ppid;
      process.once('SIGTERM', cancel); process.once('SIGINT', cancel);
      const parentWatch = setInterval(() => { if (parent <= 1 || process.ppid !== parent) { clearInterval(parentWatch); cancel(); } }, 100); parentWatch.unref();
      try { const result = await service.run(a.project_id, controller.signal); controller.signal.throwIfAborted(); return result; }
      finally { clearInterval(parentWatch); process.removeListener('SIGTERM', cancel); process.removeListener('SIGINT', cancel); }
    }
    case 'workbookCommit': { const a = z.object({ project_id: key, result: z.unknown() }).parse(args); return service.commit(a.project_id, a.result); }
    case 'workbookRecover': { const a = z.object({ project_id: key.optional() }).parse(args); return service.recover(a.project_id); }
    case 'workbookReports': { const a = z.object({ project_id: key }).parse(args); return service.reports(a.project_id); }
    case 'workbookView': { const a = z.object(scope).parse(args); return service.view(a.project_id, a.report_id); }
    case 'workbookQuery': {
      const a = z.object({ name: z.string(), args: z.record(z.string(), z.unknown()) }).parse(args), project = a.args.project_id;
      const allowed = project === undefined ? new Set(service.projects().map(p => p.project_id)) : new Set([key.parse(project)]);
      return new WorkbookQueryService(service, allowed).query(a.name, a.args);
    }
    case 'workbookGrid': {
      const a = z.object({ ...scope, revision_occurrence_id: key, sheet_id: key, row_start: z.number().int().min(1).max(1_048_576), row_limit: z.number().int().min(1).max(100), column_start: z.number().int().min(1).max(16_384), column_limit: z.number().int().min(1).max(12) }).parse(args);
      const report = service.metadata(a.project_id, a.report_id), revision = report.revisions.find(r => r.revision_occurrence_id === a.revision_occurrence_id), sheet = revision?.sheets.find(s => s.sheet_id === a.sheet_id);
      if (!sheet) throw new DocverError('WORKBOOK_SHEET_SCOPE', 'Grid sheet is outside the selected fixed report/occurrence');
      const rowEnd = Math.min(1_048_577, a.row_start + a.row_limit), columnEnd = Math.min(16_385, a.column_start + a.column_limit), items = service.indexedCells(a.project_id, report.report_id, a.revision_occurrence_id, a.sheet_id, a.row_start, rowEnd, a.column_start, columnEnd).map(c => {
        const cell = boundedWorkbookCell(c, 0, 64)!; return { ...cell, text_truncated: Object.values(cell.text_continuations).some(t => t.state === 'truncated') };
      });
      const result = { ...a, report_id: report.report_id, items, sparse: true, preview_only: true, missing_cell_meaning: 'not_materialized_not_confirmed_blank', raw_detail_query: 'get_workbook_cell' };
      if (Buffer.byteLength(JSON.stringify(result)) > 1024 * 1024) throw new DocverError('WORKBOOK_GRID_LIMIT', 'Grid preview exceeds 1 MiB; reduce the requested viewport'); return result;
    }
    case 'workbookPublish': { const a = z.object({ ...scope, label: z.string(), reason: z.string() }).parse(args); return service.publish(a.project_id, a.report_id, a.label, a.reason); }
    case 'workbookReleases': { const a = z.object({ project_id: key }).parse(args); return service.releases(a.project_id); }
    case 'workbookExport': { const a = z.object({ ...scope, folder: z.string().min(1).max(4096) }).parse(args); return service.export(a.project_id, a.report_id, a.folder); }
    default: throw new DocverError('UNKNOWN_ACTION', 'Unknown workbook application action');
  }
}
