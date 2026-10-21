import Foundation
@main struct CancellationProbe {
 @MainActor static func main() async throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1]),resources=root.appendingPathComponent("Resources"),library=root.appendingPathComponent("library"),fm=FileManager.default
  try fm.createDirectory(at:resources.appendingPathComponent("backend"),withIntermediateDirectories:true);try fm.createDirectory(at:root.appendingPathComponent("Helpers"),withIntermediateDirectories:true);try fm.createDirectory(at:library,withIntermediateDirectories:true)
  try fm.createSymbolicLink(atPath:root.appendingPathComponent("Helpers/node").path,withDestinationPath:CommandLine.arguments[2]);try fm.copyItem(atPath:CommandLine.arguments[3],toPath:resources.appendingPathComponent("backend/bridge.mjs").path)
  let bridge=Bridge(resources:resources,library:library),events=library.appendingPathComponent("events.jsonl")
  func records()->[[String:Any]]{guard let s=try? String(contentsOf:events,encoding:.utf8)else{return []};return s.split(separator:"\n").compactMap{try? JSONSerialization.jsonObject(with:Data($0.utf8))as? [String:Any]}}
  func started(_ tag:String)async throws {for _ in 0..<200{if records().contains(where:{$0["tag"]as?String==tag && $0["event"]as?String=="started"}){return};try await Task.sleep(nanoseconds:10_000_000)};throw NSError(domain:"NotStarted",code:1)}
  func cancelled(_ task:Task<JSON,Error>) async throws{do{_=try await task.value;throw NSError(domain:"CancellationReturnedSuccess",code:1)}catch is CancellationError{}}
  let pre=Task{try await bridge.call("changes",["tag":"pre","delay":5000])};pre.cancel();try await cancelled(pre)
  guard !records().contains(where:{$0["tag"]as?String=="pre"})else{throw NSError(domain:"CancelledBeforeLaunchStillSpawned",code:1)}
  let slow=Task{try await bridge.call("changes",["tag":"slow","delay":5000])};try await started("slow");let start=Date();slow.cancel();try await cancelled(slow)
  guard Date().timeIntervalSince(start)<2,records().contains(where:{$0["tag"]as?String=="slow" && $0["event"]as?String=="terminated"})else{throw NSError(domain:"ChildNotTerminated",code:1)}
  let keep=Task{try await bridge.call("changes",["tag":"keep","delay":750])},stop=Task{try await bridge.call("changes",["tag":"stop","delay":5000])};try await started("keep");try await started("stop");stop.cancel();try await cancelled(stop);let kept=try await keep.value
  guard kept["tag"].string=="keep"else{throw NSError(domain:"SiblingRequestLost",code:1)}
  let page=Task{try await bridge.call("page",["tag":"page","delay":5000])},peer=Task{try await bridge.call("reports",["tag":"page-peer","delay":250])};try await started("page");page.cancel();try await cancelled(page)
  guard try await peer.value["tag"].string=="page-peer",records().contains(where:{$0["tag"]as?String=="page" && $0["event"]as?String=="terminated"})else{throw NSError(domain:"SupersededPageWasNotTerminatedOrKilledPeer",code:1)}
  for index in 0..<24 {
    let racing=Task{try await bridge.call("changes",["tag":"race-\(index)","delay":5000])}
    try await Task.sleep(nanoseconds:UInt64(index%4+1)*250_000);racing.cancel();try await cancelled(racing)
  }
  let ordinary=Task{try await bridge.call("reports",["tag":"ordinary","delay":100])};ordinary.cancel();let unaffected=try await ordinary.value
  guard unaffected["tag"].string=="ordinary"else{throw NSError(domain:"NonRangeCallCancelled",code:1)}
  let logs=(try? fm.contentsOfDirectory(atPath:library.appendingPathComponent("logs").path)) ?? []
  guard logs.isEmpty else{throw NSError(domain:"CancellationProducedCrashDiagnostic",code:1)}
  let shutdownA=Task{try await bridge.call("sidecarCreate",["tag":"shutdown-a","delay":5000])},shutdownB=Task{try await bridge.call("sidecarCreate",["tag":"shutdown-b","delay":5000])},other=Task{try await bridge.call("changes",["tag":"shutdown-keep","delay":750])}
  try await started("shutdown-a");try await started("shutdown-b");try await started("shutdown-keep");bridge.cancelSidecars();try await cancelled(shutdownA);try await cancelled(shutdownB)
  guard try await other.value["tag"].string=="shutdown-keep"else{throw NSError(domain:"SidecarShutdownKilledRead",code:1)}
  print("PASS 8: cancelledbeforelaunch nochild; currentrange childterminated; siblingrange survives; pagecancelendsownhelperandpreservespeer; nonrangeunchanged;24midlaunchcancellationraces; nofalsecrashlog; shutdownterminatesonlyownedsidecars")
  try JSONSerialization.data(withJSONObject:records(),options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("observed.json"))
 }
}
