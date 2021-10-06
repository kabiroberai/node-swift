#ifndef node_init_h
#define node_init_h

#include <vendored/node_api.h>

_Pragma("clang assume_nonnull begin")

napi_addon_register_func _Nullable node_swift_get_thread_register_fn(void);
void node_swift_main(int (*main)(void), napi_addon_register_func local_reg);

_Pragma("clang assume_nonnull end")

#endif /* node_init_h */
