// napi_addon_register_func doesn't have a "context" param, so we
// can't declare our register func in NodeAPI (which is shared).
// Instead, each NodeSwift package contains its own register func,
// local_reg, which is a trampoline that passes along some context
// to node_swift_addon_register_func.

typedef void *(*napi_addon_register_func)(void *env, void *exports);
typedef struct {
    int nm_version;
    unsigned int nm_flags;
    const char* nm_filename;
    napi_addon_register_func nm_register_func;
    const char* nm_modname;
    void* nm_priv;
    void* reserved[4];
} napi_module;

static void *local_reg(void *env, void *exports);
static napi_module module = {
    .nm_register_func = local_reg
};

void node_swift_main(int (*main)(void), napi_module *module);
void *node_swift_addon_register_func(void *env, void *exports, const napi_module *module);

static void *local_reg(void *env, void *exports) {
    return node_swift_addon_register_func(env, exports, &module);
}

int main(void);
__attribute__((constructor)) static void ctor() {
    node_swift_main(main, &module);
}
