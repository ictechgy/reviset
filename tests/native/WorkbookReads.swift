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
        await model.chooseChange("good")
        try require(model.addressFailure.isEmpty && model.cellFailure.isEmpty && model.beforeAddress=="A2" && model.afterAddress=="A2","ChangeSelectionKeptInvalidAddressError")
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
        model.closeReads()
        await model.loadSelectedCells()
        try require(!model.ready && model.beforeCell.isNull && model.afterCell.isNull && !model.loadingCell,"ClosedWindowRetriedRead")
        print("PASS native workbook reads: first/continuation/range recovery; fourteen wrong-scope/malformed responses withheld; missing observations preserved; superseded retry and closed-window guards")
    }
}
