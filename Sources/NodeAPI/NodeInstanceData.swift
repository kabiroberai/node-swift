@_implementationOnly import CNodeAPI

typealias InstanceDataBox = Box<[ObjectIdentifier: Any]>

private class NodeInstanceDataStorage {
    private var lock = ReadWriteLock()
    private var storage: [napi_env: InstanceDataBox] = [:]
    private init() {}

    static let current = NodeInstanceDataStorage()

    @NodeActor func instanceData(for env: NodeEnvironment) -> InstanceDataBox {
        let raw = env.raw
        return lock.withReaderLock {
            // fast path: in most cases, we should have storage
            // for the env already
            storage[raw]
        } ?? lock.withWriterLock {
            // slow path: we don't have storage yet. Upgrade
            // to a writer lock to block concurrent reads
            // while we modify storage.

            // check if another thread beat us to it
            // TODO: Is this even possible?
            // I don't think napi_env can be used concurrently
            if let dict = storage[raw] {
                return dict
            }

            // we're the first to need storage for this env
            let box = Box<[ObjectIdentifier: Any]>([:])
            storage[raw] = box

            // remove our associated storage when napi destroys the env
            _ = try? env.addCleanupHook {
                self.lock.withWriterLockVoid {
                    self.storage.removeValue(forKey: raw)
                }
            }

            return box
        }
    }
}

public class NodeInstanceDataKey<T> {}

extension NodeEnvironment {
    private func instanceDataDict() -> InstanceDataBox {
        NodeInstanceDataStorage.current.instanceData(for: self)
    }

    func instanceData(for id: ObjectIdentifier) -> Any? {
        instanceDataDict().value[id]
    }

    func setInstanceData(_ value: Any?, for id: ObjectIdentifier) {
        instanceDataDict().value[id] = value
    }

    public subscript<T>(key: NodeInstanceDataKey<T>) -> T? {
        get { instanceData(for: ObjectIdentifier(key)) as? T }
        set { setInstanceData(newValue, for: ObjectIdentifier(key)) }
    }
}

@NodeActor
@propertyWrapper public final class NodeInstanceData<Value> {
    private let defaultValue: Value

    private var key: ObjectIdentifier { ObjectIdentifier(self) }

    public var wrappedValue: Value {
        get { Node.instanceData(for: key) as? Value ?? defaultValue }
        set { Node.setInstanceData(newValue, for: key) }
    }

    public var projectedValue: NodeInstanceData<Value> { self }

    public nonisolated init(wrappedValue defaultValue: Value) where Value: Sendable {
        self.defaultValue = defaultValue
    }

    @available(*, unavailable, message: "NodeInstanceData cannot be an instance member")
    public static subscript(
        _enclosingInstance object: Never,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<Never, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<Never, NodeInstanceData<Value>>
    ) -> Value {
        get {}
    }
}
