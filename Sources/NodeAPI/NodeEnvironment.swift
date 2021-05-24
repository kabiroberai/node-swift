import Foundation
import CNodeAPI

final class NodeEnvironment {
    let raw: napi_env

    init(_ raw: napi_env) {
        self.raw = raw
    }

    func check(_ status: napi_status) throws {
        guard status != napi_ok else { return }

        // always catch JS errors and convert them into `NodeException`s.
        // If the user doesn't handle them, we'll convert them back into JS
        // exceptions in the top level NodeContext.withContext
        var isExceptionPending = false
        if status == napi_pending_exception {
            isExceptionPending = true
        } else {
            napi_is_exception_pending(raw, &isExceptionPending)
        }
        var exception: napi_value!
        if isExceptionPending {
            if napi_get_and_clear_last_exception(raw, &exception) == napi_ok {
                // exceptions shouldn't be frequent so using .current is okay
                throw NodeException(try NodeValueBase(raw: exception, in: .current).concrete())
            } else {
                // there's a pending exception but we couldn't fetch it wtf
                throw NodeAPIError(.genericFailure)
            }
        }

        guard let code = NodeAPIError.Code(status: status) else { return }

        var extended: UnsafePointer<napi_extended_error_info>!
        let extendedCode = napi_get_last_error_info(raw, &extended)
        let details: NodeAPIError.Details?
        if extendedCode == napi_ok {
            details = .init(raw: extended.pointee)
        } else {
            details = nil
        }
        throw NodeAPIError(code, details: details)
    }
}

// MARK: - Instance Data

private typealias InstanceData = Box<[ObjectIdentifier: Any]>

public class NodeInstanceDataKey<T> {
    public init() {}
}

private func finalizeInstanceData(
    env rawEnv: napi_env?,
    data: UnsafeMutableRawPointer?,
    hint: UnsafeMutableRawPointer?
) {
    guard let data = data else { return }
    Unmanaged<InstanceData>.fromOpaque(data).release()
}

extension NodeEnvironment {
    private func instanceDataDict() throws -> InstanceData {
        var data: UnsafeMutableRawPointer?
        try check(napi_get_instance_data(raw, &data))
        if let data = data {
            return Unmanaged<InstanceData>.fromOpaque(data)
                .takeUnretainedValue()
        }
        let obj = InstanceData([:])
        let rawObj = Unmanaged.passRetained(obj).toOpaque()
        try check(napi_set_instance_data(raw, rawObj, finalizeInstanceData, nil))
        return obj
    }

    func instanceData<T>(for key: NodeInstanceDataKey<T>) throws -> T? {
        try instanceDataDict().value[ObjectIdentifier(key)] as? T
    }

    func setInstanceData<T>(_ value: T?, for key: NodeInstanceDataKey<T>) throws {
        try instanceDataDict().value[ObjectIdentifier(key)] = value
    }
}

extension NodeContext {
    public func instanceData<T>(for key: NodeInstanceDataKey<T>) throws -> T? {
        try environment.instanceData(for: key)
    }

    public func setInstanceData<T>(_ value: T?, for key: NodeInstanceDataKey<T>) throws {
        try environment.setInstanceData(value, for: key)
    }
}
