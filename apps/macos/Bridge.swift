import Foundation
import Darwin

struct JSON: @unchecked Sendable, Identifiable {
    let raw: Any
    init(_ raw: Any = NSNull()) { self.raw = raw }
    subscript(_ key: String) -> JSON { JSON((raw as? [String: Any])?[key] ?? NSNull()) }
    var string: String { raw as? String ?? "" }
    var number: Double { (raw as? NSNumber)?.doubleValue ?? 0 }
    var int: Int { Int(number) }
    var bool: Bool { (raw as? NSNumber)?.boolValue ?? false }
    var array: [JSON] { (raw as? [Any] ?? []).map(JSON.init) }
    var dictionary: [String: Any] { raw as? [String: Any] ?? [:] }
    var isNull: Bool { raw is NSNull }
    var id: String {
        for key in ["project_id", "change_id", "page_id", "revision_occurrence_id", "entity_id", "observation_id", "report_id"] {
            if !self[key].string.isEmpty { return self[key].string }
        }
        return String(describing: raw)
    }
    func data() throws -> Data { try JSONSerialization.data(withJSONObject: raw, options: [.fragmentsAllowed, .sortedKeys]) }
}
struct BridgeError: LocalizedError {
    var code: String; var message: String
    var errorDescription: String? { message }
}
// Read-only range/page queries can be superseded by another selection. Each request
// owns its process so cancelling one query never terminates another query or analysis.
final class BridgeRequestCancellation: @unchecked Sendable {
    private let lock=NSLock()
    private var process: Process?
    private var cancelled=false
    func run(_ process:Process) throws {
        lock.lock();defer {lock.unlock()}
        if cancelled {throw CancellationError()}
        try process.run();self.process=process
    }
    func cancel() {
        lock.lock();defer {lock.unlock()};cancelled=true
        if let process,process.isRunning {process.terminate()}
    }
    func finish() -> Bool {
        lock.lock();defer {lock.unlock()};process=nil;return cancelled
    }
}
final class Bridge: @unchecked Sendable {
    let resources: URL
    let library: URL
    private let lock = NSLock()
    private var analysisProcess: Process?
    private var sidecarRequests: [UUID:BridgeRequestCancellation] = [:]
    private var cancelled = false
    init(resources: URL, library: URL) { self.resources = resources; self.library = library }
    func cancel() {
        lock.lock();cancelled=true;let process=analysisProcess;lock.unlock()
        guard let process,process.isRunning else{return};process.terminate()
        // JS signal handlers cannot run during synchronous parsing/diff work.
        // Escalate only the captured, still-current cancelled analysis; a later
        // analysis or unrelated request must never inherit this delayed kill.
        DispatchQueue.global(qos:.utility).asyncAfter(deadline:.now()+3) { [self] in
            lock.lock();defer{lock.unlock()}
            if cancelled,analysisProcess === process,process.isRunning {_ = Darwin.kill(process.processIdentifier,SIGKILL)}
        }
    }
    func terminateAnalysis() {
        lock.lock();cancelled=true;let process=analysisProcess;lock.unlock()
        guard let process,process.isRunning else{return}
        process.terminate()
        // App termination cannot leave a delayed work item behind to kill the
        // helper. Give its cancellation handler a bounded chance to clean up.
        for _ in 0..<10 {if !process.isRunning{return};Thread.sleep(forTimeInterval:0.05)}
        if process.isRunning {_ = Darwin.kill(process.processIdentifier,SIGKILL)}
    }
    func cancelSidecars() {let owned=lock.withLock{Array(sidecarRequests.values)};for request in owned{request.cancel()}}
    func call(_ action: String, _ args: [String: Any] = [:], analysis: Bool = false, progress: (@Sendable (JSON) -> Void)? = nil, owner:BridgeRequestCancellation? = nil) async throws -> JSON {
        let request = try JSON(["action": action, "args": args]).data()
        if analysis { lock.withLock { cancelled = false } }
        let cancellation=["changes","page","sidecarCreate"].contains(action) && !analysis ? (owner ?? BridgeRequestCancellation()):nil
        let sidecarID=action=="sidecarCreate" ? UUID():nil
        if let sidecarID,let cancellation {lock.withLock{sidecarRequests[sidecarID]=cancellation}}
        return try await withTaskCancellationHandler(operation: {
          try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                defer{if let sidecarID{self.lock.withLock{_ = self.sidecarRequests.removeValue(forKey:sidecarID)}}}
                let process = Process(), input = Pipe(), output = Pipe(), errors = Pipe()
                process.executableURL = self.resources.deletingLastPathComponent().appendingPathComponent("Helpers/node")
                process.arguments = ["--max-old-space-size=2048", self.resources.appendingPathComponent("backend/bridge.mjs").path, "--root", self.library.path]
                process.currentDirectoryURL = self.resources
                process.standardInput = input; process.standardOutput = output; process.standardError = errors
                var env = ProcessInfo.processInfo.environment
                env.removeValue(forKey: "ELECTRON_RUN_AS_NODE"); env.removeValue(forKey: "NODE_OPTIONS"); env.removeValue(forKey: "NODE_PATH")
                process.environment = env
                let stderrDone = DispatchGroup(); stderrDone.enter()
                var stderrData = Data()
                DispatchQueue.global(qos:.utility).async {
                    var pending = Data()
                    while true {
                        let chunk = errors.fileHandleForReading.availableData
                        if chunk.isEmpty { break }
                        stderrData.append(chunk)
                        if stderrData.count > 262144 { stderrData.removeFirst(stderrData.count - 262144) }
                        pending.append(chunk)
                        while let range = pending.firstRange(of: Data([10])) {
                            let line = pending.subdata(in:0..<range.lowerBound); pending.removeSubrange(0...range.lowerBound)
                            if let data = try? JSONSerialization.jsonObject(with:line) { let event=JSON(data); if event["event"].string=="progress" { progress?(event["progress"]) } }
                        }
                        if pending.count > 262144 { pending.removeAll() }
                    }
                    stderrDone.leave()
                }
                func failure(_ code:String,_ message:String) -> BridgeError {
                    let folder=self.library.appendingPathComponent("logs")
                    try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                    let log=folder.appendingPathComponent("helper-"+UUID().uuidString+".log")
                    do {try stderrData.write(to:log);return BridgeError(code:code,message:message+" 진단 로그: "+log.path)}
                    catch {return BridgeError(code:code,message:message+" "+String(decoding:stderrData.suffix(1000),as:UTF8.self))}
                }
                do {
                    if analysis { self.lock.lock(); let stopped = self.cancelled; self.lock.unlock(); if stopped { throw BridgeError(code:"CANCELLED",message:"분석을 취소했습니다.") } }
                    if let cancellation { try cancellation.run(process) } else { try process.run() }
                    if analysis { self.lock.lock(); self.analysisProcess = process; let stopped = self.cancelled; self.lock.unlock(); if stopped { process.terminate() } }
                    try input.fileHandleForWriting.write(contentsOf: request); try input.fileHandleForWriting.close()
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit(); stderrDone.wait()
                    if cancellation?.finish() == true {throw CancellationError()}
                    if analysis { self.lock.lock(); if self.analysisProcess === process { self.analysisProcess = nil }; self.lock.unlock() }
                    if process.terminationReason == .uncaughtSignal {
                        let requested=self.lock.withLock {self.cancelled}
                        if analysis && requested {throw BridgeError(code:"CANCELLED",message:"분석을 취소했습니다. 이전 보고서는 유지됩니다.")}
                        throw failure("HELPER_CRASH","분석 엔진이 예기치 않게 종료되었습니다 (signal \(process.terminationStatus)).")
                    }
                    guard let object=try? JSONSerialization.jsonObject(with:data) else {throw failure("HELPER_PROTOCOL","분석 엔진 응답을 읽지 못했습니다 (exit \(process.terminationStatus)).")}
                    let reply = JSON(object)
                    guard reply["protocol_version"].string == "0.1.0" && reply["schema_version"].string == "0.4.0" else { throw BridgeError(code:"PROTOCOL_MISMATCH",message:"앱과 분석 엔진의 계약 버전이 다릅니다.") }
                    guard reply["ok"].bool else { throw BridgeError(code: reply["error"]["code"].string, message: reply["error"]["message"].string) }
                    continuation.resume(returning: reply["value"])
                } catch {
                    if analysis { self.lock.lock(); if self.analysisProcess === process { self.analysisProcess = nil }; self.lock.unlock() }
                    let rangeCancelled=cancellation?.finish() == true
                    try? input.fileHandleForWriting.close();try? errors.fileHandleForWriting.close()
                    continuation.resume(throwing: rangeCancelled ? CancellationError():error)
                }
            }
          }
        }, onCancel: { cancellation?.cancel() })
    }
}
