#pragma once

#include <JavaScriptCore/JavaScriptCore.h>

typedef struct napi_env__* napi_env;

typedef void (*napi_executor_free)(void *);
typedef void (*napi_executor_assert_current)(void *);
typedef void (*napi_executor_dispatch_async)(void *, void(*)(void *), void *);

typedef struct napi_executor {
  uint64_t version; // should be 1
  void *context;
  napi_executor_free free;
  napi_executor_assert_current assert_current;
  napi_executor_dispatch_async dispatch_async;
} napi_executor;

#ifdef __cplusplus
#define NAPI_JSC_EXTERN_C extern "C"
#else
#define NAPI_JSC_EXTERN_C
#endif

NAPI_JSC_EXTERN_C napi_env napi_env_jsc_create(JSGlobalContextRef context, napi_executor executor);
NAPI_JSC_EXTERN_C void napi_env_jsc_delete(napi_env env);
