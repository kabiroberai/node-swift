import JavaScriptCore
import NodeAPI

extension JSContext {
    func debugGC() async {
        JSSynchronousGarbageCollectForDebugging(jsGlobalContextRef)
        // some finalizer calls happen on the next RunLoop tick
        await Task { @NodeActor in }.value
    }
}

@_silgen_name("JSSynchronousGarbageCollectForDebugging")
private func JSSynchronousGarbageCollectForDebugging(_ context: JSContextRef)
