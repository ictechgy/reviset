import SwiftUI
import AppKit
import PDFKit

@MainActor private enum LayoutProbeRegistry {
    static var pdfs:[String:PDFView]=[:]
    static var grids:[String:NSScrollView]=[:]
    static var coordinators:[String:AnyObject]=[:]
    static var draft:NSTextField?
}
private struct LayoutPDF:NSViewRepresentable {
    let name:String
    func makeNSView(context:Context)->PDFView {
        let view=PDFView();let document=PDFDocument()
        for _ in 0..<3 {
            let image=NSImage(size:NSSize(width:600,height:800));image.lockFocus();NSColor.white.setFill();NSBezierPath(rect:NSRect(x:0,y:0,width:600,height:800)).fill();image.unlockFocus()
            document.insert(PDFPage(image:image)!,at:document.pageCount)
        }
        view.document=document;view.displayMode = .singlePageContinuous;view.autoScales=false;view.scaleFactor=1.5
        LayoutProbeRegistry.pdfs[name]=view;return view
    }
    func updateNSView(_ view:PDFView,context:Context){}
}
private struct LayoutGrid:NSViewRepresentable {
    final class Coordinator:NSObject {}
    let name:String
    func makeCoordinator()->Coordinator {Coordinator()}
    func makeNSView(context:Context)->NSScrollView {
        let view=NSScrollView();view.hasHorizontalScroller=true;view.hasVerticalScroller=true
        view.documentView=NSView(frame:NSRect(x:0,y:0,width:5000,height:5000))
        LayoutProbeRegistry.grids[name]=view;LayoutProbeRegistry.coordinators[name]=context.coordinator
        return view
    }
    func updateNSView(_ view:NSScrollView,context:Context){}
}
private struct LayoutDraft:NSViewRepresentable {
    func makeNSView(context:Context)->NSTextField {let view=NSTextField(string:"unsaved {0} 50% 한글 العربية");LayoutProbeRegistry.draft=view;return view}
    func updateNSView(_ view:NSTextField,context:Context){}
}
private struct LayoutHarness:View {
    @ObservedObject var layout:WorkspaceLayoutStore
    var body:some View {
        WorkspacePaneSplit(name:"probe.projects",auxiliaryFirst:true,auxiliaryVisible:layout.configuration.sidebarVisible,extent:.points(layout.configuration.sidebarWidth),primaryMinimum:760,auxiliaryMinimum:180,onResize:{value in if case .points(let width)=value {layout.update{$0.sidebarWidth=min(380,max(180,width))}}}) {
            WorkspacePaneSplit(name:"probe.inspector",auxiliaryFirst:layout.configuration.inspectorDock == .left,auxiliaryVisible:layout.configuration.inspectorVisible,extent:.points(layout.configuration.inspectorWidth),primaryMinimum:500,auxiliaryMinimum:260) {
                WorkspacePaneSplit(name:"probe.changes",isVertical:layout.configuration.changesDock != .bottom,auxiliaryFirst:layout.configuration.changesDock == .left,auxiliaryVisible:layout.configuration.changesVisible,extent:.points(layout.configuration.changesDock == .bottom ? layout.configuration.changesHeight:layout.configuration.changesWidth),primaryMinimum:240,auxiliaryMinimum:layout.configuration.changesDock == .bottom ? 110:260,onResize:{value in if case .points(let size)=value {layout.update{if $0.changesDock == .bottom{$0.changesHeight=min(600,max(110,size))}else{$0.changesWidth=min(600,max(260,size))}}}}) {
                    VStack {
                        WorkspacePaneSplit(name:"probe.pages",isVertical:layout.configuration.pageArrangement == .horizontal,extent:.fraction(layout.configuration.pageFraction),primaryMinimum:100,auxiliaryMinimum:100) {LayoutPDF(name:"before")} auxiliary:{LayoutPDF(name:"after")}
                        LayoutGrid(name:"cells").frame(height:120)
                        LayoutDraft().frame(height:28)
                    }.frame(maxWidth:.infinity,maxHeight:.infinity)
                } auxiliary:{Text("Changes")}
            } auxiliary:{Text("Evidence")}
        } auxiliary:{Text("Projects")}
    }
}
@main struct NativeWorkspaceLayoutProbe:App {
    @StateObject private var layout=WorkspaceLayoutStore(scope:.document)
    var body:some Scene {
        Window("Reviset Layout Probe",id:"probe") {
            LayoutHarness(layout:layout).frame(minWidth:1100,minHeight:740).task{await LayoutChecks.run(layout)}
        }.defaultSize(width:1440,height:960)
    }
}
@MainActor private enum LayoutChecks {
    static var started=false
    static func require(_ condition:@autoclosure()->Bool,_ message:String)throws {if !condition(){throw NSError(domain:message,code:1)}}
    static func settle()async {try? await Task.sleep(nanoseconds:120_000_000);for window in NSApp.windows{window.contentView?.layoutSubtreeIfNeeded()}}
    static func controllers()->[String:NSSplitViewController] {
        var result:[String:NSSplitViewController]=[:]
        func visit(_ view:NSView) {
            if let split=view as? NSSplitView,let name=split.identifier?.rawValue,name.hasPrefix("Reviset.workspace.probe.") {
                var responder:NSResponder?=split.nextResponder
                while let candidate=responder {
                    if let controller=candidate as? NSSplitViewController,controller.splitView === split {result[name]=controller;break}
                    responder=candidate.nextResponder
                }
            }
            for child in view.subviews{visit(child)}
        }
        for window in NSApp.windows {if let view=window.contentView{visit(view)}}
        return result
    }
    static func hostingIdentities()->[String:Set<ObjectIdentifier>] {controllers().mapValues{Set($0.children.map(ObjectIdentifier.init))}}
    static func ancestors(_ view:NSView)->[ObjectIdentifier] {
        // Native split-item wrappers above the persistent hosting root belong to
        // AppKit and can change on reorder. The complete live SwiftUI host subtree
        // containing the PDF must remain the same.
        let roots=Set(controllers().values.flatMap{$0.children}.map{ObjectIdentifier($0.view)})
        var result:[ObjectIdentifier]=[];var current:NSView?=view
        while let view=current {let identity=ObjectIdentifier(view);result.append(identity);if roots.contains(identity){break};current=view.superview}
        return result
    }
    static func run(_ layout:WorkspaceLayoutStore)async {
        guard !started else{return};started=true
        do {
            await settle();await settle()
            try require(controllers().count==4,"Missing native split controllers: \(controllers().keys)")
            try require(controllers()["Reviset.workspace.probe.projects"]!.splitView.bounds.height>700,"Workspace split failed to fill its native window")
            let hosts=hostingIdentities(),pdfs=LayoutProbeRegistry.pdfs,grid=LayoutProbeRegistry.grids["cells"]!,coordinator=LayoutProbeRegistry.coordinators["cells"]!,draft=LayoutProbeRegistry.draft!
            let ancestry=pdfs.mapValues(ancestors)
            for pdf in pdfs.values {pdf.go(to:pdf.document!.page(at:1)!);pdf.scaleFactor=1.5}
            grid.contentView.scroll(to:NSPoint(x:345,y:678));grid.reflectScrolledClipView(grid.contentView)
            let origin=grid.contentView.bounds.origin,draftValue=draft.stringValue
            func assertIdentity(_ label:String)throws {
                try require(hostingIdentities()==hosts,"Hosting controller replaced: "+label)
                try require(LayoutProbeRegistry.draft === draft && draft.stringValue==draftValue,"Draft replaced or edited: "+label)
                try require(LayoutProbeRegistry.grids["cells"] === grid && LayoutProbeRegistry.coordinators["cells"] === coordinator,"Grid/coordinator replaced: "+label)
                try require(grid.contentView.bounds.origin==origin,"Manual grid viewport reset: "+label)
                for (name,pdf) in pdfs {
                    try require(LayoutProbeRegistry.pdfs[name] === pdf,"PDFView replaced: "+label)
                    try require(ancestors(pdf)==ancestry[name],"PDF ancestry replaced: "+label)
                    try require(abs(pdf.scaleFactor-1.5)<0.001,"PDF zoom reset: "+label)
                    try require(pdf.document!.index(for:pdf.currentPage!)==1,"PDF page reset: "+label)
                }
            }
            var transitions=0
            for preset in WorkspaceLayoutPreset.allCases {layout.apply(preset);await settle();try assertIdentity(preset.rawValue);transitions+=1}
            layout.apply(.balanced);await settle()
            for dock in WorkspaceChangesDock.allCases {
                for inspector in WorkspaceInspectorDock.allCases {
                    for direction in WorkspacePageArrangement.allCases {
                        layout.update{$0.changesDock=dock;$0.inspectorDock=inspector;$0.inspectorVisible=true;$0.pageArrangement=direction}
                        await settle();try assertIdentity("\(dock.rawValue)/\(inspector.rawValue)/\(direction.rawValue)");transitions+=1
                        try require(controllers()["Reviset.workspace.probe.changes"]!.splitView.isVertical == (dock != .bottom),"Changes dock orientation")
                        try require(controllers()["Reviset.workspace.probe.pages"]!.splitView.isVertical == (direction == .horizontal),"Page orientation")
                    }
                }
            }
            layout.reset();await settle()
            let changes=controllers()["Reviset.workspace.probe.changes"]!,sizing=changes as! WorkspacePaneSizing
            sizing.resizeAuxiliary(to:210,commit:true);await settle()
            try require(abs(layout.configuration.changesHeight-210)<2,"Divider choice was not saved: \(layout.configuration.changesHeight) actual \(changes.splitView.arrangedSubviews.map{ $0.frame.height })")
            layout.update{$0.changesVisible=false};await settle();layout.update{$0.changesVisible=true};await settle()
            try assertIdentity("changes collapse/reopen")
            try require(abs(changes.splitView.arrangedSubviews[1].frame.height-210)<2,"Collapsed panel forgot size")
            layout.update{$0.changesHeight=600};await settle()
            let stored=layout.configuration.changesHeight
            let window=changes.view.window!,originalFrame=window.frame
            window.setContentSize(NSSize(width:1100,height:740));await settle()
            try require(layout.configuration.changesHeight==stored,"Temporary viewport clamp overwrote preferred size")
            try require(changes.splitView.arrangedSubviews[1].frame.height<stored,"Small viewport did not clamp the large preferred pane")
            window.setFrame(originalFrame,display:true);await settle()
            try assertIdentity("window resize")
            try require(layout.saveCurrent(named:"My {0} 50% 한글"),"Named layout save")
            let saved=layout.saved[0];layout.apply(.focus);layout.apply(saved);await settle();try assertIdentity("named layout apply")
            let reopened=WorkspaceLayoutStore(scope:.document)
            try require(reopened.configuration==saved.configuration && reopened.saved==layout.saved,"Saved layout reopen")
            try require(!layout.saveCurrent(named:"my {0} 50% 한글") && !layout.saveCurrent(named:String(repeating:"a",count:81)),"Invalid or duplicate name accepted")
            for index in 1...11 {try require(layout.saveCurrent(named:"Layout \(index)"),"Bounded save unexpectedly rejected")}
            try require(layout.saved.count==12 && !layout.saveCurrent(named:"overflow"),"Saved layout cap")
            layout.remove(saved.id);try require(layout.saved.count==11,"Named layout remove")
            layout.reset();try require(layout.configuration == .preset(.balanced,scope:.document),"Reset default")
            let before=layout.configuration;layout.update{$0.sidebarWidth = .nan};layout.update{$0.changesWidth=9999};layout.update{$0.pageFraction = .infinity}
            try require(layout.configuration==before,"Nonfinite or out of range mutation accepted")
            let envelope=WorkspaceLayoutPreferences.data(.document)!,raw=try JSONSerialization.jsonObject(with:envelope) as! [String:Any]
            var corrupt=raw;var current=raw["current"] as! [String:Any];current["changesDock"]="floating";corrupt["current"]=current
            WorkspaceLayoutPreferences.save(try JSONSerialization.data(withJSONObject:corrupt),scope:.document)
            try require(WorkspaceLayoutStore(scope:.document).configuration == .preset(.balanced,scope:.document),"Unknown enum fallback")
            current["changesDock"]="bottom";current["sidebarWidth"]=99999;corrupt["current"]=current
            WorkspaceLayoutPreferences.save(try JSONSerialization.data(withJSONObject:corrupt),scope:.document)
            try require(WorkspaceLayoutStore(scope:.document).configuration == .preset(.balanced,scope:.document),"Out of range stored geometry fallback")
            WorkspaceLayoutPreferences.save(Data("{broken".utf8),scope:.document)
            try require(WorkspaceLayoutStore(scope:.document).configuration == .preset(.balanced,scope:.document),"Malformed JSON fallback")
            var future=raw;future["schemaVersion"]=99;let futureData=try JSONSerialization.data(withJSONObject:future)
            WorkspaceLayoutPreferences.save(futureData,scope:.document)
            let oldApp=WorkspaceLayoutStore(scope:.document);oldApp.apply(.focus);_ = oldApp.saveCurrent(named:"session")
            try require(oldApp.persistenceReadOnly && WorkspaceLayoutPreferences.data(.document)==futureData,"Future schema overwritten")
            let book=WorkspaceLayoutStore(scope:.workbook);book.apply(.review)
            try require(WorkspaceLayoutPreferences.data(.document)==futureData && book.configuration.inspectorVisible,"Workspace preferences crossed scopes")
            print("PASS native customizable layouts: \(transitions) transitions, persistent hosts/PDF ancestry/grid coordinator/draft/page/zoom/manual viewport, divider/reopen/clamp, named presets/schema/corrupt preferences/test isolation")
            fflush(stdout);NSApp.terminate(nil)
        }catch{fputs("Native layout failed: \(error)\n",stderr);exit(1)}
    }
}
