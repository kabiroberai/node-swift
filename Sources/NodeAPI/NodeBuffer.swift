import Foundation
internal import CNodeAPI

public final class NodeBuffer: NodeTypedArray<UInt8> {

    override class func isObjectType(for value: NodeValueBase) throws -> Bool {
        let env = value.environment
        var result = false
        try env.check(napi_is_buffer(env.raw, value.rawValue(), &result))
        return result
    }

    @_spi(NodeAPI) public required init(_ base: NodeValueBase) {
        super.init(base)
    }

    public init(capacity: Int) throws {
        let ctx = NodeContext.current
        let env = ctx.environment
        var data: UnsafeMutableRawPointer?
        var result: napi_value!
        try env.check(napi_create_buffer(env.raw, capacity, &data, &result))
        super.init(NodeValueBase(raw: result, in: ctx))
    }

    // bytes must remain valid while the object is alive (i.e. until deallocator is called)
    public init(bytes: UnsafeMutableRawBufferPointer, deallocator: NodeDataDeallocator) throws {
        let ctx = NodeContext.current
        let env = ctx.environment
        var result: napi_value!
        let hint = Unmanaged.passRetained(Hint((deallocator, bytes))).toOpaque()
        try env.check(
            napi_create_external_buffer(env.raw, bytes.count, bytes.baseAddress, { rawEnv, _, hint in
                NodeContext.withUnsafeEntrypoint(rawEnv!) { _ in
                    let (deallocator, bytes) = Unmanaged<Hint>.fromOpaque(hint!).takeRetainedValue().value
                    deallocator.action(bytes)
                }
            }, hint, &result)
        )
        super.init(NodeValueBase(raw: result, in: ctx))
    }

    public convenience init(data: NSMutableData) throws {
        try self.init(
            bytes: UnsafeMutableRawBufferPointer(start: data.mutableBytes, count: data.length),
            deallocator: .capture(UncheckedSendable(data))
        )
    }

    public init(copying data: Data) throws {
        let ctx = NodeContext.current
        let env = ctx.environment
        var resultData: UnsafeMutableRawPointer?
        var result: napi_value!
        try data.withUnsafeBytes { buf in
            try env.check(napi_create_buffer_copy(env.raw, buf.count, buf.baseAddress, &resultData, &result))
        }
        super.init(NodeValueBase(raw: result, in: ctx))
    }

}

extension Data: NodeValueConvertible, NodeValueCreatable {
    public func nodeValue() throws -> NodeValue {
        try NodeBuffer(copying: self)
    }

    public static func from(_ value: NodeTypedArray<UInt8>) throws -> Data {
        try value.data()
    }
}

extension NodeTypedArray where Element == UInt8 {
    public func data() throws -> Data {
        try withUnsafeMutableBytes(Data.init(_:))
    }
}
