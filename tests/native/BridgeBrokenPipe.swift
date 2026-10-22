import Foundation
import Darwin

@main struct BridgeBrokenPipeProbe {
    static func main() async throws {
        // Reset the inherited disposition so this really exercises the native
        // host's broken-pipe protection, even when launched by Node.
        _ = Darwin.signal(SIGPIPE,SIG_DFL)
        let resources=Bundle.main.resourceURL!
        let bridge=Bridge(resources:resources,library:URL(fileURLWithPath:ProcessInfo.processInfo.environment["DOCVER_TEST_USER_DATA"]!))
        var caught=false
        do { _ = try await bridge.call("create",["payload":String(repeating:"x",count:2_000_000)]) }
        catch { caught=true }
        guard caught else { throw NSError(domain:"DeadHelperWasSuccessful",code:1) }
        let alive="process.stdin.resume();process.stdin.on('end',()=>console.log(JSON.stringify({ok:true,protocol_version:'0.1.0',schema_version:'0.4.0',value:{alive:true}})));"
        try Data(alive.utf8).write(to:resources.appendingPathComponent("backend/bridge.mjs"))
        let value=try await bridge.call("projects")
        guard value["alive"].bool else { throw NSError(domain:"BridgeDidNotRecoverAfterDeadHelper",code:1) }
        print("PASS native broken pipe: dead helper throws and host serves subsequent request")
    }
}
