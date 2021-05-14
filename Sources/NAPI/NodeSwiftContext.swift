import Foundation
import CNAPI

// A single NodeSwiftContext corresponds to an instance
// of the module. It persists across instances of NodeEnvironment
// as long as they correspond to the same instance of the module.
class NodeSwiftContext {
    var value: Any?

    // ghetto garbage collection
    private let lock = DispatchQueue(label: "node-swift-context")
    private var deadRefs: [napi_ref] = []

    // thread-safe
    func addDeadRef(_ ref: napi_ref) {
        lock.sync { deadRefs.append(ref) }
    }

    // thread-safe
    func deleteDeadRefs(env: NodeEnvironment) throws {
        let refs = lock.sync { () -> [napi_ref] in
            let refs = deadRefs
            deadRefs.removeAll()
            return refs
        }
        for ref in refs {
            try env.check(napi_delete_reference(env.raw, ref))
        }
    }

    func finalize(in env: NodeEnvironment) {
        // remove any remaining dead refs
        try? deleteDeadRefs(env: env)
    }
}

private func finalizeSwiftContext(
    env rawEnv: napi_env?,
    data: UnsafeMutableRawPointer?,
    hint: UnsafeMutableRawPointer?
) {
    guard let rawEnv = rawEnv,
          let data = data
    else { return }
    try? NodeEnvironment.withRaw(rawEnv) { env in
        // the object will be deinitialized after finalize is
        // called, since we called take*Retained*Value
        Unmanaged<NodeSwiftContext>.fromOpaque(data)
            .takeRetainedValue()
            .finalize(in: env)
    }
}

extension NodeEnvironment {
    func swiftContext() throws -> NodeSwiftContext {
        var data: UnsafeMutableRawPointer?
        try check(napi_get_instance_data(raw, &data))
        if let data = data {
            return Unmanaged<NodeSwiftContext>.fromOpaque(data)
                .takeUnretainedValue()
        }
        let context = NodeSwiftContext()
        let rawContext = Unmanaged.passRetained(context).toOpaque()
        try check(napi_set_instance_data(raw, rawContext, finalizeSwiftContext, nil))
        return context
    }
}

// MARK: - Utilities

extension NodeEnvironment {
    public func instanceData() throws -> Any? {
        try swiftContext().value
    }

    public func setInstanceData(_ value: Any?) throws {
        try swiftContext().value = value
    }
}
