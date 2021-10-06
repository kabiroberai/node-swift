#include <node_init.h>

static __thread napi_addon_register_func thread_reg = NULL;

napi_addon_register_func node_swift_get_thread_register_fn() {
    return thread_reg;
}

// we can't pass params to main, so use TLS to store the current local_reg.
// This is then retrieved in main (-> NodeModule.main), and used to populate
// the dict.
void node_swift_main(int (*main)(void), napi_addon_register_func local_reg) {
    thread_reg = local_reg;
    main();
    thread_reg = NULL;
}
