#if canImport(Darwin)

import Foundation
import CNodeAPISupport
internal import CNodeAPI

public enum UV {
    public static func setup() {
        MainActor.assumeIsolated { _setup() }
    }

    @MainActor private static func _setup() {
        // https://github.com/electron/electron/blob/dac5e0cd1a8d31272f428d08289b4b66cb9192fc/shell/common/node_bindings.cc#L962
        // https://github.com/electron/electron/blob/dac5e0cd1a8d31272f428d08289b4b66cb9192fc/shell/common/node_bindings_mac.cc#L24

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

        reader.setEventHandler {
            wakeUpUV()
        }

        timer.setEventHandler {
            wakeUpUV()
        }

        DispatchQueue.main.async {
            wakeUpUV()
        }

        // TODO: figure out whether this is supported.
        // specifically, RunLoop.main.run inside an async block,
        // which services DispatchQueue.main.sync { uv_run() },
        // means the above uv_run is called inside the node shell's
        // uv_run. The docs say uv_run isn't re-entrant, whoops.
        //
        // Ideally, we'd 1) perform the above setup and
        // 2) replace Node's main uv_run with a RunLoop.main.run()
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
