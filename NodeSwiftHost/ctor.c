// napi_addon_register_func doesn't have a "context" param, so we
// can't declare our register func in NodeAPI (which is shared).
// Instead, each NodeSwift package contains its own register func,
// local_reg, which is a trampoline that passes along some context
// to node_swift_addon_register_func.
//
// This context can be any handle that we have during main() as well
// as in local_reg – and so the local_reg function pointer itself is
// a good candidate. This pointer is associated with the NodeModule
// via a dictionary in node_swift_main, and a lookup for the same is
// performed later in node_swift_addon_register_func.

typedef void *(*napi_addon_register_func)(void *env, void *exports);

void node_swift_main(int (*main)(void), napi_addon_register_func local_reg);
void *node_swift_addon_register_func(void *env, void *exports, napi_addon_register_func local_reg);

static void *local_reg(void *env, void *exports) {
    return node_swift_addon_register_func(env, exports, local_reg);
}

int main(void);
__attribute__((constructor)) static void ctor() {
    node_swift_main(main, local_reg);
}
