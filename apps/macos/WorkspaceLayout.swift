import SwiftUI
import AppKit
import Combine

enum WorkspaceLayoutScope:String,Codable {case document,workbook}
enum WorkspaceChangesDock:String,Codable,CaseIterable {case bottom,left,right}
enum WorkspaceInspectorDock:String,Codable,CaseIterable {case left,right}
enum WorkspacePageArrangement:String,Codable,CaseIterable {case horizontal,vertical}
enum WorkspaceLayoutPreset:String,CaseIterable {case balanced,focus,review}

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
    var isValid:Bool {
        guard schemaVersion==1,current.isValid,saved.count<=12,Set(saved.map(\.id)).count==saved.count else{return false}
        let names=saved.map{WorkspaceLayoutStore.normalizedName($0.name)}
        return Set(names).count==names.count && saved.allSatisfy{WorkspaceLayoutStore.validName($0.name) && $0.configuration.isValid}
    }
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
    @Published var settingsPresented=false
    private(set) var persistenceReadOnly=false
    init(scope:WorkspaceLayoutScope) {
        self.scope=scope
        configuration = .preset(.balanced,scope:scope)
        if let data=WorkspaceLayoutPreferences.data(scope) {
            if data.count>65_536 {persistenceReadOnly=true}
            else if let object=try? JSONSerialization.jsonObject(with:data) as? [String:Any],let version=object["schemaVersion"] as? Int,version>1 {persistenceReadOnly=true}
            else if let envelope=try? JSONDecoder().decode(WorkspaceLayoutEnvelope.self,from:data),envelope.isValid {configuration=envelope.current;saved=envelope.saved}
        }
    }
    nonisolated static func normalizedName(_ name:String)->String {name.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_US_POSIX"))}
    nonisolated static func validName(_ name:String)->Bool {
        let trimmed=name.trimmingCharacters(in:.whitespacesAndNewlines)
        return name==trimmed && !name.isEmpty && name.count<=80 && name.utf8.count<=1024 && name.unicodeScalars.allSatisfy{!CharacterSet.controlCharacters.contains($0)}
    }
    private func persist() {
        guard !persistenceReadOnly else{return}
        if let data=try? JSONEncoder().encode(WorkspaceLayoutEnvelope(schemaVersion:1,current:configuration,saved:saved)) {WorkspaceLayoutPreferences.save(data,scope:scope)}
    }
    func update(_ edit:(inout WorkspaceLayoutConfiguration)->Void) {
        var next=configuration;edit(&next)
        guard next.isValid,next != configuration else{return}
        configuration=next;persist()
    }
    func apply(_ preset:WorkspaceLayoutPreset) {update{$0 = .preset(preset,scope:scope)}}
    func apply(_ savedLayout:SavedWorkspaceLayout) {
        guard saved.contains(where:{$0.id==savedLayout.id}),savedLayout.configuration.isValid else{return}
        update{$0=savedLayout.configuration}
    }
    func reset() {apply(.balanced)}
    func toggleFocus() {
        let focused = !configuration.sidebarVisible && !configuration.inspectorVisible && !configuration.changesVisible
        apply(focused ? .balanced:.focus)
    }
    func canSave(_ name:String)->Bool {
        let trimmed=name.trimmingCharacters(in:.whitespacesAndNewlines)
        return !persistenceReadOnly && Self.validName(trimmed) && saved.count<12 && !saved.contains{Self.normalizedName($0.name)==Self.normalizedName(trimmed)}
    }
    @discardableResult func saveCurrent(named name:String)->Bool {
        guard canSave(name) else{return false}
        saved.append(SavedWorkspaceLayout(id:UUID(),name:name.trimmingCharacters(in:.whitespacesAndNewlines),configuration:configuration));persist();return true
    }
    func remove(_ id:UUID) {saved.removeAll{$0.id==id};persist()}
}

// Reorder/collapse native split items while retaining each hosting controller and its live view.
// In particular a PDFView, NSScrollView, grid coordinator, or draft is never replaced by a preset.
enum WorkspacePaneExtent:Equatable {case points(Double),fraction(Double)}
struct WorkspacePaneSplit<Primary:View,Auxiliary:View>:NSViewControllerRepresentable {
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
        let controller=WorkspacePaneSplitController(name:name,primary:primary(),auxiliary:auxiliary())
        configure(controller);return controller
    }
    func updateNSViewController(_ controller:WorkspacePaneSplitController<Primary,Auxiliary>,context:Context) {
        controller.primary.rootView=primary();controller.auxiliary.rootView=auxiliary();configure(controller)
    }
    private func configure(_ controller:WorkspacePaneSplitController<Primary,Auxiliary>) {
        controller.configure(isVertical:isVertical,auxiliaryFirst:auxiliaryFirst,primaryVisible:primaryVisible,auxiliaryVisible:auxiliaryVisible,extent:extent,primaryMinimum:primaryMinimum,auxiliaryMinimum:auxiliaryMinimum,onResize:onResize)
    }
    static func dismantleNSViewController(_ controller:WorkspacePaneSplitController<Primary,Auxiliary>,coordinator:()) {controller.detach()}
}
@MainActor protocol WorkspacePaneSizing:AnyObject {
    var splitView:NSSplitView {get}
    func resizeAuxiliary(to points:CGFloat,commit:Bool)
}
@MainActor final class WorkspacePaneSplitController<Primary:View,Auxiliary:View>:NSSplitViewController,WorkspacePaneSizing {
    let primary:NSHostingController<Primary>,auxiliary:NSHostingController<Auxiliary>
    let primaryItem:NSSplitViewItem,auxiliaryItem:NSSplitViewItem
    private let name:String
    private var extent=WorkspacePaneExtent.fraction(0.5)
    private var auxiliaryFirst=false
    private var positioning=false
    private var observer:NSObjectProtocol?
    private var mouseMonitor:Any?
    private var isTrackingDivider=false
    private var geometryScheduled=false
    private var onResize:(WorkspacePaneExtent)->Void={_ in}
    init(name:String,primary:Primary,auxiliary:Auxiliary) {
        self.name=name
        self.primary=NSHostingController(rootView:primary);self.auxiliary=NSHostingController(rootView:auxiliary)
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
