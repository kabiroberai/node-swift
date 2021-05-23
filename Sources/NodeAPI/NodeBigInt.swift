import CNodeAPI

public final class NodeBigInt: NodeValue {

    @frozen public enum Sign {
        case positive
        case negative

        var bit: Int32 {
            switch self {
            case .positive:
                return 0
            case .negative:
                return 1
            }
        }

        init(bit: Int32) {
            if bit % 2 == 0 {
                self = .positive
            } else {
                self = .negative
            }
        }
    }

    @_spi(NodeAPI) public let base: NodeValueBase
    @_spi(NodeAPI) public init(_ base: NodeValueBase) {
        self.base = base
    }

    public init(signed: Int64, in ctx: NodeContext) throws {
        var value: napi_value!
        try ctx.environment.check(napi_create_bigint_int64(ctx.environment.raw, signed, &value))
        self.base = NodeValueBase(raw: value, in: ctx)
    }

    public init(unsigned: UInt64, in ctx: NodeContext) throws {
        var value: napi_value!
        try ctx.environment.check(napi_create_bigint_uint64(ctx.environment.raw, unsigned, &value))
        self.base = NodeValueBase(raw: value, in: ctx)
    }

    // words should be from least to most significant (little endian)
    public init(sign: Sign, words: [UInt64], in ctx: NodeContext) throws {
        var value: napi_value!
        try ctx.environment.check(napi_create_bigint_words(ctx.environment.raw, sign.bit, words.count, words, &value))
        self.base = NodeValueBase(raw: value, in: ctx)
    }

    public func signed() throws -> (value: Int64, lossless: Bool) {
        var value: Int64 = 0
        var isLossless: Bool = false
        try base.environment.check(
            napi_get_value_bigint_int64(base.environment.raw, base.rawValue(), &value, &isLossless)
        )
        return (value, isLossless)
    }

    public func unsigned() throws -> (value: UInt64, lossless: Bool) {
        var value: UInt64 = 0
        var isLossless: Bool = false
        try base.environment.check(
            napi_get_value_bigint_uint64(base.environment.raw, base.rawValue(), &value, &isLossless)
        )
        return (value, isLossless)
    }

    // little endian
    public func words() throws -> (sign: Sign, words: [UInt64]) {
        let env = base.environment
        var count: Int = 0
        let raw = try base.rawValue()
        try env.check(napi_get_value_bigint_words(env.raw, raw, nil, &count, nil))
        var signBit: Int32 = 0
        let words = try [UInt64](unsafeUninitializedCapacity: count) { buf, outCount in
            outCount = 0
            try env.check(napi_get_value_bigint_words(env.raw, raw, &signBit, &count, buf.baseAddress))
            outCount = count
        }
        return (Sign(bit: signBit), words)
    }

}
