import Foundation

struct NilValueError: Error {}

final class WeakBox<T: AnyObject> {
    weak var value: T?
    init(_ value: T) { self.value = value }
}

final class Box<T> {
    var value: T
    init(_ value: T) { self.value = value }
}

extension String {
    func copiedCString() -> UnsafeMutablePointer<CChar> {
        let utf8 = utf8CString
        let buf = UnsafeMutableBufferPointer<CChar>.allocate(capacity: utf8.count)
        _ = buf.initialize(from: utf8)
        return buf.baseAddress!
    }

    // this is preferable to bytesNoCopy because the latter calls free on Darwin/Linux
    // but deallocate on Windows (when freeWhenDone is true)
    init?(
        portableUnsafeUninitializedCapacity length: Int,
        initializingUTF8With initializer: (UnsafeMutableBufferPointer<UInt8>) throws -> Int
    ) rethrows {
        #if os(Windows) || os(Linux)
        try self.init(unsafeUninitializedCapacity: length, initializingUTF8With: initializer)
        #else
        if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
            try self.init(unsafeUninitializedCapacity: length, initializingUTF8With: initializer)
        } else {
            // we're on Darwin so we know that freeWhenDone uses libc free
            let buf = malloc(length).bindMemory(to: UInt8.self, capacity: length)
            let actualLength = try initializer(UnsafeMutableBufferPointer(start: buf, count: length))
            self.init(bytesNoCopy: buf, length: actualLength, encoding: .utf8, freeWhenDone: true)
        }
        #endif
    }
}

#if os(Windows)
public typealias CEnum = Int32
#else
public typealias CEnum = UInt32
#endif
