import Foundation
import AppKit

// App.swift owns the app entry point and capture helper. This model-only probe
// never enters WorkbookSmoke or captures images; fail explicitly if it does.
@MainActor enum Smoke {
    static func captureView(_ window:NSWindow,_ url:URL) throws {
        throw NSError(domain:"UnexpectedScreenshotInModelProbe",code:1)
    }
}

@main struct WorkbookReadProbe {
    @MainActor static func main() async throws {
        configureLegacyNativeLocalization()
        let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["DOCVER_TEST_USER_DATA"]!)
        let resources=Bundle.main.resourceURL!
        let model=WorkbookModel(bridge:Bridge(resources:resources,library:root))
        func control(_ mode:String="ok",_ value:String="fresh",delay:Int=0) throws {
            try JSON(["mode":mode,"value":value,"delay":delay]).data().write(to:root.appendingPathComponent("control.json"),options:.atomic)
        }
        func require(_ condition:Bool,_ message:String) throws {
            if !condition { throw NSError(domain:message,code:1) }
        }
        func requireCellRequestScope() throws {
            let text=try String(contentsOf:root.appendingPathComponent("read-events.jsonl"),encoding:.utf8)
            let events=try text.split(separator:"\n").map { JSON(try JSONSerialization.jsonObject(with:Data($0.utf8))) }.filter { $0["action"].string=="workbookQuery" }.suffix(2)
            try require(events.count==2,"MissingRetryRequests")
            for (i,event) in events.enumerated() {
                let query=event["query"]
                try require(query["project_id"].string=="project" && query["report_id"].string=="report" && query["revision_occurrence_id"].string==(i==0 ? "old":"new") && query["sheet_id"].string==(i==0 ? "sheet-old":"sheet-new") && query["row"].int==2 && query["column"].int==1 && query["text_offset"].int==0,"RetryChangedPinnedScope")
            }
        }
        try control();await model.start()
        model.projectID="project";model.reportID="report"
        model.report=JSON(["report_id":"report","revisions":[["revision_occurrence_id":"old","sheets":[["sheet_id":"sheet-old"]]],["revision_occurrence_id":"new","sheets":[["sheet_id":"sheet-new"]]]]])
        model.beforeID="old";model.afterID="new";model.beforeSheetID="sheet-old";model.afterSheetID="sheet-new"
        try require(model.ready,"ModelNotReady")
        model.beforeAddress="B2";model.afterAddress="";model.rowStart=2;model.columnStart=2
        try require(model.navigationRangePrefix.isEmpty,"BeforeOnlyRangeLabelledAfterEvidence")
        model.beforeAddress="B2";model.afterAddress="B3";model.rowStart=3;model.beforeRowStart=2
        try require(model.navigationRangePrefix=="이후 버전 ","MovedRangeLostAfterLabel")
        model.rowStart=2
        try require(model.navigationRangePrefix.isEmpty,"SharedRangeLabelledAfterOnly")

        try control("cell-fail");await model.selectCell(2,1)
        try require(!model.cellFailure.isEmpty && !model.loadingCell && model.beforeCell.isNull && model.afterCell.isNull,"FirstReadFailureKeptSourceOrSpinner")
        try control();await model.loadSelectedCells()
        try require(model.cellFailure.isEmpty && model.beforeCell["value"].string=="fresh" && model.afterCell["address"].string=="A2","FirstReadRetryFailed")
        try requireCellRequestScope()

        try control("cell-fail");await model.loadSelectedCells(offset:1024)
        try require(model.cellTextOffset==1024 && !model.cellFailure.isEmpty,"ContinuationFailureMissing")
        try control();await model.loadSelectedCells()
        try require(model.cellTextOffset==0 && model.cellFailure.isEmpty && model.beforeCell["address"].string=="A2","ContinuationRestartFailed")
        try requireCellRequestScope()

        for mode in ["wrong-project","wrong-report","bad-second-side","wrong-revision","wrong-sheet","wrong-address","wrong-row","fractional-row","wrong-column","duplicate","absent-available","present-missing","nonarray-missing","unknown-availability"] {
            try control(mode);await model.loadSelectedCells()
            try require(!model.cellFailure.isEmpty && model.beforeCell.isNull && model.afterCell.isNull && !model.loadingCell,"UntrustedCellDisplayed-"+mode)
        }
        try control("missing");await model.loadSelectedCells()
        try require(model.cellFailure.isEmpty && model.beforeCell.isNull && model.afterCell.isNull,"MissingCellIsReadFailure")
        try control("grid-fail");await model.loadRange()
        try require(!model.rangeFailure.isEmpty && !model.loadingRange && model.beforeCells.isEmpty && model.afterCells.isEmpty,"RangeFailureKeptStaleGrid")
        try control();await model.loadRange()
        try require(model.rangeFailure.isEmpty && model.beforeCells.first?["address"].string=="A2" && model.afterCells.first?["value"].string=="fresh","RangeRetryFailed")
        model.addressInput="ZZZZ1";await model.goToAddress()
        try require(!model.addressFailure.isEmpty && model.rangeFailure.isEmpty && model.beforeCells.first?["address"].string=="A2","InvalidAddressPretendedReadFailure")
        await model.selectCell(2,1)
        try require(model.addressFailure.isEmpty && model.cellFailure.isEmpty,"GridSelectionKeptInvalidAddressError")
        model.addressInput="ZZZZ1";await model.goToAddress()
        model.changes=[JSON(["change_id":"good","from_revision_occurrence_id":"old","to_revision_occurrence_id":"new","from_sheet_id":"sheet-old","to_sheet_id":"sheet-new","before_address":"A2","after_address":"A2"])]
        model.changesFromID="old";model.changesToID="new";model.changesMode="history"
        await model.chooseChange("good")
        try require(model.addressFailure.isEmpty && model.cellFailure.isEmpty && model.beforeAddress=="A2" && model.afterAddress=="A2","ChangeSelectionKeptInvalidAddressError")
        let pinnedRows=try JSON(model.changes.map(\.raw)).data(),pinnedQuery=model.comparisonScope
        func rangeQueryCount()throws->Int {
            try String(contentsOf:root.appendingPathComponent("read-events.jsonl"),encoding:.utf8).split(separator:"\n").map{JSON(try JSONSerialization.jsonObject(with:Data($0.utf8)))}.filter{$0["name"].string=="list_workbook_changes"}.count
        }
        let queryCount=try rangeQueryCount()
        await model.changeSheet(before:"another-physical-sheet")
        try require(model.selectedChange.isNull && model.canReturnToChange && model.beforeSheetID=="another-physical-sheet","ManualSheetKeptSemanticEventOrLostReturn")
        try require(workbookFieldDiffEligibility(change:model.selectedChange,before:model.beforeCell,after:model.afterCell,scope:WorkbookSelectedEventScope(beforeOccurrence:model.beforeID,afterOccurrence:model.afterID,beforeSheet:model.beforeSheetID,afterSheet:model.afterSheetID)) == .neutral,"ForeignSheetClaimedSelectedFieldEdit")
        await model.returnToChange()
        try require(model.selectedChangeID=="good" && model.beforeSheetID=="sheet-old" && model.afterSheetID=="sheet-new" && model.beforeAddress=="A2" && model.afterAddress=="A2","ReturnDidNotRestorePhysicalEventSources")
        await model.selectCell(2,1);try require(model.selectedChange.isNull && model.canReturnToChange,"ManualCellLostReturn")
        await model.returnToChange()
        await model.moveWindow(columns:12);try require(model.selectedChange.isNull && model.canReturnToChange,"ManualWindowLostReturn")
        await model.returnToChange()
        try require(model.selectedChangeID=="good" && model.comparisonScope==pinnedQuery && (try JSON(model.changes.map(\.raw)).data())==pinnedRows && (try rangeQueryCount())==queryCount,"ReturnRequeriedOrReplacedPinnedChangeList")
        for field in ["project","report","from","to","mode","membership","event-bytes"] {
            await model.chooseChange("good");await model.selectCell(2,1)
            switch field {
            case "project":model.projectID="other-project";model.projectID="project"
            case "report":model.reportID="other-report";model.reportID="report"
            case "from":model.changesFromID="other-from";model.changesFromID="old"
            case "to":model.changesToID="other-to";model.changesToID="new"
            case "mode":model.changesMode="range_net";model.changesMode="history"
            case "membership":model.changes=[]
            default:var changed=model.changes[0].dictionary;changed["after_address"]="B2";model.changes=[JSON(changed)]
            }
            try require(!model.canReturnToChange,"StaleWorkbookAnchorSurvived-"+field)
            await model.returnToChange();try require(model.selectedChangeID.isEmpty,"StaleWorkbookAnchorRestored-"+field)
            model.changes=[JSON(["change_id":"good","from_revision_occurrence_id":"old","to_revision_occurrence_id":"new","from_sheet_id":"sheet-old","to_sheet_id":"sheet-new","before_address":"A2","after_address":"A2"])]
        }
        model.addressInput="A2";await model.goToAddress()
        try require(model.addressFailure.isEmpty && model.cellFailure.isEmpty,"ValidAddressDidNotClearValidation")
        model.changes=[JSON(["change_id":"bad","from_revision_occurrence_id":"foreign","to_revision_occurrence_id":"new"])]
        let beforeRejected=try JSON(["before":model.beforeID,"after":model.afterID,"left_sheet":model.beforeSheetID,"right_sheet":model.afterSheetID,"left_address":model.beforeAddress,"right_address":model.afterAddress,"row":model.selectedRow,"column":model.selectedColumn,"left_raw":model.beforeCell.raw,"right_raw":model.afterCell.raw,"range":model.rangeScope,"query":model.comparisonScope,"reveal":model.revealGeneration]).data(),beforeHistory=model.cellHistoryAnchor,beforeRejectedRequests=try Data(contentsOf:root.appendingPathComponent("read-events.jsonl"))
        await model.chooseChange("bad")
        let afterRejected=try JSON(["before":model.beforeID,"after":model.afterID,"left_sheet":model.beforeSheetID,"right_sheet":model.afterSheetID,"left_address":model.beforeAddress,"right_address":model.afterAddress,"row":model.selectedRow,"column":model.selectedColumn,"left_raw":model.beforeCell.raw,"right_raw":model.afterCell.raw,"range":model.rangeScope,"query":model.comparisonScope,"reveal":model.revealGeneration]).data()
        try require(beforeRejected==afterRejected && model.cellHistoryAnchor==beforeHistory && model.cellFailure.isEmpty && model.selectedChangeID.isEmpty && model.selectedChange.isNull && !model.canReturnToChange && !model.loadingCell && (try Data(contentsOf:root.appendingPathComponent("read-events.jsonl")))==beforeRejectedRequests,"InvalidChangeMovedPhysicalSourceOrRetainedEventAuthority")
        await model.selectCell(2,1)

        try control("late","stale",delay:500)
        let late=Task { await model.loadSelectedCells() }
        var started=false
        for _ in 0..<200 {
            let events=(try? String(contentsOf:root.appendingPathComponent("read-events.jsonl"),encoding:.utf8)) ?? ""
            if events.contains("\"mode\":\"late\"") { started=true;break }
            try await Task.sleep(nanoseconds:5_000_000)
        }
        try require(started,"LateRequestDidNotStart")
        try control("ok","newest");await model.loadSelectedCells();await late.value
        try require(model.cellFailure.isEmpty && model.beforeCell["value"].string=="newest" && model.afterCell["value"].string=="newest" && !model.loadingCell,"SupersededRetryOverwroteNewSource")
        // A zero-item response must retain its coverage warning. Only the current
        // report/interval response may own the warning, independently of rows.
        for contents in ["empty","nonempty"] {
            try control("changes-unsupported",contents);await model.loadChanges()
            try require(!model.blankFormattingWarning.isEmpty && model.changes.isEmpty == (contents == "empty") && model.changesFailure.isEmpty,"BlankFormattingWarningLost-"+contents)
        }
        try control("changes-supported");await model.changeMode("history")
        try require(model.blankFormattingWarning.isEmpty && model.changesFailure.isEmpty,"SupportedIntervalKeptFormattingWarning")
        try control("changes-unsupported");await model.loadChanges()
        try control("changes-fail");await model.loadChanges()
        try require(model.blankFormattingWarning.isEmpty && !model.changesFailure.isEmpty,"FailedChangesKeptFormattingWarning")
        for field in ["project","report","from","to","mode"] {
            try control("changes-wrong-"+field);await model.loadChanges()
            try require(model.blankFormattingWarning.isEmpty && !model.changesFailure.isEmpty,"ForeignChangesOwnedFormattingWarning-"+field)
        }
        try control("changes-unsupported");await model.loadChanges()
        try control("changes-late","empty",delay:500)
        let lateChanges=Task { await model.loadChanges() }
        var changesStarted=false
        for _ in 0..<200 {
            let events=(try? String(contentsOf:root.appendingPathComponent("read-events.jsonl"),encoding:.utf8)) ?? ""
            if events.contains("\"mode\":\"changes-late\"") { changesStarted=true;break }
            try await Task.sleep(nanoseconds:5_000_000)
        }
        try require(changesStarted && model.loadingChanges && model.blankFormattingWarning.isEmpty,"PendingChangesKeptFormattingWarning")
        try control("changes-supported");await model.loadChanges();await lateChanges.value
        try require(!model.loadingChanges && model.changesFailure.isEmpty && model.blankFormattingWarning.isEmpty,"SupersededChangesRestoredFormattingWarning")
        try control("changes-unsupported");await model.loadChanges()
        model.changesToID="other"
        try require(model.blankFormattingWarning.isEmpty,"DifferentIntervalInheritedFormattingWarning")
        model.changesToID="new"
        model.reportID="other-report"
        try require(model.blankFormattingWarning.isEmpty,"DifferentReportInheritedFormattingWarning")
        model.reportID="report";model.projectID="other-project"
        try require(model.blankFormattingWarning.isEmpty,"DifferentProjectInheritedFormattingWarning")
        model.projectID="project"
        model.invalidateReads()
        try require(model.blankFormattingWarning.isEmpty,"InvalidatedReadsKeptFormattingWarning")
        try control("changes-unsupported");await model.loadChanges()
        let retainedReport=model.report
        model.clearSelection()
        try require(model.blankFormattingWarning.isEmpty,"ClearedSelectionKeptFormattingWarning")
        model.reportID="report";model.report=retainedReport;model.beforeID="old";model.afterID="new"
        await model.loadChanges()
        try require(!model.blankFormattingWarning.isEmpty,"WarningNotRestoredAfterFreshQuery")
        // Equal source coordinates reuse the same validated response, including
        // missing observations and continuation requests; no second trust path.
        model.beforeID="old";model.afterID="old";model.beforeSheetID="sheet-old";model.afterSheetID="sheet-old";model.beforeAddress="A2";model.afterAddress="A2"
        func cellRequests()throws->[JSON] {try String(contentsOf:root.appendingPathComponent("read-events.jsonl"),encoding:.utf8).split(separator:"\n").map{JSON(try JSONSerialization.jsonObject(with:Data($0.utf8)))}.filter{$0["action"].string=="workbookQuery" && !$0["query"]["row"].isNull}}
        for (mode,offset) in [("ok",0),("ok",1024),("missing",0),("wrong-report",0)] {
            try control(mode,"single saved source")
            let count=try cellRequests().count;await model.loadSelectedCells(offset:offset);let requests=try cellRequests()
            try require(requests.count==count+1,"EqualCellSourceWasReadTwice_\(mode)_\(offset)")
            let q=requests.last!["query"]
            try require(q["project_id"].string=="project" && q["report_id"].string=="report" && q["revision_occurrence_id"].string=="old" && q["sheet_id"].string=="sheet-old" && q["row"].int==2 && q["column"].int==1 && q["text_offset"].int==offset && (try model.beforeCell.data())==(try model.afterCell.data()),"ReusedSingleSourceChangedPhysicalScopeOrRawObservation")
            try require(mode=="wrong-report" ? !model.cellFailure.isEmpty && model.beforeCell.isNull : model.cellFailure.isEmpty,"EqualSourceBypassedResponseScopeValidation")
        }
        try await checkPagedFirstSelection(resources:resources,root:root)
        try await checkMethodIntervalPreservation(resources:resources,root:root)
        try await checkInitialPhysicalOwnership(resources:resources,root:root)
        try await checkEventAuthority(resources:resources,root:root)
        model.closeReads()
        try require(model.blankFormattingWarning.isEmpty,"ClosedWindowKeptFormattingWarning")
        await model.loadSelectedCells()
        try require(!model.ready && model.beforeCell.isNull && model.afterCell.isNull && !model.loadingCell,"ClosedWindowRetriedRead")
        print("PASS native workbook reads: first/continuation/range recovery; fourteen wrong-scope/malformed responses withheld; missing observations preserved; superseded retry and closed-window guards; scoped blank-formatting warnings for empty/nonempty changes, reset/pending/error/stale/foreign response guards")
    }
    @MainActor private static func checkPagedFirstSelection(resources:URL,root:URL) async throws {
        let model=WorkbookModel(bridge:Bridge(resources:resources,library:root))
        func require(_ condition:Bool,_ message:String) throws {if !condition{throw NSError(domain:message,code:1)}}
        func event(_ id:String,from:String="old",address:String="A2")->[String:Any] {["change_id":id,"kind":"value_changed","from_revision_occurrence_id":from,"to_revision_occurrence_id":"new","from_sheet_id":"sheet-old","to_sheet_id":"sheet-new","before_address":address,"after_address":address,"description":"literal é e\u{301} 👨‍👩‍👧‍👦\r\n{0} %" ]}
        let first=event("paged-first"),second=event("paged-second"),third=event("paged-third")
        let pages:[[Any]]=[[event("foreign-first",from:"foreign"),event("invalid-address-first",address:"not-a-cell"),first],[second],[third]]
        let raw="PAGED RAW\r\n한글 🧪 e\u{301}"
        func control(mode:String="changes-supported",pages:[[Any]]=pages) throws {try JSON(["mode":mode,"value":raw,"pages":pages]).data().write(to:root.appendingPathComponent("control.json"),options:.atomic)}
        func events() throws->[JSON] {try String(contentsOf:root.appendingPathComponent("read-events.jsonl"),encoding:.utf8).split(separator:"\n").map{JSON(try JSONSerialization.jsonObject(with:Data($0.utf8)))}}
        func listCount() throws->Int {try events().filter{$0["name"].string=="list_workbook_changes"}.count}
        func sourceCount() throws->Int {try events().filter{$0["action"].string=="workbookGrid" || $0["name"].string=="get_workbook_cell"}.count}
        func source() throws->Data {try JSON(["before":model.beforeID,"after":model.afterID,"before_sheet":model.beforeSheetID,"after_sheet":model.afterSheetID,"before_address":model.beforeAddress,"after_address":model.afterAddress,"row":model.selectedRow,"column":model.selectedColumn,"before_raw":model.beforeCell.raw,"after_raw":model.afterCell.raw,"row_start":model.rowStart,"column_start":model.columnStart,"before_row_start":model.beforeRowStart,"before_column_start":model.beforeColumnStart,"after_row_start":model.afterRowStart,"after_column_start":model.afterColumnStart,"before_grid":model.beforeCells.map(\.raw),"after_grid":model.afterCells.map(\.raw)]).data()}
        func paging() throws->Data {try JSON(["rows":model.changes.map(\.raw),"next":model.changeCursor,"previous":model.changePreviousCursors,"page":model.changePageNumber,"scope":model.comparisonScope]).data()}
        try control();await model.start()
        model.projectID="project";model.reportID="report";model.report=JSON(["report_id":"report","revisions":[["revision_occurrence_id":"old","sheets":[["sheet_id":"sheet-old"]]],["revision_occurrence_id":"new","sheets":[["sheet_id":"sheet-new"]]]]])
        model.beforeID="old";model.afterID="new";model.beforeSheetID="sheet-old";model.afterSheetID="sheet-new"
        let queriesBefore=try listCount()
        await model.changeVersions(before:"old",after:"new")
        try require(model.changesFailure.isEmpty && model.cellFailure.isEmpty && model.selectedChangeID=="paged-first" && (try model.selectedChange.data())==(try JSON(first).data()),"FirstSuccessfulQueryDidNotChooseFirstEligibleEvent")
        try require(model.beforeCell["address"].string=="A2" && model.afterCell["address"].string=="A2" && model.beforeCell["value"].string.utf16.elementsEqual(raw.utf16) && model.afterCell["value"].string.utf16.elementsEqual(raw.utf16),"AutomaticFirstEventDidNotLoadExactLinkedRawSources")
        try require(model.rowStart==1 && model.columnStart==1 && model.beforeRowStart==1 && model.afterRowStart==1 && model.beforeColumnStart==1 && model.afterColumnStart==1 && model.beforeCells.first?["address"].string=="A2" && model.afterCells.first?["address"].string=="A2","AutomaticFirstEventRebasedAlreadyVisibleAtoLRowOneWindow")
        try require(try listCount()==queriesBefore+1,"AutomaticFirstSelectionRequeriedChangeList")
        let fixedScope=model.comparisonScope,fixedReport=try model.report.data(),initialSource=try source(),initialGeneration=model.revealGeneration,initialSourceRequests=try sourceCount()
        await model.loadChanges(next:true)
        try require(model.selectedChange["description"].string.utf16.elementsEqual(JSON(first)["description"].string.utf16),"RetainedEventCacheChangedLiteralUTF16")
        try require(model.changePageNumber==2 && model.changes.map{$0["change_id"].string}==["paged-second"] && model.selectedChangeID=="paged-first" && (try model.selectedChange.data())==(try JSON(first).data()) && (try source())==initialSource && model.revealGeneration==initialGeneration && (try sourceCount())==initialSourceRequests,"NextPageLostOffPageFirstEventOrRequeriedManualSource")
        await model.chooseChange("paged-second")
        let selectedSource=try source(),selectedGeneration=model.revealGeneration,selectedSourceRequests=try sourceCount()
        for action in ["previous","refresh","next","next"] {
            if action=="previous" {await model.loadChanges(previous:true)}else if action=="next"{await model.loadChanges(next:true)}else{await model.loadChanges(preserveEndpoints:true)}
            try require(model.changesFailure.isEmpty && model.selectedChangeID=="paged-second" && (try model.selectedChange.data())==(try JSON(second).data()) && (try source())==selectedSource && model.revealGeneration==selectedGeneration && (try sourceCount())==selectedSourceRequests,"SameScopePaginationOrRefreshChangedSelectedEventSourceOrViewport_"+action)
        }
        try require(model.changePageNumber==3 && !model.changes.contains(where:{$0["change_id"].string=="paged-second"}),"ControlledFixtureDidNotReachOffPageSelectedEvent")
        await model.selectCell(2,1)
        try require(model.selectedChangeID.isEmpty && model.selectedChange.isNull && model.canReturnToChange,"ManualBrowseLostPagedReturnAnchorOrKeptSemanticSelection")
        let manualSource=try source(),manualGeneration=model.revealGeneration,manualSourceRequests=try sourceCount()
        for _ in 0..<2 {
            await model.loadChanges(previous:true)
            try require(model.selectedChangeID.isEmpty && model.selectedChange.isNull && model.canReturnToChange && (try source())==manualSource && model.revealGeneration==manualGeneration && (try sourceCount())==manualSourceRequests,"PaginationReselectedEventOrLostManualBrowseAndReturn")
        }
        let listBeforeReturn=try paging(),returnQueries=try listCount()
        await model.returnToChange()
        try require(model.selectedChangeID=="paged-second" && (try model.selectedChange.data())==(try JSON(second).data()) && (try source())==selectedSource && (try paging())==listBeforeReturn && (try listCount())==returnQueries,"OffPageReturnRequeriedListChangedPagingOrLostExactPhysicalEvent")
        try require(model.comparisonScope==fixedScope && (try model.report.data())==fixedReport,"PagedSelectionChangedFixedReportOrLogicalQuery")
        // A method change is a new list scope, not a new physical version pick.
        let beforeMethodSource=try source(),beforeMethodGeneration=model.revealGeneration,beforeMethodReads=try sourceCount()
        try control(mode:"changes-fail");await model.changeMode("history")
        try require(!model.changesFailure.isEmpty,"NewLogicalQueryFailureWasNotExercised")
        let historyFirst=event("history-first"),historyPages:[[Any]]=[[historyFirst],[event("history-second")]]
        try control(pages:historyPages);await model.loadChanges(preserveEndpoints:true)
        try require(model.changesMode=="history" && model.selectedChangeID.isEmpty && model.changesFailure.isEmpty && model.cellFailure.isEmpty && (try source())==beforeMethodSource && model.revealGeneration==beforeMethodGeneration && (try sourceCount())==beforeMethodReads,"MethodFailureRetryAutomaticallySelectedOrChangedPhysicalSources")
        await model.chooseChange("history-first")
        await model.selectCell(2,1);await model.loadChanges(next:true)
        try require(model.selectedChangeID.isEmpty && model.canReturnToChange,"SameModePageAutomaticallyReselectedAfterManualBrowse")
        await model.returnToChange();await model.loadChanges(previous:true);await model.selectCell(2,1)
        var mutated=model.changes[0].dictionary;mutated["after_address"]="B2";model.changes=[JSON(mutated)]
        try require(!model.canReturnToChange,"ImmutablePagedAnchorBypassedVisibleEventMutationGuard")
        await model.returnToChange();try require(model.selectedChangeID.isEmpty,"MutatedVisibleEventRestoredFromRetainedSnapshot")
        // A manually replaced list is not a qualified pagination response.
        try control();await model.changeMode("range_net");await model.chooseChange("paged-first");await model.selectCell(2,1);model.changes=[]
        try require(!model.canReturnToChange,"UnqualifiedManualListReplacementBorrowedPagedAnchorAuthority")
        let proof:[String:Any]=["first_success_selects_first_eligible_valid_revision_and_address":true,"first_selection_keeps_existing_row_one_A_to_L_window":true,"linked_before_after_raw_utf16_preserved":true,"same_scope_next_previous_refresh_keep_selected_off_page_event_and_source":true,"pagination_issues_only_list_reads":true,"manual_browse_retains_return_anchor_across_pages":true,"off_page_return_retains_list_cursor_and_query":true,"comparison_method_failure_retry_preserves_physical_sources_without_autoselection":true,"visible_mutated_event_and_unqualified_list_replacement_rejected":true,"original_stale_foreign_and_mutated_guards_preserved":true,"fixture_page_count":3,"scope":"Actual Bridge/loadChanges model regression. Manual viewport authority is physical range starts and reveal generation; actual native scrollview checks belong to mounted workspace suite." ]
        if let path=ProcessInfo.processInfo.environment["DOCVER_TEST_WORKBOOK_PAGED_SELECTION_EVIDENCE_OUT"],!path.isEmpty {try JSONSerialization.data(withJSONObject:proof,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:path))}
        try JSONSerialization.data(withJSONObject:proof,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("paged-selection-proof.json"))
        print("PASS native workbook paged selection: first eligible event, retained off-page selection/raw/window, manual browse Return, method-preserving retry and immutable source guards")
        model.closeReads()
    }
    @MainActor private static func checkEventAuthority(resources:URL,root:URL)async throws {
        func require(_ value:Bool,_ name:String)throws{if !value{throw NSError(domain:name,code:1)}}
        let raw="AUTHORITY RAW\r\né / e\u{301}",revisions=["old","mid","new"].map{["revision_occurrence_id":$0,"sheets":[["sheet_id":"sheet-"+$0]]] as [String:Any]}
        func event(_ id:String,from:String="old",to:String="new",kind:String="stored_value",left:String="D4",right:String="D4",leftSheet:String?=nil,rightSheet:String?=nil)->JSON {JSON(["change_id":id,"kind":kind,"from_revision_occurrence_id":from,"to_revision_occurrence_id":to,"from_sheet_id":leftSheet ?? "sheet-"+from,"to_sheet_id":rightSheet ?? "sheet-"+to,"before_address":left,"after_address":right])}
        func control(_ pages:[[JSON]])throws {try JSON(["mode":"changes-supported","value":raw,"scoped_cells":true,"pages":pages.map{$0.map(\.raw)}]).data().write(to:root.appendingPathComponent("control.json"),options:.atomic)}
        func records()throws->Data{try Data(contentsOf:root.appendingPathComponent("read-events.jsonl"))}
        let good=event("qualified");try control([[good],[]])
        let model=WorkbookModel(bridge:Bridge(resources:resources,library:root));await model.start();defer{model.closeReads()}
        model.projectID="project";model.reportID="authority-report";model.report=JSON(["report_id":"authority-report","revisions":revisions]);model.beforeID="old";model.afterID="new";model.beforeSheetID="sheet-old";model.afterSheetID="sheet-new"
        await model.changeVersions(before:"old",after:"new")
        func source()throws->Data{try JSON(["before":model.beforeID,"after":model.afterID,"left_sheet":model.beforeSheetID,"right_sheet":model.afterSheetID,"left_address":model.beforeAddress,"right_address":model.afterAddress,"left_raw":model.beforeCell.raw,"right_raw":model.afterCell.raw,"left_grid":model.beforeCells.map(\.raw),"right_grid":model.afterCells.map(\.raw),"row":model.selectedRow,"column":model.selectedColumn,"window":[model.rowStart,model.columnStart,model.beforeRowStart,model.beforeColumnStart,model.afterRowStart,model.afterColumnStart],"reveal_generation":model.revealGeneration,"text_offset":model.cellTextOffset]).data()}
        var rejected:[String]=[]
        let invalid:[(String,JSON,String,String,String)]=[
            ("outside_interval",event("outside",from:"old",to:"new"),"mid","new","history"),
            ("reversed",event("reversed",from:"new",to:"old"),"old","new","history"),
            ("net_intermediate",event("intermediate",to:"mid"),"old","new","range_net"),
            ("foreign_sheet",event("foreign",leftSheet:"sheet-new"),"old","new","history"),
            ("invalid_address",event("invalid",left:"D0"),"old","new","history"),
            ("address_without_sheet",event("unowned",rightSheet:""),"old","new","history")]
        for (name,bad,from,to,mode) in invalid {
            model.changesFromID=from;model.changesToID=to;model.changesMode=mode;model.changes=[bad];model.selectedChangeID=bad["change_id"].string
            try require(model.selectedChange.isNull,"InvalidVisibleEventAuthorized_"+name)
            let fixedSource=try source(),fixedReport=try model.report.data(),fixedScope=model.comparisonScope,requests=try records()
            await model.chooseChange(bad["change_id"].string)
            try require(model.selectedChangeID.isEmpty && model.selectedChange.isNull && !model.canReturnToChange && (try source())==fixedSource && (try model.report.data())==fixedReport && model.comparisonScope==fixedScope && (try records())==requests,"RejectedEventMovedSourceQueriedOrKeptAuthority_"+name)
            rejected.append(name)
        }
        model.changesFromID="old";model.changesToID="new";model.changesMode="history";model.mode="history"
        let metadata=[event("date",kind:"date_system",left:"",right:"",leftSheet:"",rightSheet:""),event("calculation",kind:"calculation_settings",left:"",right:"",leftSheet:"",rightSheet:""),event("one-sided-sheet",kind:"sheet_observation",left:"",right:"",rightSheet:""),event("merges",kind:"merges",left:"",right:"")]
        for item in metadata {model.changes=[item];await model.chooseChange(item["change_id"].string);try require(model.selectedChange["change_id"].string==item["change_id"].string && model.showingSheetMetadata,"LegitimateMetadataEventRejected_"+item["kind"].string)}
        let one=event("one-sided",right:"",rightSheet:"");model.changes=[one];await model.chooseChange("one-sided")
        try require(model.selectedChangeID=="one-sided" && model.beforeCell["value"].string.utf16.elementsEqual((raw+":old:sheet-old:D4").utf16) && model.afterCell.isNull,"LegitimateOneSidedPhysicalEventRejected")
        try control([[good],[]]);await model.loadChanges(preserveEndpoints:true);await model.chooseChange("qualified");await model.loadChanges(next:true)
        try require(model.changes.isEmpty && model.selectedChange["change_id"].string=="qualified","ControlledOffPageAuthorityNotEstablished")
        model.report=JSON(["report_id":"authority-report","revisions":revisions.map{item in var value=item;if value["revision_occurrence_id"] as? String=="old"{value["sheets"]=[]};return value}])
        try require(model.selectedChange.isNull,"OffPageRetainedEventIgnoredPhysicalMembership")
        let retainedSource=try source(),retainedReport=try model.report.data(),retainedScope=model.comparisonScope,requests=try records()
        await model.returnToChange()
        try require(model.selectedChangeID.isEmpty && !model.canReturnToChange && (try source())==retainedSource && (try model.report.data())==retainedReport && model.comparisonScope==retainedScope && (try records())==requests,"InvalidPagedAnchorMovedSourceOrRetainedReturnAuthority")
        model.report=JSON(["report_id":"authority-report","revisions":revisions]);await model.chooseChange("qualified")
        try require(model.selectedChangeID.isEmpty && !model.canReturnToChange && (try source())==retainedSource && (try records())==requests,"InvalidPagedAuthorityRevivedAfterMembershipRestored")
        let proofURL=root.appendingPathComponent("initial-ownership-proof.json");var proof=try JSONSerialization.jsonObject(with:Data(contentsOf:proofURL)) as! [String:Any]
        proof["source34_event_authority"]=["scope":"actual WorkbookModel/Bridge with controlled malformed visible and paged events; no claim of a normal backend misroute","rejected_visible_cases":rejected,"invalid_selection_clears_anchor_without_source_query_or_mutation":true,"metadata_kinds_accepted":metadata.map{$0["kind"].string},"one_sided_physical_raw_preserved":true,"invalid_off_page_membership_rejected_and_return_cleared":true]
        let data=try JSONSerialization.data(withJSONObject:proof,options:[.prettyPrinted,.sortedKeys]);try data.write(to:proofURL)
        if let path=ProcessInfo.processInfo.environment["DOCVER_TEST_WORKBOOK_INITIAL_OWNERSHIP_EVIDENCE_OUT"],!path.isEmpty{try data.write(to:URL(fileURLWithPath:path))}
        print("PASS native workbook event authority: interval/order/method/physical-sheet guards, metadata and one-sided positives, rejected paged authority without source mutation or queries")
    }
    @MainActor private static func checkMethodIntervalPreservation(resources:URL,root:URL) async throws {
        let model=WorkbookModel(bridge:Bridge(resources:resources,library:root))
        func require(_ value:Bool,_ name:String)throws {if !value{throw NSError(domain:name,code:1)}}
        func event(_ id:String,_ from:String,_ to:String,_ address:String)->JSON {JSON(["change_id":id,"kind":"stored_value","from_revision_occurrence_id":from,"to_revision_occurrence_id":to,"from_sheet_id":"sheet-"+from,"to_sheet_id":"sheet-"+to,"before_address":address,"after_address":address])}
        let intermediate=event("history-old-mid","old","mid","D4"),net=event("net-old-new","old","new","B3"),raw="MODE RAW\r\n한글 🧪 e\u{301}"
        func control(_ mode:String="changes-supported",history:JSON?=nil)throws {
            try JSON(["mode":mode,"value":raw,"scoped_cells":true,"changes_by_mode":["history":[(history ?? intermediate).raw],"range_net":[net.raw]]]).data().write(to:root.appendingPathComponent("control.json"),options:.atomic)
        }
        func events()throws->[JSON] {try String(contentsOf:root.appendingPathComponent("read-events.jsonl"),encoding:.utf8).split(separator:"\n").map{JSON(try JSONSerialization.jsonObject(with:Data($0.utf8)))}}
        func lists()throws->[JSON] {try events().filter{$0["name"].string=="list_workbook_changes"}}
        func sourceReadCount()throws->Int {try events().filter{$0["action"].string=="workbookGrid" || $0["name"].string=="get_workbook_cell"}.count}
        func physical()throws->Data {try JSON(["before":model.beforeID,"after":model.afterID,"before_sheet":model.beforeSheetID,"after_sheet":model.afterSheetID,"before_address":model.beforeAddress,"after_address":model.afterAddress,"selected_row":model.selectedRow,"selected_column":model.selectedColumn,"address_input":model.addressInput,"row_start":model.rowStart,"column_start":model.columnStart,"before_row_start":model.beforeRowStart,"before_column_start":model.beforeColumnStart,"after_row_start":model.afterRowStart,"after_column_start":model.afterColumnStart,"reveal_generation":model.revealGeneration,"before_raw":model.beforeCell.raw,"after_raw":model.afterCell.raw,"before_grid":model.beforeCells.map(\.raw),"after_grid":model.afterCells.map(\.raw),"text_offset":model.cellTextOffset,"text_next":model.cellTextNext as Any? ?? NSNull()]).data()}
        func requireCurrentQuery(_ method:String)throws {
            let requests=try lists()
            guard let query=requests.last?["query"] else{throw NSError(domain:"MethodScopedListQueryMissing",code:1)}
            try require(model.changesFromID=="old" && model.changesToID=="new" && model.changesMode==method && query["project_id"].string=="project" && query["report_id"].string=="method-report" && query["from_revision_occurrence_id"].string=="old" && query["to_revision_occurrence_id"].string=="new" && query["mode"].string==method,"MethodChangeNarrowedFixedListQueryInterval")
        }
        try control();await model.start()
        model.projectID="project";model.reportID="method-report";model.report=JSON(["report_id":"method-report","revisions":["old","mid","new"].map{["revision_occurrence_id":$0,"sheets":[["sheet_id":"sheet-"+$0,"name":"Sheet"]]]}]);model.beforeID="old";model.afterID="new";model.beforeSheetID="sheet-old";model.afterSheetID="sheet-new";model.mode="history"
        await model.changeVersions(before:"old",after:"new")
        try require(model.selectedChangeID=="history-old-mid" && model.beforeID=="old" && model.afterID=="mid" && model.beforeAddress=="D4" && model.afterAddress=="D4" && model.rangeFailure.isEmpty && model.cellFailure.isEmpty,"InitialWideHistoryQueryDidNotSelectIntermediatePhysicalEvent")
        try require(model.beforeCell["value"].string.utf16.elementsEqual((raw+":old:sheet-old:D4").utf16) && model.afterCell["value"].string.utf16.elementsEqual((raw+":mid:sheet-mid:D4").utf16),"ThreeVersionFixtureDidNotLoadDistinctExactPhysicalRaw")
        let selectedPhysical=try physical(),selectedReads=try sourceReadCount(),fixedReport=try model.report.data()
        var observations:[[String:Any]]=[]
        for method in ["range_net","history"] {
            let count=try lists().count;await model.changeMode(method);try requireCurrentQuery(method)
            let expected=method=="history" ? intermediate:net
            try require(model.changesFailure.isEmpty && model.selectedChangeID.isEmpty && !model.canReturnToChange && model.selectedChange.isNull && (try physical())==selectedPhysical && (try sourceReadCount())==selectedReads && (try lists().count)==count+1 && (try model.changes.first?.data())==(try expected.data()),"MethodSwitchReplacedIntermediateRawSourceOrFailedToReplaceOnlyScopedList_"+method)
            observations.append(["route":"selected_intermediate_event","method":method,"source_from":model.beforeID,"source_to":model.afterID,"address":model.afterAddress,"query_from":model.changesFromID,"query_to":model.changesToID,"physical_utf16_unchanged":true,"list_request_count":1,"source_request_count":0,"obsolete_selection_anchor_cleared":true])
        }
        await model.selectCell(7,6)
        try require(model.beforeCell["value"].string.utf16.elementsEqual((raw+":old:sheet-old:F7").utf16) && model.afterCell["value"].string.utf16.elementsEqual((raw+":mid:sheet-mid:F7").utf16),"ManualModeFixtureDidNotLoadDistinctF7Source")
        let manualPhysical=try physical(),manualReads=try sourceReadCount()
        for method in ["range_net","history"] {
            await model.changeMode(method);try requireCurrentQuery(method)
            try require(model.changesFailure.isEmpty && model.selectedChangeID.isEmpty && (try physical())==manualPhysical && (try sourceReadCount())==manualReads,"MethodSwitchResetManualPhysicalBrowse_"+method)
            observations.append(["route":"manual_physical_browse","method":method,"source_from":model.beforeID,"source_to":model.afterID,"address":model.afterAddress,"physical_utf16_unchanged":true,"source_request_count":0])
        }
        try control("changes-fail");await model.changeMode("range_net")
        try require(!model.changesFailure.isEmpty && (try physical())==manualPhysical && (try sourceReadCount())==manualReads,"FailedMethodResponseChangedPhysicalSourcesOrHidFailure")
        try control();await model.loadChanges(preserveEndpoints:true);try requireCurrentQuery("range_net")
        try require(model.changesFailure.isEmpty && model.selectedChangeID.isEmpty && (try physical())==manualPhysical && (try sourceReadCount())==manualReads && model.changes.first?["change_id"].string=="net-old-new","MethodResponseRetryAutoSelectedNewFirstOrKeptWrongList")
        try control("changes-limit")
        let beforeFallback=try lists().count;await model.changeMode("range_net");try requireCurrentQuery("history")
        try require(model.mode=="history" && model.changesFailure.isEmpty && !model.comparisonNotice.isEmpty && model.selectedChangeID.isEmpty && (try physical())==manualPhysical && (try sourceReadCount())==manualReads && (try lists().count)==beforeFallback+2 && model.changes.first?["change_id"].string=="history-old-mid","AutomaticHistoryFallbackAutoSelectedOrChangedPhysicalSources")
        let fallbackRequests=Array(try lists().suffix(2)).map{$0["query"]}
        try require(fallbackRequests.map{$0["mode"].string}==["range_net","history"] && fallbackRequests.allSatisfy{$0["from_revision_occurrence_id"].string=="old" && $0["to_revision_occurrence_id"].string=="new"},"FallbackDidNotUseTheSameWideInterval")
        try require((try model.report.data())==fixedReport,"MethodOnlyActionsReplacedFixedReport")
        // A later explicit version pick owns a fresh automatic link again.
        let newVersion=event("history-mid-new","mid","new","A2")
        try control(history:newVersion);await model.changeVersions(before:"mid",after:"new")
        try require(model.changesFailure.isEmpty && model.cellFailure.isEmpty && model.selectedChangeID=="history-mid-new" && model.beforeID=="mid" && model.afterID=="new" && model.changesFromID=="mid" && model.changesToID=="new" && model.beforeAddress=="A2" && model.afterAddress=="A2" && model.beforeCell["value"].string.utf16.elementsEqual((raw+":mid:sheet-mid:A2").utf16) && model.afterCell["value"].string.utf16.elementsEqual((raw+":new:sheet-new:A2").utf16),"ExplicitNewVersionQueryFailedToRestoreInitialAutomaticLink")
        let proof:[String:Any]=["scope":"Actual Bridge/model loadChanges using three controlled revisions and distinct literal UTF16 per physical revision/sheet/address; no packaged-native or viewport pixel claim","observations":observations,"wide_query_from":"old","wide_query_to":"new","inspected_source_from":"old","inspected_source_to":"mid","inspected_event_address":"D4","manual_address":"F7","selected_intermediate_source_preserved_across_method_toggles":true,"manual_browse_preserved_across_method_toggles":true,"failed_method_then_default_retry_does_not_reselect":true,"range_net_limit_fallback_keeps_sources_and_wide_interval":true,"method_actions_issue_only_list_requests":true,"distinct_before_after_exact_utf16_verified":true,"obsolete_query_selection_anchor_cleared":true,"explicit_new_version_query_still_auto_selects":true,"fixed_report_unchanged":true]
        try JSONSerialization.data(withJSONObject:proof,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("method-interval-proof.json"))
        if let path=ProcessInfo.processInfo.environment["DOCVER_TEST_WORKBOOK_MODE_INTERVAL_EVIDENCE_OUT"],!path.isEmpty {try JSONSerialization.data(withJSONObject:proof,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:path))}
        print("PASS native workbook method interval: three-version intermediate source, manual browse, failure retry, automatic history fallback and fresh-version initial selection")
        model.closeReads()
    }

    @MainActor private static func checkInitialPhysicalOwnership(resources:URL,root:URL) async throws {
        func require(_ value:Bool,_ name:String)throws {if !value{throw NSError(domain:name,code:1)}}
        let raw="INITIAL RAW\r\n한글 🧪 e\u{301}"
        let revisions:[[String:Any]]=["old","mid","new"].map{["revision_occurrence_id":$0,"sheets":[["sheet_id":"sheet-"+$0,"name":"Sheet"],["sheet_id":"other-"+$0,"name":"Other"]]]}
        func event(_ id:String,_ kind:String="stored_value",from:String="old",to:String="new",before:String="D4",after:String="D4",beforeSheet:String?=nil,afterSheet:String?=nil)->JSON {JSON(["change_id":id,"kind":kind,"from_revision_occurrence_id":from,"to_revision_occurrence_id":to,"from_sheet_id":beforeSheet ?? "sheet-"+from,"to_sheet_id":afterSheet ?? "sheet-"+to,"before_address":before,"after_address":after])}
        let metadata=[event("date-first","date_system",before:"",after:"",beforeSheet:"",afterSheet:""),event("calculation-second","calculation_settings",before:"",after:"",beforeSheet:"",afterSheet:""),event("sheet-third","sheet_name",before:"",after:""),event("merges-fourth","merges",before:"",after:"")]
        let physical=event("physical-D4"),foreign=event("foreign-sheet",beforeSheet:"not-in-old",afterSheet:"not-in-new"),typedMetadata=event("typed-metadata-with-address","date_system")
        func control(_ rows:[JSON],mode:String="changes-supported",delay:Int=0,report:JSON?=nil)throws {
            var value:[String:Any]=["mode":mode,"value":raw,"scoped_cells":true,"changes":rows.map(\.raw),"list_delay":delay]
            if let report {value["report_fixture"]=report.raw}
            try JSON(value).data().write(to:root.appendingPathComponent("control.json"),options:.atomic)
        }
        func model()async->WorkbookModel {
            let value=WorkbookModel(bridge:Bridge(resources:resources,library:root));await value.start();value.projectID="project";value.reportID="ownership-report";value.report=JSON(["project_id":"project","report_id":"ownership-report","revisions":revisions]);value.beforeID="old";value.afterID="new";value.beforeSheetID="sheet-old";value.afterSheetID="sheet-new";return value
        }
        func events()throws->[JSON] {try String(contentsOf:root.appendingPathComponent("read-events.jsonl"),encoding:.utf8).split(separator:"\n").map{JSON(try JSONSerialization.jsonObject(with:Data($0.utf8)))}}
        func listCount()throws->Int {try events().filter{$0["name"].string=="list_workbook_changes"}.count}
        func sourceReads()throws->Int {try events().filter{$0["action"].string=="workbookGrid" || $0["name"].string=="get_workbook_cell"}.count}
        func source(_ value:WorkbookModel)throws->Data {try JSON(["before":value.beforeID,"after":value.afterID,"before_sheet":value.beforeSheetID,"after_sheet":value.afterSheetID,"before_address":value.beforeAddress,"after_address":value.afterAddress,"selected_row":value.selectedRow,"selected_column":value.selectedColumn,"row_start":value.rowStart,"column_start":value.columnStart,"before_row_start":value.beforeRowStart,"before_column_start":value.beforeColumnStart,"after_row_start":value.afterRowStart,"after_column_start":value.afterColumnStart,"address_input":value.addressInput,"reveal_generation":value.revealGeneration,"before_raw":value.beforeCell.raw,"after_raw":value.afterCell.raw,"before_grid":value.beforeCells.map(\.raw),"after_grid":value.afterCells.map(\.raw),"text_offset":value.cellTextOffset,"text_next":value.cellTextNext as Any? ?? NSNull()]).data()}
        func rawCell(_ value:WorkbookModel,before:Bool,address:String)throws {
            let occurrence=before ? value.beforeID:value.afterID,sheet=before ? value.beforeSheetID:value.afterSheetID,cell=before ? value.beforeCell:value.afterCell
            try require(cell["address"].string==address && cell["value"].string.utf16.elementsEqual((raw+":"+occurrence+":"+sheet+":"+address).utf16),"InitialPhysicalExactRawMissing_"+occurrence+"_"+sheet+"_"+address)
        }
        try control(metadata+[typedMetadata,foreign,physical]);let first=await model();await first.changeVersions(before:"old",after:"new")
        try require(first.changesFailure.isEmpty && first.cellFailure.isEmpty && first.rangeFailure.isEmpty && first.selectedChangeID=="physical-D4" && first.selectedRow==4 && first.selectedColumn==4 && first.changes.map{$0["change_id"].string}==(metadata+[typedMetadata,foreign,physical]).map{$0["change_id"].string},"InitialSelectionDidNotSkipMetadataOrForeignPhysicalSheet")
        try rawCell(first,before:true,address:"D4");try rawCell(first,before:false,address:"D4");first.closeReads()
        try control(metadata);let only=await model();await only.changeVersions(before:"old",after:"new")
        try require(only.changes.count==4 && only.changesFailure.isEmpty && only.selectedChangeID.isEmpty && only.selectedRow==0 && only.beforeCell.isNull && only.afterCell.isNull,"MetadataOnlyQueryInventedInitialPhysicalSelection")
        let metadataSource=try source(only),metadataReads=try sourceReads()
        try control([physical]);await only.loadChanges()
        try require(only.changes.first?["change_id"].string=="physical-D4" && only.selectedChangeID.isEmpty && (try source(only))==metadataSource && (try sourceReads())==metadataReads,"SuccessfulMetadataOnlyQueryLeftAnAutomaticSelectionLease")
        only.closeReads()
        var oneSided:[[String:Any]]=[]
        for before in [true,false] {for address in ["D4","T150"] {
            let observed=event((before ? "before-only-":"after-only-")+address,"cell_observation",before:before ? address:"",after:before ? "":address)
            try control(metadata+[observed]);let value=await model();await value.changeVersions(before:"old",after:"new")
            let outside=address=="T150",row=outside ? 150:1,column=outside ? 20:1
            try require(value.selectedChangeID==observed["change_id"].string && value.selectedRow==(outside ? 150:4) && value.cellFailure.isEmpty && value.rangeFailure.isEmpty && (before ? value.afterCell:value.beforeCell).isNull,"OneSidedPhysicalObservationRejectedOrMissingSideInvented")
            try rawCell(value,before:before,address:address)
            try require(value.rowStart==row && value.columnStart==column && value.beforeRowStart==(before ? row:1) && value.beforeColumnStart==(before ? column:1) && value.afterRowStart==(before ? 1:row) && value.afterColumnStart==(before ? 1:column),"OneSidedInitialWindowOverwroteMissingSideOrSharedEvidenceWindow_"+address)
            let prefix = !before && outside ? L("workbook.nav.afterPrefix"):""
            try require(value.navigationRangePrefix==prefix,"OneSidedSharedRangeCaptionNamesWrongEvidenceSide_"+address)
            oneSided.append(["observed_side":before ? "before":"after","physical_address":address,"missing_side_remains_null":true,"exact_observed_utf16":true,"before_window":[value.beforeRowStart,value.beforeColumnStart],"after_window":[value.afterRowStart,value.afterColumnStart],"shared_window":[value.rowStart,value.columnStart],"shared_range_prefix":value.navigationRangePrefix,"outside_initial_window":outside]);value.closeReads()
        }}
        var missingSideOldWindows:[[String:Any]]=[]
        for before in [true,false] {
            let observed=event(before ? "before-old-window":"after-old-window","cell_observation",before:before ? "D4":"",after:before ? "":"D4",beforeSheet:before ? "sheet-old":"",afterSheet:before ? "":"sheet-new")
            try control([observed]);let value=await model();value.changes=[observed];value.changesFromID="old";value.changesToID="new"
            if before {value.afterRowStart=31;value.afterColumnStart=7}else{value.beforeRowStart=31;value.beforeColumnStart=7}
            await value.chooseChange(observed["change_id"].string,preservingVisibleWindow:true)
            try rawCell(value,before:before,address:"D4")
            try require(value.rowStart==1 && value.columnStart==1 && value.beforeRowStart==(before ? 1:31) && value.beforeColumnStart==(before ? 1:7) && value.afterRowStart==(before ? 31:1) && value.afterColumnStart==(before ? 7:1) && value.navigationRangePrefix==(before ? "":L("workbook.nav.afterPrefix")),"MissingSideFallbackLostCapturedOldWindowOrMislabeledSharedRange")
            missingSideOldWindows.append(["observed_side":before ? "before":"after","captured_missing_side_window":[31,7],"before_window":[value.beforeRowStart,value.beforeColumnStart],"after_window":[value.afterRowStart,value.afterColumnStart],"shared_window":[value.rowStart,value.columnStart],"shared_range_prefix":value.navigationRangePrefix,"scope":"explicit preservingVisibleWindow model regression with distinct captured missing-side coordinates"]);value.closeReads()
        }
        var manualObservations:[[String:Any]]=[]
        for route in ["cell","address","sheet","window"] {
            try control(metadata+[physical],delay:600);let value=await model(),initialLists=try listCount(),fixed=try value.report.data()
            let pending=Task {await value.changeVersions(before:"old",after:"new")}
            var waiting=false
            for _ in 0..<200 {
                if try listCount()>initialLists {waiting=true;break}
                try await Task.sleep(nanoseconds:5_000_000)
            }
            try require(waiting && value.loadingChanges && value.ready,"DelayedInitialQueryDidNotLeaveManualNavigationAvailable_"+route)
            try control(metadata+[physical])
            switch route {
            case "cell":await value.selectCell(7,6)
            case "address":value.addressInput="F7";await value.goToAddress()
            case "sheet":await value.changeSheet(before:"other-old",after:"other-new")
            default:await value.moveWindow(rows:100,columns:12)
            }
            if route=="cell" || route=="address" {try rawCell(value,before:true,address:"F7");try rawCell(value,before:false,address:"F7")}
            if route=="sheet" {try require(value.beforeSheetID=="other-old" && value.afterSheetID=="other-new" && value.beforeCells.first?["value"].string.utf16.elementsEqual((raw+":old:other-old:A1").utf16)==true && value.afterCells.first?["value"].string.utf16.elementsEqual((raw+":new:other-new:A1").utf16)==true,"ManualSheetDidNotLoadItsOwnExactRaw")}
            if route=="window" {try require(value.rowStart==101 && value.columnStart==13 && value.beforeCells.first?["value"].string.utf16.elementsEqual((raw+":old:sheet-old:M101").utf16)==true && value.afterCells.first?["value"].string.utf16.elementsEqual((raw+":new:sheet-new:M101").utf16)==true,"ManualWindowDidNotLoadItsOwnExactRaw")}
            let manualSource=try source(value),reads=try sourceReads();await pending.value
            try require(!value.loadingChanges && value.changesFailure.isEmpty && value.selectedChangeID.isEmpty && value.changes.map{$0["change_id"].string}==(metadata+[physical]).map{$0["change_id"].string} && value.changesFromID=="old" && value.changesToID=="new" && value.changesMode=="range_net" && (try source(value))==manualSource && (try sourceReads())==reads && (try value.report.data())==fixed,"LateInitialListOverwroteManualSourceOrWasNotInstalled_"+route)
            let retryLists=try listCount();await value.loadChanges(preserveEndpoints:true)
            try require(value.changesFailure.isEmpty && value.selectedChangeID.isEmpty && (try source(value))==manualSource && (try sourceReads())==reads && (try listCount())==retryLists+1,"DefaultRefreshReacquiredCancelledInitialIntent_"+route)
            manualObservations.append(["route":route,"initial_list_delay_ms":600,"manual_navigation_available_while_loading":true,"valid_late_list_installed":true,"fixed_query_from":"old","fixed_query_to":"new","selected_event_remains_empty":true,"physical_sources_windows_raw_and_generation_retained":true,"late_list_source_request_count":0,"refresh_does_not_reacquire_intent":true]);value.closeReads()
        }
        try control([physical],mode:"changes-fail");let failed=await model();await failed.changeVersions(before:"old",after:"new")
        try require(!failed.changesFailure.isEmpty && failed.selectedChangeID.isEmpty,"InitialFailureNotExercisedForManualRetry")
        try control([physical]);await failed.selectCell(7,6);try rawCell(failed,before:true,address:"F7");try rawCell(failed,before:false,address:"F7")
        let failedManual=try source(failed),failedReads=try sourceReads();await failed.loadChanges()
        try require(failed.changesFailure.isEmpty && failed.changes.first?["change_id"].string=="physical-D4" && failed.selectedChangeID.isEmpty && (try source(failed))==failedManual && (try sourceReads())==failedReads,"FailedInitialQueryManualBrowseDefaultRetryReacquiredIntent")
        let newPair=event("new-pair-A2",from:"mid",to:"new",before:"A2",after:"A2")
        try control([newPair]);await failed.changeVersions(before:"mid",after:"new")
        try require(failed.selectedChangeID=="new-pair-A2" && failed.changesFromID=="mid" && failed.changesToID=="new" && failed.cellFailure.isEmpty,"ExplicitNewVersionPairDidNotMintNewInitialIntent")
        try rawCell(failed,before:true,address:"A2");try rawCell(failed,before:false,address:"A2")
        let restored=event("report-restored-A2",from:"mid",to:"new",before:"A2",after:"A2"),newReport=JSON(["project_id":"project","report_id":"report-restored","revisions":revisions])
        try control([restored],report:newReport);await failed.selectReport("report-restored")
        try require(failed.reportID=="report-restored" && failed.selectedChangeID=="report-restored-A2" && failed.failure.isEmpty && failed.changesFailure.isEmpty && failed.cellFailure.isEmpty,"ExplicitNewReportDidNotMintNewInitialIntent")
        try rawCell(failed,before:true,address:"A2");try rawCell(failed,before:false,address:"A2");failed.closeReads()
        // A retry with no intervening navigation may use the original lease;
        // it never manufactures a lease from empty successful-query state.
        try control([physical],mode:"changes-fail");let untouched=await model();await untouched.changeVersions(before:"old",after:"new")
        try require(!untouched.changesFailure.isEmpty,"InitialFailureNotExercisedForUntouchedRetry")
        try control([physical]);await untouched.loadChanges()
        try require(untouched.selectedChangeID=="physical-D4" && untouched.changesFailure.isEmpty && untouched.cellFailure.isEmpty,"UntouchedRetryLostOriginalInitialIntent")
        try rawCell(untouched,before:true,address:"D4");try rawCell(untouched,before:false,address:"D4");untouched.closeReads()
        let proof:[String:Any]=["scope":"Actual Bridge with explicit production report/version ownership routes, bounded delayed list responses and controlled distinct UTF16 per revision/sheet/address; no UI disabling or packaged-runtime claim","metadata_before_physical_skipped":true,"typed_metadata_with_address_excluded":true,"foreign_sheet_membership_excluded":true,"metadata_only_stays_unlinked_and_consumes_intent":true,"one_sided_observations":oneSided,"one_sided_captured_missing_windows":missingSideOldWindows,"delayed_manual_navigation":manualObservations,"failed_initial_then_manual_default_retry_keeps_sources":true,"explicit_new_version_pair_restores_initial_link":true,"explicit_new_report_restores_initial_link":true,"untouched_retry_uses_original_intent_without_reacquisition":true,"same_query_paged_return_and_mode_suppression_covered_by_existing_regressions":true]
        try JSONSerialization.data(withJSONObject:proof,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("initial-ownership-proof.json"))
        if let path=ProcessInfo.processInfo.environment["DOCVER_TEST_WORKBOOK_INITIAL_OWNERSHIP_EVIDENCE_OUT"],!path.isEmpty {try JSONSerialization.data(withJSONObject:proof,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:path))}
        print("PASS native workbook initial ownership: metadata and sheet membership, one-sided physical observations, delayed manual navigation, failure retry and explicit version/report restoration")
    }

}
