#ifndef node_init_h
#define node_init_h

#include <vendored/node_api.h>

_Pragma("clang assume_nonnull begin")

napi_module * _Nullable node_swift_get_thread_module(void);
void node_swift_main(int (*main)(void), napi_module *local_module);

_Pragma("clang assume_nonnull end")

#endif /* node_init_h */
