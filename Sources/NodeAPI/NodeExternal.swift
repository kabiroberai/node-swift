@_implementationOnly import CNodeAPI

private func cFinalizer(rawEnv: napi_env!, data: UnsafeMutableRawPointer!, hint: UnsafeMutableRawPointer!) {
    Unmanaged<Box<Any>>.fromOpaque(data).release()
}

public final class NodeExternal: NodeValue {

    @_spi(NodeAPI) public let base: NodeValueBase
    @_spi(NodeAPI) public init(_ base: NodeValueBase) {
        self.base = base
    }

    public init(value: Any) throws {
        let ctx = NodeContext.current
        let env = ctx.environment
        let unmanaged = Unmanaged.passRetained(value as AnyObject)
        let opaque = unmanaged.toOpaque()
        var result: napi_value!
        try env.check(napi_create_external(env.raw, opaque, cFinalizer, nil, &result))
        self.base = NodeValueBase(raw: result, in: ctx)
    }

    public func value() throws -> Any {
        let env = base.environment
        var opaque: UnsafeMutableRawPointer!
        try env.check(napi_get_value_external(env.raw, base.rawValue(), &opaque))
        return Unmanaged<AnyObject>.fromOpaque(opaque).takeUnretainedValue()
    }

}
