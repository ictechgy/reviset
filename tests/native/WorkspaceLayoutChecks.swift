import SwiftUI
import AppKit
import PDFKit
import Combine

@MainActor private enum LayoutProbeRegistry {
    static var pdfs:[String:PDFView]=[:]
    static var grids:[String:NSScrollView]=[:]
    static var coordinators:[String:AnyObject]=[:]
    static var draft:NSTextField?
    static var buttons:[String:NSButton]=[:]
}
@MainActor private final class LayoutEnvironment:ObservableObject {
    @Published var enabled=true
    @Published var locale=Locale(identifier:"en_GB")
}
private struct LayoutButton:NSViewRepresentable {
    let name:String
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.locale) private var locale
    func makeNSView(context:Context)->NSButton {let button=NSButton(title:name,target:nil,action:nil);LayoutProbeRegistry.buttons[name]=button;return button}
    func updateNSView(_ view:NSButton,context:Context) {view.isEnabled=isEnabled;view.title=locale.identifier}
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
    @ObservedObject var environment:LayoutEnvironment
    var body:some View {
        WorkspacePaneSplit(name:"probe.projects",auxiliaryFirst:true,auxiliaryVisible:layout.configuration.sidebarVisible,extent:.points(layout.configuration.sidebarWidth),primaryMinimum:760,auxiliaryMinimum:180,onResize:{value in if case .points(let width)=value {layout.update{$0.sidebarWidth=min(380,max(180,width))}}}) {
            WorkspacePaneSplit(name:"probe.inspector",auxiliaryFirst:layout.configuration.inspectorDock == .left,auxiliaryVisible:layout.configuration.inspectorVisible,extent:.points(layout.configuration.inspectorWidth),primaryMinimum:500,auxiliaryMinimum:260) {
                WorkspacePaneSplit(name:"probe.changes",isVertical:layout.configuration.changesDock != .bottom,auxiliaryFirst:layout.configuration.changesDock == .left,auxiliaryVisible:layout.configuration.changesVisible,extent:.points(layout.configuration.changesDock == .bottom ? layout.configuration.changesHeight:layout.configuration.changesWidth),primaryMinimum:240,auxiliaryMinimum:layout.configuration.changesDock == .bottom ? 110:260,onResize:{value in if case .points(let size)=value {layout.update{if $0.changesDock == .bottom{$0.changesHeight=min(600,max(110,size))}else{$0.changesWidth=min(600,max(260,size))}}}}) {
                    VStack {
                        WorkspacePaneSplit(name:"probe.pages",isVertical:layout.configuration.pageArrangement == .horizontal,extent:.fraction(layout.configuration.pageFraction),primaryMinimum:100,auxiliaryMinimum:100) {LayoutPDF(name:"before")} auxiliary:{LayoutPDF(name:"after")}
                        LayoutGrid(name:"cells").frame(height:120)
                        LayoutDraft().frame(height:28)
                        LayoutButton(name:"nested").frame(height:24)
                    }.frame(maxWidth:.infinity,maxHeight:.infinity)
                } auxiliary:{Text("Changes")}
            } auxiliary:{Text("Evidence")}
        } auxiliary:{VStack{Text("Projects");LayoutButton(name:"sidebar")}}
        .disabled(!environment.enabled).environment(\.locale,environment.locale)
    }
}
@main struct NativeWorkspaceLayoutProbe:App {
    @StateObject private var layout=WorkspaceLayoutStore(scope:.document)
    @StateObject private var environment=LayoutEnvironment()
    var body:some Scene {
        Window("Reviset Layout Probe",id:"probe") {
            LayoutHarness(layout:layout,environment:environment).frame(minWidth:1100,minHeight:740).task{await LayoutChecks.run(layout,environment:environment)}
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
    static func run(_ layout:WorkspaceLayoutStore,environment:LayoutEnvironment)async {
        guard !started else{return};started=true
        do {
            await settle();await settle()
            if let window=NSApp.windows.first(where:{$0.isVisible}) {window.setContentSize(NSSize(width:1440,height:960))}
            await settle()
            try require(controllers().count==4,"Missing native split controllers: \(controllers().keys)")
            try require(controllers()["Reviset.workspace.probe.projects"]!.splitView.bounds.height>700,"Workspace split failed to fill its native window")
            var namedSplitters=0
            for (name,controller) in controllers() {
                let split=controller.splitView
                try require(!(split.accessibilityLabel() ?? "").isEmpty,"Unnamed split group: \(name)")
                let dividers=(split.accessibilityChildren() ?? []).compactMap{$0 as? NSAccessibilityProtocol}.filter{$0.accessibilityRole() == .splitter}
                for divider in dividers {
                    try require(divider.accessibilityLabel()==split.accessibilityLabel(),"Unnamed/contextless native drag splitter: \(name)")
                    namedSplitters+=1
                }
            }
            try require(namedSplitters>=3,"Visible native splitters were not exposed with names: \(namedSplitters)")
            let hosts=hostingIdentities(),pdfs=LayoutProbeRegistry.pdfs,grid=LayoutProbeRegistry.grids["cells"]!,coordinator=LayoutProbeRegistry.coordinators["cells"]!,draft=LayoutProbeRegistry.draft!
            try require(LayoutProbeRegistry.buttons.count==2 && LayoutProbeRegistry.buttons.values.allSatisfy{$0.isEnabled && $0.title=="en_GB"},"Initial hosted button environment lost")
            environment.enabled=false;environment.locale=Locale(identifier:"ko_KR");await settle()
            try require(LayoutProbeRegistry.buttons.values.allSatisfy{!$0.isEnabled && $0.title=="ko_KR"},"Outer disabled/locale environment did not cross every hosting boundary")
            environment.enabled=true;environment.locale=Locale(identifier:"en_GB");await settle()
            try require(LayoutProbeRegistry.buttons.values.allSatisfy{$0.isEnabled && $0.title=="en_GB"},"Hosted environment did not refresh after unlocking/locale update")
            try require(hostingIdentities()==hosts,"Environment propagation replaced native hosting controllers")
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
                        let changeSplit=controllers()["Reviset.workspace.probe.changes"]!.splitView
                        let auxiliary=changeSplit.arrangedSubviews[dock == .left ? 0:1],primary=changeSplit.arrangedSubviews[dock == .left ? 1:0]
                        let available=(dock == .bottom ? changeSplit.bounds.height:changeSplit.bounds.width)-changeSplit.dividerThickness
                        let minimum:CGFloat=dock == .bottom ? 110:260
                        let requested:CGFloat=dock == .bottom ? CGFloat(layout.configuration.changesHeight):CGFloat(layout.configuration.changesWidth)
                        let expected=min(max(minimum,requested),max(minimum,available-240))
                        let actual=dock == .bottom ? auxiliary.frame.height:auxiliary.frame.width
                        let sourceExtent=dock == .bottom ? primary.frame.height:primary.frame.width
                        try require(abs(actual-expected)<2,"Dock extent \(dock.rawValue)/\(inspector.rawValue)/\(direction.rawValue): actual \(actual), expected \(expected), source \(sourceExtent), available \(available)")
                        try require(sourceExtent>=239,"Docking hid the source canvas: \(sourceExtent)")
                    }
                }
            }
            layout.update{$0.sidebarVisible=true;$0.sidebarWidth=279;$0.inspectorVisible=true;$0.inspectorDock = .left;$0.inspectorWidth=341;$0.changesVisible=true;$0.changesDock = .right;$0.changesWidth=389;$0.changesHeight=233;$0.pageArrangement = .vertical;$0.pageFraction=0.37}
            await settle()
            let custom=layout.configuration,customBytes=WorkspaceLayoutPreferences.data(.document)
            layout.toggleFocus();await settle();try assertIdentity("temporary focus")
            try require(layout.isFocused && layout.configuration.changesDock==custom.changesDock && layout.configuration.pageFraction==custom.pageFraction,"Focus did not retain custom geometry")
            layout.toggleFocus();await settle();try assertIdentity("restored custom focus")
            try require(layout.configuration==custom && WorkspaceLayoutPreferences.data(.document)==customBytes,"Focus toggle lost custom layout or rewrote persisted bytes")
            for scoped in [layout,WorkspaceLayoutStore(scope:.workbook)] {
                scoped.update{$0=custom};scoped.toggleFocus()
                var edits=0
                scoped.update{edits+=1;$0.pageFraction=0.63;$0.pageArrangement = .horizontal;$0.sidebarWidth=301;$0.changesDock = .left;$0.changesWidth=417;$0.inspectorWidth=355}
                var merged=custom;merged.pageFraction=0.63;merged.pageArrangement = .horizontal;merged.sidebarWidth=301;merged.changesDock = .left;merged.changesWidth=417;merged.inspectorWidth=355
                await settle();try assertIdentity("\(scoped.scope.rawValue) focused geometry edit")
                try require(edits==1 && scoped.isFocused,"A focused geometry edit ran twice or cancelled Focus")
                let duringFocus=WorkspaceLayoutStore(scope:scoped.scope),mergedBytes=WorkspaceLayoutPreferences.data(scoped.scope)
                try require(!duringFocus.isFocused && duringFocus.configuration==merged,"Focused geometry persisted hidden panel state or lost the retained arrangement")
                scoped.toggleFocus();await settle();try assertIdentity("\(scoped.scope.rawValue) edited Focus restored")
                try require(!scoped.isFocused && scoped.configuration==merged && WorkspaceLayoutPreferences.data(scoped.scope)==mergedBytes,"Focus exit lost merged geometry or rewrote stored bytes")
                scoped.toggleFocus();scoped.update{$0.pageFraction=0.59;$0.changesHeight=245}
                var savedExpected=merged;savedExpected.pageFraction=0.59;savedExpected.changesHeight=245
                try require(scoped.saveCurrent(named:"Saved during Focus"),"Focused named layout save failed")
                let focusedSaved=scoped.saved.last!,savedReopened=WorkspaceLayoutStore(scope:scoped.scope)
                try require(scoped.isFocused && focusedSaved.configuration==savedExpected,"Saving during Focus saved transient hidden flags or left Focus")
                try require(!savedReopened.isFocused && savedReopened.configuration==savedExpected && savedReopened.saved.contains(focusedSaved),"Focused named layout or its retained current arrangement did not survive reload")
                scoped.apply(.balanced);scoped.apply(.focus);scoped.apply(focusedSaved);await settle();try assertIdentity("\(scoped.scope.rawValue) saved Focus reapplied")
                try require(!scoped.isFocused && scoped.configuration==savedExpected && WorkspaceLayoutStore(scope:scoped.scope).configuration==savedExpected,"Reapplying a layout saved during Focus lost its retained panel visibility or adjusted geometry")
                scoped.remove(focusedSaved.id)
                let panels:[(String,WritableKeyPath<WorkspaceLayoutConfiguration,Bool>)]=[("projects",\.sidebarVisible),("changes",\.changesVisible),("evidence",\.inspectorVisible)]
                for visibility in 0...2 {
                    var baseline=custom
                    if visibility==1 {baseline.sidebarVisible=false;baseline.changesVisible=true;baseline.inspectorVisible=false}
                    if visibility==2 {baseline.sidebarVisible=false;baseline.changesVisible=false;baseline.inspectorVisible=false}
                    for (name,panel) in panels {
                        scoped.update{$0=baseline};scoped.toggleFocus()
                        scoped.update{$0.sidebarVisible=false;$0.inspectorVisible=false;$0.changesVisible=false}
                        try require(scoped.isFocused,"No-op hidden-panel synchronization left Focus")
                        scoped.update{$0.pageFraction=0.57;$0.changesDock = .left;$0.sidebarWidth=301}
                        edits=0;scoped.update{edits+=1;$0[keyPath:panel].toggle();$0.inspectorWidth=355}
                        var expected=baseline;expected[keyPath:panel]=true;expected.pageFraction=0.57;expected.changesDock = .left;expected.sidebarWidth=301;expected.inspectorWidth=355
                        await settle();try assertIdentity("\(scoped.scope.rawValue) Focus opens \(name)/\(visibility)")
                        try require(edits==1 && !scoped.isFocused && scoped.configuration==expected,"Opening \(name) from Focus lost unrelated retained visibility/geometry or evaluated the edit twice")
                        let reopened=WorkspaceLayoutStore(scope:scoped.scope),bytes=WorkspaceLayoutPreferences.data(scoped.scope)
                        try require(!reopened.isFocused && reopened.configuration==expected,"Focus visibility exit persisted unrelated transient hidden panels")
                        scoped.toggleFocus();scoped.toggleFocus()
                        try require(scoped.configuration==expected && WorkspaceLayoutPreferences.data(scoped.scope)==bytes,"Focus after a visibility exit lost the merged baseline or rewrote unchanged bytes")
                    }
                }
            }
            layout.update{$0=custom};await settle()
            layout.update{$0.sidebarVisible=false};try require(!layout.isFocused,"Hiding projects incorrectly enabled focus")
            layout.update{$0.inspectorVisible=false};layout.update{$0.changesVisible=false};await settle()
            let manuallyHidden=layout.configuration,hiddenBytes=WorkspaceLayoutPreferences.data(.document)
            try require(!layout.isFocused,"Manually hiding every panel incorrectly enabled Focus")
            let hiddenReopened=WorkspaceLayoutStore(scope:.document)
            try require(!hiddenReopened.isFocused && hiddenReopened.configuration==manuallyHidden,"Reloading an all-hidden layout incorrectly enabled Focus")
            var focusSignals:[Bool]=[]
            let focusSubscription=layout.$isFocused.dropFirst().sink{focusSignals.append($0)}
            for cycle in 1...2 {
                layout.toggleFocus();await settle();try assertIdentity("all-hidden Focus on \(cycle)")
                try require(layout.isFocused && layout.configuration==manuallyHidden,"Focus did not activate when the panel geometry was already all-hidden")
                layout.update{$0.sidebarVisible=false};layout.update{$0.inspectorVisible=false};layout.update{$0.changesVisible=false}
                layout.apply(.focus)
                try require(layout.isFocused,"No-op panel synchronization or reapplying Focus cancelled the active session")
                layout.toggleFocus();await settle();try assertIdentity("all-hidden Focus restored \(cycle)")
                try require(!layout.isFocused && layout.configuration==manuallyHidden && WorkspaceLayoutPreferences.data(.document)==hiddenBytes,"All-hidden Focus exit lost custom docks/dimensions or rewrote persisted bytes")
            }
            try require(focusSignals==[true,false,true,false],"Equal-geometry Focus changes were not independently published: \(focusSignals)")
            withExtendedLifetime(focusSubscription){}
            try require(layout.saveCurrent(named:"Temporary all-hidden"),"All-hidden saved-layout setup")
            let hiddenSaved=layout.saved.last!
            layout.apply(.focus);layout.apply(hiddenSaved);await settle()
            try require(!layout.isFocused && layout.configuration==manuallyHidden,"Applying an equal-geometry saved layout did not leave Focus")
            let savedHiddenReopened=WorkspaceLayoutStore(scope:.document)
            try require(!savedHiddenReopened.isFocused && savedHiddenReopened.configuration==manuallyHidden,"Saved all-hidden layout reopened as Focus")
            layout.remove(hiddenSaved.id)
            layout.apply(.review);try require(!layout.isFocused,"Review incorrectly enabled focus")
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
            try require(abs(changes.splitView.arrangedSubviews[1].frame.height-stored)<2,"Preferred size was not restored after the window grew")
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
            current["changesDock"]="left";current["pageFraction"]=0.37;current["sidebarWidth"]=true;corrupt["current"]=current
            var entries=raw["saved"] as! [[String:Any]],first=entries[0],savedConfiguration=first["configuration"] as! [String:Any]
            savedConfiguration["inspectorWidth"]=99999;first["configuration"]=savedConfiguration;entries[0]=first
            entries.insert(["name":"malformed entry","configuration":[:]],at:0);corrupt["saved"]=entries
            WorkspaceLayoutPreferences.save(try JSONSerialization.data(withJSONObject:corrupt),scope:.document)
            let recovered=WorkspaceLayoutStore(scope:.document)
            try require(recovered.configuration.sidebarWidth==220 && recovered.configuration.changesDock == .left && recovered.configuration.pageFraction==0.37,"Per-field recovery discarded valid current geometry or accepted a Boolean dimension")
            try require(recovered.saved.map(\.id)==layout.saved.map(\.id) && recovered.saved.map(\.name)==layout.saved.map(\.name),"One malformed current/saved field discarded unrelated named layouts")
            try require(recovered.saved[0].configuration.inspectorWidth==300,"Corrupt saved geometry was not recovered per field")
            recovered.update{$0.sidebarVisible.toggle()}
            let recoveredAgain=WorkspaceLayoutStore(scope:.document)
            try require(recoveredAgain.saved==recovered.saved && recoveredAgain.configuration==recovered.configuration,"Recovered named layouts were lost on the next write/reopen")
            WorkspaceLayoutPreferences.save(Data("{broken".utf8),scope:.document)
            try require(WorkspaceLayoutStore(scope:.document).configuration == .preset(.balanced,scope:.document),"Malformed JSON fallback")
            for marker in ["\"2\"","\"1\"","true","false","null","2","0","-1","1.1","1.0","1e0"] {
                let bytes=Data(("{\"schemaVersion\":"+marker+",\"current\":{},\"saved\":[]}").utf8)
                WorkspaceLayoutPreferences.save(bytes,scope:.document)
                let unknown=WorkspaceLayoutStore(scope:.document);unknown.apply(.review)
                try require(unknown.persistenceReadOnly && !unknown.saveCurrent(named:"overwrite") && WorkspaceLayoutPreferences.data(.document)==bytes,"Unknown/noninteger schema marker overwritten: "+marker)
            }
            let missingVersion=Data("{\"current\":{},\"saved\":[]}".utf8)
            WorkspaceLayoutPreferences.save(missingVersion,scope:.document)
            let missing=WorkspaceLayoutStore(scope:.document);missing.apply(.review)
            try require(missing.persistenceReadOnly && WorkspaceLayoutPreferences.data(.document)==missingVersion,"Missing schema marker overwritten")
            let oversized=Data(repeating:32,count:65_537)
            WorkspaceLayoutPreferences.save(oversized,scope:.document)
            let bounded=WorkspaceLayoutStore(scope:.document);bounded.apply(.review)
            try require(bounded.persistenceReadOnly && WorkspaceLayoutPreferences.data(.document)==oversized,"Oversized preferences overwritten")
            let deep=Data(("{\"schemaVersion\":1,\"extra\":"+String(repeating:"[",count:20)+"0"+String(repeating:"]",count:20)+"}").utf8)
            WorkspaceLayoutPreferences.save(deep,scope:.document)
            let nested=WorkspaceLayoutStore(scope:.document);nested.apply(.review)
            try require(nested.persistenceReadOnly && WorkspaceLayoutPreferences.data(.document)==deep,"Deep preferences overwritten")
            var future=raw;future["schemaVersion"]=99;let futureData=try JSONSerialization.data(withJSONObject:future)
            WorkspaceLayoutPreferences.save(futureData,scope:.document)
            let oldApp=WorkspaceLayoutStore(scope:.document);oldApp.apply(.focus);_ = oldApp.saveCurrent(named:"session")
            try require(oldApp.persistenceReadOnly && WorkspaceLayoutPreferences.data(.document)==futureData,"Future schema overwritten")
            let book=WorkspaceLayoutStore(scope:.workbook);book.apply(.review)
            try require(WorkspaceLayoutPreferences.data(.document)==futureData && book.configuration.inspectorVisible,"Workspace preferences crossed scopes")
            print("PASS native customizable layouts: \(transitions) transitions, persistent hosts/PDF ancestry/grid coordinator/draft/page/zoom/manual viewport, hosted disabled/locale, reversible focus, divider/reopen/clamp, named presets/per-field recovery/deep/schema/test isolation")
            fflush(stdout);NSApp.terminate(nil)
        }catch{fputs("Native layout failed: \(error)\n",stderr);exit(1)}
    }
}
