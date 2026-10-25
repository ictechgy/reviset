import SwiftUI
import AppKit
import Combine
import CoreFoundation

enum WorkspaceLayoutScope:String,Codable {case document,workbook}
enum WorkspaceChangesDock:String,Codable,CaseIterable {case bottom,left,right}
enum WorkspaceInspectorDock:String,Codable,CaseIterable {case left,right}
enum WorkspacePageArrangement:String,Codable,CaseIterable {case horizontal,vertical}
enum WorkspaceLayoutPreset:String,CaseIterable {case sourceFirst,balanced,focus,review}

struct WorkspaceLayoutConfiguration:Codable,Equatable {
    var sidebarVisible=true
    var sidebarWidth:Double=220
    var changesVisible=true
    var changesDock=WorkspaceChangesDock.bottom
    var changesHeight:Double=140
    var changesWidth:Double=320
    var inspectorVisible=false
    var inspectorDock=WorkspaceInspectorDock.right
    var inspectorWidth:Double=300
    var pageArrangement=WorkspacePageArrangement.horizontal
    var pageFraction:Double=0.5
    var isValid:Bool {
        sidebarWidth.isFinite && (180...380).contains(sidebarWidth) && changesHeight.isFinite && (110...600).contains(changesHeight) && changesWidth.isFinite && (260...600).contains(changesWidth) && inspectorWidth.isFinite && (260...480).contains(inspectorWidth) && pageFraction.isFinite && (0.2...0.8).contains(pageFraction)
    }
    static func preset(_ preset:WorkspaceLayoutPreset,scope:WorkspaceLayoutScope)->Self {
        var value=Self();value.inspectorVisible=scope == .workbook;value.changesHeight=scope == .workbook ? 200:140
        switch preset {
        case .sourceFirst:value.sidebarVisible=false;value.inspectorVisible=false;value.changesDock = .left;value.changesWidth=280
        case .balanced:break
        case .focus:value.sidebarVisible=false;value.inspectorVisible=false;value.changesVisible=false
        case .review:value.sidebarVisible=false;value.inspectorVisible=true;value.changesHeight=260
        }
        return value
    }
}
struct SavedWorkspaceLayout:Codable,Equatable,Identifiable {
    let id:UUID
    let name:String
    let configuration:WorkspaceLayoutConfiguration
}
private struct WorkspaceLayoutEnvelope:Codable {
    let schemaVersion:Int
    let current:WorkspaceLayoutConfiguration
    let saved:[SavedWorkspaceLayout]
}
// These preferences contain UI geometry only. Test libraries never touch the user's defaults.
@MainActor enum WorkspaceLayoutPreferences {
    private static var testData:[String:Data]=[:]
    static func key(_ scope:WorkspaceLayoutScope)->String {"Reviset.workspaceLayout.v1."+scope.rawValue}
    static func data(_ scope:WorkspaceLayoutScope)->Data? {
        let key=key(scope)
        return ProcessInfo.processInfo.environment["DOCVER_TEST_USER_DATA"] == nil ? UserDefaults.standard.data(forKey:key):testData[key]
    }
    static func save(_ data:Data,scope:WorkspaceLayoutScope) {
        let key=key(scope)
        if ProcessInfo.processInfo.environment["DOCVER_TEST_USER_DATA"] == nil {UserDefaults.standard.set(data,forKey:key)} else {testData[key]=data}
    }
}
@MainActor final class WorkspaceLayoutStore:ObservableObject {
    let scope:WorkspaceLayoutScope
    @Published private(set) var configuration:WorkspaceLayoutConfiguration
    @Published private(set) var saved:[SavedWorkspaceLayout]=[]
    // Focus is a reversible session action. An independently hidden set of
    // panels remains a normal layout, including after preference reload.
    @Published private(set) var isFocused=false
    @Published var settingsPresented=false
    private(set) var persistenceReadOnly=false
    private var preFocusConfiguration:WorkspaceLayoutConfiguration?
    init(scope:WorkspaceLayoutScope) {
        self.scope=scope
        configuration = .preset(.sourceFirst,scope:scope)
        if let data=WorkspaceLayoutPreferences.data(scope) {
            if data.count>65_536 || Self.excessivelyNested(data) {persistenceReadOnly=true}
            else if let object=try? JSONSerialization.jsonObject(with:data) as? [String:Any],Self.currentSchema(object["schemaVersion"]) {
                configuration=Self.recoveredConfiguration(object["current"],scope:scope) ?? configuration
                for case let entry as [String:Any] in object["saved"] as? [Any] ?? [] {
                    guard saved.count<12,let rawID=entry["id"] as? String,let id=UUID(uuidString:rawID),let name=entry["name"] as? String,Self.validName(name),let value=Self.recoveredConfiguration(entry["configuration"],scope:scope),!saved.contains(where:{$0.id==id || Self.normalizedName($0.name)==Self.normalizedName(name)}) else{continue}
                    saved.append(SavedWorkspaceLayout(id:id,name:name,configuration:value))
                }
            } else {persistenceReadOnly=true}
        }
    }
    private static func currentSchema(_ raw:Any?)->Bool {
        guard let number=raw as? NSNumber,CFGetTypeID(number) != CFBooleanGetTypeID(),["c","s","i","l","q","C","S","I","L","Q"].contains(String(cString:number.objCType)) else{return false}
        return number.int64Value==1
    }
    // Bound nesting before Foundation parses the payload. Preserve unfamiliar or
    // pathological files instead of replacing them with an older app's defaults.
    private static func excessivelyNested(_ data:Data)->Bool {
        var depth=0,inString=false,escaped=false
        for byte in data {
            if inString {if escaped {escaped=false} else if byte==92 {escaped=true} else if byte==34 {inString=false}}
            else if byte==34 {inString=true}
            else if byte==123 || byte==91 {depth+=1;if depth>16{return true}}
            else if byte==125 || byte==93 {depth-=1}
        }
        return false
    }
    private static func recoveredConfiguration(_ raw:Any?,scope:WorkspaceLayoutScope)->WorkspaceLayoutConfiguration? {
        guard let object=raw as? [String:Any] else{return nil}
        var value=WorkspaceLayoutConfiguration.preset(.sourceFirst,scope:scope)
        func field<T:Decodable>(_ key:String,_ fallback:T)->T {
            guard let raw=object[key],let data=try? JSONSerialization.data(withJSONObject:raw,options:.fragmentsAllowed),let decoded=try? JSONDecoder().decode(T.self,from:data) else{return fallback}
            return decoded
        }
        func number(_ key:String,_ fallback:Double,_ range:ClosedRange<Double>)->Double {
            let candidate:Double=field(key,fallback);return candidate.isFinite && range.contains(candidate) ? candidate:fallback
        }
        value.sidebarVisible=field("sidebarVisible",value.sidebarVisible);value.sidebarWidth=number("sidebarWidth",value.sidebarWidth,180...380)
        value.changesVisible=field("changesVisible",value.changesVisible);value.changesDock=field("changesDock",value.changesDock)
        value.changesHeight=number("changesHeight",value.changesHeight,110...600);value.changesWidth=number("changesWidth",value.changesWidth,260...600)
        value.inspectorVisible=field("inspectorVisible",value.inspectorVisible);value.inspectorDock=field("inspectorDock",value.inspectorDock);value.inspectorWidth=number("inspectorWidth",value.inspectorWidth,260...480)
        value.pageArrangement=field("pageArrangement",value.pageArrangement);value.pageFraction=number("pageFraction",value.pageFraction,0.2...0.8)
        return value
    }
    nonisolated static func normalizedName(_ name:String)->String {name.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_US_POSIX"))}
    nonisolated static func validName(_ name:String)->Bool {
        let trimmed=name.trimmingCharacters(in:.whitespacesAndNewlines)
        return name==trimmed && !name.isEmpty && name.count<=80 && name.utf8.count<=1024 && name.unicodeScalars.allSatisfy{!CharacterSet.controlCharacters.contains($0)}
    }
    private func persist() {
        guard !persistenceReadOnly else{return}
        if let data=try? JSONEncoder().encode(WorkspaceLayoutEnvelope(schemaVersion:1,current:preFocusConfiguration ?? configuration,saved:saved)) {WorkspaceLayoutPreferences.save(data,scope:scope)}
    }
    func update(_ edit:(inout WorkspaceLayoutConfiguration)->Void) {
        var next=configuration;edit(&next)
        guard next.isValid,next != configuration else{return}
        if isFocused,let previous=preFocusConfiguration {
            let visibilityChanged=next.sidebarVisible != configuration.sidebarVisible || next.inspectorVisible != configuration.inspectorVisible || next.changesVisible != configuration.changesVisible
            // Merge only explicitly changed flags with the retained panels.
            // Focus's other transient hidden flags never become the baseline.
            var retained=next
            if next.sidebarVisible==configuration.sidebarVisible {retained.sidebarVisible=previous.sidebarVisible}
            if next.inspectorVisible==configuration.inspectorVisible {retained.inspectorVisible=previous.inspectorVisible}
            if next.changesVisible==configuration.changesVisible {retained.changesVisible=previous.changesVisible}
            if visibilityChanged {applyConfiguration(retained)}
            else {preFocusConfiguration=retained;configuration=next;persist()}
        } else {applyConfiguration(next)}
    }
    private func applyConfiguration(_ next:WorkspaceLayoutConfiguration) {
        guard next.isValid else{return}
        let wasFocused=isFocused
        preFocusConfiguration=nil;isFocused=false
        if next != configuration {configuration=next;persist()}
        else if wasFocused {persist()}
    }
    func apply(_ preset:WorkspaceLayoutPreset) {
        if preset == .focus {setFocus(true)} else {applyConfiguration(.preset(preset,scope:scope))}
    }
    func apply(_ savedLayout:SavedWorkspaceLayout) {
        guard saved.contains(where:{$0.id==savedLayout.id}),savedLayout.configuration.isValid else{return}
        applyConfiguration(savedLayout.configuration)
    }
    func reset() {apply(.sourceFirst)}
    func toggleFocus() {
        setFocus(!isFocused)
    }
    func setFocus(_ focused:Bool) {
        if focused {
            guard !isFocused else{return}
            preFocusConfiguration=configuration
            isFocused=true
            var next=configuration;next.sidebarVisible=false;next.inspectorVisible=false;next.changesVisible=false
            configuration=next
        } else if isFocused {
            let previous=preFocusConfiguration
            preFocusConfiguration=nil;isFocused=false
            if let previous {configuration=previous}
        }
    }
    func canSave(_ name:String)->Bool {
        let trimmed=name.trimmingCharacters(in:.whitespacesAndNewlines)
        return !persistenceReadOnly && Self.validName(trimmed) && saved.count<12 && !saved.contains{Self.normalizedName($0.name)==Self.normalizedName(trimmed)}
    }
    @discardableResult func saveCurrent(named name:String)->Bool {
        guard canSave(name) else{return false}
        saved.append(SavedWorkspaceLayout(id:UUID(),name:name.trimmingCharacters(in:.whitespacesAndNewlines),configuration:preFocusConfiguration ?? configuration));persist();return true
    }
    func remove(_ id:UUID) {saved.removeAll{$0.id==id};persist()}
}

// Reorder/collapse native split items while retaining each hosting controller and its live view.
// In particular a PDFView, NSScrollView, grid coordinator, or draft is never replaced by a preset.
enum WorkspacePaneExtent:Equatable {case points(Double),fraction(Double)}
struct WorkspacePaneSplit<Primary:View,Auxiliary:View>:NSViewControllerRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.locale) private var locale
    let name:String
    var isVertical=true
    var auxiliaryFirst=false
    var primaryVisible=true
    var auxiliaryVisible=true
    var extent:WorkspacePaneExtent
    var primaryMinimum:CGFloat=240
    var auxiliaryMinimum:CGFloat=110
    var onResize:(WorkspacePaneExtent)->Void={_ in}
    @ViewBuilder let primary:()->Primary
    @ViewBuilder let auxiliary:()->Auxiliary
    func makeNSViewController(context:Context)->WorkspacePaneSplitController<Primary,Auxiliary> {
        let controller=WorkspacePaneSplitController(name:name,primary:primary(),auxiliary:auxiliary(),isEnabled:isEnabled,locale:locale)
        configure(controller);return controller
    }
    func updateNSViewController(_ controller:WorkspacePaneSplitController<Primary,Auxiliary>,context:Context) {
        controller.primary.rootView=WorkspaceHostedRoot(content:primary(),isEnabled:isEnabled,locale:locale)
        controller.auxiliary.rootView=WorkspaceHostedRoot(content:auxiliary(),isEnabled:isEnabled,locale:locale);configure(controller)
    }
    private func configure(_ controller:WorkspacePaneSplitController<Primary,Auxiliary>) {
        controller.configure(isVertical:isVertical,auxiliaryFirst:auxiliaryFirst,primaryVisible:primaryVisible,auxiliaryVisible:auxiliaryVisible,extent:extent,primaryMinimum:primaryMinimum,auxiliaryMinimum:auxiliaryMinimum,onResize:onResize)
    }
    static func dismantleNSViewController(_ controller:WorkspacePaneSplitController<Primary,Auxiliary>,coordinator:()) {controller.detach()}
}
// Each NSHostingController starts a new SwiftUI environment. Re-inject these
// inherited values at every boundary, including nested panes and subsequent updates.
struct WorkspaceHostedRoot<Content:View>:View {
    let content:Content
    let isEnabled:Bool
    let locale:Locale
    var body:some View {content.environment(\.isEnabled,isEnabled).environment(\.locale,locale)}
}
final class WorkspaceLayoutMarkerView:NSView {
    var contentEnabled=true
    var contentLocale=Locale.current
    override func hitTest(_ point:NSPoint)->NSView? {nil}
}
@MainActor func workspaceLayoutMarkers(in view:NSView)->[WorkspaceLayoutMarkerView] {
    ((view as? WorkspaceLayoutMarkerView).map{[$0]} ?? []) + view.subviews.flatMap{workspaceLayoutMarkers(in:$0)}
}
struct WorkspaceLayoutMarker:NSViewRepresentable {
    let name:String
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.locale) private var locale
    func makeNSView(context:Context)->WorkspaceLayoutMarkerView {let view=WorkspaceLayoutMarkerView();view.identifier=NSUserInterfaceItemIdentifier(name);return view}
    func updateNSView(_ view:WorkspaceLayoutMarkerView,context:Context) {view.contentEnabled=isEnabled;view.contentLocale=locale}
}
func workspaceIdentityTitle(projectTitle:String,reportTitle:String,fallback:String)->String {
    !projectTitle.isEmpty ? projectTitle:!reportTitle.isEmpty ? reportTitle:fallback
}
struct NativeWorkspaceIdentity:NSViewRepresentable {
    let name:String
    let title:String
    let reportID:String
    func makeNSView(context:Context)->NSTextField {
        let field=NSTextField(labelWithString:"");field.identifier=NSUserInterfaceItemIdentifier(name)
        field.font = .systemFont(ofSize:14,weight:.semibold);field.lineBreakMode = .byTruncatingTail;field.maximumNumberOfLines=1
        field.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        return field
    }
    func updateNSView(_ field:NSTextField,context:Context) {
        field.stringValue=title;field.setAccessibilityLabel(title)
        field.toolTip=title+"\n"+L("git.reportChip",.verbatim(reportID));field.setAccessibilityHelp(L("git.reportChip",.verbatim(reportID)))
    }
}
@MainActor protocol WorkspacePaneSizing:AnyObject {
    var splitView:NSSplitView {get}
    var geometryPending:Bool {get}
    func resizeAuxiliary(to points:CGFloat,commit:Bool)
}
@MainActor protocol WorkspacePreferredGeometryObserver:AnyObject {
    var hasPendingPreferredGeometryAction:Bool {get}
    func workspacePreferredGeometryDidSettle()
}
// Explicit actions may wait for the native split queue. Passive layouts never
// install an action, and a later preferred-size job must finish before it runs.
@MainActor enum WorkspacePreferredGeometry {
    private final class PendingView {
        weak var view:NSView?
        init(_ view:NSView){self.view=view}
    }
    private static var pendingViews:[PendingView]=[]
    private static var scheduled:Set<ObjectIdentifier>=[]
    static func watch(_ view:NSView) {
        pendingViews.removeAll{($0.view as? WorkspacePreferredGeometryObserver)?.hasPendingPreferredGeometryAction != true}
        if !pendingViews.contains(where:{$0.view === view}) {pendingViews.append(PendingView(view))}
    }
    static func requestCompletion(in window:NSWindow?) {
        guard let window else{return}
        pendingViews.removeAll{($0.view as? WorkspacePreferredGeometryObserver)?.hasPendingPreferredGeometryAction != true}
        guard pendingViews.contains(where:{$0.view?.window === window}) else{return}
        let identity=ObjectIdentifier(window)
        guard scheduled.insert(identity).inserted else{return}
        DispatchQueue.main.async { [weak window] in
            scheduled.remove(identity)
            guard let window else{return}
            let observers=pendingViews.compactMap{$0.view}.filter{$0.window === window && ($0 as? WorkspacePreferredGeometryObserver)?.hasPendingPreferredGeometryAction==true}
            guard !observers.isEmpty else{return}
            guard let content=window.contentView else{return}
            func views(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap{views($0)}}
            let children=views(content)
            // NSSplitViewController is its managed split view's delegate.
            guard !children.contains(where:{(($0 as? NSSplitView)?.delegate as? WorkspacePaneSizing)?.geometryPending==true}) else{return}
            for observer in observers {(observer as? WorkspacePreferredGeometryObserver)?.workspacePreferredGeometryDidSettle()}
        }
    }
}
@MainActor final class WorkspacePaneSplitController<Primary:View,Auxiliary:View>:NSSplitViewController,WorkspacePaneSizing {
    let primary:NSHostingController<WorkspaceHostedRoot<Primary>>,auxiliary:NSHostingController<WorkspaceHostedRoot<Auxiliary>>
    let primaryItem:NSSplitViewItem,auxiliaryItem:NSSplitViewItem
    private let name:String
    private var extent=WorkspacePaneExtent.fraction(0.5)
    private var auxiliaryFirst=false
    private var positioning=false
    private var observer:NSObjectProtocol?
    private var mouseMonitor:Any?
    private var isTrackingDivider=false
    private var geometryScheduled=false
    var geometryPending:Bool {geometryScheduled || positioning}
    private var onResize:(WorkspacePaneExtent)->Void={_ in}
    init(name:String,primary:Primary,auxiliary:Auxiliary,isEnabled:Bool=true,locale:Locale = .current) {
        self.name=name
        self.primary=NSHostingController(rootView:WorkspaceHostedRoot(content:primary,isEnabled:isEnabled,locale:locale));self.auxiliary=NSHostingController(rootView:WorkspaceHostedRoot(content:auxiliary,isEnabled:isEnabled,locale:locale))
        // Split items own their bounds. A Text-only host's default maxSize would
        // otherwise constrain the entire split to its 16-point intrinsic height.
        self.primary.sizingOptions=[];self.auxiliary.sizingOptions=[]
        primaryItem=NSSplitViewItem(viewController:self.primary);auxiliaryItem=NSSplitViewItem(viewController:self.auxiliary)
        super.init(nibName:nil,bundle:nil)
        splitView.autoresizingMask=[.width,.height]
        splitView.dividerStyle = .thin;splitView.identifier=NSUserInterfaceItemIdentifier("Reviset.workspace."+name)
        primaryItem.canCollapse=true;auxiliaryItem.canCollapse=true
        primaryItem.holdingPriority = .defaultLow;auxiliaryItem.holdingPriority=NSLayoutConstraint.Priority(260)
        addSplitViewItem(primaryItem);addSplitViewItem(auxiliaryItem)
        observer=NotificationCenter.default.addObserver(forName:NSSplitView.didResizeSubviewsNotification,object:splitView,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else{return}
                self.rememberDivider();self.schedulePreferredGeometry()
            }
        }
        mouseMonitor=NSEvent.addLocalMonitorForEvents(matching:.leftMouseDown){[weak self] event in
            MainActor.assumeIsolated{self?.beginDividerGesture(event)};return event
        }
    }
    required init?(coder:NSCoder){fatalError("init(coder:) is not used")}
    deinit {
        if let observer{NotificationCenter.default.removeObserver(observer)}
        if let mouseMonitor{NSEvent.removeMonitor(mouseMonitor)}
    }
    func detach() {
        if let observer{NotificationCenter.default.removeObserver(observer);self.observer=nil}
        if let mouseMonitor{NSEvent.removeMonitor(mouseMonitor);self.mouseMonitor=nil}
    }
    private func beginDividerGesture(_ event:NSEvent) {
        isTrackingDivider=false
        guard event.window === splitView.window,!primaryItem.isCollapsed,!auxiliaryItem.isCollapsed,splitView.arrangedSubviews.count==2 else{return}
        let point=splitView.convert(event.locationInWindow,from:nil),frame=splitView.arrangedSubviews[0].frame
        let divider=splitView.isVertical ? NSRect(x:frame.maxX-3,y:splitView.bounds.minY,width:splitView.dividerThickness+6,height:splitView.bounds.height):NSRect(x:splitView.bounds.minX,y:frame.maxY-3,width:splitView.bounds.width,height:splitView.dividerThickness+6)
        isTrackingDivider=divider.contains(point)
    }
    func configure(isVertical:Bool,auxiliaryFirst:Bool,primaryVisible:Bool,auxiliaryVisible:Bool,extent:WorkspacePaneExtent,primaryMinimum:CGFloat,auxiliaryMinimum:CGFloat,onResize:@escaping(WorkspacePaneExtent)->Void) {
        positioning=true;defer{positioning=false}
        self.extent=extent;self.onResize=onResize
        splitView.isVertical=isVertical
        primaryItem.minimumThickness=primaryMinimum;auxiliaryItem.minimumThickness=auxiliaryMinimum
        if self.auxiliaryFirst != auxiliaryFirst {
            self.auxiliaryFirst=auxiliaryFirst
            // AppKit owns its split-item wrappers. Reorder items with its public
            // API, keeping the same hosting controllers and every live child view.
            splitViewItems=auxiliaryFirst ? [auxiliaryItem,primaryItem]:[primaryItem,auxiliaryItem]
        }
        primaryItem.isCollapsed = !primaryVisible && auxiliaryVisible
        auxiliaryItem.isCollapsed = !auxiliaryVisible
        splitView.needsLayout=true
        updateAccessibility()
        schedulePreferredGeometry()
    }
    private var available:CGFloat {(splitView.isVertical ? splitView.bounds.width:splitView.bounds.height)-splitView.dividerThickness}
    private var visibleExtent:CGFloat {splitView.isVertical ? auxiliary.view.frame.width:auxiliary.view.frame.height}
    private var desiredExtent:CGFloat {
        let requested:CGFloat
        switch extent {case .points(let value):requested=CGFloat(value);case .fraction(let value):requested=available*CGFloat(value)}
        return min(max(auxiliaryItem.minimumThickness,requested),max(auxiliaryItem.minimumThickness,available-primaryItem.minimumThickness))
    }
    override func viewDidAppear() {super.viewDidAppear();schedulePreferredGeometry()}
    override func viewDidLayout() {super.viewDidLayout();schedulePreferredGeometry()}
    private func schedulePreferredGeometry() {
        guard !geometryScheduled else{return}
        geometryScheduled=true
        DispatchQueue.main.async{[weak self] in
            guard let self else{return}
            defer{WorkspacePreferredGeometry.requestCompletion(in:self.splitView.window)}
            self.geometryScheduled=false;self.applyPreferredGeometry()
        }
    }
    private func updateAccessibility() {
        let label:String
        if name.hasSuffix(".projects") {label=L("layout.split.projects")}
        else if name.hasSuffix(".inspector") {label=L("layout.split.inspector")}
        else if name.hasSuffix(".changes") {label=L("layout.split.changes")}
        else {label=L("layout.split.pages")}
        splitView.setAccessibilityLabel(label)
        splitView.setAccessibilityHelp(L("layout.split.help"))
        for child in splitView.accessibilityChildren() ?? [] {
            if let element=child as? NSAccessibilityProtocol,element.accessibilityRole() == .splitter {element.setAccessibilityLabel(label)}
        }
    }
    private func applyPreferredGeometry() {
        updateAccessibility()
        guard splitView.window != nil,!positioning,available>0,!primaryItem.isCollapsed,!auxiliaryItem.isCollapsed,!(isTrackingDivider && NSEvent.pressedMouseButtons & 1 != 0) else{return}
        let desired=desiredExtent
        guard abs(visibleExtent-desired)>0.5 else{return}
        positioning=true
        splitView.setPosition(auxiliaryFirst ? desired:available-desired,ofDividerAt:0)
        splitView.layoutSubtreeIfNeeded()
        positioning=false
    }
    private func rememberDivider() {
        guard !positioning,isTrackingDivider,NSEvent.pressedMouseButtons & 1 != 0,!primaryItem.isCollapsed,!auxiliaryItem.isCollapsed else{return}
        rememberUserExtent()
    }
    private func rememberUserExtent() {
        guard available>0,visibleExtent.isFinite else{return}
        switch extent {
        case .points:extent = .points(Double(visibleExtent))
        case .fraction:extent = .fraction(Double(visibleExtent/available))
        }
        onResize(extent)
    }
    // Programmatic accessibility/tests can use the same geometry commit as the divider.
    func resizeAuxiliary(to points:CGFloat,commit:Bool) {
        positioning=true
        splitView.setPosition(auxiliaryFirst ? points:available-points,ofDividerAt:0)
        splitView.layoutSubtreeIfNeeded()
        positioning=false
        if commit {rememberUserExtent()}
    }
}

struct WorkspaceLayoutMenu:View {
    @ObservedObject var layout:WorkspaceLayoutStore
    @State private var savePrompt=false
    @State private var name=""
    var body:some View {
        Menu {
            Button(L("layout.preset.sourceFirst")){layout.apply(.sourceFirst)}
            Button(L("layout.preset.balanced")){layout.apply(.balanced)}
            Button(L("layout.preset.focus")){layout.apply(.focus)}
            Button(L("layout.preset.review")){layout.apply(.review)}
            Divider()
            Toggle(L("layout.panel.projects"),isOn:Binding(get:{layout.configuration.sidebarVisible},set:{value in layout.update{$0.sidebarVisible=value}}))
            Toggle(L("layout.panel.changes"),isOn:Binding(get:{layout.configuration.changesVisible},set:{value in layout.update{$0.changesVisible=value}}))
            Toggle(L("layout.panel.inspector"),isOn:Binding(get:{layout.configuration.inspectorVisible},set:{value in layout.update{$0.inspectorVisible=value}}))
            Divider()
            if !layout.saved.isEmpty {
                ForEach(layout.saved){saved in Button{layout.apply(saved)}label:{Text(verbatim:saved.name)}}
                Divider()
            }
            Button(L("layout.save")){name="";savePrompt=true}.disabled(layout.saved.count>=12 || layout.persistenceReadOnly)
            Button(L("layout.customize")){layout.settingsPresented=true}
            Button(L("layout.reset")){layout.reset()}
        } label:{Label(L("layout.title"),systemImage:"rectangle.3.group")}
        .help(L("layout.help"))
        .sheet(isPresented:$layout.settingsPresented){WorkspaceLayoutSettings(layout:layout)}
        .alert(L("layout.save"),isPresented:$savePrompt) {
            TextField(L("layout.name"),text:$name)
            Button(L("layout.save.confirm")){_ = layout.saveCurrent(named:name)}.disabled(!layout.canSave(name))
            Button(L("layout.cancel"),role:.cancel){}
        } message:{Text(L("layout.name.help"))}
    }
}
struct WorkspaceLayoutSettings:View {
    @ObservedObject var layout:WorkspaceLayoutStore
    @Environment(\.dismiss) private var dismiss
    private func binding<Value>(_ path:WritableKeyPath<WorkspaceLayoutConfiguration,Value>)->Binding<Value> {
        Binding(get:{layout.configuration[keyPath:path]},set:{value in layout.update{$0[keyPath:path]=value}})
    }
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Text(L("layout.customize")).font(.title2.weight(.semibold))
            Text(L("layout.liveDescription")).font(.callout).foregroundStyle(.secondary)
            if layout.persistenceReadOnly {Text(L("layout.persistenceReadOnly")).font(.caption).foregroundStyle(.secondary)}
            Form {
                Toggle(L("layout.panel.projects"),isOn:binding(\.sidebarVisible))
                Slider(value:binding(\.sidebarWidth),in:180...380,step:10){Text(L("layout.width.projects"))}.disabled(!layout.configuration.sidebarVisible)
                Toggle(L("layout.panel.changes"),isOn:binding(\.changesVisible))
                Picker(L("layout.dock.changes"),selection:binding(\.changesDock)) {
                    Text(L("layout.position.bottom")).tag(WorkspaceChangesDock.bottom);Text(L("layout.position.left")).tag(WorkspaceChangesDock.left);Text(L("layout.position.right")).tag(WorkspaceChangesDock.right)
                }
                if layout.configuration.changesDock == .bottom {Slider(value:binding(\.changesHeight),in:110...600,step:10){Text(L("layout.height.changes"))}.disabled(!layout.configuration.changesVisible)}
                else {Slider(value:binding(\.changesWidth),in:260...600,step:10){Text(L("layout.width.changes"))}.disabled(!layout.configuration.changesVisible)}
                Toggle(L("layout.panel.inspector"),isOn:binding(\.inspectorVisible))
                Picker(L("layout.dock.inspector"),selection:binding(\.inspectorDock)) {Text(L("layout.position.left")).tag(WorkspaceInspectorDock.left);Text(L("layout.position.right")).tag(WorkspaceInspectorDock.right)}
                Slider(value:binding(\.inspectorWidth),in:260...480,step:10){Text(L("layout.width.inspector"))}.disabled(!layout.configuration.inspectorVisible)
                Picker(L("layout.pages"),selection:binding(\.pageArrangement)) {Text(L("layout.pages.horizontal")).tag(WorkspacePageArrangement.horizontal);Text(L("layout.pages.vertical")).tag(WorkspacePageArrangement.vertical)}
                if !layout.saved.isEmpty {
                    Section(L("layout.saved")) {
                        ForEach(layout.saved){saved in HStack{Text(verbatim:saved.name);Spacer();Button(L("layout.apply")){layout.apply(saved)};Button(L("layout.delete"),role:.destructive){layout.remove(saved.id)}}}
                    }
                }
            }
            HStack {Button(L("layout.reset")){layout.reset()};Spacer();Button(L("layout.done")){dismiss()}.keyboardShortcut(.defaultAction)}
        }.padding(24).frame(width:580).fixedSize(horizontal:false,vertical:true)
    }
}

struct NativeDetailSheet<Content:View>:View {
    @Environment(\.dismiss) private var dismiss
    let title:String
    @ViewBuilder var content:()->Content
    var body:some View {VStack(spacing:0){HStack{Text(title).font(.headline);Spacer();Button(L("doc.common.close")){dismiss()}.keyboardShortcut(.cancelAction)}.padding(16);Divider();content()}.frame(width:940,height:680)}
}

// Hiding a native host visually does not remove AppKit keyboard focus. Resign
// only a responder inside that host; an editor elsewhere keeps its focus.
@MainActor @discardableResult func resignHiddenSourceFirstResponder(in source:NSView)->Bool {
    guard let window=source.window,let responder=window.firstResponder as? NSView,
          responder === source || responder.isDescendant(of:source) else{return false}
    return window.makeFirstResponder(nil)
}

// Fixed intrinsic width prevents horizontal-scroll layout from wrapping each
// source word independently. Explicit source newlines remain unchanged.
func sourceTerminatorLabel(_ value:String)->String {switch value {case "\r\n":return "⟦CRLF⟧";case "\r":return "⟦CR⟧";case "\n":return "⟦LF⟧";default:return "⟦EOF⟧"}}
struct NativeTerminatorLabel:NSViewRepresentable {
    let terminator:String
    func makeNSView(context:Context)->NSTextField {let field=NSTextField(labelWithString:"");field.font = .systemFont(ofSize:NSFont.smallSystemFontSize);field.textColor = .secondaryLabelColor;field.identifier=NSUserInterfaceItemIdentifier("Reviset.diff.terminator");return field}
    func updateNSView(_ field:NSTextField,context:Context) {field.stringValue=sourceTerminatorLabel(terminator);field.setAccessibilityLabel(L("git.lineEndingAnnotation",.verbatim(field.stringValue)))}
}
struct NativeDiffSourceLine:View {
    let prefix:String
    let text:String
    let semantic:Bool
    var terminator:String?=nil
    var markerName:String?=nil
    private var foreground:Color {guard semantic else{return .primary};return prefix=="−" ? Color(red:0.55,green:0.12,blue:0.12):prefix=="+" ? Color(red:0.08,green:0.36,blue:0.18):.primary}
    var body:some View {
        HStack(alignment:.top,spacing:8){Text(prefix).frame(width:18);Text(verbatim:text).fixedSize(horizontal:true,vertical:true).textSelection(.enabled);if let terminator {NativeTerminatorLabel(terminator:terminator).fixedSize()}}.font(.system(.body,design:.monospaced)).foregroundStyle(foreground).frame(maxWidth:.infinity,alignment:.leading).background {if let markerName {WorkspaceLayoutMarker(name:markerName)}}
    }
}

struct NativeNeutralSourceText:View {
    let text:String
    let lines:[(text:String,terminator:String)]?
    var body:some View {
        HStack(alignment:.top,spacing:6){
            NativeRawSourceCopyButton(text:text).frame(width:24,height:22)
            if let lines {
                VStack(alignment:.leading,spacing:1){ForEach(Array(lines.enumerated()),id:\.offset){_,line in NativeDiffSourceLine(prefix:"",text:line.text,semantic:false,terminator:line.terminator)}}
            } else {
                Text(verbatim:text).font(.system(.body,design:.monospaced)).fixedSize(horizontal:true,vertical:true).textSelection(.enabled)
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}
struct NativeRawSourceCopyButton:NSViewRepresentable {
    let text:String
    @MainActor final class Coordinator:NSObject {
        var text=""
        var pasteboard:NSPasteboard = .general
        @objc func copyRaw(_ sender:NSButton) {pasteboard.clearContents();pasteboard.setString(text,forType:.string)}
    }
    func makeCoordinator()->Coordinator {Coordinator()}
    func makeNSView(context:Context)->NSButton {
        let button=NSButton(image:NSImage(systemSymbolName:"doc.on.doc",accessibilityDescription:nil) ?? NSImage(),target:context.coordinator,action:#selector(Coordinator.copyRaw(_:)));button.bezelStyle = .rounded;button.imagePosition = .imageOnly;button.identifier=NSUserInterfaceItemIdentifier("Reviset.source.copyRaw");return button
    }
    func updateNSView(_ button:NSButton,context:Context) {context.coordinator.text=text;button.toolTip=L("common.copyRaw");button.setAccessibilityLabel(L("common.copyRaw"))}
}

// Persistent context is a summary, not an unbounded raw-text canvas. The full
// exact reason remains available in the independent scrolling native reader.
struct NativeContextSummaryLine:View {
    let text:String
    let symbol:String
    let warning:Bool
    var body:some View {
        HStack(alignment:.center,spacing:5){Image(systemName:symbol);Text(verbatim:text).lineLimit(1).truncationMode(.tail).frame(maxWidth:.infinity,alignment:.leading)}
            .font(.caption2).foregroundStyle(warning ? Color.orange:Color.secondary)
            .frame(height:16,alignment:.leading).clipped().accessibilityElement(children:.ignore).accessibilityLabel(text)
    }
}
struct NativeVerbatimReasonReader:NSViewRepresentable {
    let text:String
    func makeNSView(context:Context)->NSScrollView {
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.autohidesScrollers=false;scroll.borderType = .bezelBorder
        let reader=NSTextView(frame:scroll.contentView.bounds)
        reader.isEditable=false;reader.isSelectable=true;reader.isRichText=false
        reader.font = .monospacedSystemFont(ofSize:NSFont.smallSystemFontSize,weight:.regular)
        reader.textContainerInset=NSSize(width:8,height:8)
        reader.isVerticallyResizable=true;reader.isHorizontallyResizable=false;reader.autoresizingMask = [.width]
        reader.minSize = .zero;reader.maxSize=NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
        reader.textContainer?.widthTracksTextView=true;reader.textContainer?.containerSize=NSSize(width:scroll.contentSize.width,height:CGFloat.greatestFiniteMagnitude)
        reader.setAccessibilityIdentifier("Reviset.document.rawContextReasons");reader.setAccessibilityLabel(L("git.rawReasons"))
        scroll.documentView=reader;return scroll
    }
    func updateNSView(_ scroll:NSScrollView,context:Context) {
        guard let reader=scroll.documentView as? NSTextView else{return}
        reader.setAccessibilityLabel(L("git.rawReasons"))
        if !reader.string.utf16.elementsEqual(text.utf16) {reader.string=text;reader.scrollToBeginningOfDocument(nil)}
    }
}

// Opt-in packaged probes exercise public AppKit properties and local traversal.
// This does not certify OS Full Keyboard Access or VoiceOver interaction.
@MainActor func hiddenNativeSourceInputFacts(window:NSWindow,sources:[NSView])throws->[String:Any] {
    guard !sources.isEmpty else{throw NSError(domain:"HiddenSourceInputMissing",code:1)}
    for source in sources {
        guard !source.acceptsFirstResponder,!source.canBecomeKeyView,source.isAccessibilityHidden() else{throw NSError(domain:"HiddenSourceInputGateAbsent",code:1)}
        _ = window.makeFirstResponder(source)
        if let responder=window.firstResponder as? NSView,responder === source || responder.isDescendant(of:source) {throw NSError(domain:"HiddenSourceInputReacquired",code:1)}
    }
    for forward in [true,false] {for _ in 0..<12 {
        if forward {window.selectNextKeyView(nil)}else{window.selectPreviousKeyView(nil)}
        if let responder=window.firstResponder as? NSView,sources.contains(where:{responder === $0 || responder.isDescendant(of:$0)}) {throw NSError(domain:"KeyViewEnteredHiddenSource",code:1)}
    }}
    return ["source_count":sources.count,"accepts_first_responder":false,"can_become_key_view":false,"native_accessibility_hidden":true,"direct_reacquisition_rejected":true,"local_keyview_steps":24,"scope":"controlled public AppKit source controls and local next/previous traversal; no OS Full Keyboard Access or VoiceOver claim"]
}

// Shared native empty-state guidance; actions are provided by each workspace.
private final class WorkbookEmptyGuidanceDocument:NSView {override var isFlipped:Bool {true}}
final class WorkbookEmptyGuidanceView:NSScrollView {
    let message=NSTextField(wrappingLabelWithString:"")
    let importButton=NSButton(title:"",target:nil,action:nil)
    private let bodyView=WorkbookEmptyGuidanceDocument()
    override init(frame:NSRect) {
        super.init(frame:frame);drawsBackground=false;borderType = .noBorder;hasVerticalScroller=true;autohidesScrollers=true
        message.identifier=NSUserInterfaceItemIdentifier("Reviset.workbook.emptyGuidance");message.font = .systemFont(ofSize:NSFont.systemFontSize);message.textColor = .secondaryLabelColor;message.alignment = .center;message.maximumNumberOfLines=0
        importButton.identifier=NSUserInterfaceItemIdentifier("Reviset.workbook.newComparison");importButton.bezelStyle = .rounded
        bodyView.addSubview(message);bodyView.addSubview(importButton);documentView=bodyView
    }
    required init?(coder:NSCoder) {fatalError("init(coder:) is unavailable")}
    override func layout() {
        super.layout()
        let width=max(1,contentSize.width-28)
        message.preferredMaxLayoutWidth=width
        let textHeight=max(20,message.cell?.cellSize(forBounds:NSRect(x:0,y:0,width:width,height:CGFloat.greatestFiniteMagnitude)).height ?? 20)
        let buttonHeight=importButton.isHidden ? 0:importButton.fittingSize.height+12
        let block=textHeight+buttonHeight,documentHeight=max(contentSize.height,block+24)
        bodyView.frame=NSRect(x:0,y:0,width:contentSize.width,height:documentHeight)
        let top=max(12,(documentHeight-block)/2)
        message.frame=NSRect(x:14,y:top,width:width,height:textHeight)
        if !importButton.isHidden {let size=importButton.fittingSize;importButton.frame=NSRect(x:max(14,(contentSize.width-size.width)/2),y:top+textHeight+12,width:min(size.width,width),height:size.height)}
    }
}
struct NativeEmptyComparisonGuidance:NSViewRepresentable {
    let message:String
    let showsImport:Bool
    let canImport:Bool
    let onImport:()->Void
    var actionIdentifier="Reviset.workbook.newComparison"
    final class Coordinator:NSObject {var onImport:()->Void={};@objc func openImport(_ sender:NSButton){onImport()}}
    func makeCoordinator()->Coordinator {Coordinator()}
    func makeNSView(context:Context)->WorkbookEmptyGuidanceView {let view=WorkbookEmptyGuidanceView();view.importButton.target=context.coordinator;view.importButton.action=#selector(Coordinator.openImport(_:));return view}
    func updateNSView(_ view:WorkbookEmptyGuidanceView,context:Context) {context.coordinator.onImport=onImport;view.message.stringValue=message;view.importButton.title=L("git.workbookNewComparison");view.importButton.identifier=NSUserInterfaceItemIdentifier(actionIdentifier);view.importButton.isHidden = !showsImport;view.importButton.isEnabled=canImport;view.needsLayout=true}
}
