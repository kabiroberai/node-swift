internal import CNodeAPI

// TODO: Can we implement NodeArrayBuffer as a collection and make
// DataView its slice? How would that interact with typed arrays?
public final class NodeDataView: NodeObject {

    override class func isObjectType(for value: NodeValueBase) throws -> Bool {
        let env = value.environment
        var result = false
        try env.check(napi_is_dataview(env.raw, value.rawValue(), &result))
        return result
    }

    @_spi(NodeAPI) public required init(_ base: NodeValueBase) {
        super.init(base)
    }

    public init<E: RangeExpression>(
        for buf: NodeArrayBuffer,
        range: E
    ) throws where E.Bound == Int {
        let range = try buf.withUnsafeMutableBytes { range.relative(to: $0) }
        let env = buf.base.environment
        var result: napi_value!
        try env.check(napi_create_dataview(env.raw, range.count, buf.base.rawValue(), range.lowerBound, &result))
        super.init(NodeValueBase(raw: result, in: .current))
    }

    public convenience init(
        for buf: NodeArrayBuffer,
        range: UnboundedRange
    ) throws {
        try self.init(for: buf, range: 0...)
    }

    public func arrayBuffer() throws -> NodeArrayBuffer {
        let env = base.environment
        var buf: napi_value!
        try env.check(napi_get_dataview_info(env.raw, base.rawValue(), nil, nil, &buf, nil))
        return NodeArrayBuffer(NodeValueBase(raw: buf, in: .current))
    }

    // range of bytes in backing array buffer
    public func byteRange() throws -> Range<Int> {
        let env = base.environment
        var length = 0
        var offset = 0
        try env.check(napi_get_dataview_info(env.raw, base.rawValue(), &length, nil, nil, &offset))
        return offset ..< (offset + length)
    }

    public func withUnsafeMutableBytes<T>(_ body: (UnsafeMutableRawBufferPointer) throws -> T) throws -> T {
        let env = base.environment
        var data: UnsafeMutableRawPointer?
        var count = 0
        try env.check(napi_get_dataview_info(env.raw, base.rawValue(), &count, &data, nil, nil))
        return try body(UnsafeMutableRawBufferPointer(start: data, count: count))
    }

}
