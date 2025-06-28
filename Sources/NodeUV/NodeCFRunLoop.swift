#if canImport(Darwin)

import Foundation
import CNodeUV

public enum NodeCFRunLoop {
    // would ideally be marked @MainActor but we can't prove that
    // MainActor == NodeActor, because the runtime notices that the Node actor
    // is active when it runs (although this is also on the main thread...),
    // causing MainActor.assumeIsolated to abort.
    private nonisolated(unsafe) static var cancelHandlers: (() -> Void)?
    private nonisolated(unsafe) static var refCount = 0

    public static func ref() {
        refCount += 1
        // check the mode to determine whether the RunLoop is already running.
        // this could be the case if we're in an Electron (or other embedder)
        // context. only set up our own loop if it's not running.
        if refCount == 1 && RunLoop.main.currentMode == nil {
            cancelHandlers = setUp()
        }
    }

    public static func unref() {
        if Thread.isMainThread {
            _unref()
        } else {
            Task { @MainActor in _unref() }
        }
    }

    private static func _unref() {
        refCount -= 1
        if refCount == 0 {
            cancelHandlers?()
            cancelHandlers = nil
        }
    }

    private static func setUp() -> (() -> Void) {
        #if false
        // By default, node takes over the main thread with an indefinite uv_run().
        // This causes CFRunLoop sources to not be processed (also breaking GCD & MainActor)
        // since the CFRunLoop never gets ticked. We instead need to flip things on their
        // head: ie use CFRunLoop as the main driver of the process. This is feasible because
        // libuv offers an API to "embed" its RunLoop into another. Specifically, it exposes
        // a backend file descriptor & timer; we can tell GCD to watch these. Any time they
        // trigger, we tick the uv loop once.

        // References:
        // https://github.com/TooTallNate/NodObjC/issues/2
        // https://github.com/electron/electron/blob/dac5e0cd1a8d31272f428d08289b4b66cb9192fc/shell/common/node_bindings.cc#L962
        // https://github.com/electron/electron/blob/dac5e0cd1a8d31272f428d08289b4b66cb9192fc/shell/common/node_bindings_mac.cc#L24
        // https://github.com/indutny/node-cf/blob/de90092bb65bbdb6acbd0b00e18a360028b815f5/src/cf.cc
        // [SpinEventLoopInternal]: https://github.com/nodejs/node/blob/11222f1a272b9b2ab000e75cbe3e09942bd2d877/src/api/embed_helpers.cc#L41

        let loop = uv_default_loop()
        let fd = uv_backend_fd(loop)

        let reader = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        let timer = DispatchSource.makeTimerSource(queue: .main)

        nonisolated(unsafe) let wakeUpUV = {
            let runResult = uv_run(loop, UV_RUN_NOWAIT)
            guard runResult != 0 else { return }

            reader.activate()

            let timeout = Int(uv_backend_timeout(loop))
            if timeout != -1 {
                timer.schedule(deadline: .now() + .milliseconds(timeout))
                timer.activate()
            }
        }

        reader.setEventHandler { wakeUpUV() }
        timer.setEventHandler { wakeUpUV() }
        // bootstrap
        DispatchQueue.main.async { wakeUpUV() }

        // Now that we've set up the CF/GCD sources, we need to
        // start the CFRunLoop. Ideally, we'd patch the Node.js
        // source to 1) perform the above setup and 2) replace
        // its uv_run with RunLoop.run: insertion point would
        // be [SpinEventLoopInternal] linked above.
        // However, the hacky alternative (while avoiding the need
        // to patch Node) is to kick off the CFRunLoop inside the next
        // uv tick. This is hacky because we eventually end up with
        // a callstack that looks like:
        // uv_run -> [process uv_async_t] -> RunLoop.run
        // -> [some event uv cares about] -> wakeUpUV -> uv_run
        // Note that uv_run is called re-entrantly here, which is
        // explicitly unsupported per the documentation. This seems
        // to work okay based on rudimentary testing but could definitely
        // break in the future / under edge cases.
        // TODO: figure out whether there's a better solution.
        let uvAsync = OpaquePointer(UnsafeMutableRawPointer.allocate(
            // for ABI stability, don't hardcode current uv_async_t size
            byteCount: uv_handle_size(UV_ASYNC),
            alignment: MemoryLayout<max_align_t>.alignment
        ))
        uv_async_init(loop, uvAsync) { _ in
            while NodeCFRunLoop.refCount > 0 && RunLoop.main.run(mode: .default, before: .distantFuture) {}
        }
        uv_async_send(uvAsync)

        return {
            reader.cancel()
            timer.cancel()
            uv_close(uvAsync) { UnsafeMutableRawPointer($0)?.deallocate() }
        }
        #else
        // This is a slightly less intrusive approach than the above,
        // since it doesn't replace the existing uv loop (but it's less
        // powerful):
        //
        // It's fragile to try extracting the CFRunLoop's entire waitset,
        // but if we're okay with only supporting the GCD bits,
        // we can extract GCD's mach port with _dispatch_get_main_queue_port_4CF
        // and integrate it into uv. Inspiration:
        // https://gist.github.com/daurnimator/8cc2ef09ad72a5577b66f34957559e47
        //
        // It's theoretically possible to support all of CF this way, but it
        // would be fragile. Specifically, we can union the GCD port with
        // CFRunLoop->_currentMode->_portSet and create a uv_poll from there
        // (like we currently do in this code), and also add a uv_timer_t with
        // `CFRunLoopGetNextTimerFireDate`. The issue is that extracting the
        // port set is extra fragile due to unstable struct layout.
        //
        // https://github.com/swiftlang/swift-corelibs-foundation/blob/ae61520/Sources/CoreFoundation/CFRunLoop.c#L3014

        let fd = getDispatchFileDescriptor()

        let uvPoll = OpaquePointer(UnsafeMutableRawPointer.allocate(
            byteCount: uv_handle_size(UV_POLL),
            alignment: MemoryLayout<max_align_t>.alignment
        ))
        uv_poll_init(uv_default_loop(), uvPoll, fd)
        uv_poll_start(uvPoll, CInt(UV_READABLE.rawValue)) { _, _, _ in
            _dispatch_main_queue_callback_4CF()
        }

        return {
            uv_close(uvPoll) {
                UnsafeMutableRawPointer($0)?.deallocate()
            }
        }
        #endif
    }

    // TODO: error handling
    private static func getDispatchFileDescriptor() -> CInt {
        let port = _dispatch_get_main_queue_port_4CF()

        #if canImport(Darwin)
        var portset = mach_port_t()
        mach_port_allocate(mach_task_self_, MACH_PORT_RIGHT_PORT_SET, &portset)
        mach_port_insert_member(mach_task_self_, port, portset)

        let fd = kqueue()
        let changelist = [node_swift_create_event_descriptor_for_mach_port(portset)]
        var timeout = timespec(tv_sec: 0, tv_nsec: 0)
        kevent64(fd, changelist, numericCast(changelist.count), nil, 0, 0, &timeout)

        return fd
        #elseif os(Linux)
        // TODO: drop the top level canImport guard
        // also support BSD (and Windows if possible)
        return CInt(port)
        #endif
    }
}

#else

public enum NodeCFRunLoop {
    public static func ref() {}
    public static func unref()
}

#endif
