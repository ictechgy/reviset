import Foundation
import AppKit
import SwiftUI

enum Smoke { @MainActor static func captureView(_ window:NSWindow,_ url:URL)throws {throw NSError(domain:"UnexpectedScreenshotInModelProbe",code:1)} }

@main struct GitDiffWorkspaceProbe {
    @MainActor static func main() async throws {
        configureLegacyNativeLocalization()
        func require(_ value:Bool,_ name:String)throws {if !value {throw NSError(domain:name,code:1)}}
        for (before,after) in [("100","120"),("a\nb\na","a\na\nb"),("", ""),("a\n","\na"),("문서 👨‍👩‍👧‍👦\r\n금액 100", "문서 👨‍👩‍👧‍👦\r\n금액 120"),("é", "e\u{301}"),("e\u{301}","é"),("각\n내용", "\u{1100}\u{1161}\u{11a8}\n내용")] {
            let diff=unifiedTextDiff(before:before,after:after,semantic:true)
            try require(diff.bounded && diff.semantic,"UnexpectedDiffFallback")
            try require(Array(diff.lines.filter{$0.prefix != "+"}.map(\.text).joined(separator:"\n").utf16)==Array(before.utf16),"BeforeTextChangedByDiff")
            try require(Array(diff.lines.filter{$0.prefix != "−"}.map(\.text).joined(separator:"\n").utf16)==Array(after.utf16),"AfterTextChangedByDiff")
        }
        for long in [String(repeating:"가",count:4097),String(repeating:"😀",count:2049),String(repeating:"x\n",count:128)] {
            let diff=unifiedTextDiff(before:long,after:"short",semantic:true)
            try require(!diff.bounded && diff.lines.isEmpty && !diff.semantic,"ExceededDiffBoundOrPresentedTruncatedText")
        }
        for kind in ["text_occluded","text_struck_through","text_revealed","coverage_gap","page_deleted","page_merged","visual_region_changed"] {
            let diff=documentTextDiff(JSON(["kind":kind,"before":"hidden 100","after":"hidden 120"]))
            try require(!diff.semantic && diff.lines.allSatisfy{$0.prefix.isEmpty},"AppearanceInterpretedAsTextDeletion")
        }
        let absent=documentTextDiff(JSON(["kind":"text_modified","before":"100"]))
        try require(!absent.semantic,"MissingObservationInterpretedAsEmptyText")
        let structural=documentTextDiff(JSON(["kind":"text_modified","before":"100","after":"120","topology":["semantics":"directed_reachability"]]))
        try require(!structural.semantic,"TopologyInterpretedAsTextDeletion")

        // Canonical equivalence is not raw source equality: preserve each exact
        // UTF-16 sequence even when Swift String == considers it the same text.
        let canonical=unifiedTextDiff(before:"é",after:"e\u{301}",semantic:true)
        try require(canonical.lines.contains(where:{$0.prefix=="−"}) && canonical.lines.contains(where:{$0.prefix=="+"}),"CanonicalEquivalentSourceDifferenceHidden")
        func cell(_ value:Any,state:String,total:Int,offset:Int=0,cache:String="present",role:String="explicit",type:String="string")->JSON {
            JSON(["address":"C3","source_ref":"source!C3","value":value,"value_type":type,"formula":"SUM(C1:C2)","formula_interpretation":role,"cached_result":cache,"cache_freshness":"unknown","text_continuations":["value":["state":state,"offset":offset,"next_offset":NSNull(),"total_length":total],"formula":["state":"complete","offset":0,"next_offset":NSNull(),"total_length":10]]])
        }
        let missing=cell(NSNull(),state:"missing",total:0,cache:"missing"),empty=cell("",state:"empty",total:0),zero=cell("0",state:"complete",total:1,type:"number")
        try require(workbookRawField(missing,field:"value").state == .missing && workbookRawField(missing,field:"value").text == nil,"MissingCacheBecameEmptyString")
        try require(workbookRawField(empty,field:"value").state == .empty && workbookRawField(empty,field:"value").text?.utf16.count==0,"ObservedEmptyStringBecameUnavailable")
        try require(workbookRawField(zero,field:"value").state == .complete && workbookRawField(zero,field:"value").text=="0","ZeroBecameMissingOrEmpty")
        try require(workbookFieldTextDiff(before:missing,after:empty,field:"value",textOffset:0)==nil,"MissingCacheDiffUsedInventedEmptyString")
        try require(workbookSelectedWarningMessages(missing).contains(L("git.cacheMissing")) && workbookSelectedWarningMessages(empty).contains(L("git.cacheUnknown")),"SelectedCacheWarningsHiddenByInspector")
        let unresolved=cell("100",state:"complete",total:3,role:"unresolved"),newValue=cell("120",state:"complete",total:3)
        let unresolvedDiff=workbookFieldTextDiff(before:unresolved,after:newValue,field:"value",textOffset:0)
        try require(unresolvedDiff?.semantic==false && unresolvedDiff?.lines.allSatisfy({$0.prefix.isEmpty})==true && workbookSelectedWarningMessages(unresolved).contains(L("workbook.cell.unresolvedFormula")),"UnresolvedFormulaClaimedSemanticValueEdit")
        let partial=cell("abc",state:"truncated",total:10),earlier=cell("",state:"truncated",total:10,offset:10),contradictory=cell("",state:"missing",total:0)
        try require(workbookRawField(partial,field:"value").state == .partial && workbookRawField(earlier,field:"value").state == .earlier && workbookRawField(contradictory,field:"value").state == .missing,"ContinuationStatesWereFlattened")
        try require(workbookFieldTextDiff(before:partial,after:newValue,field:"value",textOffset:0)==nil && workbookFieldTextDiff(before:earlier,after:empty,field:"value",textOffset:10)==nil,"PartialOrEarlierFragmentPresentedAsCompleteDiff")
        try require(workbookRawField(cell("a",state:"complete",total:2),field:"value").state == .unavailable,"InconsistentContinuationWasTrusted")
        try require(missing["address"].string=="C3" && missing["source_ref"].string=="source!C3" && earlier["text_continuations"]["value"]["offset"].int==10,"DisplayProjectionChangedPhysicalOrFragmentIdentity")

        let fresh=WorkspaceLayoutStore(scope:.document),bookLayout=WorkspaceLayoutStore(scope:.workbook)
        for value in [fresh.configuration,bookLayout.configuration] {try require(!value.sidebarVisible && !value.inspectorVisible && value.changesVisible && value.changesDock == .left,"FreshWorkspaceNotSourceFirst")}
        var previous=WorkspaceLayoutConfiguration();previous.sidebarVisible=true;previous.inspectorVisible=true;previous.changesDock = .bottom;previous.sidebarWidth=299;previous.changesHeight=211
        let savedID=UUID(),legacy:[String:Any]=["schemaVersion":1,"current":try JSONSerialization.jsonObject(with:JSONEncoder().encode(previous)),"saved":[["id":savedID.uuidString,"name":"My old layout","configuration":try JSONSerialization.jsonObject(with:JSONEncoder().encode(previous))]]]
        let legacyData=try JSONSerialization.data(withJSONObject:legacy)
        WorkspaceLayoutPreferences.save(legacyData,scope:.document)
        let retained=WorkspaceLayoutStore(scope:.document)
        try require(retained.configuration==previous && retained.saved.count==1 && retained.saved[0].name=="My old layout" && retained.saved[0].configuration==previous && WorkspaceLayoutPreferences.data(.document)==legacyData,"ExistingCustomLayoutWasMigratedDestructively")
        retained.reset();try require(retained.configuration==fresh.configuration && retained.saved.count==1,"SourceFirstResetDeletedSavedLayouts")

        let model=AppModel();model.initializing=false
        let revisions=(0..<3).map {index in JSON(["revision_occurrence_id":"occ_\(index)","label":"version \(index)","assets":[["asset_id":"asset_\(index)","format":"pdf"]],"pages":[["page_id":"page_\(index)","asset_id":"asset_\(index)","page":1],["page_id":"manual_\(index)","asset_id":"asset_\(index)","page":2]]])}
        model.report=JSON(["report_id":"rpt_fixed","revisions":revisions.map(\.raw)]);model.projectID="prj_fixed";model.from=0;model.to=2;model.tab="history"
        let changes=(0..<2).map{index in JSON(["change_id":"change_\(index)","kind":"text_modified","from_occurrence":"occ_\(index)","to_occurrence":"occ_\(index+1)","before":index==0 ? "100":"120","after":index==0 ? "120":"100","evidence":[["revision_occurrence_id":"occ_\(index)","page_id":"page_\(index)"],["revision_occurrence_id":"occ_\(index+1)","page_id":"page_\(index+1)"]]])}
        model.changes=changes;let rows=try JSON(changes.map(\.raw)).data(),report=try model.report.data()
        model.chooseChange("change_1")
        try require(model.from==0 && model.to==2 && model.tab=="history" && model.sourceFrom==1 && model.sourceTo==2 && model.leftPageID=="page_1" && model.rightPageID=="page_2" && model.eventInsideQuery && !model.loadingChanges,"HistorySelectionReplacedQueryOrWrongEvidence")
        model.navigatePage("manual_1",in:"occ_1");model.selectEvidence();try require(model.manuallyBrowsing && model.leftPageID=="manual_1","ManualHistoryViewportWasOverwritten")
        model.returnToChange();try require(!model.manuallyBrowsing && model.leftPageID=="page_1","ReturnToSelectedChangeLostEvidence")
        model.stepChange(-1);try require(model.selectedChangeID=="change_0" && model.sourceFrom==0 && model.sourceTo==1 && model.from==0 && model.to==2,"PreviousChangeResetInterval")
        model.search="120";model.stepChange(1);try require(model.selectedChangeID=="change_1","FilteredNextChangeFailed")
        try require(try JSON(model.changes.map(\.raw)).data()==rows && model.report.data()==report,"NavigationChangedFixedReportOrRows")
        model.changes.append(JSON(["change_id":"foreign","from_occurrence":"unknown","to_occurrence":"occ_2"]))
        model.chooseChange("foreign");try require(model.selected.isNull && model.leftPageID.isEmpty && model.rightPageID.isEmpty && !model.evidenceWarning.isEmpty && model.from==0 && model.to==2,"UnknownHistoryEvidenceKeptStaleSource")
        model.from=0;model.to=0;model.tab="compare";try await model.updateChanges();try require(model.readingSingleVersion && model.changes.isEmpty && model.leftPageID=="page_0","SingleVersionReadRequestedDiff")
        let workbook=WorkbookModel(bridge:model.bridge);await workbook.start();workbook.projectID="workbook";workbook.reportID="workbook_report";workbook.report=JSON(["report_id":"workbook_report","revisions":[["revision_occurrence_id":"w0","index":0,"sheets":[]],["revision_occurrence_id":"w1","index":1,"sheets":[]]]]);workbook.beforeID="w0";workbook.afterID="w1";workbook.changesFromID="w0";workbook.changesToID="w1"
        await workbook.selectVersion("w0");try require(workbook.beforeID=="w0" && workbook.afterID=="w0" && workbook.changesFromID=="w0" && workbook.changesToID=="w0" && workbook.changes.isEmpty && !workbook.loadingChanges && workbook.changesFailure.isEmpty,"WorkbookFirstVersionDidNotReadSingleSource")
        print("PASS native Git diff workspace: bounded exact Unicode diff, neutral appearance/unavailable/topology, Source First defaults, old custom layouts retained, query/event/manual navigation separation, previous/next, unknown evidence guard, document/workbook v1 reading")
    }
}
