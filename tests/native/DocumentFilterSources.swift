import Foundation
import AppKit

@main struct DocumentFilterSourcesProbe {
    @MainActor static func main() async throws {
        configureLegacyNativeLocalization()
        let model=AppModel();model.initializing=false
        func require(_ value:Bool,_ name:String)throws {if !value {throw NSError(domain:name,code:1)}}
        try require(model.libraryAvailable,"IsolatedLibraryLocked")
        let control=model.bridge.library.appendingPathComponent("control.json"),events=model.bridge.library.appendingPathComponent("read-events.jsonl")
        let text=String(repeating:"가😀 abc ",count:24000)
        func row(_ id:String,_ kind:String,_ a:String,_ b:String,_ phrase:String)->[String:Any] {
            ["schema_version":"0.4.0","report_id":"fixed","change_id":id,"kind":kind,"from_occurrence":"occ_"+a,"to_occurrence":"occ_"+b,"before":phrase+text,"after":phrase+" after","evidence":[["revision_occurrence_id":"occ_"+a,"page_id":"page_"+a],["revision_occurrence_id":"occ_"+b,"page_id":"page_"+b]]]
        }
        let rows=[row("middle","text_modified","a","b","needle "),row("later","text_modified","b","c","later "),row("style","font_changed","b","c","later style ")]
        let report=JSON(["report_id":"fixed","revisions":["a","b","c"].map{k in ["revision_occurrence_id":"occ_"+k,"assets":[["asset_id":"asset_"+k,"format":"pdf"]],"pages":[["page_id":"page_"+k,"asset_id":"asset_"+k,"page":1],["page_id":"manual_"+k,"asset_id":"asset_"+k,"page":2]]]}])
        func configure(_ mode:String="ok",delay:Int=0,documentChanges:[[String:Any]]?=nil)throws {try JSON(["mode":mode,"document_changes":documentChanges ?? rows,"document_report":report.raw,"detail_delay":delay]).data().write(to:control)}
        func records()->[JSON] {guard let text=try? String(contentsOf:events,encoding:.utf8)else{return []};return text.split(separator:"\n").compactMap{try? JSONSerialization.jsonObject(with:Data($0.utf8))}.map(JSON.init)}
        func wait(_ name:String,_ condition:()->Bool)async throws {
            for _ in 0..<800 {if condition(){return};try await Task.sleep(nanoseconds:5_000_000)}
            throw NSError(domain:name,code:1)
        }
        func detailStarted(_ id:String,after:Int,continuation:Bool=false)async throws {
            try await wait("DetailDidNotStart_"+id) {records().dropFirst(after).contains(where:{$0["action"].string=="changeDetail" && $0["query"]["change_id"].string==id && (!continuation || $0["query"]["detail_offset"].int>0)})}
        }
        func selected(_ id:String)async throws {try await wait("VerifiedDetailDidNotSettle_"+id) {!model.loadingChanges && !model.loadingChangeDetail && model.selected["change_id"].string==id}}
        func pair(_ a:Int,_ b:Int,_ left:String,_ right:String,_ name:String)throws {try require(model.from==0 && model.to==2 && model.sourceFrom==a && model.sourceTo==b && model.leftPageID==left && model.rightPageID==right,name)}

        try configure();model.projectID="project";model.report=report;model.from=0;model.to=2;model.tab="history";try await model.updateChanges();try await selected("middle")
        try pair(0,1,"page_a","page_b","InitialIntermediateEventMissing")
        // A filter is a new list/detail query within the same fixed physical
        // interval. Its debounce must not make the retired row authoritative,
        // nor may retiring that row change the already displayed source pair.
        try configure(delay:180);var count=records().count;model.search="needle"
        try require(model.selected.isNull && model.selectedChangeID==nil && model.loadingChanges,"FilterRetainedRetiredSelectionAuthority")
        try pair(0,1,"page_a","page_b","SearchDebounceMovedIntermediateSources")
        model.selectEvidence();try pair(0,1,"page_a","page_b","SearchDebounceNormalizedAnUnrelatedEndpoint")
        try await detailStarted("middle",after:count,continuation:true)
        try require(model.loadingChangeDetail && model.selected.isNull,"MatchingSearchDetailWasNotWithheld")
        try pair(0,1,"page_a","page_b","MatchingSearchContinuationMovedIntermediateSources")
        try await selected("middle");try pair(0,1,"page_a","page_b","VerifiedMatchingSearchLostIntermediateSources")

        try configure("document-wrong-detail",delay:180);count=records().count;model.search="later"
        try pair(0,1,"page_a","page_b","ReplacementSearchDebounceMovedSources")
        try await detailStarted("later",after:count)
        try pair(0,1,"page_a","page_b","UnverifiedReplacementSearchMovedSources")
        try await wait("FilteredDetailFailureMissing") {!model.loadingChanges && !model.loadingChangeDetail && !model.evidenceWarning.isEmpty}
        model.selectEvidence();try require(model.selected.isNull && !model.evidenceWarning.isEmpty,"FailedSearchReacquiredEventAuthorityOrHidError")
        try pair(0,1,"page_a","page_b","FailedSearchNormalizedToOuterEndpoint")

        try configure(delay:180);count=records().count;model.kind="font_changed"
        try pair(0,1,"page_a","page_b","KindDebounceLostSourcesAfterFailure")
        try await detailStarted("style",after:count,continuation:true)
        try pair(0,1,"page_a","page_b","KindContinuationInstalledUnverifiedSources")
        try await selected("style");try pair(1,2,"page_b","page_c","VerifiedKindDetailDidNotInstallReplacementSources")

        try configure("document-wrong-detail",delay:180);count=records().count;model.kind="text_modified"
        try pair(1,2,"page_b","page_c","FailedKindDebounceMovedSources")
        try await detailStarted("later",after:count)
        try await wait("KindDetailFailureMissing") {!model.loadingChanges && !model.loadingChangeDetail && !model.evidenceWarning.isEmpty}
        model.selectEvidence();try pair(1,2,"page_b","page_c","FailedKindLostLastVerifiedPair")
        try configure();model.search="no matching event"
        try await wait("EmptyFilteredQueryDidNotFinish") {!model.loadingChanges && !model.loadingChangeDetail && model.changes.isEmpty}
        model.selectEvidence();try pair(1,2,"page_b","page_c","EmptyFilterLostPhysicalSourcesWithoutSelectedRow")

        // A different fixed interval retires the source anchor. Re-selecting
        // the same version afterwards must reuse its rows, cancel old detail,
        // and restore a selection instead of leaving a permanent spinner.
        model.search="";model.kind="all";model.from=0;model.to=1;try await model.updateChanges();try await selected("middle")
        try require(model.sourceFrom==0 && model.sourceTo==1 && model.leftPageID=="page_a" && model.rightPageID=="page_b","NewFixedIntervalRetainedFilterSourceAnchor")
        let installed=try JSON(model.changes.map(\.raw)).data()
        let queryReads=records().filter{$0["action"].string=="changes"}.count
        model.selectVersion(1);try await model.updateChanges();try await selected("middle")
        try require(try JSON(model.changes.map(\.raw)).data()==installed && records().filter{$0["action"].string=="changes"}.count==queryReads,"ReadyVersionReselectionReloadedOrRewoundRows")

        try configure(delay:180);count=records().count;model.chooseChange("middle");try await detailStarted("middle",after:count,continuation:true)
        model.selectVersion(1)
        try require(!model.loadingChangeDetail,"VersionReselectionDidNotSynchronouslyRetireDetail")
        try await model.updateChanges();try await selected("middle")
        try require(try JSON(model.changes.map(\.raw)).data()==installed && records().filter{$0["action"].string=="changes"}.count==queryReads,"PendingVersionReselectionReloadedOrRewoundRows")

        model.tab="compare";try await model.updateChanges();try await selected("middle")
        count=records().count;model.chooseChange("middle");try await detailStarted("middle",after:count,continuation:true)
        let pageQueryReads=records().filter{$0["action"].string=="changes"}.count
        model.openHistoryPage(1,"manual_b")
        try require(!model.loadingChangeDetail && model.selectedChangeID==nil && model.manuallyBrowsing && model.rightPageID=="manual_b","HistoryPageDidNotSynchronouslyRetireDetail")
        try await model.updateChanges();await Task.yield()
        try require(!model.loadingChangeDetail && model.selected.isNull && model.selectedChangeID==nil && model.manuallyBrowsing && model.rightPageID=="manual_b" && model.sourceFrom==0 && model.sourceTo==1 && records().filter{$0["action"].string=="changes"}.count==pageQueryReads,"SameQuestionHistoryPageReacquiredEventOrStuckLoading")
        let paged=(0..<125).map{i -> [String:Any] in ["schema_version":"0.4.0","report_id":"fixed","change_id":"paged_\(i)","kind":"text_modified","from_occurrence":"occ_a","to_occurrence":"occ_b","before":"pagination \(i)","after":"after \(i)","evidence":[["revision_occurrence_id":"occ_a","page_id":"page_a"],["revision_occurrence_id":"occ_b","page_id":"page_b"]]]}
        try configure(documentChanges:paged);model.search="pagination";try await selected("paged_0");await model.loadMoreChanges()
        let appended=try JSON(model.changes.map(\.raw)).data(),appendedReads=records().filter{$0["action"].string=="changes"}.count
        try require(model.changes.count==125 && model.nextChangesCursor.isEmpty,"ReselectionContinuationFixtureNotInstalled")
        model.selectVersion(1);try await model.updateChanges();try await selected("paged_0")
        try require(model.changes.count==125 && model.nextChangesCursor.isEmpty && JSON(model.changes.map(\.raw)).data()==appended && records().filter{$0["action"].string=="changes"}.count==appendedReads,"SameVersionReselectionRewoundAppendedRows")
        print("PASS native filtered document sources: debounce/first/continued detail and failures preserve the last verified physical pair independently of row selection; verified replacements transition; empty filters retain pages; new fixed scopes retire anchors; ready/inflight same-version reselection and same-question history-page navigation cancel detail without refetching rows")
    }
}
