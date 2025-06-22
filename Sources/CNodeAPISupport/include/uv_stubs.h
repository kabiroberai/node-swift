#ifndef uv_stubs_h
#define uv_stubs_h

#ifdef __APPLE__

#include <stdlib.h>

typedef enum {
    UV_RUN_DEFAULT = 0,
    UV_RUN_ONCE,
    UV_RUN_NOWAIT
} uv_run_mode;

typedef enum {
    UV_ASYNC = 1,
} uv_handle_type;

typedef struct uv_handle_s uv_handle_t;
typedef struct uv_loop_s uv_loop_t;
typedef struct uv_async_s uv_async_t;
typedef void (*uv_async_cb)(uv_async_t *handle);

size_t uv_handle_size(uv_handle_type type);
void uv_close(uv_handle_t *handle, void *close_cb);

uv_loop_t *uv_default_loop(void);
int uv_backend_fd(const uv_loop_t *);
int uv_backend_timeout(const uv_loop_t *);
int uv_run(uv_loop_t *, uv_run_mode mode);
int uv_loop_alive(const uv_loop_t *loop);

int uv_async_init(uv_loop_t *loop,
                  uv_async_t *async,
                  uv_async_cb async_cb);
int uv_async_send(uv_async_t *async);

#endif /* __APPLE__ */

#endif /* uv_stubs_h */
