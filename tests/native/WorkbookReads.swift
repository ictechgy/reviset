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
        model.report=JSON(["report_id":"report","revisions":[["revision_occurrence_id":"old"],["revision_occurrence_id":"new"]]])
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
        await model.chooseChange("bad")
        try require(!model.cellFailure.isEmpty && model.cellHistoryAnchor==nil && model.selectedRow==0 && model.selectedChangeID.isEmpty && !model.loadingCell,"InvalidChangeRetriedPreviousCell")
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
        model.closeReads()
        try require(model.blankFormattingWarning.isEmpty,"ClosedWindowKeptFormattingWarning")
        await model.loadSelectedCells()
        try require(!model.ready && model.beforeCell.isNull && model.afterCell.isNull && !model.loadingCell,"ClosedWindowRetriedRead")
        print("PASS native workbook reads: first/continuation/range recovery; fourteen wrong-scope/malformed responses withheld; missing observations preserved; superseded retry and closed-window guards; scoped blank-formatting warnings for empty/nonempty changes, reset/pending/error/stale/foreign response guards")
    }
    @MainActor private static func checkPagedFirstSelection(resources:URL,root:URL) async throws {
        let model=WorkbookModel(bridge:Bridge(resources:resources,library:root))
        func require(_ condition:Bool,_ message:String) throws {if !condition{throw NSError(domain:message,code:1)}}
        func event(_ id:String,from:String="old",address:String="A2")->[String:Any] {["change_id":id,"kind":"value_changed","from_revision_occurrence_id":from,"to_revision_occurrence_id":"new","from_sheet_id":"sheet-old","to_sheet_id":"sheet-new","before_address":address,"after_address":address]}
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
        await model.loadChanges()
        try require(model.changesFailure.isEmpty && model.cellFailure.isEmpty && model.selectedChangeID=="paged-first" && (try model.selectedChange.data())==(try JSON(first).data()),"FirstSuccessfulQueryDidNotChooseFirstEligibleEvent")
        try require(model.beforeCell["address"].string=="A2" && model.afterCell["address"].string=="A2" && model.beforeCell["value"].string.utf16.elementsEqual(raw.utf16) && model.afterCell["value"].string.utf16.elementsEqual(raw.utf16),"AutomaticFirstEventDidNotLoadExactLinkedRawSources")
        try require(model.rowStart==1 && model.columnStart==1 && model.beforeRowStart==1 && model.afterRowStart==1 && model.beforeColumnStart==1 && model.afterColumnStart==1 && model.beforeCells.first?["address"].string=="A2" && model.afterCells.first?["address"].string=="A2","AutomaticFirstEventRebasedAlreadyVisibleAtoLRowOneWindow")
        try require(try listCount()==queriesBefore+1,"AutomaticFirstSelectionRequeriedChangeList")
        let fixedScope=model.comparisonScope,fixedReport=try model.report.data(),initialSource=try source(),initialGeneration=model.revealGeneration,initialSourceRequests=try sourceCount()
        await model.loadChanges(next:true)
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
        // A new logical mode chooses once, on its first successful response.
        try control(mode:"changes-fail");await model.changeMode("history")
        try require(!model.changesFailure.isEmpty,"NewLogicalQueryFailureWasNotExercised")
        let historyFirst=event("history-first"),historyPages:[[Any]]=[[historyFirst],[event("history-second")]]
        try control(pages:historyPages);await model.loadChanges(preserveEndpoints:true)
        try require(model.changesMode=="history" && model.selectedChangeID=="history-first" && model.changesFailure.isEmpty && model.cellFailure.isEmpty,"FirstSuccessfulNewModeDidNotAutomaticallySelect")
        await model.selectCell(2,1);await model.loadChanges(next:true)
        try require(model.selectedChangeID.isEmpty && model.canReturnToChange,"SameModePageAutomaticallyReselectedAfterManualBrowse")
        await model.returnToChange();await model.loadChanges(previous:true);await model.selectCell(2,1)
        var mutated=model.changes[0].dictionary;mutated["after_address"]="B2";model.changes=[JSON(mutated)]
        try require(!model.canReturnToChange,"ImmutablePagedAnchorBypassedVisibleEventMutationGuard")
        await model.returnToChange();try require(model.selectedChangeID.isEmpty,"MutatedVisibleEventRestoredFromRetainedSnapshot")
        // A manually replaced list is not a qualified pagination response.
        try control();await model.changeMode("range_net");await model.selectCell(2,1);model.changes=[]
        try require(!model.canReturnToChange,"UnqualifiedManualListReplacementBorrowedPagedAnchorAuthority")
        let proof:[String:Any]=["first_success_selects_first_eligible_valid_revision_and_address":true,"first_selection_keeps_existing_row_one_A_to_L_window":true,"linked_before_after_raw_utf16_preserved":true,"same_scope_next_previous_refresh_keep_selected_off_page_event_and_source":true,"pagination_issues_only_list_reads":true,"manual_browse_retains_return_anchor_across_pages":true,"off_page_return_retains_list_cursor_and_query":true,"new_logical_mode_selects_once_after_first_success":true,"visible_mutated_event_and_unqualified_list_replacement_rejected":true,"original_stale_foreign_and_mutated_guards_preserved":true,"fixture_page_count":3,"scope":"Actual Bridge/loadChanges model regression. Manual viewport authority is physical range starts and reveal generation; actual native scrollview checks belong to mounted workspace suite." ]
        if let path=ProcessInfo.processInfo.environment["DOCVER_TEST_WORKBOOK_PAGED_SELECTION_EVIDENCE_OUT"],!path.isEmpty {try JSONSerialization.data(withJSONObject:proof,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:path))}
        try JSONSerialization.data(withJSONObject:proof,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("paged-selection-proof.json"))
        print("PASS native workbook paged selection: first eligible event, retained off-page selection/raw/window, manual browse Return, first-success mode switch and immutable source guards")
        model.closeReads()
    }
}
