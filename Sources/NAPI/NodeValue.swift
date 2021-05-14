import CNAPI

// MARK: - Value Types

extension NodeValue {

    public enum ValueType {
        case undefined
        case null
        case boolean
        case number
        case string
        case symbol
        case object
        case function
        case external
        case bigint

        init?(raw: napi_valuetype) {
            switch raw {
            case napi_undefined:
                self = .undefined
            case napi_null:
                self = .null
            case napi_boolean:
                self = .boolean
            case napi_number:
                self = .number
            case napi_string:
                self = .string
            case napi_symbol:
                self = .symbol
            case napi_object:
                self = .object
            case napi_function:
                self = .function
            case napi_external:
                self = .external
            case napi_bigint:
                self = .bigint
            default:
                return nil
            }
        }
    }

    public func type(in env: NodeEnvironment) throws -> ValueType {
        var type = napi_undefined
        try env.check(napi_typeof(env.raw, rawValue(in: env), &type))
        return ValueType(raw: type)!
    }

    public convenience init(nullIn env: NodeEnvironment) throws {
        var val: napi_value!
        try env.check(napi_get_null(env.raw, &val))
        self.init(raw: val, in: env)
    }

    public convenience init(undefinedIn env: NodeEnvironment) throws {
        var val: napi_value!
        try env.check(napi_get_undefined(env.raw, &val))
        self.init(raw: val, in: env)
    }

}

// MARK: - Finalizers

private class FinalizeWrapper {
    let finalizer: (NodeEnvironment) throws -> Void
    init(finalizer: @escaping (NodeEnvironment) throws -> Void) {
        self.finalizer = finalizer
    }
}

private func cFinalizer(rawEnv: napi_env!, data: UnsafeMutableRawPointer!, hint: UnsafeMutableRawPointer!) {
    try? NodeEnvironment.withRaw(rawEnv) { env in
        try Unmanaged<FinalizeWrapper>
            .fromOpaque(data)
            .takeRetainedValue() // releases the wrapper post-call
            .finalizer(env)
    }
}

extension NodeValue {

    public func addFinalizer(in env: NodeEnvironment, finalizer: @escaping (NodeEnvironment) throws -> Void) throws {
        let data = Unmanaged.passRetained(FinalizeWrapper(finalizer: finalizer)).toOpaque()
        try env.check(napi_add_finalizer(env.raw, rawValue(in: env), data, cFinalizer, nil, nil))
    }

    func isInstance(of constructor: NodeValue, in env: NodeEnvironment) throws -> Bool {
        var result = false
        try env.check(napi_instanceof(env.raw, rawValue(in: env), constructor.rawValue(in: env), &result))
        return result
    }

}
