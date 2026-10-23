import Foundation
import Darwin

struct JSON: @unchecked Sendable, Identifiable {
    let raw: Any
    init(_ raw: Any = NSNull()) { self.raw = raw }
    subscript(_ key: String) -> JSON { JSON((raw as? [String: Any])?[key] ?? NSNull()) }
    var string: String { raw as? String ?? "" }
    var number: Double { (raw as? NSNumber)?.doubleValue ?? 0 }
    var int: Int { Int(exactly:number.rounded(.towardZero)) ?? 0 }
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
struct BridgeError: LocalizedError, Sendable {
    var code: String
    var message: String
    let uiMessage: UIMessage?
    init(code: String, message: String) { self.code=code; self.message=message; self.uiMessage=nil }
    init(code: String, message: UIMessage) { self.code=code; self.message=code; self.uiMessage=message }
    // LocalizedError can be queried off the UI actor. Keep the source detail here;
    // presentation resolves only typed messages or the closed code map below.
    var errorDescription: String? { message }
}
@MainActor func bridgeErrorMessage(_ error: Error) -> UIMessage {
    guard let error=error as? BridgeError else { return .raw(error.localizedDescription) }
    if let message=error.uiMessage { return message }
    switch error.code {
    case "FILE_LIMIT": return UIMessage("doc.error.fileLimit")
    case "INPUT_NOT_REGULAR": return UIMessage("doc.error.inputNotRegular")
    default: return UIMessage("doc.error.backendDetail", .verbatim(error.code), .verbatim(error.message))
    }
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
final class BridgeStderrBuffer: @unchecked Sendable {
    private let lock=NSLock()
    private var bytes=Data()
    func append(_ chunk:Data) {lock.withLock {bytes.append(chunk);if bytes.count>262144{bytes.removeFirst(bytes.count-262144)}}}
    func snapshot()->Data {lock.withLock{bytes}}
}
final class Bridge: @unchecked Sendable {
    let resources: URL
    let library: URL
    private let lock = NSLock()
    private var analysisProcess: Process?
    private var analysisReserved = false
    private var currentAnalysisOwner: UUID?
    private var sidecarRequests: [UUID:BridgeRequestCancellation] = [:]
    private var cancelled = false
    init(resources: URL, library: URL) {
        // A helper can exit before consuming stdin. Let FileHandle report EPIPE
        // as an error instead of allowing that write to terminate the app.
        _ = Darwin.signal(SIGPIPE,SIG_IGN)
        self.resources = resources; self.library = library
    }
    func cancel(owner:UUID? = nil) {
        lock.lock();guard analysisReserved,currentAnalysisOwner == owner else{lock.unlock();return};cancelled=true;let process=analysisProcess;lock.unlock()
        guard let process,process.isRunning else{return};let pid=process.processIdentifier;guard pid>1 else{return};process.terminate()
        // JS signal handlers cannot run during synchronous parsing/diff work.
        // Escalate only the captured, still-current cancelled analysis; a later
        // analysis or unrelated request must never inherit this delayed kill.
        DispatchQueue.global(qos:.utility).asyncAfter(deadline:.now()+3) { [self] in
            lock.lock();defer{lock.unlock()}
            if cancelled,analysisProcess === process,process.isRunning {_ = Darwin.kill(pid,SIGKILL)}
        }
    }
    func terminateAnalysis() {
        lock.lock();cancelled=true;let process=analysisProcess;lock.unlock()
        guard let process,process.isRunning else{return}
        let pid=process.processIdentifier;guard pid>1 else{return}
        process.terminate()
        // App termination cannot leave a delayed work item behind to kill the
        // helper. Give its cancellation handler a bounded chance to clean up.
        for _ in 0..<10 {if !process.isRunning{return};Thread.sleep(forTimeInterval:0.05)}
        if process.isRunning {_ = Darwin.kill(pid,SIGKILL)}
    }
    func cancelSidecars() {let owned=lock.withLock{Array(sidecarRequests.values)};for request in owned{request.cancel()}}
    func releaseAnalysis(owner:UUID?) {lock.withLock {
        if analysisReserved,currentAnalysisOwner==owner,analysisProcess==nil {analysisReserved=false;currentAnalysisOwner=nil}
    }}
    func call(_ action: String, _ args: [String: Any] = [:], analysis: Bool = false, progress: (@Sendable (JSON) -> Void)? = nil, owner:BridgeRequestCancellation? = nil, analysisOwner:UUID? = nil, holdAnalysis:Bool = false) async throws -> JSON {
        let request = try JSON(["action": action, "args": args]).data()
        if analysis {try lock.withLock {
            guard !analysisReserved else{throw BridgeError(code:"ANALYSIS_BUSY",message:UIMessage("doc.tail.engine.busyInAnotherWindow"))}
            analysisReserved=true;currentAnalysisOwner=analysisOwner;cancelled=false
        }}
        let cancellation=["changes","page","sidecarCreate","workbookQuery","workbookGrid","workbookProjects","workbookReports","workbookView","workbookReleases","workbookMcpConfig"].contains(action) && !analysis ? (owner ?? BridgeRequestCancellation()):nil
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
                let stderrData = BridgeStderrBuffer()
                DispatchQueue.global(qos:.utility).async {
                    var pending = Data()
                    while true {
                        let chunk = errors.fileHandleForReading.availableData
                        if chunk.isEmpty { break }
                        stderrData.append(chunk)
                        pending.append(chunk)
                        while let range = pending.firstRange(of: Data([10])) {
                            let line = pending.subdata(in:0..<range.lowerBound); pending.removeSubrange(0...range.lowerBound)
                            if let data = try? JSONSerialization.jsonObject(with:line) { let event=JSON(data); if event["event"].string=="progress" { progress?(event["progress"]) } }
                        }
                        if pending.count > 262144 { pending.removeAll() }
                    }
                    stderrDone.leave()
                }
                func failure(_ code:String,_ message:UIMessage) -> BridgeError {
                    let stderr=stderrData.snapshot()
                    let folder=self.library.appendingPathComponent("logs")
                    try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                    let log=folder.appendingPathComponent("helper-"+UUID().uuidString+".log")
                    do {try stderr.write(to:log);return BridgeError(code:code,message:UIMessage("doc.error.diagnosticLog", .message(message), .verbatim(log.path)))}
                    catch {return BridgeError(code:code,message:UIMessage("doc.error.diagnosticDetail", .message(message), .verbatim(String(decoding:stderr.suffix(1000),as:UTF8.self))))}
                }
                func finishAnalysis(success:Bool = false) {
                    if analysis {self.lock.withLock {
                        if self.analysisProcess === process {self.analysisProcess=nil}
                        if !success || !holdAnalysis {self.analysisReserved=false;self.currentAnalysisOwner=nil}
                    }}
                }
                do {
                    if analysis { self.lock.lock(); let stopped = self.cancelled; self.lock.unlock(); if stopped { throw BridgeError(code:"CANCELLED",message:UIMessage("doc.analysis.cancelled")) } }
                    if let cancellation { try cancellation.run(process) } else { try process.run() }
                    if analysis { self.lock.lock(); self.analysisProcess = process; let stopped = self.cancelled; self.lock.unlock(); if stopped { process.terminate() } }
                    try input.fileHandleForWriting.write(contentsOf: request); try input.fileHandleForWriting.close()
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit(); stderrDone.wait()
                    if cancellation?.finish() == true {throw CancellationError()}
                    if analysis { self.lock.lock(); if self.analysisProcess === process { self.analysisProcess = nil }; self.lock.unlock() }
                    if process.terminationReason == .uncaughtSignal {
                        let requested=self.lock.withLock {self.cancelled}
                        if analysis && requested {throw BridgeError(code:"CANCELLED",message:UIMessage("doc.analysis.cancelledRetained"))}
                        throw failure("HELPER_CRASH",UIMessage("doc.tail.engine.terminatedBySignal", .count(Int(process.terminationStatus))))
                    }
                    guard let object=try? JSONSerialization.jsonObject(with:data) else {throw failure("HELPER_PROTOCOL",UIMessage("doc.tail.engine.responseUnreadableExitCode", .count(Int(process.terminationStatus))))}
                    let reply = JSON(object)
                    guard reply["protocol_version"].string == "0.1.0" && reply["schema_version"].string == "0.4.0" else { throw BridgeError(code:"PROTOCOL_MISMATCH",message:UIMessage("doc.tail.engine.contractVersionMismatch")) }
                    guard reply["ok"].bool else { throw BridgeError(code: reply["error"]["code"].string, message: reply["error"]["message"].string) }
                    finishAnalysis(success:true);continuation.resume(returning: reply["value"])
                } catch {
                    if analysis { self.lock.lock(); if self.analysisProcess === process { self.analysisProcess = nil }; self.lock.unlock() }
                    let rangeCancelled=cancellation?.finish() == true
                    try? input.fileHandleForWriting.close();try? errors.fileHandleForWriting.close()
                    finishAnalysis();continuation.resume(throwing: rangeCancelled ? CancellationError():error)
                }
            }
          }
        }, onCancel: { cancellation?.cancel() })
    }
}
