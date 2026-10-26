import Foundation
import AppKit
@main struct DocumentChangesProbe {
    @MainActor static func main() async throws {
        configureLegacyNativeLocalization()
        let model=AppModel();model.initializing=false;guard model.libraryAvailable else{throw NSError(domain:"Lock",code:1)}
        func require(_ value:Bool,_ name:String)throws {if !value{throw NSError(domain:name,code:1)}}
        let full=String(repeating:"한😀\"\\\n",count:30000)+" NEEDLE TAIL"
        let rows=(0..<125).map { index -> [String:Any] in
            ["schema_version":"0.4.0","report_id":"fixed","change_id":"change_\(index)","kind":"text_modified","from_occurrence":"occ_a","to_occurrence":"occ_b","before":index==124 ? full:full.replacingOccurrences(of:"NEEDLE TAIL",with:"ordinary tail"),"after":"after \(index)","evidence":(0..<12).map{i in ["revision_occurrence_id":i<9 ? "occ_a":"occ_b","page_id":i<9 ? "page_a":"page_b","page":1,"quote":"source \(i)"]}]
        }
        let control=model.bridge.library.appendingPathComponent("control.json")
        let events=model.bridge.library.appendingPathComponent("read-events.jsonl")
        let fixedReport=JSON(["report_id":"fixed","revisions":["a","b","c"].map{k in ["revision_occurrence_id":"occ_"+k,"assets":[["asset_id":"asset_"+k,"format":"pdf"]],"pages":[["page_id":"page_"+k,"asset_id":"asset_"+k,"page":1],["page_id":"manual_"+k,"asset_id":"asset_"+k,"page":2]]]}])
        func records()->[JSON] {guard let text=try? String(contentsOf:events,encoding:.utf8)else{return []};return text.split(separator:"\n").compactMap{try? JSONSerialization.jsonObject(with:Data($0.utf8))}.map(JSON.init)}
        func startedDetail(_ id:String,after:Int,continuation:Bool=false)async throws {
            for _ in 0..<400 {if records().dropFirst(after).contains(where:{$0["action"].string=="changeDetail" && $0["query"]["change_id"].string==id && (!continuation || $0["query"]["detail_offset"].int>0)}){return};try await Task.sleep(nanoseconds:5_000_000)}
            throw NSError(domain:continuation ? "DetailContinuationDidNotStart":"DetailDidNotStart",code:1)
        }
        func configure(_ mode:String="ok",delay:Int=0)throws {try JSON(["mode":mode,"document_changes":rows,"document_report":fixedReport.raw,"detail_delay":delay]).data().write(to:control)}
        try configure()
        model.projectID="project";model.report=fixedReport;model.from=0;model.to=2;model.tab="history"
        try await model.updateChanges()
        try require(model.changes.count==100 && model.changesTotalCount==125 && !model.nextChangesCursor.isEmpty,"InitialNativeDocumentPageNotBounded")
        try require(model.selected["before"].string.utf16.count>128*1024 && model.selected["evidence"].array.count==12 && model.leftPageID=="page_a" && model.rightPageID=="page_b" && model.from==0 && model.to==2 && model.sourceFrom==0 && model.sourceTo==1,"SelectedDetailTruncatedOrHistoryScopeLost")
        let selected=model.selected["change_id"].string
        await model.loadMoreChanges()
        try require(model.changes.count==125 && Set(model.changes.map{$0["change_id"].string}).count==125 && model.nextChangesCursor.isEmpty && model.selected["change_id"].string==selected,"ContinuationLostEventsOrSelectedDetail")
        model.search="needle tail"
        for _ in 0..<400 {if !model.loadingChanges && !model.loadingChangeDetail && model.changesTotalCount==1{break};try await Task.sleep(nanoseconds:5_000_000)}
        try require(model.changesTotalCount==1 && model.changes.count==1 && model.selected["change_id"].string=="change_124" && model.selected["before"].string==full,"FullTextSearchUsedOnlyPreview")
        model.search="";try await model.updateChanges();try configure("document-wrong-detail")
        model.chooseChange("change_1")
        for _ in 0..<200 {if !model.loadingChangeDetail && !model.evidenceWarning.isEmpty{break};try await Task.sleep(nanoseconds:5_000_000)}
        try require(model.selected.isNull && model.changes.count==100 && !model.evidenceWarning.isEmpty,"ForeignDetailRemainedAuthoritativeOrClearedQueryRows")
        try configure(delay:30);model.chooseChange("change_0");try await Task.sleep(nanoseconds:10_000_000);model.chooseChange("change_1")
        for _ in 0..<400 {if !model.loadingChangeDetail && model.selected["change_id"].string=="change_1"{break};try await Task.sleep(nanoseconds:5_000_000)}
        try require(model.selected["change_id"].string=="change_1" && model.selected["after"].string=="after 1","SupersededDetailReplacedNewSelection")
        // The list question is a→c; the selected event resolves to a→b only
        // after its full detail has arrived. A newer manual a/c source choice
        // must retain the pair that was visible when the user navigated.
        func browseOuterPair()throws {
            model.navigatePage("manual_a",in:"occ_a");model.navigatePage("manual_c",in:"occ_c")
            try require(model.leftPageID=="manual_a" && model.rightPageID=="manual_c" && model.manuallyBrowsing && model.sourceFrom==0 && model.sourceTo==2 && model.selected.isNull && !model.loadingChangeDetail && model.canReturnToChange,"PendingDetailDidNotRetireForManualNavigation")
        }
        func assertManual(_ name:String)throws {
            try require(model.leftPageID=="manual_a" && model.rightPageID=="manual_c" && model.manuallyBrowsing && model.sourceFrom==0 && model.sourceTo==2 && model.selected.isNull && !model.loadingChangeDetail && model.canReturnToChange && model.evidenceWarning.isEmpty,name)
        }
        try configure(delay:120)
        let queuedReads=records().count;model.chooseChange("change_2");try browseOuterPair()
        try await Task.sleep(nanoseconds:150_000_000);try assertManual("QueuedDetailOverwroteNewManualPair")
        try require(!records().dropFirst(queuedReads).contains(where:{$0["action"].string=="changeDetail" && $0["query"]["change_id"].string=="change_2"}),"RetiredQueuedDetailStillStarted")
        for continuation in [false,true] {
            let count=records().count;model.chooseChange("change_2");try await startedDetail("change_2",after:count,continuation:continuation)
            try require(model.loadingChangeDetail && model.selected.isNull && model.sourceFrom==0 && model.sourceTo==2,"RaceDidNotBeginAtUnresolvedOuterPair")
            try browseOuterPair();let query=try JSON(["project":model.projectID,"report":model.report.raw,"from":model.from,"to":model.to,"rows":model.changes.map(\.raw),"cursor":model.nextChangesCursor]).data()
            try await Task.sleep(nanoseconds:900_000_000);model.selectEvidence();try assertManual(continuation ? "ContinuedDetailOverwroteNewManualPair":"FirstDetailOverwroteNewManualPair")
            try require(try JSON(["project":model.projectID,"report":model.report.raw,"from":model.from,"to":model.to,"rows":model.changes.map(\.raw),"cursor":model.nextChangesCursor]).data()==query,"ManualDetailRetirementReplacedFixedQuery")
            model.returnToChange()
            for _ in 0..<600 {if !model.loadingChangeDetail && model.selected["change_id"].string=="change_2"{break};try await Task.sleep(nanoseconds:5_000_000)}
            try require(model.selected["change_id"].string=="change_2" && model.selected["before"].string.utf16.count>128*1024 && model.selected["evidence"].array.count==12 && model.sourceFrom==0 && model.sourceTo==1 && model.leftPageID=="page_a" && model.rightPageID=="page_b" && !model.manuallyBrowsing && model.from==0 && model.to==2,"ExplicitReturnDidNotRestoreFullExactEvent")
        }
        let switching=records().count;model.chooseChange("change_3");try await startedDetail("change_3",after:switching)
        await model.selectProject("other_project",snapshot:"fixed")
        try require(model.projectID=="other_project" && model.report["report_id"].string=="fixed" && !model.loadingChangeDetail && model.selected["change_id"].string != "change_3" && model.from==1 && model.to==2,"RetiredProjectDetailReplacedNewProjectScope")
        model.projectID="project";model.report=fixedReport;model.from=0;model.to=2;try configure();try await model.updateChanges()
        model.from=1;try await model.updateChanges()
        try require(model.changes.isEmpty && model.selected.isNull && !model.loadingChangeDetail && model.changesTotalCount==0,"NewHistoryQueryRetainedOldEventDetail")
        print("PASS native document pages: bounded list, exact multi-chunk full detail, intermediate event evidence, explicit continuation, full-text search beyond preview, foreign detail rejection, selection cancellation, queued/first/continued detail manual-navigation retirement, explicit full-event return, project-switch and new-range invalidation")
    }
}
