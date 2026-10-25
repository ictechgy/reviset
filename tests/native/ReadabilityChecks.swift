import SwiftUI
import AppKit
import PDFKit

@MainActor private enum ReadabilityRegistry {
    static var pdf:PDFView?
    static var grid:NSScrollView?
    static var coordinator:AnyObject?
    static var draft:NSTextField?
}
private struct ReadabilityPDF:NSViewRepresentable {
    func makeNSView(context:Context)->PDFView {
        let view=PDFView(),document=PDFDocument()
        for _ in 0..<3 {
            let image=NSImage(size:NSSize(width:600,height:800));image.lockFocus();NSColor.white.setFill();NSBezierPath(rect:NSRect(x:0,y:0,width:600,height:800)).fill();image.unlockFocus()
            document.insert(PDFPage(image:image)!,at:document.pageCount)
        }
        view.document=document;view.displayMode = .singlePageContinuous;view.autoScales=false;view.scaleFactor=1.5
        ReadabilityRegistry.pdf=view;return view
    }
    func updateNSView(_ view:PDFView,context:Context){}
}
private struct ReadabilityGrid:NSViewRepresentable {
    final class Coordinator:NSObject {}
    func makeCoordinator()->Coordinator {Coordinator()}
    func makeNSView(context:Context)->NSScrollView {
        let view=NSScrollView();view.hasVerticalScroller=true;view.hasHorizontalScroller=true;view.documentView=NSView(frame:NSRect(x:0,y:0,width:5000,height:5000))
        ReadabilityRegistry.grid=view;ReadabilityRegistry.coordinator=context.coordinator;return view
    }
    func updateNSView(_ view:NSScrollView,context:Context){}
}
private struct ReadabilityDraft:NSViewRepresentable {
    func makeNSView(context:Context)->NSTextField {let field=NSTextField(string:"Unsaved 한글 {0} 50%");ReadabilityRegistry.draft=field;return field}
    func updateNSView(_ view:NSTextField,context:Context){}
}
private struct ReadabilityHarness:View {
    var body:some View {
        WorkspacePaneSplit(name:"typography.outer",auxiliaryFirst:true,extent:.points(240),primaryMinimum:500,auxiliaryMinimum:200) {
            WorkspacePaneSplit(name:"typography.inner",isVertical:false,extent:.points(160),primaryMinimum:350,auxiliaryMinimum:120) {
                VStack {
                    Text("Readable interface 한글").readableFont(.body).fixedSize().background(WorkspaceLayoutMarker(name:"typography.body"))
                    NativeWorkspaceIdentity(name:"typography.identity",title:"Project identity 한글",reportID:"report-1").frame(minHeight:32)
                    ReadabilityPDF()
                    ReadabilityGrid().frame(height:100)
                    ReadabilityDraft().frame(height:30)
                }
            } auxiliary:{
                VStack {
                    NativeContextSummaryLine(text:"Context remains readable 한글",symbol:"info.circle",warning:false).background(WorkspaceLayoutMarker(name:"typography.context"))
                    NativeVerbatimReasonReader(text:"Verbatim source reason 한글\r\nSecond line")
                }
            }
        } auxiliary:{
            VStack {
                Text("Default body 한글").fixedSize().background(WorkspaceLayoutMarker(name:"typography.inherited"))
                Text("Version history 한글").readableFont(.caption).fixedSize().background(WorkspaceLayoutMarker(name:"typography.caption"))
                NativeTerminatorLabel(terminator:"\r\n").fixedSize()
                Spacer()
            }
        }
        .frame(maxWidth:.infinity,maxHeight:.infinity)
    }
}
@main private enum ReadabilityChecks {
    @MainActor static func require(_ condition:@autoclosure()->Bool,_ message:String)throws {if !condition(){throw NSError(domain:message,code:1)}}
    @MainActor static func persistence()throws {
        let suite="org.reviset.readability-probe."+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
        defer{defaults.removePersistentDomain(forName:suite)}
        defaults.set("unknown-future-size",forKey:ReadabilityPreferences.preferenceKey)
        let preference=ReadabilityPreferences(defaults:defaults)
        try require(preference.selection == .standard,"Unknown text size did not recover")
        try require(defaults.string(forKey:ReadabilityPreferences.preferenceKey)=="unknown-future-size","Loading changed an unfamiliar preference")
        preference.increase()
        try require(ReadabilityPreferences(defaults:defaults).selection == .large,"Text size did not survive reload")
        for _ in 0..<12 {preference.increase()}
        try require(preference.selection == .extraLarge && !preference.canIncrease,"Increase exceeded the supported size bound")
        for _ in 0..<12 {preference.decrease()}
        try require(preference.selection == .standard && !preference.canDecrease,"Decrease exceeded the supported size bound")
        print("PASS readability preference recovery, persistence and bounds")
    }
    @MainActor static func isolatedPreference()throws {
        let suite="org.reviset.readability-isolation."+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
        defer{defaults.removePersistentDomain(forName:suite)}
        defaults.set("extraLarge",forKey:ReadabilityPreferences.preferenceKey)
        let preference=ReadabilityPreferences(defaults:defaults)
        try require(preference.selection == .standard,"Test library read persistent UI size")
        preference.increase()
        try require(ReadabilityPreferences(defaults:defaults).selection == .large,"Test library did not retain in-memory size")
        try require(defaults.string(forKey:ReadabilityPreferences.preferenceKey)=="extraLarge","Test library wrote persistent UI size")
        preference.selection = .standard
    }
    @MainActor static func sharedLanguageIsolation()throws {
        guard let domain=Bundle.main.bundleIdentifier else{throw NSError(domain:"IsolationProbeRequiresUniqueBundle",code:1)}
        let defaults=UserDefaults.standard
        let original=NSDictionary(dictionary:defaults.persistentDomain(forName:domain) ?? [:])
        let language=LanguagePreferences.shared,text=ReadabilityPreferences.shared
        let expected=CommandLine.arguments.contains("expect-ko") ? UILanguage.ko:.system
        try require(language.selection==expected,"Isolated language ignored its explicit launch argument or read a persistent choice")
        // Check immediately after each mutation, with no cleanup/restore write.
        // A failure or process exit cannot make a transient standard write pass.
        for choice in [UILanguage.en,.ko,.system] {
            language.selection=choice
            try require(language.effectiveLanguage==(choice == .system ? Localizer.preferredLanguage():choice.rawValue),"In-memory language did not rerender")
            try require(original.isEqual(to:defaults.persistentDomain(forName:domain) ?? [:]),"Synthetic language switch wrote standard preferences before restoration")
        }
        for choice in ReadableTextSize.allCases {
            text.selection=choice
            try require(original.isEqual(to:defaults.persistentDomain(forName:domain) ?? [:]),"Synthetic text-size switch wrote standard preferences before restoration")
        }
        let suite="org.reviset.language-persistence-control."+UUID().uuidString,injected=UserDefaults(suiteName:suite)!
        defer{injected.removePersistentDomain(forName:suite)}
        let persistent=LanguagePreferences(defaults:injected)
        persistent.selection = .ko
        // Launch arguments also override reads from an injected defaults suite;
        // inspect its persisted domain rather than the argument-domain overlay.
        try require(injected.persistentDomain(forName:suite)?[LanguagePreferences.preferenceKey] as? String == "ko","Injected language preferences lost normal persistence in test mode")
        print("PASS isolated shared language/text size: launch override, immediate no-standard-write checks and injected persistence control")
    }
    @MainActor static func settle()async {try? await Task.sleep(nanoseconds:150_000_000);for window in NSApp.windows {window.contentView?.layoutSubtreeIfNeeded()}}
    @MainActor static func hostIDs(_ root:NSView)->Set<ObjectIdentifier> {
        var result=Set<ObjectIdentifier>()
        func visit(_ view:NSView) {if let split=view as? NSSplitView,let controller=split.delegate as? NSSplitViewController {for child in controller.children {result.insert(ObjectIdentifier(child))}};view.subviews.forEach(visit)}
        visit(root);return result
    }
    @MainActor static func run(_ window:NSWindow)async {
        do {
            await settle();await settle()
            guard let root=window.contentView,let pdf=ReadabilityRegistry.pdf,let grid=ReadabilityRegistry.grid,let coordinator=ReadabilityRegistry.coordinator,let draft=ReadabilityRegistry.draft else{throw NSError(domain:"ReadabilityHostsMissing",code:1)}
            let originalDefaults=String(describing:UserDefaults.standard.object(forKey:ReadabilityPreferences.preferenceKey))
            let hosts=hostIDs(root)
            try require(hosts.count==4,"Nested hosting-controller boundaries were not present")
            pdf.go(to:pdf.document!.page(at:1)!);pdf.scaleFactor=1.5
            grid.contentView.scroll(to:NSPoint(x:345,y:678));grid.reflectScrolledClipView(grid.contentView)
            try require(window.makeFirstResponder(draft),"Draft focus setup failed")
            await settle()
            let focus=window.firstResponder,origin=grid.contentView.bounds.origin,document=pdf.document,page=pdf.currentPage,draftText=draft.stringValue
            var observed:[[String:Any]]=[]
            func views(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(views)}
            for size in [ReadableTextSize.standard,.large,.extraLarge,.standard] {
                ReadabilityPreferences.shared.selection=size
                await settle()
                let children=views(root),markers=workspaceLayoutMarkers(in:root)
                guard let identity=children.compactMap({$0 as? NSTextField}).first(where:{$0.identifier?.rawValue=="typography.identity"}),let terminator=children.compactMap({$0 as? NSTextField}).first(where:{$0.identifier?.rawValue=="Reviset.diff.terminator"}),let reader=children.compactMap({$0 as? NSTextView}).first(where:{$0.accessibilityIdentifier()=="Reviset.document.rawContextReasons"}),let body=markers.first(where:{$0.identifier?.rawValue=="typography.body"}),let inherited=markers.first(where:{$0.identifier?.rawValue=="typography.inherited"}),let caption=markers.first(where:{$0.identifier?.rawValue=="typography.caption"}),let context=markers.first(where:{$0.identifier?.rawValue=="typography.context"}) else{throw NSError(domain:"ReadabilityFontObservationsMissing",code:1)}
                try require(identity.font?.pointSize==ReadabilityPreferences.shared.pointSize(.headline) && terminator.font?.pointSize==ReadabilityPreferences.shared.pointSize(.caption) && reader.font?.pointSize==ReadabilityPreferences.shared.pointSize(.body),"Native font did not update across a hosting boundary")
                try require(context.bounds.height>=ReadabilityPreferences.shared.pointSize(.caption2),"Context summary clipped its larger text")
                try require(hostIDs(root)==hosts && ReadabilityRegistry.pdf === pdf && ReadabilityRegistry.grid === grid && ReadabilityRegistry.coordinator === coordinator && ReadabilityRegistry.draft === draft,"Text size replaced a live host or coordinator")
                try require(pdf.document === document && pdf.currentPage === page && abs(pdf.scaleFactor-1.5)<0.001 && grid.contentView.bounds.origin==origin,"Text size reset source page/zoom or manual grid viewport")
                try require(draft.stringValue==draftText && window.firstResponder === focus,"Text size changed a draft or stole editor focus")
                observed.append(["size":size.rawValue,"body_height":body.bounds.height,"inherited_body_height":inherited.bounds.height,"caption_height":caption.bounds.height,"context_height":context.bounds.height])
            }
            try require((observed[2]["body_height"] as! CGFloat)>(observed[0]["body_height"] as! CGFloat) && (observed[2]["caption_height"] as! CGFloat)>(observed[0]["caption_height"] as! CGFloat),"Explicit SwiftUI fonts failed to observe size changes")
            try require((observed[2]["inherited_body_height"] as! CGFloat)>(observed[0]["inherited_body_height"] as! CGFloat),"Default interface font did not cross the hosting-controller boundary")
            try require(String(describing:UserDefaults.standard.object(forKey:ReadabilityPreferences.preferenceKey))==originalDefaults,"Native typography probe wrote user defaults")
            if let path=ProcessInfo.processInfo.environment["DOCVER_TEST_USER_DATA"] {try JSONSerialization.data(withJSONObject:["observations":observed,"native_hosts_retained":true,"page_zoom_grid_viewport_draft_and_focus_retained":true,"scope":"in-process native font and geometry observations; no OS accessibility or gesture claim"],options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:path).appendingPathComponent("readability-observations.json"))}
            print("PASS live readability: nested fonts update; PDF/grid/hosts/page/zoom/manual viewport/draft/focus retained; test defaults isolated")
            fflush(stdout);NSApp.terminate(nil)
        }catch{fputs("Readability failed: \(error)\n",stderr);exit(1)}
    }
    @MainActor static func main()throws {
        if CommandLine.arguments.contains("preferences") {try persistence();return}
        if CommandLine.arguments.contains("language-isolation") {try sharedLanguageIsolation();return}
        try isolatedPreference()
        NSApplication.shared.setActivationPolicy(.accessory)
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1100,height:820),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;window.contentView=NSHostingView(rootView:ReadabilityHarness());window.makeKeyAndOrderFront(nil)
        Task{@MainActor in await run(window)}
        NSApp.run()
    }
}
