@import Foundation;
@import CNodeAPI;

NAPI_MODULE_INIT() {
    napi_value node_swift_register(napi_env);
    return node_swift_register(env);
}
