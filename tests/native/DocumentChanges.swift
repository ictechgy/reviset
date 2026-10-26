import Foundation
import AppKit
@main struct DocumentChangesProbe {
    @MainActor static func main() async throws {
        configureLegacyNativeLocalization()
        let model=AppModel();model.initializing=false;guard model.libraryAvailable else{throw NSError(domain:"Lock",code:1)}
        func require(_ value:Bool,_ name:String)throws {if !value{throw NSError(domain:name,code:1)}}
        let full=String(repeating:"한😀\"\\\n",count:30000)+" NEEDLE TAIL"
        let rows=(0..<125).map { index -> [String:Any] in
            let a=index==124 ? "b":"a",b=index==124 ? "c":"b"
            return ["schema_version":"0.4.0","report_id":"fixed","change_id":"change_\(index)","kind":"text_modified","from_occurrence":"occ_"+a,"to_occurrence":"occ_"+b,"before":index==124 ? full:full.replacingOccurrences(of:"NEEDLE TAIL",with:"ordinary tail"),"after":"after \(index)","evidence":(0..<12).map{i in ["revision_occurrence_id":"occ_"+(i<9 ? a:b),"page_id":"page_"+(i<9 ? a:b),"page":1,"quote":"source \(i)"]}]
        }
        let control=model.bridge.library.appendingPathComponent("control.json")
        let events=model.bridge.library.appendingPathComponent("read-events.jsonl")
        let fixedReport=JSON(["report_id":"fixed","revisions":["a","b","c"].map{k in ["revision_occurrence_id":"occ_"+k,"assets":[["asset_id":"asset_"+k,"format":"pdf"]],"pages":[["page_id":"page_"+k,"asset_id":"asset_"+k,"page":1],["page_id":"manual_"+k,"asset_id":"asset_"+k,"page":2]]]}])
        func records()->[JSON] {guard let text=try? String(contentsOf:events,encoding:.utf8)else{return []};return text.split(separator:"\n").compactMap{try? JSONSerialization.jsonObject(with:Data($0.utf8))}.map(JSON.init)}
        func startedDetail(_ id:String,after:Int,continuation:Bool=false)async throws {
            for _ in 0..<400 {if records().dropFirst(after).contains(where:{$0["action"].string=="changeDetail" && $0["query"]["change_id"].string==id && (!continuation || $0["query"]["detail_offset"].int>0)}){return};try await Task.sleep(nanoseconds:5_000_000)}
            throw NSError(domain:continuation ? "DetailContinuationDidNotStart":"DetailDidNotStart",code:1)
        }
        func selectedDetail(_ id:String?=nil)async throws {
            for _ in 0..<800 {if !model.loadingChangeDetail && !model.selected.isNull && (id==nil || model.selected["change_id"].string==id){return};try await Task.sleep(nanoseconds:5_000_000)}
            throw NSError(domain:"VerifiedSelectedDetailDidNotSettle_"+(id ?? model.selectedChangeID ?? "none"),code:1)
        }
        func configure(_ mode:String="ok",delay:Int=0,listDelay:Int=0,documentReport:JSON?=nil)throws {try JSON(["mode":mode,"document_changes":rows,"document_report":(documentReport ?? fixedReport).raw,"detail_delay":delay,"delay":listDelay]).data().write(to:control)}
        try configure(delay:300)
        model.projectID="project";model.report=fixedReport;model.from=0;model.to=2;model.tab="history"
        try await model.updateChanges()
        try require(model.changes.count==100 && model.changesTotalCount==125 && !model.nextChangesCursor.isEmpty,"InitialNativeDocumentPageNotBounded")
        try require(!model.loadingChanges && model.loadingChangeDetail && model.selected.isNull,"SummaryWaitedForFullSelectedEvent")
        await model.loadMoreChanges()
        let installedReads=records().filter{$0["action"].string=="changes"}.count
        try await model.updateChanges()
        try require(model.changes.count==125 && model.nextChangesCursor.isEmpty && records().filter{$0["action"].string=="changes"}.count==installedReads,"SameQuestionReinstalledFirstPageDuringDetailRead")
        try await selectedDetail()
        try require(model.selected["before"].string.utf16.count>128*1024 && model.selected["evidence"].array.count==12 && model.leftPageID=="page_a" && model.rightPageID=="page_b" && model.from==0 && model.to==2 && model.sourceFrom==0 && model.sourceTo==1,"SelectedDetailTruncatedOrHistoryScopeLost")
        let selected=model.selected["change_id"].string
        await model.loadMoreChanges()
        try require(model.changes.count==125 && Set(model.changes.map{$0["change_id"].string}).count==125 && model.nextChangesCursor.isEmpty && model.selected["change_id"].string==selected,"ContinuationLostEventsOrSelectedDetail")
        model.search="needle tail"
        for _ in 0..<400 {if !model.loadingChanges && !model.loadingChangeDetail && model.changesTotalCount==1{break};try await Task.sleep(nanoseconds:5_000_000)}
        try require(model.changesTotalCount==1 && model.changes.count==1 && model.selected["change_id"].string=="change_124" && model.selected["before"].string==full,"FullTextSearchUsedOnlyPreview")
        model.search="";try await model.updateChanges();try await selectedDetail();await model.loadMoreChanges();model.chooseChange("change_124");try await selectedDetail("change_124");try configure("document-wrong-detail")
        let previousSources=(model.sourceFrom,model.sourceTo,model.leftPageID,model.rightPageID)
        try require(previousSources.0==1 && previousSources.1==2 && previousSources.2=="page_b" && previousSources.3=="page_c","DistinctPreviousPhysicalPairWasNotInstalled")
        model.chooseChange("change_1")
        try require(model.selected.isNull && model.sourceFrom==previousSources.0 && model.sourceTo==previousSources.1 && model.leftPageID==previousSources.2 && model.rightPageID==previousSources.3,"PendingDetailMovedPreviouslyDisplayedSources")
        for _ in 0..<200 {if !model.loadingChangeDetail && !model.evidenceWarning.isEmpty{break};try await Task.sleep(nanoseconds:5_000_000)}
        try require(model.selected.isNull && model.changes.count==125 && !model.evidenceWarning.isEmpty,"ForeignDetailRemainedAuthoritativeOrClearedQueryRows")
        try require(model.sourceFrom==previousSources.0 && model.sourceTo==previousSources.1 && model.leftPageID==previousSources.2 && model.rightPageID==previousSources.3,"FailedDetailMovedPreviouslyDisplayedSources")
        try configure(delay:30);model.chooseChange("change_0");try await Task.sleep(nanoseconds:10_000_000);model.chooseChange("change_1")
        for _ in 0..<400 {if !model.loadingChangeDetail && model.selected["change_id"].string=="change_1"{break};try await Task.sleep(nanoseconds:5_000_000)}
        try require(model.selected["change_id"].string=="change_1" && model.selected["after"].string=="after 1","SupersededDetailReplacedNewSelection")
        // The list question is a→c; the selected event resolves to a→b only
        // after its full detail has arrived. A newer manual a/b source choice
        // must retain the pair that was visible when the user navigated.
        func browsePreviousPair()throws {
            model.navigatePage("manual_a",in:"occ_a");model.navigatePage("manual_b",in:"occ_b")
            try require(model.leftPageID=="manual_a" && model.rightPageID=="manual_b" && model.manuallyBrowsing && model.sourceFrom==0 && model.sourceTo==1 && model.selected.isNull && !model.loadingChangeDetail && model.canReturnToChange,"PendingDetailDidNotRetireForManualNavigation")
        }
        func assertManual(_ name:String)throws {
            try require(model.leftPageID=="manual_a" && model.rightPageID=="manual_b" && model.manuallyBrowsing && model.sourceFrom==0 && model.sourceTo==1 && model.selected.isNull && !model.loadingChangeDetail && model.canReturnToChange && model.evidenceWarning.isEmpty,name)
        }
        try configure(delay:120)
        let queuedReads=records().count;model.chooseChange("change_2");try browsePreviousPair()
        try await Task.sleep(nanoseconds:150_000_000);try assertManual("QueuedDetailOverwroteNewManualPair")
        try require(!records().dropFirst(queuedReads).contains(where:{$0["action"].string=="changeDetail" && $0["query"]["change_id"].string=="change_2"}),"RetiredQueuedDetailStillStarted")
        for continuation in [false,true] {
            let count=records().count;model.chooseChange("change_2");try await startedDetail("change_2",after:count,continuation:continuation)
            try require(model.loadingChangeDetail && model.selected.isNull && model.sourceFrom==0 && model.sourceTo==1 && ["page_a","manual_a"].contains(model.leftPageID) && ["page_b","manual_b"].contains(model.rightPageID),"RaceDidNotPreservePreviouslyDisplayedPhysicalPair")
            try browsePreviousPair();let query=try JSON(["project":model.projectID,"report":model.report.raw,"from":model.from,"to":model.to,"rows":model.changes.map(\.raw),"cursor":model.nextChangesCursor]).data()
            try await Task.sleep(nanoseconds:900_000_000);model.selectEvidence();try assertManual(continuation ? "ContinuedDetailOverwroteNewManualPair":"FirstDetailOverwroteNewManualPair")
            try require(try JSON(["project":model.projectID,"report":model.report.raw,"from":model.from,"to":model.to,"rows":model.changes.map(\.raw),"cursor":model.nextChangesCursor]).data()==query,"ManualDetailRetirementReplacedFixedQuery")
            model.returnToChange()
            for _ in 0..<600 {if !model.loadingChangeDetail && model.selected["change_id"].string=="change_2"{break};try await Task.sleep(nanoseconds:5_000_000)}
            try require(model.selected["change_id"].string=="change_2" && model.selected["before"].string.utf16.count>128*1024 && model.selected["evidence"].array.count==12 && model.sourceFrom==0 && model.sourceTo==1 && model.leftPageID=="page_a" && model.rightPageID=="page_b" && !model.manuallyBrowsing && model.from==0 && model.to==2,"ExplicitReturnDidNotRestoreFullExactEvent")
        }
        let switching=records().count;model.chooseChange("change_3");try await startedDetail("change_3",after:switching)
        await model.selectProject("other_project",snapshot:"fixed")
        try await selectedDetail("change_124")
        try require(model.projectID=="other_project" && model.report["report_id"].string=="fixed" && !model.loadingChangeDetail && model.selected["change_id"].string != "change_3" && model.from==1 && model.to==2,"RetiredProjectDetailReplacedNewProjectScope")
        var initialReport=fixedReport.dictionary;initialReport["revisions"]=Array(fixedReport["revisions"].array.prefix(2)).map(\.raw)
        try configure(delay:300,documentReport:JSON(initialReport));await model.selectProject("project",snapshot:"fixed")
        try require(!model.loading && !model.loadingChanges && model.loadingChangeDetail && model.canStartNewComparison && model.selected.isNull,"InitialSelectedEventBlockedProjectControls")
        model.selectVersion(0)
        for _ in 0..<400 {if !model.loadingChanges && !model.loadingChangeDetail && model.changes.isEmpty{break};try await Task.sleep(nanoseconds:5_000_000)}
        try require(model.from==0 && model.to==0 && !model.loadingChangeDetail && model.selected.isNull,"InitialDetailBlockedNewVersionIntent")
        model.projectID="project";model.report=fixedReport;model.from=0;model.to=2;try configure();try await model.updateChanges();try await selectedDetail()
        for navigation in ["manual_during_append","event_during_append","manual_before_append_task"] {
            try configure();model.from=1;try await model.updateChanges();model.from=0;try await model.updateChanges();model.chooseChange("change_99")
            for _ in 0..<400 {if !model.loadingChangeDetail && model.selected["change_id"].string=="change_99"{break};try await Task.sleep(nanoseconds:5_000_000)}
            try require(model.changes.count==100 && !model.nextChangesCursor.isEmpty && model.selected["change_id"].string=="change_99","NextContinuationDidNotBeginAtLastLoadedEvent")
            try configure(listDelay:300);let count=records().count,report=try model.report.data(),firstRows=try JSON(model.changes.map(\.raw)).data()
            model.stepChange(1)
            if navigation != "manual_before_append_task" {
                for _ in 0..<400 {if records().dropFirst(count).contains(where:{$0["action"].string=="changes" && $0["query"]["cursor"].string=="100"}){break};try await Task.sleep(nanoseconds:5_000_000)}
                try require(model.loadingMoreChanges,"ContinuationReplyWasNotDelayedForNavigationRace")
            }
            if navigation=="event_during_append" {model.chooseChange("change_1")}
            else {model.navigatePage("manual_a",in:"occ_a");model.navigatePage("manual_b",in:"occ_b")}
            for _ in 0..<600 {if model.changes.count==125 && !model.loadingMoreChanges && !model.loadingChangeDetail{break};try await Task.sleep(nanoseconds:5_000_000)}
            // Give an incorrectly queued chooseChange task a turn after rows
            // install; its old Next action must never steal newer page focus.
            try await Task.sleep(nanoseconds:100_000_000)
            try require(model.changes.count==125 && Set(model.changes.map{$0["change_id"].string}).count==125 && model.nextChangesCursor.isEmpty && !model.loadingMoreChanges && model.changesPaginationFailure.isEmpty && model.changes.contains(where:{$0["change_id"].string=="change_100"}),"NewNavigationCancelledOrLostValidAppend_"+navigation)
            try require(try model.report.data()==report && JSON(Array(model.changes.prefix(100)).map(\.raw)).data()==firstRows && model.from==0 && model.to==2,"AppendNavigationRaceChangedFixedReportOrInstalledRows_"+navigation)
            if navigation=="event_during_append" {try require(model.selected["change_id"].string=="change_1" && model.selected["after"].string=="after 1" && !model.manuallyBrowsing,"QueuedNextOverrodeNewEventDuringAppend")}
            else {try require(model.selected["change_id"].string=="change_99" && model.leftPageID=="manual_a" && model.rightPageID=="manual_b" && model.manuallyBrowsing && model.sourceFrom==0 && model.sourceTo==1,"QueuedNextOverrodeNewManualPages_"+navigation)}
        }
        model.from=1;try await model.updateChanges()
        try await selectedDetail("change_124")
        try require(model.changes.count==1 && model.selected["change_id"].string=="change_124" && model.changesTotalCount==1 && model.sourceFrom==1 && model.sourceTo==2,"NewHistoryQueryRetainedOldEventDetail")
        print("PASS native document pages: bounded summary returns before full detail, installed continuation survives same-query refresh, exact incrementally hashed multi-chunk full detail, previous distinct physical source pair survives pending/failed reads, intermediate event evidence, explicit continuation, full-text search beyond preview, foreign detail rejection, selection cancellation, queued/first/continued detail manual-navigation retirement, explicit full-event return, project controls/version intent available during initial detail, pending/queued Next continuation respects newer manual/event intent while retaining appended rows, and new-range invalidation")
    }
}
