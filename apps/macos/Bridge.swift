import Foundation

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
final class Bridge: @unchecked Sendable {
    let resources: URL
    let library: URL
    private let lock = NSLock()
    private var analysisProcess: Process?
    private var cancelled = false
    init(resources: URL, library: URL) { self.resources = resources; self.library = library }
    func cancel() { lock.lock(); cancelled = true; let process = analysisProcess; lock.unlock(); if process?.isRunning == true { process?.terminate() } }
    func call(_ action: String, _ args: [String: Any] = [:], analysis: Bool = false, progress: (@Sendable (JSON) -> Void)? = nil) async throws -> JSON {
        let request = try JSON(["action": action, "args": args]).data()
        if analysis { lock.withLock { cancelled = false } }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process(), input = Pipe(), output = Pipe(), errors = Pipe()
                process.executableURL = self.resources.deletingLastPathComponent().appendingPathComponent("Helpers/node")
                process.arguments = ["--max-old-space-size=2048", self.resources.appendingPathComponent("backend/bridge.mjs").path, "--root", self.library.path]
                process.currentDirectoryURL = self.resources
                process.standardInput = input; process.standardOutput = output; process.standardError = errors
                var env = ProcessInfo.processInfo.environment
                env.removeValue(forKey: "ELECTRON_RUN_AS_NODE"); env.removeValue(forKey: "NODE_OPTIONS"); env.removeValue(forKey: "NODE_PATH")
                process.environment = env
                let errorQueue = DispatchQueue(label: "org.docver.stderr")
                var errorBuffer = Data()
                errors.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    if chunk.isEmpty { return }
                    errorQueue.sync {
                        errorBuffer.append(chunk)
                        while let range = errorBuffer.firstRange(of: Data([10])) {
                            let line = errorBuffer.subdata(in: 0..<range.lowerBound); errorBuffer.removeSubrange(0...range.lowerBound)
                            if let data = try? JSONSerialization.jsonObject(with: line) { let event = JSON(data); if event["event"].string == "progress" { progress?(event["progress"]) } }
                        }
                    }
                }
                do {
                    if analysis { self.lock.lock(); let stopped = self.cancelled; self.lock.unlock(); if stopped { throw BridgeError(code:"CANCELLED",message:"분석을 취소했습니다.") } }
                    try process.run()
                    if analysis { self.lock.lock(); self.analysisProcess = process; let stopped = self.cancelled; self.lock.unlock(); if stopped { process.terminate() } }
                    try input.fileHandleForWriting.write(contentsOf: request); try input.fileHandleForWriting.close()
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit(); errors.fileHandleForReading.readabilityHandler = nil
                    if analysis { self.lock.lock(); if self.analysisProcess === process { self.analysisProcess = nil }; self.lock.unlock() }
                    if process.terminationReason == .uncaughtSignal { throw BridgeError(code: "CANCELLED", message: "분석을 취소했습니다. 이전 보고서는 유지됩니다.") }
                    let reply = JSON(try JSONSerialization.jsonObject(with: data))
                    guard reply["protocol_version"].string == "0.1.0" && reply["schema_version"].string == "0.1.0" else { throw BridgeError(code:"PROTOCOL_MISMATCH",message:"앱과 분석 엔진의 계약 버전이 다릅니다.") }
                    guard reply["ok"].bool else { throw BridgeError(code: reply["error"]["code"].string, message: reply["error"]["message"].string) }
                    continuation.resume(returning: reply["value"])
                } catch {
                    if analysis { self.lock.lock(); if self.analysisProcess === process { self.analysisProcess = nil }; self.lock.unlock() }
                    errors.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
