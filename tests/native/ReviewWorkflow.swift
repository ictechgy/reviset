import Foundation
import AppKit
import SwiftUI
@main struct ReviewWorkflowProbe {
 @MainActor static func main() async throws {
  let previous="매출 전망\n예상 매출 120억",next="매출 전망\n예상 매출 110억"
  let old=changeTextRuns(previous,comparedWith:next),new=changeTextRuns(next,comparedWith:previous)
  guard old.map(\.text).joined()==previous,new.map(\.text).joined()==next,old.filter(\.changed).map(\.text).joined()=="120",new.filter(\.changed).map(\.text).joined()=="110" else{throw NSError(domain:"InlineDiffChangedUnchangedTitle",code:1)}
  let unicode="가족 👨‍👩‍👧‍👦\n 금액 −120억";guard changeTextRuns(unicode,comparedWith:"가족 👨‍👩‍👧‍👦\n 금액 −110억").map(\.text).joined()==unicode,changeTextRuns(String(repeating:"x",count:5000),comparedWith:"").allSatisfy({!$0.changed}) else{throw NSError(domain:"InlineDiffLostUnicodeOrExceededWorkBound",code:1)}
  let revisions=[JSON(["revision_occurrence_id":"first","revision_id":"same"]),JSON(["revision_occurrence_id":"second","revision_id":"same"])]
  let event=JSON(["from_occurrence":"first","to_occurrence":"second"])
  guard evidenceVersionLabel(JSON(["revision_occurrence_id":"second","page":3]),change:event,revisions:revisions)=="이후 · v2 · p.3",evidenceVersionLabel(JSON(["revision_id":"same","page":3]),change:event,revisions:revisions)=="버전 확인 필요 · p.3" else{throw NSError(domain:"EvidenceVersionGuessedDuplicateAlias",code:1)}
  let model=AppModel();model.initializing=false;guard model.libraryAvailable else{throw NSError(domain:"LibraryLock",code:1)}
  let events=model.bridge.library.appendingPathComponent("review-events.jsonl")
  func records()->[JSON]{guard let text=try? String(contentsOf:events,encoding:.utf8)else{return []};return text.split(separator:"\n").compactMap{try? JSONSerialization.jsonObject(with:Data($0.utf8))}.map(JSON.init)}
  func started(_ action:String,_ project:String,_ count:Int=0)async throws{for _ in 0..<200{if records().contains(where:{$0["action"].string==action&&$0["project"].string==project&&$0["count"].int==count}){return};try await Task.sleep(nanoseconds:5_000_000)};throw NSError(domain:"ActionDidNotStart",code:1)}
  func require(_ value:Bool,_ name:String)throws{if !value{throw NSError(domain:name,code:1)}}
  model.projectID="prj_a";let a=Task{await model.loadMCP()};try await started("mcpConfig","prj_a",1)
  model.projectID="prj_b";try require(model.mcp.isEmpty&&model.currentMCPConfig==nil,"OldConfigurationRemainsCopyable")
  await model.loadMCP();await a.value;try require(model.currentMCPConfig?.contains("prj_b")==true && !model.mcp.contains("prj_a"),"LateAReplacedBConfiguration")
  model.projectID="prj_a";let oldA=Task{await model.loadMCP()};try await started("mcpConfig","prj_a",2);model.projectID="prj_b";model.projectID="prj_a";await model.loadMCP();await oldA.value
  let config=JSON(try JSONSerialization.jsonObject(with:Data(model.mcp.utf8)));try require(config["mcpServers"]["docver"]["generation"].int==3,"ABASwitchAcceptedStaleGeneration")
  model.projectID="prj_mcp_retry";model.error="Unrelated global error";await model.loadMCP();try require(!model.mcpFailure.isEmpty && model.currentMCPConfig==nil && model.error=="Unrelated global error","MCPFailureLooksLikeLoadingOrCopyable");await model.loadMCP();try require(model.mcpFailure.isEmpty && model.currentMCPConfig?.contains("prj_mcp_retry")==true && model.error=="Unrelated global error","MCPRetryDidNotRecover");model.error="";model.projectID="prj_a"
  let select=Task{await model.selectProject("prj_a")};try await started("reports","prj_a");_ = try await model.create(title:"new",rows:[ImportRow(label:"new",urls:[URL(fileURLWithPath:"/synthetic.pdf")])]);model.projectID="prj_b";model.report=JSON();await select.value
  try require(model.projectID=="prj_b"&&model.report.isNull && !model.loading,"OldSelectionPublishedAfterCreate")
  let project=JSON(["project_id":"prj_b","revisions":[["label":"one"],["label":"two"]],"mapping_relations":[["reason":"preserved reason"]],"mapping_decisions":[],"bundle_decision_count":2,"draft_hash":String(repeating:"a",count:64)])
  model.projects=[project];await model.reorder(0,delta:1);guard let confirmation=model.reorderConfirmation else{throw NSError(domain:"DestructiveReorderNoConfirmation",code:1)}
  try require(!records().contains(where:{$0["action"].string=="reorder"}),"ReorderWroteBeforeConfirmation");model.reorderConfirmation=nil
  try require(model.project["mapping_relations"].array.count==1&&model.project["bundle_decision_count"].int==2,"CancelChangedDraft")
  var dirty=project.dictionary;dirty["dirty"]=true;model.projects=[JSON(dirty)];await model.reorder(0,delta:1);try require(model.reorderConfirmation==nil && model.error.contains("먼저 분석"),"PendingDecisionsOfferedDestructiveReset");model.projects=[project]
  model.projectID="prj_a";await model.confirmReorder(confirmation);try require(!records().contains(where:{$0["action"].string=="reorder"}),"StaleConfirmationWroteOtherProject")
  model.projectID="prj_history";model.error="";model.report=JSON(["report_id":"rpt_history","revisions":["a","b","c"].map{k in ["revision_occurrence_id":"occ_"+k,"label":k,"assets":[["asset_id":"asset_"+k,"format":"pdf"]],"pages":[["page_id":"page_"+k,"asset_id":"asset_"+k,"page":1]]]},"matches":[]]);model.from=0;model.to=2;model.tab="history";model.changes=[JSON(["change_id":"chg_history","from_occurrence":"occ_b","to_occurrence":"occ_c"])];model.chooseChange("chg_history");model.changeRange()
  for _ in 0..<200 {if model.selectedChangeID=="chg_history"&&model.leftPageID=="page_b"&&model.rightPageID=="page_c"{break};try await Task.sleep(nanoseconds:5_000_000)}
  try require(model.tab=="compare"&&model.from==1&&model.to==2&&model.leftPageID=="page_b"&&model.rightPageID=="page_c"&&model.inspector,"HistoryDidNotOpenExactIntervalAndEvidence")
  let validReport=model.report
  for mode in ["run","cancel","create"] {
   model.projectID="prj_pending_"+mode;model.report=validReport;model.error="";let pending=Task{try? await model.updateChanges()};try await started("changes",model.projectID)
   try require(model.loadingChanges,"PendingRangeDidNotOwnLoadingState");try require(model.changes.isEmpty && model.selected.isNull,"LoadingNewRangeDisplayedPriorChanges")
   if mode=="create" {let create=Task{try await model.create(title:"fail",rows:[])};try await started("create","create:fail");try require(!model.changesFailure.isEmpty && model.emptyChangesMessage.contains("새 입력 처리로") && !model.emptyChangesMessage.contains("감지된 변경이 없습니다"),"ImportInterruptedRangeClaimedNoChanges");var failed=false;do{_ = try await create.value}catch let error as BridgeError{failed=error.code=="CONTROLLED_CREATE_FAILURE"};try require(failed,"CreateDidNotFailAsExpected")}
   else {let run=Task{await model.run(model.projectID)};try await started("analyze",model.projectID);try require(model.emptyChangesMessage.contains("분석 중") && !model.emptyChangesMessage.contains("감지된 변경이 없습니다"),"BusyInterruptedRangeClaimedNoChanges");if mode=="cancel" {model.cancel()};await run.value;try require(mode=="cancel" ? model.status.contains("취소"):model.error.contains("controlled run failure"),"RunDidNotReachExpectedFailureOrCancellation")}
   await pending.value;try require(!model.loadingChanges && !model.busy,"FailedActionLeftChangesLoading")
  }
  model.projectID="prj_history";var bad=validReport.dictionary;bad["report_id"]="rpt_range_fail";model.report=JSON(bad);model.changes=[JSON(["change_id":"stale_change"])];model.selectedChangeID="stale_change"
  do{try await model.updateChanges();throw NSError(domain:"RangeFailureExpected",code:1)}catch{}
  try require(model.changes.isEmpty && model.selected.isNull && !model.changesFailure.isEmpty && !model.loadingChanges,"FailedRangeDisplayedPriorChanges")
  print("PASS actual native workflow: scoped MCP late/ABA replies, copy readiness, selection/create race, reorder cancel/stale safety, history interval/evidence")
 }
}
