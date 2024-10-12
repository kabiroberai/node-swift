#include "../../CNodeAPI/vendored/node_api.h"

NAPI_MODULE_INIT() {
    return node_swift_register(env);
}
