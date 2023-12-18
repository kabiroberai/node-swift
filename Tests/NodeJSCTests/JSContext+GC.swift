import JavaScriptCore

extension JSContext {
    func debugGC() {
        JSSynchronousGarbageCollectForDebugging(jsGlobalContextRef)
    }
}

@_silgen_name("JSSynchronousGarbageCollectForDebugging")
private func JSSynchronousGarbageCollectForDebugging(_ context: JSContextRef)
