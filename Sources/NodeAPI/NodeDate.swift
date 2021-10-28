import Foundation
@_implementationOnly import CNodeAPI

public final class NodeDate: NodeObject {

    @_spi(NodeAPI) public required init(_ base: NodeValueBase) {
        super.init(base)
    }

    override class func isObjectType(for value: NodeValueBase) throws -> Bool {
        let env = value.environment
        var result = false
        try env.check(napi_is_date(env.raw, value.rawValue(), &result))
        return result
    }

    public init(_ date: Date) throws {
        let ctx = NodeContext.current
        var result: napi_value!
        try ctx.environment.check(napi_create_date(ctx.environment.raw, date.timeIntervalSince1970 * 1000, &result))
        super.init(NodeValueBase(raw: result, in: ctx))
    }

    public func date() throws -> Date {
        let env = base.environment
        var msec: Double = 0
        try env.check(napi_get_date_value(env.raw, base.rawValue(), &msec))
        return Date(timeIntervalSince1970: msec / 1000)
    }

}

extension Date: NodeValueConvertible, NodeValueCreatable {
    public func nodeValue() throws -> NodeValue {
        try NodeDate(self)
    }

    public static func from(_ value: NodeDate) throws -> Date {
        try value.date()
    }
}
