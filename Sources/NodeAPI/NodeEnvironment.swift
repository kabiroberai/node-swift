import Foundation
import CNodeAPI

final class NodeEnvironment {
    let raw: napi_env

    init(_ raw: napi_env) {
        self.raw = raw
    }

    func check(_ status: napi_status) throws {
        guard let code = NodeError.Code(status: status) else { return }
        var extended: UnsafePointer<napi_extended_error_info>!
        let extendedCode = napi_get_last_error_info(raw, &extended)
        let details: NodeError.Details?
        if extendedCode == napi_ok {
            details = .init(raw: extended.pointee)
        } else {
            details = nil
        }
        throw NodeError(code, details: details)
    }
}

private func finalizeInstanceData(
    env rawEnv: napi_env?,
    data: UnsafeMutableRawPointer?,
    hint: UnsafeMutableRawPointer?
) {
    guard let rawEnv = rawEnv,
          let data = data
    else { return }
    try? NodeContext.withContext(environment: NodeEnvironment(rawEnv)) { ctx in
        // the object will be deinitialized after finalize is
        // called, since we called take*Retained*Value
        try Unmanaged<NodeEnvironment.InstanceData>.fromOpaque(data)
            .takeRetainedValue()
            .finalize(in: ctx)
    }
}

extension NodeEnvironment {
    // A single InstanceData corresponds to an instance of the
    // module. It persists across instances of NodeEnvironment
    // as long as they correspond to the same instance of the
    // module.
    final class InstanceData {
        let environment: NodeEnvironment
        var userData: Any?

        init(environment: NodeEnvironment) {
            self.environment = environment
        }

        // ghetto garbage collection
        private let lock = DispatchQueue(label: "node-swift-context")
        private var deadRefs: [napi_ref] = []

        // thread-safe
        func addDeadRef(_ ref: napi_ref) {
            lock.sync { deadRefs.append(ref) }
        }

        // thread-safe
        func deleteDeadRefs() throws {
            let refs = lock.sync { () -> [napi_ref] in
                let refs = deadRefs
                deadRefs.removeAll()
                return refs
            }
            for ref in refs {
                try environment.check(
                    napi_delete_reference(environment.raw, ref)
                )
            }
        }

        func finalize(in ctx: NodeContext) throws {
            // remove any remaining dead refs
            try deleteDeadRefs()
        }
    }

    func instanceData() throws -> InstanceData {
        var data: UnsafeMutableRawPointer?
        try check(napi_get_instance_data(raw, &data))
        if let data = data {
            return Unmanaged<InstanceData>.fromOpaque(data)
                .takeUnretainedValue()
        }
        let context = InstanceData(environment: self)
        let rawContext = Unmanaged.passRetained(context).toOpaque()
        try check(napi_set_instance_data(raw, rawContext, finalizeInstanceData, nil))
        return context
    }
}

extension NodeContext {
    public func userData() throws -> Any? {
        try environment.instanceData().userData
    }

    public func setUserData(_ value: Any?) throws {
        try environment.instanceData().userData = value
    }
}
