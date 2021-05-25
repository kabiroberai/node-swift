import Foundation
import CNodeAPI

public final class NodeBuffer: NodeObject {

    override class func isObjectType(for value: NodeValueBase) throws -> Bool {
        let env = value.environment
        var result = false
        try env.check(napi_is_buffer(env.raw, value.rawValue(), &result))
        return result
    }

    @_spi(NodeAPI) public required init(_ base: NodeValueBase) {
        super.init(base)
    }

    public init(capacity: Int, in ctx: NodeContext) throws {
        let env = ctx.environment
        var data: UnsafeMutableRawPointer?
        var result: napi_value!
        try env.check(napi_create_buffer(env.raw, capacity, &data, &result))
        super.init(NodeValueBase(raw: result, in: ctx))
    }

    // bytes must remain valid while the object is alive (i.e. until deallocator is called)
    public init(bytes: UnsafeMutableRawBufferPointer, deallocator: NodeArrayBuffer.Deallocator, in ctx: NodeContext) throws {
        let env = ctx.environment
        var result: napi_value!
        let hint = Unmanaged.passRetained(Hint((deallocator, bytes))).toOpaque()
        try env.check(napi_create_external_buffer(env.raw, bytes.count, bytes.baseAddress, cBufFinalizer, hint, &result))
        super.init(NodeValueBase(raw: result, in: ctx))
    }

    public init(copying data: Data, in ctx: NodeContext) throws {
        let env = ctx.environment
        var resultData: UnsafeMutableRawPointer?
        var result: napi_value!
        try data.withUnsafeBytes { buf in
            try env.check(napi_create_buffer_copy(env.raw, buf.count, buf.baseAddress, &resultData, &result))
        }
        super.init(NodeValueBase(raw: result, in: ctx))
    }

    public func withUnsafeMutableBytes<T>(_ body: (UnsafeMutableRawBufferPointer) throws -> T) throws -> T {
        let env = base.environment
        var data: UnsafeMutableRawPointer?
        var count = 0
        try env.check(napi_get_buffer_info(env.raw, base.rawValue(), &data, &count))
        return try body(UnsafeMutableRawBufferPointer(start: data, count: count))
    }

}

extension Data: NodeValueConvertible {
    public func nodeValue(in ctx: NodeContext) throws -> NodeValue {
        try NodeBuffer(copying: self, in: ctx)
    }
}
