import CNodeJSC
import NodeAPI

extension NodeEnvironment {
    public nonisolated static func withJSC(context: JSContext? = nil, _ perform: @NodeActor () throws -> Void) {
        let context = context ?? JSContext()!
        let executor = napi_executor(
            version: 1,
            context: nil,
            free: { _ in },
            assert_current: { _ in },
            dispatch_async: { _, cb, ctx in DispatchQueue.main.async { cb?(ctx) } }
        )
        let raw = napi_env_jsc_create(context.jsGlobalContextRef, executor)!
        performUnsafe(raw) {
            try perform()
        }
    }
}
