import SwiftUI
import AppKit

// Native draggable document/change panes. Only UI geometry is persisted;
// smoke libraries keep preferences in memory so validation cannot change user settings.
struct WorkspaceSplit<Top:View,Bottom:View>:NSViewControllerRepresentable {
    let name:String
    var defaultBottomHeight:CGFloat
    var compactTopHeight:CGFloat?=nil
    let top:()->Top
    let bottom:()->Bottom
    init(name:String,defaultBottomHeight:CGFloat,compactTopHeight:CGFloat?=nil,@ViewBuilder top:@escaping ()->Top,@ViewBuilder bottom:@escaping ()->Bottom) {
        self.name=name;self.defaultBottomHeight=defaultBottomHeight;self.compactTopHeight=compactTopHeight;self.top=top;self.bottom=bottom
    }
    func makeNSViewController(context:Context)->WorkspaceSplitController<Top,Bottom> {
        WorkspaceSplitController(name:name,defaultBottomHeight:defaultBottomHeight,compactTopHeight:compactTopHeight,top:top(),bottom:bottom())
    }
    func updateNSViewController(_ controller:WorkspaceSplitController<Top,Bottom>,context:Context) {
        controller.top.rootView=top();controller.bottom.rootView=bottom()
    }
    static func dismantleNSViewController(_ controller:WorkspaceSplitController<Top,Bottom>,coordinator:()) {controller.detach()}
}
@MainActor enum WorkspaceGeometryPreferences {
    private static var smokeHeights:[String:Double]=[:]
    static func height(_ key:String)->Double? {
        ProcessInfo.processInfo.environment["DOCVER_TEST_USER_DATA"] == nil ? UserDefaults.standard.object(forKey:key) as? Double:smokeHeights[key]
    }
    static func save(_ height:Double,for key:String) {
        if ProcessInfo.processInfo.environment["DOCVER_TEST_USER_DATA"] == nil {UserDefaults.standard.set(height,forKey:key)}
        else {smokeHeights[key]=height}
    }
}
@MainActor final class WorkspaceSplitController<Top:View,Bottom:View>:NSSplitViewController {
    let top:NSHostingController<Top>,bottom:NSHostingController<Bottom>
    private let preferenceKey:String
    private let defaultBottomHeight:CGFloat
    private let compactTopHeight:CGFloat?
    private var positioned=false
    private var positioning=false
    private var observer:NSObjectProtocol?
    init(name:String,defaultBottomHeight:CGFloat,compactTopHeight:CGFloat?,top:Top,bottom:Bottom) {
        self.top=NSHostingController(rootView:top);self.bottom=NSHostingController(rootView:bottom)
        preferenceKey="Docver.workspace."+name+".changesHeight";self.defaultBottomHeight=defaultBottomHeight;self.compactTopHeight=compactTopHeight
        super.init(nibName:nil,bundle:nil)
        splitView.isVertical=false;splitView.dividerStyle = .thin;splitView.identifier=NSUserInterfaceItemIdentifier("Docver.workspace."+name)
        let upper=NSSplitViewItem(viewController:self.top),lower=NSSplitViewItem(viewController:self.bottom)
        upper.minimumThickness=150;lower.minimumThickness=105;lower.maximumThickness=900
        upper.holdingPriority = .defaultLow;lower.holdingPriority=NSLayoutConstraint.Priority(260)
        addSplitViewItem(upper);addSplitViewItem(lower)
        observer=NotificationCenter.default.addObserver(forName:NSSplitView.didResizeSubviewsNotification,object:splitView,queue:.main) { [weak self] _ in
            // NotificationCenter delivers this observer on the main queue.
            MainActor.assumeIsolated {self?.rememberVisibleGeometry()}
        }
    }
    required init?(coder:NSCoder){fatalError("init(coder:) is not used")}
    deinit {if let observer {NotificationCenter.default.removeObserver(observer)}}
    private func rememberVisibleGeometry() {
        guard positioned,!positioning,splitView.window != nil,splitView.arrangedSubviews.count==2,splitView.bounds.height>260 else{return}
        let height=splitView.arrangedSubviews[1].frame.height
        if height>=105 && height.isFinite {WorkspaceGeometryPreferences.save(Double(height),for:preferenceKey)}
    }
    func detach() {
        rememberVisibleGeometry()
        // Resizing a removed hosting view is teardown, not a new user choice.
        if let observer {NotificationCenter.default.removeObserver(observer);self.observer=nil}
    }
    override func viewDidLayout() {
        super.viewDidLayout()
        guard !positioned,splitView.bounds.height>260,splitView.arrangedSubviews.count==2 else{return}
        positioning=true;positioned=true
        let available=splitView.bounds.height-splitView.dividerThickness
        let initial=compactTopHeight.map {available-$0} ?? defaultBottomHeight
        let saved=WorkspaceGeometryPreferences.height(preferenceKey)
        let height=min(max(105,CGFloat(saved ?? Double(initial))),max(105,available-150))
        splitView.setPosition(available-height,ofDividerAt:0)
        positioning=false
    }
}
