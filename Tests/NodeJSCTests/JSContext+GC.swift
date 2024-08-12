@preconcurrency import JavaScriptCore
import NodeAPI

extension JSContext {
    func debugGCSync() {
        JSSynchronousGarbageCollectForDebugging(jsGlobalContextRef)
    }

    @NodeActor func debugGC() async {
        // we have to executor-switch to ensure that any existing NodeContext.withContext
        // completes and protects escaped values before GCing
        await MainActor.run { debugGCSync() }
    }
}

@_silgen_name("JSSynchronousGarbageCollectForDebugging")
private func JSSynchronousGarbageCollectForDebugging(_ context: JSContextRef)
