import SwiftUI
import AppKit

@MainActor final class GeometryState:ObservableObject {@Published var visible=true}
@main struct WorkspaceGeometryProbe:App {
    @StateObject private var state=GeometryState()
    var body:some Scene {
        Window("Docver native geometry control",id:"probe") {
            VStack(spacing:0) {
                if state.visible {WorkspaceSplit(name:"probe",defaultBottomHeight:140) {Color.white.overlay(Text("Document"))} bottom:{Color.gray.opacity(0.1).overlay(Text("Changes"))}}
                else {Color.white}
            }.frame(minWidth:700,minHeight:500).preferredColorScheme(.light).task {await GeometryChecks.run(state)}
        }.defaultSize(width:900,height:700)
    }
}
@MainActor enum GeometryChecks {
    static var started=false
    static func find(_ view:NSView)->NSSplitView? {
        if let split=view as? NSSplitView,split.identifier?.rawValue=="Docver.workspace.probe"{return split}
        for child in view.subviews {if let split=find(child){return split}};return nil
    }
    static func pane()throws->NSSplitView {
        for window in NSApp.windows where window.isVisible {if let view=window.contentView,let split=find(view){return split}}
        throw NSError(domain:"MissingNativeSplit",code:1)
    }
    static func run(_ state:GeometryState)async {
        guard !started else{return};started=true
        do {
            try await Task.sleep(nanoseconds:300_000_000);let initial=try pane().arrangedSubviews[1].frame.height
            guard abs(initial-140)<2 else{throw NSError(domain:"InitialHeight_\(initial)",code:1)}
            var observations:[[String:Double]]=[]
            for target:CGFloat in [180,160,220,140] {
                let split=try pane();split.setPosition(split.bounds.height-split.dividerThickness-target,ofDividerAt:0);split.layoutSubtreeIfNeeded()
                try await Task.sleep(nanoseconds:100_000_000);let resized=split.arrangedSubviews[1].frame.height
                guard abs(resized-target)<2 else{throw NSError(domain:"Resize_\(target)_actual_\(resized)",code:1)}
                state.visible=false;try await Task.sleep(nanoseconds:100_000_000);state.visible=true;try await Task.sleep(nanoseconds:200_000_000)
                let reopened=try pane().arrangedSubviews[1].frame.height
                guard abs(reopened-target)<2 else{throw NSError(domain:"Reopen_\(target)_actual_\(reopened)_saved_\(WorkspaceGeometryPreferences.height("Docver.workspace.probe.changesHeight") ?? -1)",code:1)}
                observations.append(["target":Double(target),"resized":Double(resized),"reopened":Double(reopened)])
            }
            print("PASS native actual embedded default140 +4 divider/hide/reopen cycles: \(observations)");fflush(stdout);NSApp.terminate(nil)
        }catch{fputs("Native geometry failed: \(error)\n",stderr);exit(1)}
    }
}
