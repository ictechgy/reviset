import Foundation
import AppKit
import SwiftUI

@main struct SidecarLifetimeProbe {
    @MainActor static func main()async throws {
        let model=AppModel(),fm=FileManager.default,events=model.bridge.library.appendingPathComponent("sidecar-events.jsonl")
        guard model.bridge.resources.path.hasPrefix(CommandLine.arguments[1]) else{throw NSError(domain:"FixtureBundleResources",code:1)}
        func records()->[JSON]{guard let s=try? String(contentsOf:events,encoding:.utf8)else{return []};return s.split(separator:"\n").compactMap{try? JSONSerialization.jsonObject(with:Data($0.utf8))}.map(JSON.init)}
        func observed(_ action:String,_ session:String)async throws {for _ in 0..<200 {if records().contains(where:{$0["action"].string==action&&$0["args"]["session_id"].string==session&&$0["event"].string=="started"}){return};try await Task.sleep(nanoseconds:10_000_000)};throw NSError(domain:"LifecycleActionMissing",code:1)}
        func cancelled(_ task:Task<JSON,Error>)async throws{do{_ = try await task.value;throw NSError(domain:"ClosedRequestReturnedSuccess",code:1)}catch is CancellationError{}}
        model.initializing=false;model.sidecarConfigured=true;model.projectID="prj_before";model.report=JSON(["report_id":"rpt_before"])
        model.openSidecar(JSON(["revision_occurrence_id":"occ_before","label":"Before"]),page:"page_before");let first=model.sidecarRequest!
        let a=Task{try await model.bridge.call("sidecarCreate",first.scope,owner:first.owner)};try await observed("sidecarCreate",first.id)
        // No SwiftUI sheet is constructed: the model owns the immutable old
        // scope even when the current project/report changes before dismissal.
        model.projectID="prj_after";model.report=JSON(["report_id":"rpt_after"]);let reportBefore=try model.report.data()
        model.openSidecar(JSON(["revision_occurrence_id":"occ_after","label":"After"]),page:"page_after");let second=model.sidecarRequest!
        try await cancelled(a);try await observed("sidecarClose",first.id)
        let b=Task{try await model.bridge.call("sidecarCreate",second.scope,owner:second.owner)};try await observed("sidecarCreate",second.id)
        let peer=Task{try await model.bridge.call("changes",["tag":"independent-read"])};model.sidecarRequest=nil
        try await cancelled(b);try await observed("sidecarClose",second.id)
        guard try await peer.value["tag"].string=="independent-read"else{throw NSError(domain:"ClosedRequestKilledPeer",code:1)}
        let late=Task{try await model.bridge.call("sidecarCreate",first.scope,owner:first.owner)};try await cancelled(late)
        model.sidecarRequest=nil;try await Task.sleep(nanoseconds:100_000_000)
        let closes=records().filter{$0["action"].string=="sidecarClose"&&$0["event"].string=="started"}
        guard closes.count==2,try closes.first(where:{$0["args"]["session_id"].string==first.id})!["args"].data()==JSON(first.scope).data(),try closes.first(where:{$0["args"]["session_id"].string==second.id})!["args"].data()==JSON(second.scope).data(),try reportBefore==model.report.data(),model.sidecarRecoveryWarning.isEmpty,records().filter({$0["action"].string=="sidecarCreate"&&$0["event"].string=="started"}).count==2 else{throw NSError(domain:"LifecycleScopeOrDoubleCleanup",code:1)}
        let logs=(try? fm.contentsOfDirectory(atPath:model.bridge.library.appendingPathComponent("logs").path)) ?? [];guard logs.isEmpty else{throw NSError(domain:"FalseLifecycleCrashLog",code:1)}
        print("PASS model-owned immutable replacement/dismissal, prelaunch ownership, independent read, exact scopes and no duplicate cleanup without any sheet")
    }
}
