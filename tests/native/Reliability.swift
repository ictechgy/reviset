import Foundation
import AppKit

@MainActor enum Smoke {
    static func captureView(_ window:NSWindow,_ url:URL) throws { throw NSError(domain:"UnexpectedScreenshot",code:1) }
}
@MainActor final class ReusedReliabilityTable:NSTableView {
    var reused:NSView?
    override func makeView(withIdentifier identifier:NSUserInterfaceItemIdentifier,owner:Any?) -> NSView? { reused }
}

@main struct ReliabilityProbe {
    @MainActor static func main() async throws {
        configureLegacyNativeLocalization()
        let model=AppModel(),root=model.bridge.library
        func require(_ condition:Bool,_ message:String) throws { if !condition { throw NSError(domain:message,code:1) } }
        func control(_ mode:String,_ extra:[String:Any]=[:]) throws {
            var value=extra;value["mode"]=mode
            try JSON(value).data().write(to:root.appendingPathComponent("control.json"),options:.atomic)
        }
        func events()->[JSON] {
            ((try? String(contentsOf:root.appendingPathComponent("reliability-events.jsonl"),encoding:.utf8)) ?? "").split(separator:"\n").compactMap { try? JSONSerialization.jsonObject(with:Data($0.utf8)) }.map(JSON.init)
        }
        func waitFor(_ mode:String,_ action:String) async throws {
            for _ in 0..<200 {
                if events().contains(where:{$0["mode"].string==mode && $0["action"].string==action}) { return }
                try await Task.sleep(nanoseconds:5_000_000)
            }
            throw NSError(domain:"RequestDidNotStart-"+mode+"-"+action,code:1)
        }
        for (code,expected) in [("FILE_LIMIT","파일당 512 MiB 이하를 지원합니다."),("INPUT_NOT_REGULAR","일반 파일만 가져올 수 있습니다. 링크·폴더·특수 파일은 지원하지 않습니다."),("OTHER_FAILURE","original diagnostic")] {
            let error=BridgeError(code:code,message:"original diagnostic")
            let rendered=bridgeErrorMessage(error).text
            try require(error.localizedDescription=="original diagnostic" && error.code==code && error.message=="original diagnostic","NativeErrorLostRawCodeOrMessage-"+code)
            try require(code=="OTHER_FAILURE" ? rendered.contains(code) && rendered.contains(expected) : rendered==expected,"NativeErrorLocalizationLostCodeOrMessage-"+code)
        }
        try require(JSON(1.9).int==1 && JSON(-1.9).int == -1,"IntegerTruncationChanged")
        for value in [Double.infinity,-Double.infinity,Double.nan,1e300,-1e300,Double(Int.max)] {
            try require(JSON(value).int==0,"UnrepresentableNumberDidNotFallBack")
        }
        try control("startup");await model.start()
        try require(!model.initializing && model.error.isEmpty && !model.documentRecoveryWarning.isEmpty && model.report["report_id"].string=="retained","StartupCleanupPreventedReadingReport")
        model.from=0;model.to=1;model.leftPageID="page_a1";model.rightPageID="page_b1"
        try await model.updateChanges();model.to=2;try await model.updateChanges();model.from=1;try await model.updateChanges()
        try require(model.leftPageID=="page_b1" && model.rightPageID=="page_c1","EmptyIntervalRetainedOtherRevisionPages")
        model.navigatePage("page_b2",in:"occ_b");try await model.updateChanges()
        try require(model.leftPageID=="page_b2","EmptyIntervalOverwroteValidNavigationPin")
        model.changes=[JSON(["change_id":"before-only","evidence":[["revision_occurrence_id":"occ_b","page_id":"page_b1"]]])]
        model.chooseChange("before-only")
        try require(model.leftPageID=="page_b1" && model.rightPageID.isEmpty,"SelectedChangeLostIntentionalAbsentSide")
        model.openHistoryPage(2,"page_c2")
        for _ in 0..<100 { if !model.loadingChanges { break };try await Task.sleep(nanoseconds:2_000_000) }
        try require(model.rightPageID=="page_c2" && model.leftPageID.isEmpty,"HistoryPinLostIntentionalAbsentCounterpart")
        // Let the history range task settle before starting writer scenarios.
        try await model.updateChanges()

        for scenario in ["cleanup","normal","lost-success","partial","lost-cleanup","noncommitted","unknown","wrong-scope","owned-failure","unowned-failure"] {
            try control(scenario);await model.selectProject("project",snapshot:"retained")
            model.documentRecoveryWarning=""
            await model.run("project")
            try require(!model.busy && !model.committing,"RunDidNotSettle-"+scenario)
            let saved=["cleanup","normal","lost-success","partial","lost-cleanup"].contains(scenario)
            try require(model.report["report_id"].string==(saved ? "saved_"+scenario:"retained"),"WrongReportAfterRun-"+scenario)
            let calls=events().filter{$0["mode"].string==scenario}
            if saved { try require(model.error.isEmpty,"SavedRunPresentedAsFailure-"+scenario) }
            if scenario=="cleanup" || scenario=="lost-cleanup" { try require(!model.documentRecoveryWarning.isEmpty,"CleanupWarningMissing-"+scenario) }
            if scenario=="unknown" || scenario=="wrong-scope" {
                try require(model.status.contains("저장 여부 확인 필요") && !model.documentRecoveryWarning.isEmpty,"UnknownCommitReportedFailed-"+scenario)
                try require(!calls.contains(where:{$0["action"].string=="recover"}),"UnknownCommitWasDiscarded-"+scenario)
            }
            if scenario=="noncommitted" || scenario=="owned-failure" {
                try require(calls.contains(where:{$0["action"].string=="recover" && $0["args"]["run_id"].string=="run_"+scenario}),"OwnRunNotRecovered-"+scenario)
            }
            if scenario=="unowned-failure" { try require(!calls.contains(where:{$0["action"].string=="recover"}),"FailureSweptUnownedRuns") }
            try require(!calls.contains(where:{$0["action"].string=="recover" && $0["args"]["run_id"].string.isEmpty}),"BroadRecoveryDuringRun-"+scenario)
            try require(model.reports.contains(where:{$0["report_id"].string=="saved_"+scenario}),"ReportListNotRefreshed-"+scenario)
        }

        for outcome in ["cleanup","unknown"] {
            let mode="superseded-"+outcome
            try control(mode);await model.selectProject("project",snapshot:"retained");model.documentRecoveryWarning=""
            let running=Task { await model.run("project") }
            try await waitFor(mode,"commit")
            let created=try await model.create(title:"open import sheet",rows:[ImportRow(label:"input",urls:[URL(fileURLWithPath:"/synthetic.pdf")])])
            model.report=JSON();try await model.refresh();model.projectID=created["project_id"].string
            await model.run(model.projectID);await running.value
            try require(!model.documentRecoveryWarning.isEmpty,"SupersededRunLostLibraryWarning-"+outcome)
            try require(model.projectID==created["project_id"].string && model.report.isNull && !model.busy,"SupersededRunReopenedPriorSelection-"+outcome)
        }

        let workbook=WorkbookModel(bridge:model.bridge)
        try control("workbook");await workbook.start();await workbook.selectProject("workbook-project")
        let rows=[WorkbookImportRow(label:"input",url:URL(fileURLWithPath:"/changed.xlsx"),identity:ImportFileIdentity(sha256:String(repeating:"a",count:64),bytes:1))]
        func failedCreate() async throws {
            do { try await workbook.create(title:"failing input",rows:rows);throw NSError(domain:"ExpectedImportFailure",code:1) }
            catch let error as BridgeError { try require(error.code=="SOURCE_CHANGED","UnexpectedImportFailure") }
        }
        for channel in ["range","cell","changes","history","reports","view"] {
            try control("prepare-"+channel);await workbook.selectProject("workbook-project")
            await workbook.selectCell(2,1)
            let action=channel=="range" ? "workbookGrid":channel=="reports" ? "workbookReports":channel=="view" ? "workbookView":"workbookQuery"
            let query=channel=="cell" ? "get_workbook_cell":channel=="changes" ? "list_workbook_changes":"get_workbook_cell_history"
            try control("pending-"+channel,action=="workbookQuery" ? ["delayQuery":query]:["delayAction":action])
            let pending=Task {
                switch channel {
                case "range":await workbook.loadRange()
                case "cell":await workbook.loadSelectedCells()
                case "changes":await workbook.loadChanges()
                case "history":await workbook.loadCellHistory()
                case "reports":await workbook.selectProject("workbook-project")
                default:await workbook.selectReport("workbook-report")
                }
            }
            try await waitFor("pending-"+channel,action);try await failedCreate();await pending.value
            try require(workbook.ready && !workbook.loadingReport && !workbook.loadingRange && !workbook.loadingCell && !workbook.loadingChanges && !workbook.loadingHistory,"FailedImportLeftLoading-"+channel)
            try require(!workbook.beforeCells.isEmpty && !workbook.afterCells.isEmpty && workbook.rangeFailure.isEmpty,"FailedImportLeftUnreadRange-"+channel)
            if channel=="cell" { try require(workbook.beforeCell["value"].string=="restored" && workbook.afterCell["value"].string=="restored","FailedImportLostCellRetry") }
            if channel=="history" { try require(!workbook.cellHistory.isEmpty && workbook.cellHistoryFailure.isEmpty,"FailedImportLostHistoryRetry") }
            if channel=="changes" { try require(!workbook.changes.isEmpty && workbook.changesFailure.isEmpty,"FailedImportLostChangesRetry") }
        }
        try control("superseded-range",["delayAction":"workbookGrid"])
        let oldRange=Task { await workbook.loadRange() }
        try await waitFor("superseded-range","workbookGrid")
        try control("superseded-create",["createDelay":150])
        let supersededCreate=Task { try await failedCreate() }
        try await waitFor("superseded-create","workbookCreate")
        try control("restoration",["delayAction":"workbookGrid"])
        try await waitFor("restoration","workbookGrid")
        try control("new-selection");await workbook.selectProject("other-project",snapshot:"other-report")
        try await supersededCreate.value;await oldRange.value
        try require(workbook.ready && workbook.projectID=="other-project" && workbook.reportID=="other-report" && workbook.beforeCells.first?["value"].string=="new-selection","ImportRestorationOverwroteNewSelection")
        // Closing the window invalidates the import's completion ticket even
        // though its project/report strings remain on the retained model.
        try control("close-create",["createDelay":200])
        let closing=Task { try await failedCreate() }
        try await waitFor("close-create","workbookCreate");workbook.closeReads()
        let afterClose=events().count;try await closing.value
        try require(!workbook.ready && !workbook.loadingReport && !workbook.busy && events().count==afterClose,"ClosedWindowRestartedReadsAfterFailedCreate")

        _ = NSApplication.shared;NSApp.setActivationPolicy(.prohibited)
        let grid=WorkbookGrid(language:LanguagePreferences.shared.effectiveLanguage,pane:"before",revealIntent:"probe",cells:[],rowStart:1,columnStart:1,rowCount:100,columnCount:12,selectedRow:0,selectedColumn:0,onSelect:{_,_ in})
        let coordinator=grid.makeCoordinator(),table=ReusedReliabilityTable()
        coordinator.sparse=["7:2":JSON(["row":7,"column":2,"value":"other data"])]
        let dataColumn=NSTableColumn(identifier:NSUserInterfaceItemIdentifier("2")),rowColumn=NSTableColumn(identifier:NSUserInterfaceItemIdentifier("row"))
        let cell=coordinator.tableView(table,viewFor:dataColumn,row:6) as! NSTableCellView
        try require(cell.textField?.accessibilityLabel()?.contains("B7")==true,"DataAccessibilityFixtureInvalid")
        table.reused=cell
        let rowCell=coordinator.tableView(table,viewFor:rowColumn,row:8) as! NSTableCellView
        try require(rowCell.textField?.stringValue=="9" && rowCell.textField?.accessibilityLabel()=="9행" && rowCell.toolTip==nil,"ReusedRowAnnouncesPriorDataCell")
        print("PASS native reliability: integer bounds; empty interval membership and explicit pins; cleanup-tolerant startup; exact-run commit reconciliation; six interrupted import read channels; new-selection and closed-window ownership; reused row accessibility")
    }
}
