#ifdef _WIN32
#include "../../CNodeAPI/vendored/node_api.h"
#else
@import Foundation;
@import CNodeAPI;
#endif

napi_value node_swift_register(napi_env);

NAPI_MODULE_INIT() {
    return node_swift_register(env);
}
