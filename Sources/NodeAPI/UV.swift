#if canImport(Darwin)

import Foundation
import CNodeAPISupport
internal import CNodeAPI

public enum UV {
    public static func setup() {
        nonisolated(unsafe) let loop = uv_default_loop()

        // https://github.com/electron/electron/blob/dac5e0cd1a8d31272f428d08289b4b66cb9192fc/shell/common/node_bindings.cc#L962
        let poller = Thread {
            nonisolated(unsafe) let loop = loop

            while !Thread.current.isCancelled {
                // https://github.com/electron/electron/blob/dac5e0cd1a8d31272f428d08289b4b66cb9192fc/shell/common/node_bindings_mac.cc#L24
                let fd = uv_backend_fd(loop)
                let timeoutMS = Int(uv_backend_timeout(loop))
                var readset = fd_set()
                node_swift_fd_set(fd, &readset)
                var result: Int32
                repeat {
                    if timeoutMS == -1 {
                        result = select(fd + 1, &readset, nil, nil, nil)
                    } else {
                        var timeout = timeval(
                            tv_sec: timeoutMS / 1000,
                            tv_usec: Int32((timeoutMS % 1000) * 1000)
                        )
                        result = select(fd + 1, &readset, nil, nil, &timeout)
                    }
                } while result == -1 && errno == EINTR

                let runResult = DispatchQueue.main.sync {
                    uv_run(loop, UV_RUN_NOWAIT)
                }
                if runResult == 0 { break }
            }
        }
        poller.start()

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
