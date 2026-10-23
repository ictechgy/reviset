import Foundation
import AppKit
import Darwin

@MainActor enum Smoke {
    static func captureView(_ window:NSWindow,_ url:URL) throws { throw NSError(domain:"UnexpectedCapture",code:1) }
}
@MainActor final class ClickedTable:NSTableView {
    var simulatedClickedRow = -1
    var simulatedClickedColumn = -1
    var simulatedSelectedRow = -1
    var simulatedSelectedColumn = -1
    override var clickedRow:Int { simulatedClickedRow }
    override var clickedColumn:Int { simulatedClickedColumn }
    override var selectedRow:Int { simulatedSelectedRow }
    override var selectedColumn:Int { simulatedSelectedColumn }
}
@main struct WorkbookRowHeaderProbe {
    @MainActor static func main() {
        configureLegacyNativeLocalization()
        do { try check();print("PASS actual WorkbookGrid.Coordinator clicked: row headers retain/clamp physical column; data cells, keyboard, bounds, duplicate and update suppression") }
        catch { print("FAIL",error.localizedDescription);Darwin.exit(1) }
    }
    @MainActor static func check() throws {
        _ = NSApplication.shared;NSApp.setActivationPolicy(.prohibited)
        func require(_ condition:Bool,_ message:String) throws { if !condition { throw NSError(domain:"RowHeader",code:1,userInfo:[NSLocalizedDescriptionKey:message]) } }
        func table() -> ClickedTable {
            let value=ClickedTable();for name in ["row","10","11","12","13","14"] { value.addTableColumn(NSTableColumn(identifier:NSUserInterfaceItemIdentifier(name))) };return value
        }
        var selections:[[Int]]=[]
        func grid(_ selectedColumn:Int)->WorkbookGrid { WorkbookGrid(language:LanguagePreferences.shared.effectiveLanguage,pane:"before",revealIntent:"test",cells:[],rowStart:101,columnStart:10,rowCount:6,columnCount:5,selectedRow:101,selectedColumn:selectedColumn,onSelect:{selections.append([$0,$1])}) }
        let coordinator=grid(13).makeCoordinator(),view=table()
        view.simulatedClickedRow=2;view.simulatedClickedColumn=0;coordinator.clicked(view)
        print("row_header_action",selections)
        try require(selections==[[103,13]],"row-header click did not route clicked physical row at current physical column")
        coordinator.clicked(view);try require(selections.count==1,"row-header duplicate request escaped suppression")
        view.simulatedClickedRow=1;view.simulatedClickedColumn=2;coordinator.clicked(view)
        try require(selections.last==[102,11],"data-cell click changed column interpretation")
        let count=selections.count
        for (row,column) in [(-1,0),(6,0),(1,-1),(1,6)] { view.simulatedClickedRow=row;view.simulatedClickedColumn=column;coordinator.clicked(view) }
        try require(selections.count==count,"out-of-range click reached model")
        view.tableColumns[2].identifier=NSUserInterfaceItemIdentifier("not-a-column");view.simulatedClickedRow=3;view.simulatedClickedColumn=2;coordinator.clicked(view)
        try require(selections.count==count,"nonnumeric data column reached model")
        view.tableColumns[2].identifier=NSUserInterfaceItemIdentifier("11")
        coordinator.updating=true;view.simulatedClickedRow=3;view.simulatedClickedColumn=0;coordinator.clicked(view);coordinator.updating=false
        try require(selections.count==count,"programmatic grid update produced click request")
        view.simulatedSelectedRow=4;view.simulatedSelectedColumn=3
        coordinator.tableViewSelectionDidChange(Notification(name:NSTableView.selectionDidChangeNotification,object:view))
        try require(selections.last==[105,12],"keyboard selection behavior changed")
        view.simulatedSelectedRow=5;view.simulatedSelectedColumn=0
        coordinator.tableViewSelectionDidChange(Notification(name:NSTableView.selectionDidChangeNotification,object:view))
        try require(selections.last==[106,13],"keyboard current-column fallback changed")
        for (current,expected) in [(0,10),(99,14)] {
            let clamp=grid(current).makeCoordinator(),clampTable=table()
            clampTable.simulatedClickedRow=0;clampTable.simulatedClickedColumn=0;clamp.clicked(clampTable)
            try require(selections.last==[101,expected],"row-header physical column was not clamped to non-first viewport")
        }
        print("recorded_physical_selections",selections)
    }
}
