import Foundation
@main struct BridgeSmoke {
    static func main() async throws {
        let base=FileManager.default.temporaryDirectory.appendingPathComponent("docver-bridge-"+UUID().uuidString),resources=base.appendingPathComponent("Contents/Resources"),helper=base.appendingPathComponent("Contents/Helpers/node")
        try FileManager.default.createDirectory(at:resources,withIntermediateDirectories:true);try FileManager.default.createDirectory(at:helper.deletingLastPathComponent(),withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:base)}
        func install(_ source:String)throws{try Data(source.utf8).write(to:helper);try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:helper.path)}
        try install("#!/bin/sh\ncat >/dev/null\necho deliberate-crash >&2\nkill -USR1 $$\n")
        let bridge=Bridge(resources:resources,library:base.appendingPathComponent("library"))
        do{_=try await bridge.call("analyze",analysis:true);fatalError("crash accepted")}catch let e as BridgeError{guard e.code=="HELPER_CRASH" else{throw e}}
        let logs=try FileManager.default.contentsOfDirectory(at:base.appendingPathComponent("library/logs"),includingPropertiesForKeys:nil);let evidence=try String(contentsOf:logs[0],encoding:.utf8);guard evidence.contains("deliberate-crash")else{fatalError("stderr lost")}
        try install("#!/bin/sh\ncat >/dev/null\nexec /bin/sleep 30\n")
        let pending=Task{try await bridge.call("analyze",analysis:true)};try await Task.sleep(nanoseconds:150_000_000);bridge.cancel()
        do{_=try await pending.value;fatalError("cancel accepted")}catch let e as BridgeError{guard e.code=="CANCELLED"else{throw e}}
        print("PASS native bridge: unexpected crash != user cancel; bounded stderr log preserved")
    }
}
