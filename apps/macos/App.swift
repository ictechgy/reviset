import SwiftUI
import AppKit
import PDFKit
import CryptoKit
import Combine

@main struct RevisetApp: App {
    @StateObject private var model=AppModel()
    @StateObject private var language=LanguagePreferences.shared
    @StateObject private var documentLayout=WorkspaceLayoutStore(scope:.document)
    @Environment(\.openWindow) private var openWindow
    var body: some Scene {
        Window("Reviset", id:"main") {MainView().environmentObject(model).environmentObject(documentLayout).environment(\.locale,language.localizer.locale).task {
            await Smoke.runIfRequested(model,layout:documentLayout)
            if ProcessInfo.processInfo.environment["DOCVER_WORKBOOK_SMOKE_REQUEST"] != nil {
                for _ in 0..<400 { if !model.initializing { break }; try? await Task.sleep(nanoseconds:50_000_000) }
                if let path=ProcessInfo.processInfo.environment["DOCVER_WORKBOOK_SMOKE_REQUEST"],let data=try? Data(contentsOf:URL(fileURLWithPath:path)),let raw=try? JSONSerialization.jsonObject(with:data),JSON(raw)["expect_library_locked"].bool {
                    openWindow(id:"workbooks")
                    await Smoke.workbookLockProbe(model,request:JSON(raw))
                } else if model.libraryAvailable && !model.initializing { openWindow(id:"workbooks") }
            }
        }.onReceive(NotificationCenter.default.publisher(for:NSApplication.willTerminateNotification)){_ in model.bridge.terminateAnalysis();model.sidecarRequest=nil;model.bridge.cancelSidecars()}}
        .defaultSize(width:1440,height:960)
        .windowToolbarStyle(.unifiedCompact)
        .commands { RevisetCommands(model:model,language:language) }

        Window(L("app.window.workbooks"),id:"workbooks") {
            Group {
            if !model.libraryAvailable {
                VStack(spacing:12) { Image(systemName:"lock.fill").font(.largeTitle); Text(L("app.library.locked")); Text(L("app.library.reopen")).foregroundStyle(.secondary) }.frame(minWidth:640,minHeight:420)
            } else if model.initializing {
                ProgressView(L("app.library.preparing")).frame(minWidth:640,minHeight:420)
            } else {
                VStack(spacing:0) {
                    if !model.workbookRecoveryWarning.isEmpty { Label(model.workbookRecoveryWarning,systemImage:"info.circle").font(.caption).padding(10).frame(maxWidth:.infinity,alignment:.leading).background(.orange.opacity(0.1)) }
                    WorkbookWorkspace(bridge:model.bridge)
                }
            }
            }.task { await model.start() }
            .environment(\.locale,language.localizer.locale)
            .navigationTitle(L("app.window.workbooks"))
        }.defaultSize(width:1440,height:960).windowToolbarStyle(.unifiedCompact)
        Settings { LanguageSettingsView().environment(\.locale,language.localizer.locale) }
    }
}
@MainActor struct RevisetCommands: Commands {
    @ObservedObject var model: AppModel
    @ObservedObject var language: LanguagePreferences
    @FocusedObject private var activeLayout:WorkspaceLayoutStore?
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        // Commands cache native menu labels; an observed input explicitly invalidates
        // this builder when the in-app language changes.
        let localizer=language.localizer
        CommandGroup(after:.newItem) {
            Button(localizer.string("app.menu.importVersions")) { model.importSheet=true }.keyboardShortcut("o").disabled(model.busy || model.loading || !model.libraryAvailable || model.initializing)
            Button(localizer.string("app.menu.workbooks")) { openWindow(id:"workbooks") }.keyboardShortcut("o",modifiers:[.command,.shift]).disabled(!model.libraryAvailable || model.initializing)
        }
        CommandGroup(after:.sidebar) {
            Button(localizer.string("app.menu.focus")) { activeLayout?.toggleFocus() }.keyboardShortcut("f",modifiers:[.command,.option]).disabled(activeLayout == nil)
            Button(localizer.string("app.menu.evidence")) { activeLayout?.update{$0.inspectorVisible.toggle()} }.keyboardShortcut("i",modifiers:[.command,.option]).disabled(activeLayout == nil)
            Button(localizer.string("layout.panel.projects")) { activeLayout?.update{$0.sidebarVisible.toggle()} }.keyboardShortcut("s",modifiers:[.command,.option]).disabled(activeLayout == nil)
            Button(localizer.string("layout.panel.changes")) { activeLayout?.update{$0.changesVisible.toggle()} }.keyboardShortcut("c",modifiers:[.command,.option]).disabled(activeLayout == nil)
            Button(localizer.string("layout.customize")) { activeLayout?.settingsPresented=true }.keyboardShortcut("l",modifiers:[.command,.option]).disabled(activeLayout == nil)
            Button(localizer.string("layout.reset")) { activeLayout?.reset() }.keyboardShortcut("0",modifiers:[.command,.option]).disabled(activeLayout == nil)
        }
    }
}
struct LanguageSettingsView: View {
    @State private var language=LanguagePreferences.shared
    var body: some View {
        @Bindable var preference=language
        Form {
            Picker(L("app.settings.language"),selection:$preference.selection) {
                Text(L("language.system")).tag(UILanguage.system)
                Text("English").tag(UILanguage.en)
                Text("한국어").tag(UILanguage.ko)
            }
            Text(L("app.settings.description")).font(.callout).foregroundStyle(.secondary)
            Text(L("app.settings.ocrScope")).font(.callout).foregroundStyle(.secondary)
            Text(L("app.settings.systemMenuNote")).font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width:520).fixedSize(horizontal:false,vertical:true)
        .navigationTitle(L("app.settings.title"))
    }
}
private struct SmokeStructureView: View {
    let page: JSON
    var body: some View { StructureCanvas(language:LanguagePreferences.shared.effectiveLanguage,page:page,evidence:JSON()) }
}
// The native SwiftUI menu delegate materializes labels when tracking starts.
// Qualify that public AppKit lifecycle rather than inspect a closed-menu cache.
@MainActor private final class SmokeMenuTracker: NSObject {
    let menu:NSMenu
    private(set) var titles:[String]=[]
    private(set) var enteredTracking=false
    init(_ menu:NSMenu) {self.menu=menu}
    @objc private func captureAndClose(_ timer:Timer) {
        enteredTracking=true;titles=menu.items.map(\.title)
        menu.cancelTrackingWithoutAnimation()
    }
    func track(in view:NSView)->[String] {
        let timer=Timer(timeInterval:0.25,target:self,selector:#selector(captureAndClose(_:)),userInfo:nil,repeats:false)
        RunLoop.main.add(timer,forMode:.eventTracking)
        menu.popUp(positioning:nil,at:NSPoint(x:20,y:20),in:view)
        timer.invalidate()
        return titles
    }
}
@MainActor enum Smoke {
    private static var started=false
    static func workbookLockProbe(_ model:AppModel,request:JSON) async {
        let folder=URL(fileURLWithPath:request["output"].string)
        do {
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let db=model.bridge.library.appendingPathComponent("docver.sqlite"),before=try fileDigest(db)
            try await Task.sleep(nanoseconds:500_000_000)
            func hasGrid(_ view:NSView)->Bool { if view.identifier?.rawValue.hasPrefix("Docver.workbook.grid.") == true {return true};return view.subviews.contains(where:hasGrid) }
            let grids=NSApp.windows.compactMap(\.contentView).contains(where:hasGrid),after=try fileDigest(db)
            let passed = !model.libraryAvailable && !model.initializing && !grids && before == after
            try JSON(["completed":passed,"checks":["library_lock_denied":!model.libraryAvailable,"workbook_grid_not_instantiated":!grids,"database_bytes_unchanged":before == after],"interaction_scope":"actual second app process and restored workbook scene; no OS gestures"]).data().write(to:folder.appendingPathComponent("validation.json"))
        } catch {try? JSON(["completed":false,"error":error.localizedDescription]).data().write(to:folder.appendingPathComponent("validation.json"))}
        NSApp.terminate(nil)
    }
    static func runIfRequested(_ model:AppModel,layout:WorkspaceLayoutStore) async {
        guard !started,let path=ProcessInfo.processInfo.environment["DOCVER_SMOKE_REQUEST"] else{return};started=true
        do{
            let request=JSON(try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:path))))
            let output=URL(fileURLWithPath:request["output"].string);try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
            // MainView's startup task may still be loading; wait cooperatively without blocking the app.
            for _ in 0..<200 {if !model.initializing{break};try await Task.sleep(nanoseconds:50_000_000)}
            guard !model.initializing else{throw BridgeError(code:"STARTUP_TIMEOUT",message:"초기화가 완료되지 않았습니다.")}
            if request["expect_library_locked"].bool {
                // Source First hides Projects. Reveal that production pane before
                // qualifying its real disabled controls in the locked process.
                layout.update{$0.sidebarVisible=true}
                for _ in 0..<100 {
                    let mounted=NSApp.windows.compactMap(\.contentView).flatMap{workspaceLayoutMarkers(in:$0)}.contains{$0.identifier?.rawValue=="Reviset.document.sidebar" && $0.window != nil}
                    if mounted {break};try await Task.sleep(nanoseconds:20_000_000)
                }
                try await documentLockProbe(model,request:request,output:output)
                NSApp.terminate(nil);return
            }
            let startedAt=Date()
            if !request["existing_project_id"].string.isEmpty {
                await model.selectProject(request["existing_project_id"].string,snapshot:request["existing_report_id"].string)
            } else if !request["bundle_revisions"].array.isEmpty {
                let rows=request["bundle_revisions"].array.map{r in ImportRow(label:r["label"].string,urls:r["files"].array.map{URL(fileURLWithPath:$0.string)})}
                let p=try await model.create(title:"제공 PDF 화면 근거 검증",rows:rows);model.projectID=p["project_id"].string;await model.run(model.projectID)
            } else if request["files"].array.isEmpty{await model.demo()}
            else{let rows=request["files"].array.map{ImportRow(label:URL(fileURLWithPath:$0.string).deletingPathExtension().lastPathComponent,urls:[URL(fileURLWithPath:$0.string)])};let p=try await model.create(title:"수백 페이지 합성 검증",rows:rows);model.projectID=p["project_id"].string;await model.run(model.projectID)}
            guard !model.report.isNull else{throw BridgeError(code:"SMOKE_NO_REPORT",message:model.error)}
            let assets=model.bridge.library.appendingPathComponent("assets")
            let assetFacts=try FileManager.default.contentsOfDirectory(at:assets,includingPropertiesForKeys:nil).filter{$0.lastPathComponent.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil}.map{url in
                (url:url,sha:try fileDigest(url),modified:try FileManager.default.attributesOfItem(atPath:url.path)[.modificationDate] as? Date)
            }
            let gitDiffChecks=request["git_diff_checks"].bool ? try await exerciseGitDiffWorkspace(model,layout:layout,output:output,expectReversion:request["git_diff_reversion"].bool):[:]
            let aspectChecks=request["aspect_ratio_checks"].bool ? try await exerciseAspectRatios(model,output):[]
            if request["bundle_sheet_page"].int>0 {
                let revision=model.revision(0),number=request["bundle_sheet_page"].int
                guard let selected=model.primaryPages(revision).first(where:{$0["page"].int==number}) else{throw BridgeError(code:"BUNDLE_LARGE_PAGE",message:"수백 페이지 묶음의 선택 페이지를 찾지 못했습니다.")}
                let context=try await model.bundleContext(project:model.projectID,report:model.report["report_id"].string,occurrence:revision["revision_occurrence_id"].string)
                guard context["revision"]["pages"].array.count>=600,context["mapping"].array.contains(where:{$0["source_page_id"].string==selected["page_id"].string}) else{throw BridgeError(code:"BUNDLE_LARGE_CONTEXT",message:"수백 페이지 묶음의 연결 정보가 다릅니다.")}
                model.openBundle(revision,source:selected["page_id"].string);try await Task.sleep(nanoseconds:850_000_000)
                guard model.bundleSourceID==selected["page_id"].string,let sheet=NSApp.windows.compactMap({$0.sheets.first}).first else{throw BridgeError(code:"BUNDLE_LARGE_SHEET",message:"선택한 페이지의 묶음 수정 창을 열지 못했습니다.")}
                try captureView(sheet,output.appendingPathComponent("native-bundle-page240.png"));model.bundleSheet=false;try await Task.sleep(nanoseconds:200_000_000)
            }
            let manualChecks=request["manual_relations"].bool ? try await exerciseManualRelations(model,output):[]
            let layoutChecks=request["layout_checks"].bool ? try await exerciseLayout(model,layout:layout,output:output):[:]
            let referenceChecks=request["reference_appearance_checks"].bool ? try await exerciseReferenceAppearance(model):[:]
            let importChecks=request["import_draft_files"].array.isEmpty ? [:]:try await exerciseImportDraft(model,output,request["import_draft_files"].array.map{URL(fileURLWithPath:$0.string)})
            let bundleChecks=request["bundle_mapping_checks"].bool ? try await exerciseBundleMapping(model,output):[:]
            let sidecarChecks=request["sidecar_checks"].bool ? try await exerciseSidecar(model,output,request["sidecar_page"].int):[:]
            model.inspector=true
            try await Task.sleep(nanoseconds:700_000_000);try capture(output.appendingPathComponent("native-compare.png"))
            model.inspector=false;model.focus=true;model.showChanges=false;model.pageMode="after"
            if model.primaryPages(model.revision(model.to)).count>=300{model.rightPageID=model.primaryPages(model.revision(model.to))[299]["page_id"].string}
            try await Task.sleep(nanoseconds:700_000_000);try capture(output.appendingPathComponent("native-focus.png"))
            if model.from != model.to && model.primaryPages(model.revision(model.from)).count>=300 && model.primaryPages(model.revision(model.to)).count>=300 {
                model.focus=false;model.pageMode="both";model.inspector=true
                model.leftPageID=model.primaryPages(model.revision(model.from))[239]["page_id"].string;model.rightPageID=model.primaryPages(model.revision(model.to))[239]["page_id"].string
                try await Task.sleep(nanoseconds:250_000_000);model.mappingSheet=true;try await Task.sleep(nanoseconds:500_000_000)
                guard let sheet=NSApp.windows.compactMap({$0.sheets.first}).first else { throw BridgeError(code:"LARGE_MAPPING_SHEET",message:"수백 페이지 대응 창 표시 실패") }
                try captureView(sheet,output.appendingPathComponent("native-mapping-page240.png"));model.mappingSheet=false;model.inspector=false
            }
            model.from=0;model.to=max(0,model.revisions.count-1);model.tab="history";model.focus=false;try await model.updateChanges()
            try await Task.sleep(nanoseconds:300_000_000);try capture(output.appendingPathComponent("native-history.png"))
            var historyChangeCheck:[String:Any]=[:]
            if let change=model.changes.last(where:{$0["kind"].string=="text_modified"}) {
                let id=change["change_id"].string,before=change["from_occurrence"].string,after=change["to_occurrence"].string
                let evidence=change["evidence"].array,selectionStarted=Date(),queryFrom=model.from,queryTo=model.to,queryRows=try JSON(model.changes.map(\.raw)).data()
                var observedLoading=false
                let loadingObservation=model.$loadingChanges.dropFirst().sink { if $0 { observedLoading=true } }
                defer { loadingObservation.cancel() }
                func selectionReady()->Bool {
                    !model.loadingChanges && model.tab=="history" && model.from==queryFrom && model.to==queryTo && model.selectedChangeID==id && model.revision(model.sourceFrom)["revision_occurrence_id"].string==before && model.revision(model.sourceTo)["revision_occurrence_id"].string==after &&
                    evidence.contains(where:{$0["revision_occurrence_id"].string==before && model.displayPageID($0["page_id"].string,in:model.revision(model.sourceFrom))==model.leftPageID}) &&
                    evidence.contains(where:{$0["revision_occurrence_id"].string==after && model.displayPageID($0["page_id"].string,in:model.revision(model.sourceTo))==model.rightPageID})
                }
                model.chooseChange(id)
                for _ in 0..<200 {
                    // Event selection keeps the query rows and does not start another read.
                    try await Task.sleep(nanoseconds:20_000_000)
                    if !observedLoading && selectionReady() {break}
                }
                guard !observedLoading && selectionReady(),try JSON(model.changes.map(\.raw)).data()==queryRows else {
                    try? JSON(["requested_change_id":id,"selected_change_id":model.selectedChangeID ?? "","loading_cycle_observed":observedLoading,"loading_changes":model.loadingChanges,"tab":model.tab,"expected_from_occurrence":before,"actual_from_occurrence":model.revision(model.from)["revision_occurrence_id"].string,"expected_to_occurrence":after,"actual_to_occurrence":model.revision(model.to)["revision_occurrence_id"].string,"left_page_id":model.leftPageID,"right_page_id":model.rightPageID,"changes_failure":model.changesFailure]).data().write(to:output.appendingPathComponent("history-selection-failure.json"))
                    throw BridgeError(code:"HISTORY_CHANGE_SELECTION",message:"실제 이력 선택과 비교 구간·원문 근거가 다릅니다.")
                }
                historyChangeCheck=["selected_change_id":id,"from_occurrence":before,"to_occurrence":after,"source_pages_verified":true,"loading_cycle_observed":observedLoading,"selection_wait_seconds":Date().timeIntervalSince(selectionStarted)]
                historyChangeCheck["capture_readiness"]=try await captureSelectedPages(model,output,selectionReady:selectionReady)
                model.tab="history";try await model.updateChanges()
            }
            // Navigate both the first and final history columns and let pending range calls settle.
            for index in [0,model.revisions.count-1]{
                let id=model.primaryPages(model.revision(index)).last!["page_id"].string
                model.openHistoryPage(index,id);try await Task.sleep(nanoseconds:250_000_000)
                guard (index==0 ? model.leftPageID:model.rightPageID)==id else{throw BridgeError(code:"HISTORY_NAVIGATION",message:"전체 이력의 원문 페이지 이동 실패")}
            }
            model.tab="history";try await model.updateChanges()
            await model.loadMCP()
            let numeric=model.changes.filter{$0["kind"].string=="text_modified"}
            let result:[String:Any]=["native_ui":"SwiftUI/AppKit/PDFKit","report_id":model.report["report_id"].string,"project_id":model.projectID,"pages":model.revisions.map{model.primaryPages($0).count},"numeric_changes":numeric.map(\.raw),"analysis_and_ui_seconds":Date().timeIntervalSince(startedAt),"error":model.error,"mcp_config":model.mcp,"manual_relation_checks":manualChecks,"layout_checks":layoutChecks,"git_diff_checks":gitDiffChecks,"reference_appearance_checks":referenceChecks,"import_draft_checks":importChecks,"bundle_mapping_checks":bundleChecks,"smoke_invocation_id":request["smoke_invocation_id"].string]
            var complete=result;complete["aspect_ratio_checks"]=aspectChecks
            for fact in assetFacts {
                let modified=try FileManager.default.attributesOfItem(atPath:fact.url.path)[.modificationDate] as? Date
                guard try fileDigest(fact.url)==fact.sha,modified==fact.modified else{throw BridgeError(code:"SOURCE_ASSET_CHANGED",message:"화면 표시 후 저장 원본의 hash 또는 수정 시간이 바뀌었습니다.")}
            }
            complete["source_assets_unchanged"]=assetFacts.map{["name":$0.url.lastPathComponent,"sha256":$0.sha]}
            complete["history_change_check"]=historyChangeCheck
            complete["sidecar_checks"]=sidecarChecks
            complete["language_checks"]=request["language_checks"].bool ? try await exerciseLanguageSwitch(model,output):[:]
            try JSON(complete).data().write(to:output.appendingPathComponent("result.json"));NSApp.terminate(nil)
        }catch{if let output=ProcessInfo.processInfo.environment["DOCVER_SMOKE_OUTPUT"]{try? JSON(["error":error.localizedDescription]).data().write(to:URL(fileURLWithPath:output))};fputs("Reviset native smoke failed: \(error)\n",stderr);NSApp.terminate(nil)}
    }
    static func exerciseLanguageSwitch(_ model:AppModel,_ output:URL) async throws->[String:Any] {
        let preferences=LanguagePreferences.shared,original=preferences.selection
        let defaults=UserDefaults.standard,domain=Bundle.main.bundleIdentifier ?? "org.docver.native"
        let stored=defaults.persistentDomain(forName:domain)?[LanguagePreferences.preferenceKey]
        let status=model.statusMessage,identity=ObjectIdentifier(model),report=try model.report.data(),project=model.projectID
        let originalZoom=model.zoom,originalTab=model.tab
        defer {
            preferences.selection=original;model.statusMessage=status;model.zoom=originalZoom;model.tab=originalTab
            if let stored { defaults.set(stored,forKey:LanguagePreferences.preferenceKey) }
            else { defaults.removeObject(forKey:LanguagePreferences.preferenceKey) }
        }
        guard let parent=NSApp.windows.first(where:{$0.isVisible && $0.contentView != nil}) else {throw BridgeError(code:"L10N_WINDOW",message:"No document window")}
        let opaque="language.system {0} %@ %% 한글 العربية"
        let row=ImportRow(label:opaque,urls:[URL(fileURLWithPath:"/not-opened/"+opaque+".pdf")])
        let sheet=NSWindow(contentRect:NSRect(x:0,y:0,width:900,height:500),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        sheet.isReleasedWhenClosed=false
        defer {if sheet.sheetParent != nil {parent.endSheet(sheet)};sheet.orderOut(nil);sheet.close()}
        sheet.isOpaque=true;sheet.backgroundColor = .windowBackgroundColor
        sheet.contentView=NSHostingView(rootView:ImportView(initialRows:[row],initialTitle:opaque).environmentObject(model).background(Color(nsColor:.windowBackgroundColor)))
        func fields(_ root:NSView)->[NSTextField] { (root as? NSTextField).map{[$0]} ?? [] + root.subviews.flatMap(fields) }
        func menuTitles(_ menu:NSMenu)->[String] { menu.items.flatMap{[$0.title]+($0.submenu.map(menuTitles) ?? [])} }
        func pdfs(_ root:NSView)->[PDFView] { if let view=root as? PDFView {return [view]};return root.subviews.flatMap(pdfs) }
        model.statusMessage=UIMessage("app.settings.description")
        model.tab="compare";model.zoom=1.5
        // The tab intentionally changes query scope. Settle that setup before
        // taking the baseline that a language mutation must preserve.
        try await Task.sleep(nanoseconds:50_000_000)
        try await model.updateChanges()
        guard !model.loadingChanges else {throw BridgeError(code:"L10N_SETUP",message:"Compare range did not settle")}
        let viewportOutput=output.appendingPathComponent("language-viewport")
        try FileManager.default.createDirectory(at:viewportOutput,withIntermediateDirectories:true)
        let mountedSources=try await captureSelectedPages(model,viewportOutput,selectionReady:{!model.loadingChanges && model.tab=="compare"})
        let expectedPages=model.pageMode == "before" ? [model.leftPageID] : model.pageMode == "after" ? [model.rightPageID] : [model.leftPageID,model.rightPageID]
        let expectedPDFCount=expectedPages.filter{!$0.isEmpty}.count
        var pdfViews:[PDFView]=[]
        for _ in 0..<200 {
            parent.contentView?.layoutSubtreeIfNeeded()
            pdfViews=parent.contentView.map(pdfs) ?? []
            if pdfViews.count==expectedPDFCount && !pdfViews.isEmpty && pdfViews.allSatisfy({$0.document != nil && $0.currentPage != nil}) {break}
            try await Task.sleep(nanoseconds:50_000_000)
        }
        guard !pdfViews.isEmpty,pdfViews.count==expectedPDFCount,pdfViews.allSatisfy({$0.document != nil && $0.currentPage != nil}) else {throw BridgeError(code:"L10N_VIEWPORT",message:"Selected production PDF views did not mount")}
        for view in pdfViews { if let clip=view.documentView?.enclosingScrollView?.contentView {
            clip.scroll(to:NSPoint(x:clip.bounds.origin.x+24,y:clip.bounds.origin.y+32));clip.enclosingScrollView?.reflectScrolledClipView(clip)
        }}
        try await Task.sleep(nanoseconds:200_000_000)
        let pdfState=pdfViews.map { view in (ObjectIdentifier(view),view.scaleFactor,view.documentView?.enclosingScrollView?.contentView.bounds.origin ?? .zero,view.currentPage) }
        let selected=model.selectedChangeID,left=model.leftPageID,right=model.rightPageID,from=model.from,to=model.to
        func selectionFacts()->[String:Any] { ["selected":model.selectedChangeID ?? "","left":model.leftPageID,"right":model.rightPageID,"from":model.from,"to":model.to,"project":model.projectID,"report":model.report["report_id"].string,"tab":model.tab,"loading_changes":model.loadingChanges] }
        let preparedFacts=selectionFacts()
        let emptySheet=NSWindow(contentRect:NSRect(x:0,y:0,width:900,height:500),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        emptySheet.isReleasedWhenClosed=false
        defer {if emptySheet.sheetParent != nil {parent.endSheet(emptySheet)};emptySheet.orderOut(nil);emptySheet.close()}
        emptySheet.isOpaque=true;emptySheet.backgroundColor = .windowBackgroundColor
        emptySheet.contentView=NSHostingView(rootView:ImportView(initialRows:[row]).environmentObject(model).background(Color(nsColor:.windowBackgroundColor)))
        let structurePage=JSON(["page_id":"opaque-structure-fixture","elements":[
            ["kind":"text","text":opaque,"bbox":[0.05,0.05,0.9,0.2]],
            ["kind":"image","bbox":[0.05,0.35,0.4,0.4]],
            ["kind":"unsupported","bbox":[0.5,0.35,0.45,0.4]]]])
        let structure=NSWindow(contentRect:NSRect(x:0,y:0,width:600,height:300),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        structure.isReleasedWhenClosed=false
        defer {if structure.sheetParent != nil {parent.endSheet(structure)};structure.orderOut(nil);structure.close()}
        structure.isOpaque=true;structure.backgroundColor = .white
        structure.contentView=NSHostingView(rootView:SmokeStructureView(page:structurePage))
        func canvases(_ root:NSView)->[StructureCanvas.Canvas] {if let view=root as? StructureCanvas.Canvas{return [view]};return root.subviews.flatMap(canvases)}
        var canvasID:ObjectIdentifier?,structureCaptures:[Data]=[],stages:[[String:Any]]=[]
        for choice in [UILanguage.en,.ko] {
            preferences.selection=choice
            try await Task.sleep(nanoseconds:650_000_000)
            parent.contentView?.layoutSubtreeIfNeeded();parent.contentView?.displayIfNeeded()
            let menuKeys:[StaticString]=["app.menu.importVersions","app.menu.workbooks","app.menu.focus","app.menu.evidence"]
            let expectedMenus=menuKeys.map{preferences.localizer.string($0)}
            let knownTitles=Set(menuKeys.flatMap{[Localizer(language:"en").string($0),Localizer(language:"ko").string($0)]})
            let cachedMenus=NSApp.mainMenu.map(menuTitles) ?? []
            let ownedMenus=(NSApp.mainMenu?.items ?? []).compactMap(\.submenu).filter{$0.items.contains(where:{knownTitles.contains($0.title)})}
            var trackedMenus:[[String:Any]]=[],openedTitles:[String]=[]
            guard let parentView=parent.contentView,!ownedMenus.isEmpty else {throw BridgeError(code:"L10N_MENU",message:"App-owned native menus are missing")}
            for menu in ownedMenus {
                let tracker=SmokeMenuTracker(menu),titles=tracker.track(in:parentView)
                guard tracker.enteredTracking else {throw BridgeError(code:"L10N_MENU",message:"Native menu did not enter tracking")}
                trackedMenus.append(["menu":menu.title,"titles_while_open":titles,"entered_tracking":true]);openedTitles += titles
            }
            try JSON(["language":choice.rawValue,"is_active":NSApp.isActive,"expected":expectedMenus,"cached_before_open":cachedMenus,"tracked":trackedMenus]).data().write(to:output.appendingPathComponent("native-language-\(choice.rawValue)-menus.json"))
            guard expectedMenus.allSatisfy({openedTitles.contains($0)}) else {
                try JSON(["language":choice.rawValue,"is_active":NSApp.isActive,"expected":expectedMenus,"cached_before_open":cachedMenus,"tracked":trackedMenus]).data().write(to:output.appendingPathComponent("language-menu-failure.json"))
                throw BridgeError(code:"L10N_MENU",message:"Opened custom menus did not present selected-language labels")
            }
            let label=L("app.menu.importVersions")
            try captureView(parent,output.appendingPathComponent("native-language-\(choice.rawValue)-document.png"))
            if sheet.sheetParent == nil { parent.beginSheet(sheet,completionHandler:{_ in}) }
            try await Task.sleep(nanoseconds:350_000_000)
            sheet.contentView?.layoutSubtreeIfNeeded();sheet.contentView?.displayIfNeeded()
            guard let content=sheet.contentView,fields(content).filter({$0.stringValue==opaque}).count>=2 else {throw BridgeError(code:"L10N_DRAFT",message:"Import draft title or version label changed")}
            try captureView(sheet,output.appendingPathComponent("native-language-\(choice.rawValue)-import.png"))
            parent.endSheet(sheet);sheet.orderOut(nil)
            parent.beginSheet(emptySheet,completionHandler:{_ in});try await Task.sleep(nanoseconds:250_000_000)
            emptySheet.contentView?.layoutSubtreeIfNeeded()
            let defaultFields=emptySheet.contentView.map(fields) ?? []
            let defaultFacts:[String:Any] = ["language":choice.rawValue,"expected_title":L("doc.import.defaultTitle"),"expected_placeholder":L("doc.import.projectName"),"is_key_window":emptySheet.isKeyWindow,"editable_fields":defaultFields.filter(\.isEditable).map{["placeholder":$0.placeholderString ?? "","value":$0.stringValue]}]
            try JSON(defaultFacts).data().write(to:output.appendingPathComponent("native-language-\(choice.rawValue)-default-title.json"))
            guard defaultFields.contains(where:{$0.placeholderString==L("doc.import.projectName") && $0.stringValue==L("doc.import.defaultTitle")}) else {throw BridgeError(code:"L10N_DEFAULT_TITLE",message:"Untouched document title did not follow language")}
            try captureView(emptySheet,output.appendingPathComponent("native-language-\(choice.rawValue)-import-default.png"));parent.endSheet(emptySheet);emptySheet.orderOut(nil)
            parent.beginSheet(structure,completionHandler:{_ in});try await Task.sleep(nanoseconds:250_000_000)
            structure.contentView?.layoutSubtreeIfNeeded();structure.contentView?.displayIfNeeded()
            guard let canvas=structure.contentView.flatMap({canvases($0).first}),try canvas.page.data()==structurePage.data() else {throw BridgeError(code:"L10N_STRUCTURE",message:"Structure source changed")}
            if let canvasID {guard ObjectIdentifier(canvas)==canvasID else {throw BridgeError(code:"L10N_STRUCTURE",message:"Structure canvas was recreated")}} else {canvasID=ObjectIdentifier(canvas)}
            let structurePath=output.appendingPathComponent("native-language-\(choice.rawValue)-structure.png")
            try captureView(structure,structurePath);structureCaptures.append(try Data(contentsOf:structurePath));parent.endSheet(structure);structure.orderOut(nil)
            let settings=NSWindow(contentRect:NSRect(x:0,y:0,width:560,height:340),styleMask:[.titled,.closable],backing:.buffered,defer:false)
            settings.isReleasedWhenClosed=false
            defer {if settings.sheetParent != nil {parent.endSheet(settings)};settings.orderOut(nil);settings.close()}
            settings.isOpaque=true;settings.backgroundColor = .windowBackgroundColor
            settings.contentView=NSHostingView(rootView:LanguageSettingsView().environment(\.locale,preferences.localizer.locale).background(Color(nsColor:.windowBackgroundColor)))
            parent.beginSheet(settings,completionHandler:{_ in});try await Task.sleep(nanoseconds:350_000_000)
            try captureView(settings,output.appendingPathComponent("native-language-\(choice.rawValue)-settings.png"));parent.endSheet(settings);settings.orderOut(nil)
            guard ObjectIdentifier(model)==identity,model.projectID==project,try model.report.data()==report,model.selectedChangeID==selected,model.leftPageID==left,model.rightPageID==right,model.from==from,model.to==to else {
                try JSON(["before":preparedFacts,"after":selectionFacts(),"same_model":ObjectIdentifier(model)==identity,"same_report_bytes":try model.report.data()==report]).data().write(to:output.appendingPathComponent("language-model-failure.json"))
                throw BridgeError(code:"L10N_MODEL",message:"Language switch changed document model or selection")
            }
            let currentPDFs=parent.contentView.map(pdfs) ?? []
            guard currentPDFs.count==pdfState.count else {throw BridgeError(code:"L10N_VIEWPORT",message:"PDF view count changed")}
            for (view,state) in zip(currentPDFs,pdfState) {
                let origin=view.documentView?.enclosingScrollView?.contentView.bounds.origin ?? .zero
                guard ObjectIdentifier(view)==state.0,abs(view.scaleFactor-state.1)<0.0001,abs(origin.x-state.2.x)<1,abs(origin.y-state.2.y)<1,view.currentPage===state.3 else {throw BridgeError(code:"L10N_VIEWPORT",message:"PDF identity, scale, viewport or page changed")}
            }
            stages.append(["language":choice.rawValue,"custom_menu":label,"native_menu_tracking":trackedMenus,"status":model.status,"draft_text_unchanged":true,"untouched_default_title_translated":true,"same_structure_canvas_and_source":true,"same_pdf_identity_zoom_viewport_and_page":true,"same_model_report_and_selection":true])
        }
        guard structureCaptures.count==2,structureCaptures[0] != structureCaptures[1] else {throw BridgeError(code:"L10N_STRUCTURE",message:"Fallback placeholder labels did not redraw")}
        guard stages[0]["status"] as? String != stages[1]["status"] as? String else{throw BridgeError(code:"L10N_STATUS",message:"Stored typed status did not rerender")}
        return ["passed":true,"stages":stages,"prepared_selection":preparedFacts,"mounted_sources":mountedSources,"draft_opaque_text":opaque,"interaction_scope":"actual app; model-driven language, production import/settings hosts and native NSMenu tracking with timed cancellation; no OS keyboard/mouse or full VoiceOver claim"]
    }
    private static func exerciseGitDiffWorkspace(_ model:AppModel,layout:WorkspaceLayoutStore,output:URL,expectReversion:Bool)async throws->[String:Any] {
        let report=try model.report.data(),reportID=model.report["report_id"].string
        let defaultPair=model.from==max(0,model.revisions.count-2) && model.to==max(0,model.revisions.count-1)
        guard defaultPair else{throw BridgeError(code:"GIT_DEFAULT_PAIR",message:"New report did not open predecessor → latest.")}
        layout.reset();model.tab="compare";model.pageMode="both";model.diffMode="source"
        guard !layout.configuration.sidebarVisible,!layout.configuration.inspectorVisible,layout.configuration.changesVisible,layout.configuration.changesDock == .left else{throw BridgeError(code:"GIT_DEFAULT_LAYOUT",message:"Source First default has incorrect panel visibility.")}
        try await Task.sleep(nanoseconds:400_000_000);try capture(output.appendingPathComponent("native-git-source-first.png"))
        model.from=0;model.to=max(0,model.revisions.count-1);try await model.updateChanges()
        let netText=model.changes.filter{$0["kind"].string=="text_modified"}
        model.tab="history";try await model.updateChanges()
        let historyText=model.changes.filter{$0["kind"].string=="text_modified"},queryFrom=model.from,queryTo=model.to,rows=try JSON(model.changes.map(\.raw)).data()
        if expectReversion {guard netText.isEmpty,historyText.count>=2 else{throw BridgeError(code:"GIT_REVERSION",message:"Reverted endpoints and intermediate events were conflated.")}}
        guard let change=historyText.first else{throw BridgeError(code:"GIT_HISTORY_EVIDENCE",message:"Qualification needs at least one text event.")}
        var loaded=false;let observation=model.$loadingChanges.dropFirst().sink{if $0{loaded=true}};defer{observation.cancel()}
        model.chooseChange(change["change_id"].string)
        try await Task.sleep(nanoseconds:100_000_000)
        guard !loaded,model.tab=="history",model.from==queryFrom,model.to==queryTo,try JSON(model.changes.map(\.raw)).data()==rows,model.revision(model.sourceFrom)["revision_occurrence_id"].string==change["from_occurrence"].string,model.revision(model.sourceTo)["revision_occurrence_id"].string==change["to_occurrence"].string else{throw BridgeError(code:"GIT_HISTORY_SCOPE",message:"Event selection replaced query scope or rows.")}
        observation.cancel();let selectionDidNotQuery = !loaded
        _ = try await captureSelectedPages(model,output,selectionReady:{model.tab=="history" && model.selectedChangeID==change["change_id"].string})
        try capture(output.appendingPathComponent("native-git-history.png"))
        func pdfs(_ view:NSView)->[PDFView] {(view as? PDFView).map{[$0]} ?? view.subviews.flatMap{pdfs($0)}}
        guard let window=NSApp.windows.first(where:{$0.isVisible && $0.contentView != nil}),let content=window.contentView else{throw BridgeError(code:"GIT_WINDOW",message:"No native source window.")}
        let mounted=pdfs(content),identities=Set(mounted.map(ObjectIdentifier.init))
        let state=mounted.map{($0,$0.document,$0.currentPage,$0.scaleFactor,$0.documentView?.enclosingScrollView?.contentView.bounds.origin ?? .zero)}
        model.diffMode="text";try await Task.sleep(nanoseconds:250_000_000);try capture(output.appendingPathComponent("native-git-unified.png"));model.diffMode="source";try await Task.sleep(nanoseconds:250_000_000)
        guard !mounted.isEmpty,Set(pdfs(content).map(ObjectIdentifier.init))==identities else{throw BridgeError(code:"GIT_HOST",message:"Text mode recreated PDF hosts.")}
        for (view,document,page,zoom,origin) in state {let now=view.documentView?.enclosingScrollView?.contentView.bounds.origin ?? .zero;guard view.document===document,view.currentPage===page,abs(view.scaleFactor-zoom)<0.001,abs(now.x-origin.x)<1,abs(now.y-origin.y)<1 else{throw BridgeError(code:"GIT_VIEWPORT",message:"Text mode changed source page, zoom or viewport.")}}
        layout.setFocus(true);try await Task.sleep(nanoseconds:200_000_000)
        guard workspaceLayoutMarkers(in:content).contains(where:{$0.identifier?.rawValue=="Reviset.document.reportBar"}) else{throw BridgeError(code:"GIT_REPORT_FOCUS",message:"Focus hid fixed report identity.")}
        guard workspaceLayoutMarkers(in:content).contains(where:{$0.identifier?.rawValue=="Reviset.document.selectedContext"}) else{throw BridgeError(code:"GIT_CONTEXT_FOCUS",message:"Focus hid selected correspondence/observation context.")}
        try capture(output.appendingPathComponent("native-git-focus.png"));layout.setFocus(false)
        model.selectVersion(0);try await model.updateChanges();guard model.readingSingleVersion,model.changes.isEmpty else{throw BridgeError(code:"GIT_V1_READ",message:"First version did not enter single-source reading.")}
        model.selectVersion(max(0,model.revisions.count-1));try await model.updateChanges();model.tab="compare";try await model.updateChanges()
        guard model.report["report_id"].string==reportID,try model.report.data()==report else{throw BridgeError(code:"GIT_REPORT_MUTATION",message:"Workspace navigation modified report data.")}
        return ["passed":true,"default_predecessor_latest":defaultPair,"source_first_default":true,"query_interval_preserved":true,"query_rows_preserved":true,"selection_started_no_range_query":selectionDidNotQuery,"net_text_changes":netText.count,"history_text_changes":historyText.count,"reversion_expected":expectReversion,"native_pdf_hosts_preserved":mounted.count,"text_mode_page_zoom_viewport_preserved":true,"focus_fixed_report_visible":true,"focus_selected_context_visible":true,"first_version_single_read":true,"fixed_report_unchanged":true,"captures":["native-git-source-first.png","native-git-history.png","native-git-unified.png","native-git-focus.png"],"interaction_scope":"production model actions and actual AppKit/PDFKit hosts; no OS gestures or full VoiceOver claim"]
    }
    static func captureSelectedPages(_ model:AppModel,_ output:URL,selectionReady:()->Bool) async throws->[String:Any] {
        let report=model.report["report_id"].string,mode=model.pageMode,left=model.leftPageID,right=model.rightPageID,started=Date()
        let pageIDs=mode=="before" ? [left]:mode=="after" ? [right]:[left,right]
        var expected:[[String:Any]]=[]
        for id in pageIDs {
            let payload=try await model.page(id)
            expected.append(["page_id":id,"kind":payload["source"]["kind"].string,"path":payload["source"]["path"].string,"page_index":(payload["display_page_number"].isNull ? payload["page"]["page"].int:payload["display_page_number"].int)-1])
        }
        func stillSelected()->Bool {selectionReady() && model.report["report_id"].string==report && model.pageMode==mode && model.leftPageID==left && model.rightPageID==right}
        func visiblePages(_ root:NSView,_ window:NSWindow)->[(NSView,[String:Any])] {
            var pages:[(NSView,[String:Any])]=[]
            if root.window===window && !root.isHiddenOrHasHiddenAncestor && root.bounds.width>0 && root.bounds.height>0 && root.visibleRect.width>0 && root.visibleRect.height>0 {
                if let pdf=root as? PDFView,let document=pdf.document,let page=pdf.currentPage {
                    pages.append((pdf,["kind":"pdf","path":document.documentURL?.resolvingSymlinksInPath().standardizedFileURL.path ?? "","page_index":document.index(for:page)]))
                } else if let canvas=root as? StructureCanvas.Canvas {
                    pages.append((canvas,["kind":"structure","page_id":canvas.page["page_id"].string]))
                }
            }
            for child in root.subviews {pages.append(contentsOf:visiblePages(child,window))}
            return pages
        }
        var actual:[[String:Any]]=[],consecutive=0,polls=0
        for _ in 0..<200 {
            // PageColumn reads its payload after the model's range read. Yield to
            // that task and require the selected source to be mounted for capture.
            try await Task.sleep(nanoseconds:20_000_000);polls+=1
            guard stillSelected() else{break}
            guard let window=NSApp.windows.first(where:{$0.isVisible && $0.contentView != nil}),let view=window.contentView else{consecutive=0;continue}
            view.layoutSubtreeIfNeeded();view.displayIfNeeded()
            let candidates=visiblePages(view,window);actual=candidates.map{$0.1}
            var used=Set<ObjectIdentifier>()
            let matched=expected.allSatisfy { target in
                guard let match=candidates.first(where:{ candidate in
                    guard !used.contains(ObjectIdentifier(candidate.0)) else{return false}
                    if target["kind"] as? String == "pdf" {
                        let path=URL(fileURLWithPath:target["path"] as? String ?? "").resolvingSymlinksInPath().standardizedFileURL.path
                        return candidate.1["kind"] as? String == "pdf" && candidate.1["path"] as? String == path && candidate.1["page_index"] as? Int == target["page_index"] as? Int
                    }
                    return candidate.1["kind"] as? String == "structure" && candidate.1["page_id"] as? String == target["page_id"] as? String
                }) else{return false}
                used.insert(ObjectIdentifier(match.0));return true
            }
            consecutive=matched ? consecutive+1:0
            if consecutive>=2 && stillSelected() {
                view.layoutSubtreeIfNeeded();view.displayIfNeeded()
                guard stillSelected() else{break}
                try captureView(window,output.appendingPathComponent("native-history-change.png"))
                return ["mounted_selected_pages_verified":true,"distinct_visible_views":used.count,"expected":expected,"actual":actual,"polls":polls,"wait_seconds":Date().timeIntervalSince(started)]
            }
        }
        try? JSON(["report_id":report,"page_mode":mode,"expected":expected,"actual":actual,"polls":polls,"selection_ready":stillSelected(),"selected_change_id":model.selectedChangeID ?? "","loading_changes":model.loadingChanges,"tab":model.tab,"left_page_id":model.leftPageID,"right_page_id":model.rightPageID]).data().write(to:output.appendingPathComponent("history-capture-failure.json"))
        throw BridgeError(code:"HISTORY_CAPTURE_READINESS",message:"선택한 원문 페이지의 실제 화면 표시를 확인하지 못했습니다.")
    }
    static func exerciseSidecar(_ model:AppModel,_ output:URL,_ requestedPage:Int) async throws->[String:Any] {
        guard model.sidecarConfigured else{throw BridgeError(code:"SIDECAR_NOT_CONFIGURED",message:"참고 렌더러가 준비되지 않았습니다.")}
        let revision=model.revision(0),pages=model.primaryPages(revision)
        guard let page=(requestedPage>0 ? pages.first(where:{$0["page"].int==requestedPage}):pages.last) else{throw BridgeError(code:"SIDECAR_PAGE",message:"참고 화면의 원문 페이지가 없습니다.")}
        let before=try model.report.data(),database=model.bridge.library.appendingPathComponent("docver.sqlite"),beforeDB=try fileDigest(database)
        model.openSidecar(revision,page:page["page_id"].string)
        guard let request=model.sidecarRequest else{throw BridgeError(code:"SIDECAR_OPEN",message:"참고 화면 요청을 만들지 못했습니다.")}
        func pdfView(_ view:NSView)->PDFView? {
            if let pdf=view as? PDFView{return pdf}
            for child in view.subviews{if let pdf=pdfView(child){return pdf}}
            return nil
        }
        do {
            var sheet:NSWindow?,pdf:PDFView?
            for _ in 0..<3600 {
                if !model.sidecarFailure.isEmpty{throw BridgeError(code:"SIDECAR_RENDER_FAILED",message:model.sidecarFailure)}
                sheet=NSApp.windows.compactMap{$0.sheets.first}.first
                if let content=sheet?.contentView,let candidate=pdfView(content),let doc=candidate.document,let current=candidate.currentPage,doc.pageCount==pages.count,doc.index(for:current)==page["page"].int-1 {pdf=candidate;break}
                try await Task.sleep(nanoseconds:50_000_000)
            }
            guard let sheet,let pdf,let doc=pdf.document else{throw BridgeError(code:"SIDECAR_PDFKIT",message:"실제 PDFKit 참고 페이지가 열리지 않았습니다.")}
            try await Task.sleep(nanoseconds:350_000_000);try captureView(sheet,output.appendingPathComponent("native-sidecar.png"))
            let jobs=model.bridge.library.appendingPathComponent("sidecars-v1/jobs"),leases=model.bridge.library.appendingPathComponent("sidecars-v1/leases")
            let pdfPath=jobs.appendingPathComponent(request.id).appendingPathComponent("converted.pdf"),pdfSHA=try fileDigest(pdfPath)
            guard model.sidecarResult["pdf_sha256"].string==pdfSHA,doc.documentURL?.resolvingSymlinksInPath().standardizedFileURL==pdfPath.resolvingSymlinksInPath().standardizedFileURL else{throw BridgeError(code:"SIDECAR_PDF_HASH",message:"참고 화면과 변환 결과의 PDF hash 또는 경로가 다릅니다.")}
            guard FileManager.default.fileExists(atPath:leases.appendingPathComponent(request.id+".active.json").path) else{throw BridgeError(code:"SIDECAR_LEASE",message:"참고 화면 작업의 소유권이 없습니다.")}
            model.sidecarRequest=nil
            for _ in 0..<200 {
                let a=(try? FileManager.default.contentsOfDirectory(atPath:jobs.path)) ?? [],b=(try? FileManager.default.contentsOfDirectory(atPath:leases.path)) ?? []
                if a.isEmpty&&b.isEmpty{break};try await Task.sleep(nanoseconds:25_000_000)
            }
            let remainingJobs=try FileManager.default.contentsOfDirectory(atPath:jobs.path),remainingLeases=try FileManager.default.contentsOfDirectory(atPath:leases.path)
            guard remainingJobs.isEmpty&&remainingLeases.isEmpty else{throw BridgeError(code:"SIDECAR_CLEANUP",message:"참고 화면의 임시 작업이 남았습니다.")}
            let after=try await model.bridge.call("view",["project_id":request.project,"report_id":request.report])
            guard try before==model.report.data(),try before==after.data(),try beforeDB==fileDigest(database) else{throw BridgeError(code:"SIDECAR_REPORT_MUTATION",message:"참고 화면이 저장된 결과를 변경했습니다.")}
            return ["renderer":"ONLYOFFICE Desktop Editors","native_pdfkit":true,"page":page["page"].int,"page_count":doc.pageCount,"pdf_sha256":pdfSHA,"report_and_database_unchanged":true,"owned_jobs_and_leases_removed":true]
        }catch{model.sidecarRequest=nil;_ = try? await model.bridge.call("sidecarClose",request.scope);throw error}
    }
    static func fileDigest(_ url:URL)throws->String {
        let file=try FileHandle(forReadingFrom:url);defer{try? file.close()};var digest=SHA256()
        while let bytes=try file.read(upToCount:1024*1024),!bytes.isEmpty{digest.update(data:bytes)}
        return digest.finalize().map{String(format:"%02x",$0)}.joined()
    }
    static func exerciseAspectRatios(_ model:AppModel,_ output:URL) async throws->[[String:Any]] {
        model.focus=true;model.pageMode="both";model.showChanges=false;model.inspector=false;model.tab="compare";try await model.updateChanges();try await Task.sleep(nanoseconds:650_000_000)
        // The first change can be one-sided (these pages intentionally differ).
        // Select both fixture pages through the same production navigation as
        // the page picker before measuring the two visible source canvases.
        for index in [model.from,model.to] {
            let revision=model.revision(index)
            guard let page=model.primaryPages(revision).first else{throw BridgeError(code:"ASPECT_PAGE",message:"비율 검증 원문이 없습니다.")}
            model.navigatePage(page["page_id"].string,in:revision["revision_occurrence_id"].string)
        }
        // Inspect the neutral page edge independently from the legitimate blue
        // selected-evidence overlay, which is covered by the evidence checks.
        model.selectedChangeID=nil
        try await Task.sleep(nanoseconds:650_000_000)
        func canvases(_ view:NSView)->[StructureCanvas.Canvas] {
            var found:[StructureCanvas.Canvas]=[];if let canvas=view as? StructureCanvas.Canvas{found.append(canvas)}
            for child in view.subviews{found += canvases(child)};return found
        }
        func checks(_ view:NSView)throws->[[String:Any]] {
            try canvases(view).map{canvas in
                let width=canvas.page["width"].number,height=canvas.page["height"].number,displayWidth=Double(canvas.bounds.width),displayHeight=Double(canvas.bounds.height)
                // AppKit aligns representable bounds to device pixels. Measure
                // absolute error in the shorter dimension, not a percentage of
                // a thin page's width (35.2pt can legitimately snap to35pt).
                let backingScale=Double(canvas.window?.backingScaleFactor ?? 1),tolerance=1/max(1,backingScale)
                let error=abs(displayWidth*height-displayHeight*width)/max(width,height)
                guard width>0,height>0,displayWidth>0,displayHeight>0,error.isFinite,error<=tolerance+0.000001 else{throw BridgeError(code:"ASPECT_STRETCHED",message:"실제 구조 보기의 페이지 비율이 원본과 다릅니다. 원본 \(width)×\(height), 화면 \(displayWidth)×\(displayHeight), 오차 \(error)pt")}
                return ["source_width":width,"source_height":height,"display_width":displayWidth,"display_height":displayHeight,"backing_scale":backingScale,"aspect_error_points":error,"pixel_rounding_tolerance_points":tolerance,"page_ratio_preserved":true]
            }
        }
        guard let window=NSApp.windows.first(where:{$0.isVisible && $0.contentView != nil}),let content=window.contentView else{throw BridgeError(code:"ASPECT_WINDOW",message:"페이지 비율 검증 창을 찾지 못했습니다.")}
        try capture(output.appendingPathComponent("native-aspect-main.png"))
        let main=try checks(content);try JSON(["canvases":main]).data().write(to:output.appendingPathComponent("aspect-main-bounds.json"));guard main.count==2,main.contains(where:{$0["source_width"] as? Double ?? 0 < ($0["source_height"] as? Double ?? 0)/10}),main.contains(where:{$0["source_width"] as? Double ?? 0 > ($0["source_height"] as? Double ?? 0)*10}) else{throw BridgeError(code:"ASPECT_FIXTURE",message:"세로·가로로 긴 두 원본 구조를 표시하지 못했습니다. \(main)")}
        let source=model.primaryPages(model.revision(0))[0],payload=try await model.page(source["page_id"].string);guard payload["source"]["kind"].string=="pptx",payload["page"]["preview"].isNull else{throw BridgeError(code:"ASPECT_STRUCTURE",message:"구조 보기 검증에 별도 PDF 렌더를 사용했습니다.")}
        model.openBundle(model.revision(0),source:source["page_id"].string);try await Task.sleep(nanoseconds:700_000_000)
        guard let sheet=window.sheets.first,let sheetContent=sheet.contentView else{throw BridgeError(code:"ASPECT_BUNDLE_SHEET",message:"긴 페이지의 제공 PDF 연결 창을 열지 못했습니다.")}
        let selected=try checks(sheetContent);guard selected.count==1 else{throw BridgeError(code:"ASPECT_BUNDLE_SOURCE",message:"연결 창의 독립 구조 원문을 확인하지 못했습니다.")};try captureView(sheet,output.appendingPathComponent("native-aspect-bundle.png"));model.bundleSheet=false;model.focus=false;model.showChanges=true;try await Task.sleep(nanoseconds:200_000_000)
        return main+selected
    }
    static func exerciseBundleMapping(_ model:AppModel,_ output:URL) async throws->[String:Any] {
        let project=model.projectID,original=model.report["report_id"].string,revision=model.revision(0),occurrence=revision["revision_occurrence_id"].string,sources=model.primaryPages(revision)
        guard sources.count>=2,model.isBundle(revision),let pdfAsset=revision["assets"].array.first(where:{$0["format"].string=="pdf"}) else{throw BridgeError(code:"BUNDLE_FIXTURE",message:"슬라이드 두 장 이상의 PPTX·PDF 묶음이 필요합니다.")}
        let source=sources[0]["page_id"].string,wrong=sources[1]["appearance"]["source_page_id"].string,correct=sources[0]["appearance"]["source_page_id"].string,reason="  사용자 확인 🧭\n문구가 다른 PDF 페이지도 사유와 경고를 보존  "
        guard !wrong.isEmpty,!correct.isEmpty else{throw BridgeError(code:"BUNDLE_AUTO_FIXTURE",message:"최초 자동 연결 두 쌍을 확인하지 못했습니다.")}
        let first=try await model.bundleContext(project:project,report:original,occurrence:occurrence)
        guard first["current_snapshot"].bool,first["mapping"].array.count>=2,first["revision"]["pages"].array.count>=4 else{throw BridgeError(code:"BUNDLE_CONTEXT",message:"실제 수정 화면의 연결 정보를 불러오지 못했습니다.")}
        model.openBundle(revision,source:source);try await Task.sleep(nanoseconds:700_000_000)
        guard model.bundleSheet,let sheet=NSApp.windows.compactMap({$0.sheets.first}).first else{throw BridgeError(code:"BUNDLE_NATIVE_SHEET",message:"제공 PDF 연결 창을 표시하지 못했습니다.")}
        try captureView(sheet,output.appendingPathComponent("native-bundle-before.png"));model.bundleSheet=false;try await Task.sleep(nanoseconds:200_000_000)
        let untouched=try await model.bundleContext(project:project,report:original,occurrence:occurrence)
        guard untouched["decision_count"].int==0,!model.project["dirty"].bool else{throw BridgeError(code:"BUNDLE_CANCEL_WRITE",message:"적용 전 닫은 창에서 이력이 바뀌었습니다.")}
        try await model.applyBundle(project:project,report:original,draftHash:first["draft_hash"].string,occurrence:occurrence,sourceAsset:sources[0]["asset_id"].string,pdfAsset:pdfAsset["asset_id"].string,source:source,pdf:wrong,action:"link",reason:reason)
        do{try await model.applyBundle(project:project,report:original,draftHash:first["draft_hash"].string,occurrence:occurrence,sourceAsset:sources[0]["asset_id"].string,pdfAsset:pdfAsset["asset_id"].string,source:source,pdf:correct,action:"link",reason:"오래된 요청 거부");throw BridgeError(code:"BUNDLE_STALE_ACCEPTED",message:"오래된 연결 변경을 허용했습니다.")}catch let e as BridgeError where e.code=="STALE_REPORT"{}
        await model.run(project);guard model.error.isEmpty else{throw BridgeError(code:"BUNDLE_LINK_ANALYSIS",message:model.error)}
        var currentReport=model.report["report_id"].string
        let linked=try await model.page(source),independent=try await model.bridge.call("page",["project_id":project,"report_id":currentReport,"page_id":source,"basis":"source"])
        guard linked["source"]["origin"].string=="reference_pdf",linked["page"]["appearance"]["association"].string=="human_confirmed",linked["page"]["appearance"]["reason"].string==reason,linked["display_page_number"].int==first["revision"]["pages"].array.first(where:{$0["page_id"].string==wrong})?["page"].int,independent["source"]["kind"].string=="pptx" else{throw BridgeError(code:"BUNDLE_SOURCE_AUTHORITY",message:"사용자 연결의 PDF 출처·원본 구분이 일치하지 않습니다.")}
        let context=try await model.bundleContext(project:project,report:currentReport,occurrence:occurrence)
        guard context["decision_count"].int==1,context["manual_states"].array.contains(where:{$0["source_page_id"].string==sources[1]["page_id"].string && $0["displaced"].bool}) else{throw BridgeError(code:"BUNDLE_DISPLACEMENT",message:"기존 연결의 해제 이력을 확인하지 못했습니다.")}
        model.openBundle(model.revision(0),source:source);try await Task.sleep(nanoseconds:650_000_000)
        guard let changedSheet=NSApp.windows.compactMap({$0.sheets.first}).first else{throw BridgeError(code:"BUNDLE_CHANGED_SHEET",message:"수정 후 연결 창을 표시하지 못했습니다.")};try captureView(changedSheet,output.appendingPathComponent("native-bundle-human.png"));model.bundleSheet=false;try await Task.sleep(nanoseconds:150_000_000)
        for (action,target,why) in [("unlink",Optional<String>.none,"사용자가 제공 PDF 연결 해제"),("link",Optional(correct),"올바른 PDF 페이지로 재연결")]{
            let state=try await model.bundleContext(project:project,report:currentReport,occurrence:occurrence)
            try await model.applyBundle(project:project,report:currentReport,draftHash:state["draft_hash"].string,occurrence:occurrence,sourceAsset:sources[0]["asset_id"].string,pdfAsset:pdfAsset["asset_id"].string,source:source,pdf:target,action:action,reason:why)
            await model.run(project);guard model.error.isEmpty else{throw BridgeError(code:"BUNDLE_REANALYSIS",message:model.error)};currentReport=model.report["report_id"].string
            let payload=try await model.page(source);guard action=="unlink" ? payload["source"]["origin"].string != "reference_pdf":payload["page"]["appearance"]["source_page_id"].string==correct else{throw BridgeError(code:"BUNDLE_UNLINK_RELINK",message:"연결 해제·재연결 결과가 다릅니다.")}
        }
        let history=try await model.bridge.call("bundleDecisions",["project_id":project,"report_id":currentReport,"revision_id":occurrence,"max_output_tokens":8000])
        guard history["items"].array.count==3,history["items"].array[0]["reason"].string==reason else{throw BridgeError(code:"BUNDLE_HISTORY",message:"연결 이유와 세 개의 이력을 확인하지 못했습니다.")}
        let old=try await model.bridge.call("view",["project_id":project,"report_id":original]);guard old["bundle_decision_count"].int==0 else{throw BridgeError(code:"BUNDLE_OLD_CHANGED",message:"이전 보고서의 이력이 변경되었습니다.")}
        let displaced=try await model.page(sources[1]["page_id"].string);guard displaced["source"]["origin"].string != "reference_pdf" else{throw BridgeError(code:"BUNDLE_DISPLACED_REFILLED",message:"해제된 슬라이드에 PDF가 자동으로 다시 연결되었습니다.")}
        await model.selectProject(project,snapshot:currentReport);guard model.report["bundle_decision_count"].int==3 else{throw BridgeError(code:"BUNDLE_REOPEN",message:"재조회 후 연결 이력이 다릅니다.")}
        guard let parent=NSApp.windows.first(where:{$0.isVisible && $0.contentView != nil}) else{throw BridgeError(code:"BUNDLE_HISTORY_WINDOW",message:"연결 이력 창을 표시하지 못했습니다.")}
        let finalContext=try await model.bundleContext(project:project,report:currentReport,occurrence:occurrence),activeIDs=Set(finalContext["manual_states"].array.filter{!$0["displaced"].bool}.map{$0["decision_id"].string})
        let historyWindow=NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:580),styleMask:[.titled,.closable],backing:.buffered,defer:false);historyWindow.contentView=NSHostingView(rootView:BundleHistorySheet(projectID:project,reportID:currentReport,occurrence:occurrence,activeDecisionIDs:activeIDs).environmentObject(model));parent.beginSheet(historyWindow,completionHandler:{_ in});try await Task.sleep(nanoseconds:500_000_000);try captureView(historyWindow,output.appendingPathComponent("native-bundle-history.png"));parent.endSheet(historyWindow);historyWindow.orderOut(nil)
        return ["original_report_id":original,"revision_occurrence_id":occurrence,"verbatim_first_reason":reason,"native_context_contract":true,"native_sheet_cancel_no_write":true,"stale_write_rejected":true,"source_and_pdf_preview_authority":true,"displaced_source_stays_unlinked":true,"append_only_link_unlink_relink":true,"old_snapshot_unchanged":true,"reopen_history_count":3,"interaction_scope":"production model/actions and rendered native sheets; no OS mouse/keyboard input automation"]
    }
    static func exerciseImportDraft(_ model:AppModel,_ output:URL,_ files:[URL]) async throws->[String:Any] {
        guard files.count==2 else{throw BridgeError(code:"IMPORT_FIXTURE",message:"가져오기 묶음 검증 파일이 필요합니다.")}
        let analysedProject=model.projectID,analysedReport=model.report["report_id"].string
        var rows=try files.map{try ImportRow.selected($0)}
        rows[0].label="초안 원본";rows[1].label="검토 화면";let original=rows
        guard ImportRow.group(&rows,at:1),ImportRow.ungroup(&rows,at:0),rows==original,ImportRow.group(&rows,at:1) else{throw BridgeError(code:"IMPORT_ROUNDTRIP",message:"묶기·해제 후 파일 정보가 달라졌습니다.")}
        rows[0].label="통합 검토본"
        guard let parent=NSApp.windows.first(where:{$0.isVisible && $0.contentView != nil}) else{throw BridgeError(code:"IMPORT_WINDOW",message:"가져오기 창을 표시할 수 없습니다.")}
        let sheet=NSWindow(contentRect:NSRect(x:0,y:0,width:900,height:500),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        sheet.contentView=NSHostingView(rootView:ImportView(initialRows:rows).environmentObject(model).background(Color(nsColor:.windowBackgroundColor)))
        parent.beginSheet(sheet,completionHandler:{_ in});try await Task.sleep(nanoseconds:500_000_000)
        do{try captureView(sheet,output.appendingPathComponent("native-import-bundle.png"))}catch{parent.endSheet(sheet);sheet.orderOut(nil);throw error}
        parent.endSheet(sheet);sheet.orderOut(nil)
        guard ImportRow.ungroup(&rows,at:0),rows.map(\.id)==original.map(\.id),rows.map(\.label)==["통합 검토본",original[1].label],ImportRow.group(&rows,at:1) else{throw BridgeError(code:"IMPORT_EDITED_LABEL",message:"묶음 이름과 파일 순서 보존 실패")}
        let count=try await model.bridge.call("projects").array.count
        let created=try await model.create(title:"묶음 가져오기 동작 검증",rows:rows)
        guard created["revisions"].array.count==1,created["revisions"].array[0]["files"].array.count==2 else{throw BridgeError(code:"IMPORT_CREATE",message:"묶은 원본 두 개를 가져오지 못했습니다.")}
        var mixed=[try ImportRow.selected(files[0]),ImportRow(label:"내부 호환 입력",urls:[files[1]])]
        guard ImportRow.group(&mixed,at:1) else{throw BridgeError(code:"IMPORT_MIXED_GROUP",message:"검증 정보가 다른 파일 묶기 실패")}
        let mixedCreated=try await model.create(title:"파일별 검증 전달 확인",rows:mixed)
        guard mixedCreated["revisions"].array[0]["files"].array.count==2 else{throw BridgeError(code:"IMPORT_MIXED_SERIALIZATION",message:"파일별 검증 정보를 전달하지 못했습니다.")}
        let changed=output.appendingPathComponent("selected-then-changed.pdf");try Data("abc".utf8).write(to:changed)
        let picked=try ImportRow.selected(changed);try Data("abd".utf8).write(to:changed)
        do{_ = try await model.create(title:"변경 파일 거부 검증",rows:[picked]);throw BridgeError(code:"IMPORT_MUTATION_ACCEPTED",message:"선택 후 변경된 파일을 허용했습니다.")}
        catch let e as BridgeError where e.code=="SOURCE_CHANGED" {}
        guard try await model.bridge.call("projects").array.count==count+2 else{throw BridgeError(code:"IMPORT_REJECT_WRITE",message:"거절한 가져오기가 프로젝트를 바꿨습니다.")}
        try await model.refresh()
        guard model.projectID==analysedProject,model.report["report_id"].string==analysedReport else{throw BridgeError(code:"IMPORT_CHANGED_SELECTION",message:"가져오기 검증이 기존 보고서 선택을 바꿨습니다.")}
        return ["mixed_nullable_identity_serialized_through_native_bridge":true,"analysed_project_and_report_unchanged":true,"group_ungroup_id_label_order_roundtrip":true,"edited_group_label_retained":true,"selected_sha_bundle_create":true,"changed_source_rejected_without_project":true,"actual_native_sheet_capture":true,"interaction_scope":"production model/actions and rendered native sheet; no OS input automation"]
    }
    static func exerciseReferenceAppearance(_ model:AppModel) async throws->[String:Any] {
        var references=0
        for revision in model.revisions {for page in model.primaryPages(revision) where !page["appearance"].isNull {
            let payload=try await model.bridge.call("page",["project_id":model.projectID,"report_id":model.report["report_id"].string,"page_id":page["page_id"].string])
            guard payload["source"]["origin"].string=="reference_pdf",payload["page"]["preview"].isNull,payload["page"]["raster"].isNull,payload["display_page"]["asset_id"].string==page["appearance"]["asset_id"].string,payload["display_page_number"].int==payload["page"]["appearance"]["page"].int else{throw BridgeError(code:"REFERENCE_SOURCE",message:"제공 PDF의 원본·페이지 근거가 일치하지 않습니다.")}
            references+=1
        }}
        guard references>0,model.revisions.count>=2 else{throw BridgeError(code:"REFERENCE_MISSING",message:"제공 PDF 대응이 없습니다.")}
        model.tab="compare";model.from=0;model.to=1;try await model.updateChanges()
        guard let visual=model.changes.first(where:{$0["kind"].string=="visual_region_changed" || $0["coverage_gaps"].array.contains(where:{$0["reason"].string=="reference_pdf_changed_without_pptx_source_change"})}) else{throw BridgeError(code:"REFERENCE_VISUAL",message:"제공 PDF의 화면 차이 근거가 없습니다.")}
        model.selectedChangeID=visual["change_id"].string;model.selectEvidence()
        guard model.primaryPages(model.revision(0)).contains(where:{$0["page_id"].string==model.leftPageID}),model.primaryPages(model.revision(1)).contains(where:{$0["page_id"].string==model.rightPageID}),visual["appearance_assessment"].string=="inferred",visual["evidence"].array.allSatisfy({$0["method"].string=="provided_pdf_native_raster"}) else{throw BridgeError(code:"REFERENCE_NAVIGATION",message:"PDF 화면 근거에서 원본 슬라이드로 이동하지 못했습니다.")}
        model.leftPageID="";model.rightPageID=""
        for evidence in visual["evidence"].array {model.navigateEvidence(evidence)}
        model.selectEvidence()
        guard model.primaryPages(model.revision(0)).contains(where:{$0["page_id"].string==model.leftPageID}),model.primaryPages(model.revision(1)).contains(where:{$0["page_id"].string==model.rightPageID}) else{throw BridgeError(code:"REFERENCE_BUTTON_NAVIGATION",message:"근거 버튼에서 원본 슬라이드로 이동하지 못했습니다.")}
        for id in [model.leftPageID,model.rightPageID]{let payload=try await model.page(id);guard payload["source"]["origin"].string=="reference_pdf" else{throw BridgeError(code:"REFERENCE_BUTTON_SOURCE",message:"근거 버튼 이동 후 PDF 화면을 열지 못했습니다.")}}
        return ["reference_pages":references,"hash_verified_pdf_source":true,"source_slide_navigation":true,"evidence_button_navigation":true,"visual_association_inferred":true,"source_unchanged_reference_difference_withheld":visual["kind"].string=="coverage_gap"]
    }
    static func exerciseManualRelations(_ model:AppModel,_ output:URL) async throws -> [String] {
        let project=model.projectID,original=model.report["report_id"].string
        let a=model.primaryPages(model.revision(0)),b=model.primaryPages(model.revision(1)),c=model.primaryPages(model.revision(2))
        guard a.count==2 && b.count==3 && c.count==2 else { throw BridgeError(code:"MANUAL_FIXTURE",message:"분할·병합 검증 문서가 다릅니다.") }
        try await model.applyRelation(project:project,report:original,draftHash:model.report["draft_hash"].string,before:model.revision(0)["revision_occurrence_id"].string,after:model.revision(1)["revision_occurrence_id"].string,left:[a[0]["page_id"].string],right:[b[0]["page_id"].string,b[1]["page_id"].string],kind:"split",reason:"원문 확인: 전략 페이지를 설계·구현으로 분할")
        await model.run(project)
        guard model.error.isEmpty else { throw BridgeError(code:"MANUAL_SPLIT",message:model.error) }
        try await model.applyRelation(project:project,report:model.report["report_id"].string,draftHash:model.report["draft_hash"].string,before:model.revision(1)["revision_occurrence_id"].string,after:model.revision(2)["revision_occurrence_id"].string,left:[b[0]["page_id"].string,b[1]["page_id"].string],right:[c[0]["page_id"].string],kind:"merge",reason:"원문 확인: 설계·구현 페이지를 다시 병합")
        await model.run(project)
        guard model.error.isEmpty && model.report["mapping_relations"].array.count==2 else { throw BridgeError(code:"MANUAL_MERGE",message:model.error.isEmpty ? "확정 관계 저장 실패":model.error) }
        model.from=0;model.to=max(0,model.revisions.count-1);model.tab="history"
        async let first:Void=model.updateChanges();async let second:Void=model.updateChanges();_=try await(first,second)
        guard model.changes.filter({$0["kind"].string=="page_split"}).count==1 && model.changes.filter({$0["kind"].string=="page_merged"}).count==1 else { throw BridgeError(code:"MANUAL_EVENTS",message:"분할·병합 이벤트 조회 실패") }
        try await Task.sleep(nanoseconds:300_000_000);try capture(output.appendingPathComponent("native-manual-history.png"))
        for page in b.prefix(2) { model.openHistoryPage(1,page["page_id"].string);try await Task.sleep(nanoseconds:250_000_000);guard model.rightPageID==page["page_id"].string else { throw BridgeError(code:"MANUAL_BRANCH_NAVIGATION",message:"분기 원문 선택이 초기화됐습니다.") } }
        model.from=0;model.to=1;model.tab="compare";try await model.updateChanges();model.inspector=true
        let split=model.changes.first { $0["kind"].string=="page_split" }!;model.chooseChange(split["change_id"].string)
        try await Task.sleep(nanoseconds:250_000_000);model.mappingSheet=true;try await Task.sleep(nanoseconds:500_000_000)
        guard let sheet=NSApp.windows.compactMap({$0.sheets.first}).first else { throw BridgeError(code:"MANUAL_SHEET",message:"네이티브 대응 수정 창을 표시하지 못했습니다.") }
        try captureView(sheet,output.appendingPathComponent("native-relations-sheet.png"));model.mappingSheet=false
        let reports=try await model.bridge.call("reports",["project_id":project]).array
        guard reports.count==3 else { throw BridgeError(code:"MANUAL_CANCEL",message:"적용하지 않은 창에서 보고서가 바뀌었습니다.") }
        let old=try await model.bridge.call("view",["project_id":project,"report_id":original])
        guard old["mapping_relations"].array.isEmpty else { throw BridgeError(code:"MANUAL_IMMUTABILITY",message:"과거 보고서의 대응이 바뀌었습니다.") }
        return ["concurrent same-range awaits settle the immutable history response","native model split + merge persisted in3 immutable reports","every branch opens without async selection reset","actual paired native sheet rendered and dismissed without writes","original snapshot retains original topology"]
    }
    static func exerciseLayout(_ model:AppModel,layout:WorkspaceLayoutStore,output:URL) async throws->[String:Any] {
        let originalLayout=layout.configuration,originalZoom=model.zoom
        defer{layout.update{$0=originalLayout};model.zoom=originalZoom}
        model.zoom=1.5
        let chromeChecks=try await exerciseDocumentChrome(model,layout:layout,output:output)
        layout.reset();layout.update{$0.changesDock = .bottom};model.tab="compare";model.focus=false;model.showChanges=true;try await model.updateChanges()
        try await Task.sleep(nanoseconds:300_000_000)
        func pane(_ view:NSView)->NSSplitView? {
            if let split=view as? NSSplitView,split.identifier?.rawValue=="Reviset.workspace.document.changes" {return split}
            for child in view.subviews {if let split=pane(child){return split}};return nil
        }
        func current()throws->NSSplitView {
            for window in NSApp.windows where window.isVisible {if let content=window.contentView,let split=pane(content){return split}}
            throw BridgeError(code:"LAYOUT_SPLIT",message:"네이티브 문서·변경 분할 창을 찾지 못했습니다.")
        }
        let split=try current(),initial=split.arrangedSubviews[1].frame.height,canvas=split.arrangedSubviews[0].frame.height
        guard abs(initial-140)<2 && canvas>initial else {throw BridgeError(code:"LAYOUT_DEFAULT",message:"문서 영역의 기본 높이가 충분하지 않습니다: \(canvas), \(initial)")}
        var responder:NSResponder?=split.nextResponder
        var resizer:WorkspacePaneSizing?
        while let candidate=responder {
            if let sizing=candidate as? WorkspacePaneSizing,sizing.splitView === split {resizer=sizing;break}
            responder=candidate.nextResponder
        }
        guard let resizer else{throw BridgeError(code:"LAYOUT_CONTROLLER",message:"The native layout controller is unavailable.")}
        resizer.resizeAuxiliary(to:initial+40,commit:true);split.layoutSubtreeIfNeeded();try await Task.sleep(nanoseconds:100_000_000)
        let resized=split.arrangedSubviews[1].frame.height
        guard resized>=initial+35 else{throw BridgeError(code:"LAYOUT_DRAG",message:"네이티브 분할선으로 변경 목록 크기를 바꾸지 못했습니다.")}
        model.showChanges=false;try await Task.sleep(nanoseconds:150_000_000);model.showChanges=true;try await Task.sleep(nanoseconds:250_000_000)
        let reopened=try current(),remembered=reopened.arrangedSubviews[1].frame.height
        guard abs(remembered-resized)<2 else{throw BridgeError(code:"LAYOUT_MEMORY",message:"변경 목록 높이 유지 실패: 조절 \(resized), 다시 열기 \(remembered), 저장 \(WorkspaceGeometryPreferences.height("Docver.workspace.compare.changesHeight") ?? -1)")}
        resizer.resizeAuxiliary(to:initial,commit:true)
        func pdfs(_ view:NSView)->[PDFView] {var result=(view as? PDFView).map{[$0]} ?? [];for child in view.subviews{result+=pdfs(child)};return result}
        guard let window=split.window,let content=window.contentView else{throw BridgeError(code:"LAYOUT_WINDOW",message:"The source window is unavailable.")}
        model.zoom=1.5;try await Task.sleep(nanoseconds:400_000_000)
        let originalPDFs=pdfs(content),pdfIdentities=Set(originalPDFs.map(ObjectIdentifier.init))
        let pdfFacts=originalPDFs.map{pdf in (pdf,pdf.document,pdf.currentPage,pdf.scaleFactor)}
        let project=model.projectID,report=model.report["report_id"].string,selected=model.selectedChangeID,left=model.leftPageID,right=model.rightPageID
        var captures:[String]=[],checks=0,geometry:[[String:Any]]=[]
        func qualify(_ name:String)async throws {
            try await Task.sleep(nanoseconds:300_000_000);content.layoutSubtreeIfNeeded()
            guard model.projectID==project,model.report["report_id"].string==report,model.selectedChangeID==selected,model.leftPageID==left,model.rightPageID==right,model.zoom==1.5,Set(pdfs(content).map(ObjectIdentifier.init))==pdfIdentities else{throw BridgeError(code:"LAYOUT_STATE",message:"A layout change replaced source views or changed the selected report/page/evidence.")}
            for (pdf,document,page,scale) in pdfFacts {
                guard pdf.document === document,pdf.currentPage === page,abs(pdf.scaleFactor-scale)<0.001 else{throw BridgeError(code:"LAYOUT_PDF_STATE",message:"A layout change replaced the PDF document or reset its page/zoom.")}
            }
            if layout.configuration.changesVisible {
                let split=try current(),dock=layout.configuration.changesDock
                guard split.arrangedSubviews.count==2 else{throw BridgeError(code:"LAYOUT_GEOMETRY",message:"The native change/source split has missing panes.")}
                let auxiliary=split.arrangedSubviews[dock == .left ? 0:1],source=split.arrangedSubviews[dock == .left ? 1:0]
                let available=(dock == .bottom ? split.bounds.height:split.bounds.width)-split.dividerThickness
                let minimum:CGFloat=dock == .bottom ? 110:260
                let requested=CGFloat(dock == .bottom ? layout.configuration.changesHeight:layout.configuration.changesWidth)
                let expected=min(max(minimum,requested),max(minimum,available-240))
                let actual=dock == .bottom ? auxiliary.frame.height:auxiliary.frame.width,sourceExtent=dock == .bottom ? source.frame.height:source.frame.width
                guard abs(actual-expected)<2,sourceExtent>=239 else{throw BridgeError(code:"LAYOUT_GEOMETRY",message:"Dock \(dock.rawValue) has actual \(actual), preferred/clamped \(expected), source \(sourceExtent).")}
                geometry.append(["action":name,"dock":dock.rawValue,"available":available,"changes_actual":actual,"changes_expected":expected,"source_extent":sourceExtent])
            }
            let file="native-layout-"+LanguagePreferences.shared.effectiveLanguage+"-"+name+".png"
            try captureView(window,output.appendingPathComponent(file));captures.append(file);checks+=1
        }
        for preset in WorkspaceLayoutPreset.allCases {layout.apply(preset);try await qualify(preset.rawValue)}
        for dock in [WorkspaceChangesDock.left,.right] {
            layout.apply(.review);layout.update{$0.changesDock=dock;$0.inspectorDock=dock == .left ? .right:.left}
            try await qualify("changes-"+dock.rawValue)
        }
        layout.apply(.balanced);layout.update{$0.pageArrangement = .vertical};try await qualify("stacked")
        layout.reset()
        return ["document_chrome_checks":chromeChecks,"default_change_pane_points":initial,"default_document_pane_points":canvas,"resized_change_pane_points":resized,"reopened_change_pane_points":remembered,"native_divider_and_height_reopen":true,"existing_snapshot_reopen":!model.report.isNull,"custom_layout_transitions":checks,"actual_dock_geometry":geometry,"retained_pdf_views":originalPDFs.count,"report_selection_page_zoom_and_pdf_identity_preserved":true,"captures":captures,"interaction_scope":"production layout actions and native public AppKit geometry; no OS gestures; PDF viewport may clamp naturally when its available size changes"]
    }
    private static func exerciseDocumentChrome(_ model:AppModel,layout:WorkspaceLayoutStore,output:URL)async throws->Int {
        var checks=0,observations:[[String:Any]]=[]
        func check(_ action:String,focused:Bool)async throws {
            try await Task.sleep(nanoseconds:180_000_000)
            let names=Set(NSApp.windows.compactMap(\.contentView).flatMap{workspaceLayoutMarkers(in:$0)}.compactMap{$0.identifier?.rawValue})
            let report=names.contains("Reviset.document.reportBar"),versions=names.contains("Reviset.document.versionBar")
            guard layout.isFocused==focused,model.focus==focused,report,versions else{throw BridgeError(code:"LAYOUT_REPORT_CHROME",message:"A panel or Focus action incorrectly changed the report/history controls or explicit focus state.")}
            observations.append(["tab":model.tab,"action":action,"focused":focused,"report_bar":report,"history_version_bar":versions])
            checks+=1
        }
        for tab in ["compare","history"] {
            model.tab=tab
            for preset in WorkspaceLayoutPreset.allCases {layout.apply(preset);try await check(preset.rawValue,focused:preset == .focus)}
            layout.reset();layout.update{$0.sidebarVisible=false};try await check("projects hidden",focused:false)
            layout.update{$0.sidebarVisible=true};try await check("projects shown",focused:false)
            layout.update{$0.sidebarWidth=279;$0.changesDock = .right;$0.changesWidth=389;$0.changesHeight=233;$0.inspectorVisible=false;$0.inspectorDock = .left;$0.inspectorWidth=341;$0.pageArrangement = .vertical;$0.pageFraction=0.37}
            layout.update{$0.sidebarVisible=false};layout.update{$0.changesVisible=false}
            try await check("manually all panels hidden",focused:false)
            let hidden=layout.configuration,hiddenBytes=WorkspaceLayoutPreferences.data(.document),reloaded=WorkspaceLayoutStore(scope:.document)
            guard !reloaded.isFocused,reloaded.configuration==hidden else{throw BridgeError(code:"LAYOUT_HIDDEN_RELOAD",message:"An independently hidden layout reopened as Focus.")}
            if let window=NSApp.windows.first(where:{$0.isVisible && $0.contentView != nil}) {try captureView(window,output.appendingPathComponent("native-layout-"+LanguagePreferences.shared.effectiveLanguage+"-manual-hidden-"+tab+".png"))}
            for cycle in 1...2 {
                layout.toggleFocus();try await check("all-hidden Focus on \(cycle)",focused:true)
                layout.update{$0.sidebarVisible=false};layout.update{$0.changesVisible=false};layout.update{$0.inspectorVisible=false}
                guard layout.isFocused,layout.configuration==hidden,WorkspaceLayoutPreferences.data(.document)==hiddenBytes else{throw BridgeError(code:"LAYOUT_HIDDEN_FOCUS",message:"Equal-geometry Focus entry or no-op synchronization changed the retained layout.")}
                layout.toggleFocus();try await check("all-hidden Focus restored \(cycle)",focused:false)
                guard layout.configuration==hidden,WorkspaceLayoutPreferences.data(.document)==hiddenBytes else{throw BridgeError(code:"LAYOUT_HIDDEN_RESTORE",message:"Leaving Focus replaced an independently hidden custom layout or its persisted bytes.")}
            }
            layout.update{$0.sidebarVisible=true;$0.changesVisible=true;$0.inspectorVisible=true}
            try await check("custom geometry before Focus",focused:false)
            let before=layout.configuration,report=model.report["report_id"].string,selection=[model.projectID,model.selectedChangeID,model.leftPageID,model.rightPageID],zoom=model.zoom
            func pdfs(_ view:NSView)->[PDFView] {(view as? PDFView).map{[$0]} ?? view.subviews.flatMap(pdfs)}
            let sources=NSApp.windows.compactMap(\.contentView).flatMap(pdfs).map{($0,$0.document,$0.currentPage,$0.scaleFactor)}
            guard tab != "compare" || sources.count==2 else{throw BridgeError(code:"LAYOUT_FOCUS_SOURCE_COUNT",message:"Two live source PDF views are required for focused geometry qualification.")}
            func retainedSources()throws {
                guard model.report["report_id"].string==report,[model.projectID,model.selectedChangeID,model.leftPageID,model.rightPageID]==selection,model.zoom==zoom else{throw BridgeError(code:"LAYOUT_FOCUS_SELECTION",message:"Editing focused geometry changed the report or selected source evidence.")}
                let current=NSApp.windows.compactMap(\.contentView).flatMap(pdfs)
                guard current.count==sources.count else{throw BridgeError(code:"LAYOUT_FOCUS_HOST",message:"Editing focused geometry replaced source hosts.")}
                for (pdf,document,page,scale) in sources {guard current.contains(where:{$0 === pdf}),pdf.document === document,pdf.currentPage === page,abs(pdf.scaleFactor-scale)<0.001 else{throw BridgeError(code:"LAYOUT_FOCUS_PDF",message:"Editing focused geometry replaced the PDF or changed its page/zoom.")}}
            }
            layout.toggleFocus();try await check("geometry Focus on",focused:true)
            layout.update{$0.pageFraction=0.63;$0.pageArrangement = .horizontal;$0.sidebarWidth=301;$0.changesDock = .left;$0.changesWidth=417;$0.inspectorWidth=355}
            var merged=before;merged.pageFraction=0.63;merged.pageArrangement = .horizontal;merged.sidebarWidth=301;merged.changesDock = .left;merged.changesWidth=417;merged.inspectorWidth=355
            try await check("geometry edited during Focus",focused:true);try retainedSources()
            guard layout.saveCurrent(named:"Focus QA "+tab),let named=layout.saved.last,named.configuration==merged else{throw BridgeError(code:"LAYOUT_FOCUS_NAMED_SAVE",message:"Saving during Focus captured transient hidden panels instead of the retained arrangement.")}
            try await check("named layout saved during Focus",focused:true);try retainedSources()
            let stored=WorkspaceLayoutStore(scope:.document),mergedBytes=WorkspaceLayoutPreferences.data(.document)
            guard !stored.isFocused,stored.configuration==merged,stored.saved.contains(named) else{throw BridgeError(code:"LAYOUT_FOCUS_PERSIST",message:"A focused geometry edit or named save persisted transient hidden panels or lost the retained arrangement.")}
            layout.toggleFocus();try await check("edited geometry restored",focused:false);try retainedSources()
            guard layout.configuration==merged,WorkspaceLayoutPreferences.data(.document)==mergedBytes else{throw BridgeError(code:"LAYOUT_FOCUS_GEOMETRY",message:"Focus exit lost the edited geometry or rewrote its persisted bytes.")}
            layout.apply(.balanced);layout.apply(named)
            try await check("focused named layout reapplied",focused:false);try retainedSources()
            guard layout.configuration==merged else{throw BridgeError(code:"LAYOUT_FOCUS_NAMED_APPLY",message:"Reapplying the focused named layout lost retained visibility or geometry.")}
            layout.remove(named.id)
            let panels:[(String,WritableKeyPath<WorkspaceLayoutConfiguration,Bool>)]=[("projects",\.sidebarVisible),("changes",\.changesVisible),("evidence",\.inspectorVisible)]
            for allHidden in [false,true] {
                for (name,panel) in panels {
                    var baseline=merged;baseline.sidebarVisible = !allHidden;baseline.changesVisible = !allHidden;baseline.inspectorVisible = !allHidden
                    layout.update{$0=baseline};layout.toggleFocus()
                    try await check("visibility \(name) Focus on, previously hidden \(allHidden)",focused:true);try retainedSources()
                    layout.update{$0.pageFraction=0.57;$0.changesDock = .right;$0.changesHeight=247}
                    layout.update{$0[keyPath:panel].toggle();$0.inspectorWidth=367}
                    var expected=baseline;expected[keyPath:panel]=true;expected.pageFraction=0.57;expected.changesDock = .right;expected.changesHeight=247;expected.inspectorWidth=367
                    try await check("Focus opens \(name), previously hidden \(allHidden)",focused:false);try retainedSources()
                    let reopened=WorkspaceLayoutStore(scope:.document)
                    guard !reopened.isFocused,layout.configuration==expected,reopened.configuration==expected else{throw BridgeError(code:"LAYOUT_FOCUS_VISIBILITY",message:"Opening a panel from Focus discarded unrelated retained panels or edited geometry.")}
                }
            }
        }
        try JSON(["checks":checks,"manual_all_hidden_remains_nonfocus":true,"equal_geometry_focus_published_and_restored":true,"focused_geometry_merges_into_persisted_baseline":true,"focused_visibility_exit_merges_only_changed_flags":true,"focused_named_save_reload_and_apply_retain_baseline":true,"report_selection_pdf_identity_page_and_zoom_retained":true,"observations":observations,"viewport_scope":"existing native hosts remain; viewport may clamp naturally when pane dimensions change","interaction_scope":"production model/layout actions and AppKit content; no OS gestures"]).data().write(to:output.appendingPathComponent("document-chrome-observations.json"))
        return checks
    }
    private static func documentLockProbe(_ model:AppModel,request:JSON,output:URL)async throws {
        let database=model.bridge.library.appendingPathComponent("docver.sqlite"),before=try fileDigest(database)
        func assetDigests()throws->[String:String] {
            let folder=model.bridge.library.appendingPathComponent("assets")
            return try Dictionary(uniqueKeysWithValues:FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil).filter{$0.lastPathComponent.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil}.map{($0.lastPathComponent,try fileDigest($0))})
        }
        let assetsBefore=try assetDigests()
        try await Task.sleep(nanoseconds:350_000_000)
        let windows=NSApp.windows.filter{$0.isVisible && $0.contentView != nil}
        let markers=windows.compactMap(\.contentView).flatMap{workspaceLayoutMarkers(in:$0)}
        guard let sidebar=markers.first(where:{$0.identifier?.rawValue=="Reviset.document.sidebar"}),let window=sidebar.window else{throw BridgeError(code:"LOCK_DOCUMENT_VIEW",message:"The actual document sidebar is unavailable.")}
        var visited=Set<ObjectIdentifier>(),buttons:[NSAccessibilityProtocol]=[]
        func visit(_ element:NSAccessibilityProtocol) {
            guard visited.count<10_000,visited.insert(ObjectIdentifier(element as AnyObject)).inserted else{return}
            if ["Reviset.document.import.plus","Reviset.document.import.sidebar"].contains(element.accessibilityIdentifier()) {buttons.append(element)}
            for child in element.accessibilityChildren() ?? [] {if let accessible=child as? NSAccessibilityProtocol {visit(accessible)}}
        }
        visit(window)
        // SwiftUI's semantic AX identifiers are not materialized by a closed
        // in-process AX tree. Observe each actual Button label's environment,
        // then corroborate the top plus import action with its physical native button.
        let expected=Set(["Reviset.document.import.environment.plus","Reviset.document.import.environment.sidebar"])
        let imports=markers.filter{expected.contains($0.identifier?.rawValue ?? "")}
        let disabled=Set(imports.compactMap{$0.identifier?.rawValue})==expected && imports.count==2 && imports.allSatisfy{!$0.contentEnabled}
        var ancestor:NSView?=imports.first(where:{$0.identifier?.rawValue=="Reviset.document.import.environment.plus"}),nativeButton:NSButton?
        while let view=ancestor {if let button=view as? NSButton {nativeButton=button;break};ancestor=view.superview}
        let nativeDisabled=nativeButton.map{!$0.isEnabled} ?? false
        let localeMatches=imports.allSatisfy{$0.contentLocale.identifier==LanguagePreferences.shared.localizer.locale.identifier}
        let unchanged=try fileDigest(database)==before
        let assetsUnchanged=try assetDigests()==assetsBefore
        let facts:[String:Any]=["library_lock_denied":!model.libraryAvailable,"initialization_settled":!model.initializing,"sidebar_environment_disabled":!sidebar.contentEnabled,"import_controls_disabled":disabled,"disabled_import_controls":imports.filter{!$0.contentEnabled}.count,"native_plus_import_button_found":nativeButton != nil,"native_plus_import_button_disabled":nativeDisabled,"database_bytes_unchanged":unchanged,"source_assets_unchanged":assetsUnchanged,"hosted_locale":sidebar.contentLocale.identifier,"import_locales_match_scene":localeMatches,"ax_import_identifiers_observed":buttons.count,"observation_scope":"two actual Button-label environment markers and physical top-plus sidebar import NSButton; semantic AX identifiers and OS gestures are not qualified"]
        try JSON(facts).data().write(to:output.appendingPathComponent("lock-observation.json"))
        try captureView(window,output.appendingPathComponent("native-document-library-locked.png"))
        guard !model.libraryAvailable,!model.initializing,!sidebar.contentEnabled,disabled,nativeDisabled,localeMatches,unchanged,assetsUnchanged else{throw BridgeError(code:"LOCK_DOCUMENT_CONTROLS",message:"The locked document controls, hosted environment or immutable library bytes failed validation; see lock-observation.json.")}
        try JSON(["completed":true,"checks":facts,"smoke_invocation_id":request["smoke_invocation_id"].string,"interaction_scope":"actual second app process, two production Button-label environments and physical top-plus sidebar import NSButton; no OS AX/gesture or VoiceOver automation"]).data().write(to:output.appendingPathComponent("validation.json"))
    }
    static func captureView(_ window:NSWindow,_ url:URL) throws {
        guard let view=window.contentView,let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) else { throw BridgeError(code:"CAPTURE_FAILED",message:"앱 화면을 캡처할 수 없습니다.") }
        view.cacheDisplay(in:view.bounds,to:bitmap)
        guard let png=bitmap.representation(using:.png,properties:[:]) else { throw BridgeError(code:"CAPTURE_FAILED",message:"PNG 생성 실패") };try png.write(to:url)
    }
    static func capture(_ url:URL) throws {
        guard let window=NSApp.windows.first(where:{$0.isVisible && $0.contentView != nil}),let view=window.contentView,let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) else{throw BridgeError(code:"CAPTURE_FAILED",message:"앱 화면을 캡처할 수 없습니다.")}
        view.cacheDisplay(in:view.bounds,to:bitmap)
        guard let png=bitmap.representation(using:.png,properties:[:]) else{throw BridgeError(code:"CAPTURE_FAILED",message:"PNG 생성 실패")};try png.write(to:url)
    }
}
