import Foundation
import CNodeAPI

public struct NodeDataDeallocator {
    let action: (UnsafeMutableRawBufferPointer) -> Void

    public init(action: @escaping (UnsafeMutableRawBufferPointer) -> Void) {
        self.action = action
    }

    public static let deallocate = Self { $0.deallocate() }

    // retains the object until the deallocator is called, after which
    // it's released
    public static func capture(_ object: AnyObject) -> Self {
        .init { _ in _ = object }
    }
}

typealias Hint = Box<(NodeDataDeallocator, UnsafeMutableRawBufferPointer)>

func cBufFinalizer(_: napi_env!, _: UnsafeMutableRawPointer!, hint: UnsafeMutableRawPointer!) {
    let (deallocator, bytes) = Unmanaged<Hint>.fromOpaque(hint).takeRetainedValue().value
    deallocator.action(bytes)
}

public final class NodeArrayBuffer: NodeObject {

    override class func isObjectType(for value: NodeValueBase) throws -> Bool {
        let env = value.environment
        var result = false
        try env.check(napi_is_arraybuffer(env.raw, value.rawValue(), &result))
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
        try env.check(napi_create_arraybuffer(env.raw, capacity, &data, &result))
        super.init(NodeValueBase(raw: result, in: ctx))
    }

    // bytes must remain valid while the object is alive (i.e. until
    // deallocator is called)
    public init(bytes: UnsafeMutableRawBufferPointer, deallocator: NodeDataDeallocator) throws {
        let ctx = NodeContext.current
        let env = ctx.environment
        var result: napi_value!
        let hint = Unmanaged.passRetained(Hint((deallocator, bytes))).toOpaque()
        try env.check(napi_create_external_arraybuffer(env.raw, bytes.baseAddress, bytes.count, cBufFinalizer, hint, &result))
        super.init(NodeValueBase(raw: result, in: ctx))
    }

    public convenience init(data: NSMutableData) throws {
        try self.init(
            bytes: UnsafeMutableRawBufferPointer(start: data.mutableBytes, count: data.length),
            deallocator: .capture(data)
        )
    }

    public func withUnsafeMutableBytes<T>(_ body: (UnsafeMutableRawBufferPointer) throws -> T) throws -> T {
        let env = base.environment
        var data: UnsafeMutableRawPointer?
        var count = 0
        try env.check(napi_get_arraybuffer_info(env.raw, base.rawValue(), &data, &count))
        return try body(UnsafeMutableRawBufferPointer(start: data, count: count))
    }

    #if !NAPI_VERSIONED || NAPI_GE_7

    public func detach() throws {
        try base.environment.check(
            napi_detach_arraybuffer(base.environment.raw, base.rawValue())
        )
    }

    public func isDetached() throws -> Bool {
        var result = false
        try base.environment.check(
            napi_is_detached_arraybuffer(base.environment.raw, base.rawValue(), &result)
        )
        return result
    }

    #endif

}
