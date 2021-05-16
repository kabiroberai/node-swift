import CNodeAPI

public struct NodeAPIError: Error {
    public enum Code {
        case unknown
        case invalidArg
        case objectExpected
        case stringExpected
        case nameExpected
        case functionExpected
        case numberExpected
        case booleanExpected
        case arrayExpected
        case genericFailure
        case cancelled
        case escapeCalledTwice
        case handleScopeMismatch
        case callbackScopeMismatch
        case queueFull
        case closing
        case bigintExpected
        case dateExpected
        case arraybufferExpected
        case detachableArraybufferExpected
        case wouldDeadlock

        init?(status: napi_status) {
            switch status {
            case napi_ok:
                return nil
            case napi_invalid_arg:
                self = .invalidArg
            case napi_object_expected:
                self = .objectExpected
            case napi_string_expected:
                self = .stringExpected
            case napi_name_expected:
                self = .nameExpected
            case napi_function_expected:
                self = .functionExpected
            case napi_number_expected:
                self = .numberExpected
            case napi_boolean_expected:
                self = .booleanExpected
            case napi_array_expected:
                self = .arrayExpected
            case napi_generic_failure:
                self = .genericFailure
            case napi_cancelled:
                self = .cancelled
            case napi_escape_called_twice:
                self = .escapeCalledTwice
            case napi_handle_scope_mismatch:
                self = .handleScopeMismatch
            case napi_callback_scope_mismatch:
                self = .callbackScopeMismatch
            case napi_queue_full:
                self = .queueFull
            case napi_closing:
                self = .closing
            case napi_bigint_expected:
                self = .bigintExpected
            case napi_date_expected:
                self = .dateExpected
            case napi_arraybuffer_expected:
                self = .arraybufferExpected
            case napi_detachable_arraybuffer_expected:
                self = .detachableArraybufferExpected
            case napi_would_deadlock:
                self = .wouldDeadlock
            default:
                self = .unknown
            }
        }
    }

    public struct Details {
        public let message: String
        public let engineErrorCode: UInt32

        init(raw: napi_extended_error_info) {
            self.message = String(cString: raw.error_message)
            self.engineErrorCode = raw.engine_error_code
        }
    }

    let code: Code
    var details: Details?

    init(_ code: Code, details: Details? = nil) {
        self.code = code
        self.details = details
    }
}
