#if canImport(Darwin)

import Foundation
import CNodeAPISupport

public enum UV {
    public static func setup() {
        MainActor.assumeIsolated { _setup() }
    }

    @MainActor private static func _setup() {
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

        let wakeUpUV = {
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
        // its uv_run with CFRunLoopRun: insertion point would
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
            RunLoop.main.run()
        }
        uv_async_send(uvAsync)
    }
}

#endif
