#include <node_init.h>

static __thread napi_module *thread_module = NULL;

napi_module *node_swift_get_thread_module() {
    return thread_module;
}

// we can't pass params to main, so use TLS to store the current local_module.
// This is then retrieved in main (-> NodeModule.main), and the NodeModule.Type
// is assigned to mod.priv
void node_swift_main(int (*main)(void), napi_module *local_module) {
    thread_module = local_module;
    main();
    thread_module = NULL;
}
