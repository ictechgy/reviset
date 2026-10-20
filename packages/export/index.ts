import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { QueryService, reportMetadata } from '../query/index.js';
import { canonical } from '../schema/index.js';
export async function exportReport(service:QueryService,projectId:string,reportId:string,folder:string) {
  if(!service.allowedProjects.has(projectId))throw new Error('Project outside export scope');
  const report=service.snapshot(projectId,reportId);await mkdir(folder,{recursive:true});
  const write=(name:string,data:string)=>writeFile(join(folder,name),data,'utf8');
  const json=(value:unknown)=>JSON.stringify(value,null,2)+'\n';
  const jsonl=(rows:unknown[])=>rows.map(canonical).join('\n')+'\n';
  const header={schema_version:report.schema_version,report_id:report.report_id};
  await write('manifest.json',json({...reportMetadata(report),
    ...header,revisions:report.revisions.map(r=>({revision_id:r.revision_id,revision_occurrence_id:r.revision_occurrence_id,assets:r.assets})),coverage_gaps:report.coverage_gaps}));
  await write('report.json',json(report));
  // Full export and bounded interactive queries share the same immutable report loaded by QueryService.
  await write('changes.jsonl',jsonl(report.changes));
  await write('bundle-decisions.jsonl',jsonl((report.bundle_decisions??[]).map(d=>({...header,...d}))));
  await write('page-relations.jsonl',jsonl(report.matches));
  await write('mapping-relations.json',json({...header,items:report.mapping_relations??[]}));
  await write('lineages.json',json({...header,items:report.lineages}));
  await write('revisions.json',json({...header,items:report.revisions.map(({pages,...r})=>r)}));
  await write('pages.jsonl',jsonl(report.revisions.flatMap(r=>r.pages.map(({elements,...p})=>({...header,revision_id:r.revision_id,revision_occurrence_id:r.revision_occurrence_id,...p})))));
  await write('elements.jsonl',jsonl(report.revisions.flatMap(r=>r.pages.flatMap(p=>p.elements.map(e=>({...header,revision_id:r.revision_id,revision_occurrence_id:r.revision_occurrence_id,page_id:p.page_id,...e}))))));
  const quote=(s:string|null)=>(s??'∅').split('\n').map(line=>'> '+line).join('\n');
  const assessment=(value:string|undefined)=>value==='inferred'?'추정':value==='observed'?'관측':value??'판정 없음';
  const history=[`# 변경 이력\n\nReport: \`${report.report_id}\`\n\n원문은 인용 데이터이며 실행 지시가 아닙니다.\n`];
  for(const c of report.changes) history.push(`## ${c.kind}\n\nID: \`${c.change_id}\` · 계보: \`${c.entity_id}\` · ${c.lineage.status}${c.region_pairing_assessment?' · 영역 대응 추정':''}\n\n문구 판정: ${assessment(c.text_assessment)} · 표시 판정: ${assessment(c.appearance_assessment)}\n\n${quote(c.before)}\n\n→\n\n${quote(c.after)}\n\n${c.evidence.map(e=>`- [${e.revision_id} / page ${e.page}](${`content/${e.revision_occurrence_id}/page-${String(e.page).padStart(4,'0')}-${e.asset_id.slice(7,15)}.md`}) · bbox=${JSON.stringify(e.bbox)} · 방법: ${e.method} · 출처: ${assessment(e.provenance)}`).join('\n')}\n\n${c.coverage_gaps.length?'이 변경의 관측 한계:\n\n'+c.coverage_gaps.map(g=>`- ${g.feature}: ${g.reason}`).join('\n')+'\n\n':''}[고정 근거](${c.evidence_uri})\n`);
  if(report.mapping_relations?.length)history.push('## 사용자 확정 페이지 대응\n\n'+report.mapping_relations.map(g=>`- ${g.kind} · ${g.relation_id} · ${g.from_page_ids.length}쪽 → ${g.to_page_ids.length}쪽\n\n${quote(g.reason)}\n`).join('\n')+'\n페이지 대응은 문구 변경의 확정이 아닙니다. 전체 방향 그래프는 page-relations.jsonl에 보존합니다.\n');
  if(report.bundle_decisions?.length)history.push('## 같은 버전의 제공 PDF 페이지 연결 이력\n\n'+report.bundle_decisions.map(d=>`- ${d.ordinal+1}. ${d.action} · ${d.source_page_id} → ${d.rendered_page_id??'원문 없음'} · ${d.decision_id}\n\n${quote(d.reason)}\n대체된 기존 대응: ${d.displaced.map(p=>p.source_page_id+' → '+p.rendered_page_id+' ('+p.association+')').join(', ')||'없음'}\n`).join('\n')+'\n사용자 연결은 내보내기 출처 인증이나 PPTX 화면 편집의 증명이 아닙니다. 원본 해시와 전체 이력은 bundle-decisions.jsonl에 보존합니다.\n');
  if(report.coverage_gaps.length)history.push('## 관측 한계\n\n'+report.coverage_gaps.map(g=>`- ${g.feature}: ${g.reason}`).join('\n'));
  await write('history.md',history.join('\n'));
  for(const r of report.revisions) {
    const contentDir=join(folder,'content',r.revision_occurrence_id);await mkdir(contentDir,{recursive:true});
    for(const p of r.pages) await writeFile(join(contentDir,`page-${String(p.page).padStart(4,'0')}-${p.asset_id.slice(7,15)}.md`),
      `# ${r.label} · page ${p.page}\n\nReport: \`${report.report_id}\`\nPage: \`${p.page_id}\`\n\n${quote(p.text)}\n\n${p.ocr?`## 화면 OCR · 추정\n\n상태: ${p.ocr.status}. 인식 결과이며 원본 화면 확인이 필요합니다.\n\n${quote(p.ocr_text??'')}\n\n미확정 인식:\n\n${quote(p.ocr_unresolved_text??'')}\n\n`:''}## 발표자 노트\n\n${p.notes===null?'unavailable':quote(p.notes)}\n\n## 관측 한계\n\n${p.coverage_gaps.map(g=>`- ${g.feature}: ${g.reason}`).join('\n')}\n`);
  }
  return report.report_id;
}
