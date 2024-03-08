// Based on code from BabylonNative, licensed under the MIT license.
// See: https://github.com/BabylonJS/JsRuntimeHost

#include "../CNodeAPI/vendored/node_api.h"
#include "embedder.h"
#include <mutex>
#include <unordered_set>
#include <unordered_map>
#include <list>
#include <thread>
#include <algorithm>
#include <cassert>
#include <cmath>
#include <cstring>
#include <functional>
#include <stdexcept>
#include <string>
#include <vector>
#include <locale>

#define RETURN_STATUS_IF_FALSE(env, condition, status) \
  do {                                                 \
    if (!(condition)) {                                \
      return napi_set_last_error((env), (status));     \
    }                                                  \
  } while (0)

#define CHECK_ENV(env)                                    \
  do {                                                    \
    if ((env) == nullptr) {                               \
      return napi_invalid_arg;                            \
    }                                                     \
    env->executor.assert_current(env->executor.context); \
  } while (0)

#define CHECK_ARG(env, arg) \
  RETURN_STATUS_IF_FALSE((env), ((arg) != nullptr), napi_invalid_arg)

#define CHECK_JSC(env, exception)                \
  do {                                           \
    if ((exception) != nullptr) {                \
      return napi_set_exception(env, exception); \
    }                                            \
  } while (0)

// This does not call napi_set_last_error because the expression
// is assumed to be a NAPI function call that already did.
#define CHECK_NAPI(expr)                  \
  do {                                    \
    napi_status status = (expr);          \
    if (status != napi_ok) return status; \
  } while (0)

struct napi_env__ {
private:
  struct pairhash {
    template <typename T, typename U>
    std::size_t operator()(const std::pair<T, U> &x) const {
      // bad hash fn but it'll do for now
      return std::hash<T>()(x.first) ^ std::hash<U>()(x.second);
    }
  };

public:
  JSGlobalContextRef context{};
  JSValueRef last_exception{};
  JSValueRef finalization_registry{};
  JSValueRef tag_map{};
  napi_extended_error_info last_error{nullptr, nullptr, 0, napi_ok};
  std::list<napi_ref> strong_refs{};
  std::unordered_map<napi_cleanup_hook, std::unordered_set<void *>> cleanup_hooks;
  std::unordered_set<void *> all_tsfns;
  std::unordered_set<void *> strong_tsfns;
  bool is_deleting = false;

  const napi_executor executor;

  napi_env__(JSGlobalContextRef context, napi_executor executor) : context{context}, executor{executor} {
    JSGlobalContextRetain(context);
  }

  ~napi_env__() {
    deinit_refs();
    JSGlobalContextRelease(context);
    executor.free(executor.context);
  }

  void check_empty() {
    if (is_deleting || !is_empty()) return;
    is_deleting = true;
    // TODO: delete
    // in fact we should strongly retain napi_env__ until check_empty succeeds.
  }
 private:
  void deinit_refs();

  bool is_empty() const {
    return strong_refs.empty() && strong_tsfns.empty();
  }
};

napi_env napi_env_jsc_create(JSGlobalContextRef context, napi_executor executor) {
  return new napi_env__{context, executor};
}

void napi_env_jsc_delete(napi_env env) {
  delete env;
}

struct napi_callback_info__ {
  napi_value newTarget;
  napi_value thisArg;
  napi_value* argv;
  void* data;
  uint16_t argc;
};

namespace {
  class JSString {
   public:
    JSString(const JSString&) = delete;

    JSString(JSString&& other) {
      _string = other._string;
      other._string = nullptr;
    }

    JSString(const char* string, size_t length = NAPI_AUTO_LENGTH)
      : _string{CreateUTF8(string, length)} {
    }

    JSString(const JSChar* string, size_t length = NAPI_AUTO_LENGTH)
      : _string{JSStringCreateWithCharacters(string, length == NAPI_AUTO_LENGTH ? std::char_traits<char16_t>::length(reinterpret_cast<const char16_t *>(string)) : length)} {
    }

    ~JSString() {
      if (_string != nullptr) {
        JSStringRelease(_string);
      }
    }

    static JSString Attach(JSStringRef string) {
      return {string};
    }

    operator JSStringRef() const {
      return _string;
    }

    size_t Length() const {
      return JSStringGetLength(_string);
    }

    size_t LengthUTF8() const {
      std::vector<char> buffer(JSStringGetMaximumUTF8CStringSize(_string));
      return JSStringGetUTF8CString(_string, buffer.data(), buffer.size()) - 1;
    }

    size_t LengthLatin1() const {
      // Latin1 has the same length as Unicode.
      return JSStringGetLength(_string);
    }

    void CopyTo(JSChar* buf, size_t bufsize, size_t* result) const {
      size_t length{JSStringGetLength(_string)};
      const JSChar* chars{JSStringGetCharactersPtr(_string)};
      size_t size{std::min(length, bufsize - 1)};
      std::memcpy(buf, chars, size);
      buf[size] = 0;
      if (result != nullptr) {
        *result = size;
      }
    }

    void CopyToUTF8(char* buf, size_t bufsize, size_t* result) const {
      size_t size{JSStringGetUTF8CString(_string, buf, bufsize)};
      if (result != nullptr) {
        // JSStringGetUTF8CString returns size with null terminator.
        *result = size - 1;
      }
    }

    void CopyToLatin1(char* buf, size_t bufsize, size_t* result) const {
      size_t length{JSStringGetLength(_string)};
      const JSChar* chars{JSStringGetCharactersPtr(_string)};
      size_t size{std::min(length, bufsize - 1)};
      for (int i = 0; i < size; ++i) {
        const JSChar ch{chars[i]};
        buf[i] = (ch < 256) ? ch : '?';
      }
      if (result != nullptr) {
        *result = size;
      }
    }

   private:
    static JSStringRef CreateUTF8(const char* string, size_t length) {
      if (length == NAPI_AUTO_LENGTH) {
        return JSStringCreateWithUTF8CString(string);
      }

      auto cfstr = CFStringCreateWithBytesNoCopy(nullptr, reinterpret_cast<const UInt8 *>(string), length, kCFStringEncodingUTF8, false, kCFAllocatorNull);
      auto jsstr = JSStringCreateWithCFString(cfstr);
      CFRelease(cfstr);
      return jsstr;
    }

    JSString(JSStringRef string)
      : _string{string} {
    }

    JSStringRef _string;
  };

  JSValueRef ToJSValue(const napi_value value) {
    return reinterpret_cast<JSValueRef>(value);
  }

  const JSValueRef* ToJSValues(const napi_value* values) {
    return reinterpret_cast<const JSValueRef*>(values);
  }

  JSObjectRef ToJSObject(napi_env env, const napi_value value) {
    assert(value == nullptr || JSValueIsObject(env->context, reinterpret_cast<JSValueRef>(value)));
    return reinterpret_cast<JSObjectRef>(value);
  }

  JSString ToJSString(napi_env env, napi_value value, JSValueRef* exception) {
    return JSString::Attach(JSValueToStringCopy(env->context, ToJSValue(value), exception));
  }

  napi_value ToNapi(const JSValueRef value) {
    return reinterpret_cast<napi_value>(const_cast<OpaqueJSValue*>(value));
  }

  napi_value* ToNapi(const JSValueRef* values) {
    return reinterpret_cast<napi_value*>(const_cast<OpaqueJSValue**>(values));
  }

  napi_status napi_clear_last_error(napi_env env) {
    env->last_error.error_code = napi_ok;
    env->last_error.engine_error_code = 0;
    env->last_error.engine_reserved = nullptr;
    return napi_ok;
  }

  napi_status napi_set_last_error(napi_env env, napi_status error_code, uint32_t engine_error_code = 0, void* engine_reserved = nullptr) {
    env->last_error.error_code = error_code;
    env->last_error.engine_error_code = engine_error_code;
    env->last_error.engine_reserved = engine_reserved;
    return error_code;
  }

  napi_status napi_set_exception(napi_env env, JSValueRef exception) {
    env->last_exception = exception;
    return napi_set_last_error(env, napi_pending_exception);
  }

  napi_status napi_set_error_code(napi_env env,
                                  napi_value error,
                                  napi_value code,
                                  const char* code_cstring) {
    napi_value code_value{code};
    if (code_value == nullptr) {
      code_value = ToNapi(JSValueMakeString(env->context, JSString(code_cstring)));
    } else {
      RETURN_STATUS_IF_FALSE(env, JSValueIsString(env->context, ToJSValue(code_value)), napi_string_expected);
    }

    CHECK_NAPI(napi_set_named_property(env, error, "code", code_value));
    return napi_ok;
  }

  enum class NativeType {
    Constructor,
    External,
    Function,
    Wrapper
  };

  class NativeInfo {
   public:
    NativeType Type() const {
      return _type;
    }

    template<typename T>
    static T* Get(JSObjectRef obj) {
      return reinterpret_cast<T*>(JSObjectGetPrivate(obj));
    }

    template<typename T>
    static T* FindInPrototypeChain(JSContextRef ctx, JSObjectRef obj) {
      while (true) {
        JSValueRef exception{};
        JSObjectRef prototype = JSValueToObject(ctx, JSObjectGetPrototype(ctx, obj), &exception);
        if (exception != nullptr) {
          return nullptr;
        }

        NativeInfo* info = Get<NativeInfo>(prototype);
        if (info != nullptr && info->Type() == T::StaticType) {
          return reinterpret_cast<T*>(info);
        }

        obj = prototype;
      }
    }

   protected:
    NativeInfo(NativeType type)
      : _type{type} {
    }

   private:
    NativeType _type;
  };

  class ConstructorInfo : public NativeInfo {
   public:
    static const NativeType StaticType = NativeType::Constructor;

    static napi_status Create(napi_env env,
                              const char* utf8name,
                              size_t length,
                              napi_callback cb,
                              void* data,
                              napi_value* result) {
      ConstructorInfo* info{new ConstructorInfo(env, utf8name, length, cb, data)};
      if (info == nullptr) {
        return napi_set_last_error(env, napi_generic_failure);
      }

      JSObjectRef constructor{JSObjectMakeConstructor(env->context, nullptr, CallAsConstructor)};
      JSObjectRef prototype{JSObjectMake(env->context, info->_class, info)};
      JSObjectSetPrototype(env->context, prototype, JSObjectGetPrototype(env->context, constructor));
      JSObjectSetPrototype(env->context, constructor, prototype);

      JSValueRef exception{};
      JSObjectSetProperty(env->context, prototype, JSString("constructor"), constructor,
        kJSPropertyAttributeReadOnly | kJSPropertyAttributeDontDelete, &exception);
      CHECK_JSC(env, exception);

      *result = ToNapi(constructor);
      return napi_ok;
    }

   private:
    ConstructorInfo(napi_env env, const char* name, size_t length, napi_callback cb, void* data)
      : NativeInfo{NativeType::Constructor}
      , _env{env}
      , _name{name, (length == NAPI_AUTO_LENGTH ? std::strlen(name) : length)}
      , _cb{cb}
      , _data{data} {
      JSClassDefinition classDefinition{kJSClassDefinitionEmpty};
      classDefinition.className = _name.data();
      classDefinition.finalize = Finalize;
      _class = JSClassCreate(&classDefinition);
    }

    ~ConstructorInfo() {
      JSClassRelease(_class);
    }

    // JSObjectCallAsConstructorCallback
    static JSObjectRef CallAsConstructor(JSContextRef ctx,
                                         JSObjectRef constructor,
                                         size_t argumentCount,
                                         const JSValueRef arguments[],
                                         JSValueRef* exception) {
      ConstructorInfo* info = NativeInfo::FindInPrototypeChain<ConstructorInfo>(ctx, constructor);

      // Make sure any errors encountered last time we were in N-API are gone.
      napi_clear_last_error(info->_env);

      JSObjectRef instance{JSObjectMake(ctx, nullptr, nullptr)};
      JSObjectSetPrototype(ctx, instance, JSObjectGetPrototype(ctx, constructor));

      napi_callback_info__ cbinfo{};
      cbinfo.thisArg = ToNapi(instance);
      cbinfo.newTarget = ToNapi(constructor);
      cbinfo.argc = argumentCount;
      cbinfo.argv = ToNapi(arguments);
      cbinfo.data = info->_data;

      napi_value result = info->_cb(info->_env, &cbinfo);

      if (info->_env->last_exception != nullptr) {
        *exception = info->_env->last_exception;
        info->_env->last_exception = nullptr;
      }

      return ToJSObject(info->_env, result);
    }

    // JSObjectFinalizeCallback
    static void Finalize(JSObjectRef object) {
      ConstructorInfo* info = NativeInfo::Get<ConstructorInfo>(object);
      assert(info->Type() == NativeType::Constructor);
      delete info;
    }

   private:
    napi_env _env;
    std::string _name;
    napi_callback _cb;
    void* _data;
    JSClassRef _class;
  };

  class FunctionInfo : public NativeInfo {
   public:
    static const NativeType StaticType = NativeType::Function;

    static napi_status Create(napi_env env,
                              const char* utf8name,
                              size_t length,
                              napi_callback cb,
                              void* data,
                              napi_value* result) {
      FunctionInfo* info{new FunctionInfo(env, cb, data)};
      if (info == nullptr) {
        return napi_set_last_error(env, napi_generic_failure);
      }

      JSObjectRef function{JSObjectMakeFunctionWithCallback(env->context, JSString(utf8name), CallAsFunction)};
      JSObjectRef prototype{JSObjectMake(env->context, info->_class, info)};
      JSObjectSetPrototype(env->context, prototype, JSObjectGetPrototype(env->context, function));
      JSObjectSetPrototype(env->context, function, prototype);

      *result = ToNapi(function);
      return napi_ok;
    }

   private:
    FunctionInfo(napi_env env, napi_callback cb, void* data)
      : NativeInfo{NativeType::Function}
      , _env{env}
      , _cb{cb}
      , _data{data} {
      JSClassDefinition definition{kJSClassDefinitionEmpty};
      definition.className = "Native";
      definition.finalize = Finalize;
      _class = JSClassCreate(&definition);
    }

    ~FunctionInfo() {
      JSClassRelease(_class);
    }

    // JSObjectCallAsFunctionCallback
    static JSValueRef CallAsFunction(JSContextRef ctx,
                                     JSObjectRef function,
                                     JSObjectRef thisObject,
                                     size_t argumentCount,
                                     const JSValueRef arguments[],
                                     JSValueRef* exception) {
      FunctionInfo* info = NativeInfo::FindInPrototypeChain<FunctionInfo>(ctx, function);

      // Make sure any errors encountered last time we were in N-API are gone.
      napi_clear_last_error(info->_env);

      napi_callback_info__ cbinfo{};
      cbinfo.thisArg = ToNapi(thisObject);
      cbinfo.newTarget = nullptr;
      cbinfo.argc = argumentCount;
      cbinfo.argv = ToNapi(arguments);
      cbinfo.data = info->_data;

      napi_value result = info->_cb(info->_env, &cbinfo);

      if (info->_env->last_exception != nullptr) {
        *exception = info->_env->last_exception;
        info->_env->last_exception = nullptr;
      }

      return ToJSValue(result);
    }

    // JSObjectFinalizeCallback
    static void Finalize(JSObjectRef object) {
      FunctionInfo* info = NativeInfo::Get<FunctionInfo>(object);
      assert(info->Type() == NativeType::Function);
      delete info;
    }

    napi_env _env;
    napi_callback _cb;
    void* _data;
    JSClassRef _class;
  };

  template<typename T, NativeType TType>
  class BaseInfoT : public NativeInfo {
   public:
    static const NativeType StaticType = TType;

    ~BaseInfoT() {
      JSClassRelease(_class);
    }

    napi_env Env() const {
      return _env;
    }

    void Data(void* value) {
      _data = value;
    }

    void* Data() const {
      return _data;
    }

    using FinalizerT = std::function<void(T*)>;
    void AddFinalizer(FinalizerT finalizer) {
      _finalizers.push_back(finalizer);
    }

   protected:
    BaseInfoT(napi_env env, const char* className)
      : NativeInfo{TType}
      , _env{env} {
      JSClassDefinition definition{kJSClassDefinitionEmpty};
      definition.className = className;
      definition.finalize = Finalize;
      _class = JSClassCreate(&definition);
    }

    // JSObjectFinalizeCallback
    static void Finalize(JSObjectRef object) {
      T* info = Get<T>(object);
      assert(info->Type() == TType);
      for (const FinalizerT& finalizer : info->_finalizers) {
        finalizer(info);
      }
      delete info;
    }

    napi_env _env;
    void* _data{};
    std::vector<FinalizerT> _finalizers{};
    JSClassRef _class{};
  };

  class ExternalInfo: public BaseInfoT<ExternalInfo, NativeType::External> {
   public:
    static napi_status Create(napi_env env,
                              void* data,
                              napi_finalize finalize_cb,
                              void* finalize_hint,
                              napi_value* result) {
      ExternalInfo* info = new ExternalInfo(env);
      if (info == nullptr) {
        return napi_set_last_error(env, napi_generic_failure);
      }

      info->Data(data);

      if (finalize_cb != nullptr) {
        info->AddFinalizer([finalize_cb, finalize_hint](ExternalInfo* info) {
          finalize_cb(info->Env(), info->Data(), finalize_hint);
        });
      }

      *result = ToNapi(JSObjectMake(env->context, info->_class, info));
      return napi_ok;
    }

   private:
    ExternalInfo(napi_env env)
      : BaseInfoT{env, "Native (External)"} {
    }
  };

  class WrapperInfo : public BaseInfoT<WrapperInfo, NativeType::Wrapper> {
   public:
    static napi_status Wrap(napi_env env, napi_value object, WrapperInfo** result) {
      WrapperInfo* info{};
      CHECK_NAPI(Unwrap(env, object, &info));
      if (info == nullptr) {
        info = new WrapperInfo(env);
        if (info == nullptr) {
          return napi_set_last_error(env, napi_generic_failure);
        }

        JSObjectRef prototype{JSObjectMake(env->context, info->_class, info)};
        JSObjectSetPrototype(env->context, prototype, JSObjectGetPrototype(env->context, ToJSObject(env, object)));
        JSObjectSetPrototype(env->context, ToJSObject(env, object), prototype);
      }

      *result = info;
      return napi_ok;
    }

    static napi_status Unwrap(napi_env env, napi_value object, WrapperInfo** result) {
      *result = NativeInfo::FindInPrototypeChain<WrapperInfo>(env->context, ToJSObject(env, object));
      return napi_ok;
    }

   private:
    WrapperInfo(napi_env env)
      : BaseInfoT{env, "Native (Wrapper)"} {
    }
  };

  class ExternalArrayBufferInfo {
   public:
    static napi_status Create(napi_env env,
                              void* external_data,
                              size_t byte_length,
                              napi_finalize finalize_cb,
                              void* finalize_hint,
                              napi_value* result) {
      ExternalArrayBufferInfo* info{new ExternalArrayBufferInfo(env, finalize_cb, finalize_hint)};
      if (info == nullptr) {
        return napi_set_last_error(env, napi_generic_failure);
      }

      JSValueRef exception{};
      *result = ToNapi(JSObjectMakeArrayBufferWithBytesNoCopy(
        env->context,
        external_data,
        byte_length,
        BytesDeallocator,
        info,
        &exception));
      CHECK_JSC(env, exception);

      return napi_ok;
    }

   private:
    ExternalArrayBufferInfo(napi_env env, napi_finalize finalize_cb, void* hint)
      : _env{env}
      , _cb{finalize_cb}
      , _hint{hint} {
    }

    // JSTypedArrayBytesDeallocator
    static void BytesDeallocator(void* bytes, void* deallocatorContext) {
      ExternalArrayBufferInfo* info{reinterpret_cast<ExternalArrayBufferInfo*>(deallocatorContext)};
      if (info->_cb != nullptr) {
        info->_cb(info->_env, bytes, info->_hint);
      }
      delete info;
    }

    napi_env _env;
    napi_finalize _cb;
    void* _hint;
  };
}

static napi_value finalizer_cb(napi_env env, napi_callback_info info) {
  napi_value undefined;
  napi_get_undefined(env, &undefined);

  void *external = nullptr;
  if (napi_get_value_external(env, info->argv[0], &external) != napi_ok || !external) return undefined;

  (*static_cast<std::function<void(void)> *>(external))();

  return undefined;
}

static void finalizer_data_cb(napi_env env, void *finalize_data, void *finalize_hint) {
  delete static_cast<std::function<void(void)> *>(finalize_data);
}

static napi_status add_finalizer(napi_env env, napi_value value, std::function<void(void)> did_finalize) {
  napi_value registry;
  if (env->finalization_registry) {
    registry = ToNapi(env->finalization_registry);
  } else {
    napi_value global{}, registry_ctor{}, registry_cb{}, registry_{};
    CHECK_NAPI(napi_get_global(env, &global));
    CHECK_NAPI(napi_get_named_property(env, global, "FinalizationRegistry", &registry_ctor));
    CHECK_NAPI(napi_create_function(env, "", 0, finalizer_cb, nullptr, &registry_cb));
    CHECK_NAPI(napi_new_instance(env, registry_ctor, 1, &registry_cb, &registry_));
    JSValueRef js_registry = ToJSValue(registry_);
    JSValueProtect(env->context, js_registry);
    env->finalization_registry = js_registry;
    registry = registry_;
  }
  napi_value register_fn{}, ext{};
  CHECK_NAPI(napi_get_named_property(env, registry, "register", &register_fn));
  void *finalizer_data = new std::function<void(void)> { std::move(did_finalize) };
  CHECK_NAPI(napi_create_external(env, finalizer_data, finalizer_data_cb, nullptr, &ext));
  napi_value args[] { value, ext };
  CHECK_NAPI(napi_call_function(env, registry, register_fn, 2, args, nullptr));
  return napi_ok;
}

struct napi_ref__ {
  napi_ref__(napi_env env, napi_value value, uint32_t count)
  : _value{value}, _count{count}, _has_deleted{std::make_shared<bool>(false)} {
    if (_count != 0) {
      protect(env);
    }

    // we use has_deleted to signal that the napi_ref has been `delete`d
    // via napi_delete_reference. If the ref has been deleted, setting
    // this->_value=nullptr would be a UAF (and would be redundant) so
    // we skip it in that case.
    add_finalizer(env, _value, [has_deleted=_has_deleted, self=this] {
      if (!has_deleted) self->_value = nullptr;
    });

    return napi_ok;
  }

  void deinit(napi_env env) {
    if (_count != 0) {
      unprotect(env);
    }

    *_has_deleted = true;
    _value = nullptr;
    _count = 0;
  }

  void ref(napi_env env) {
    if (_count++ == 0) {
      protect(env);
    }
  }

  void unref(napi_env env) {
    if (--_count == 0) {
      unprotect(env);
    }
  }

  uint32_t count() const {
    return _count;
  }

  napi_value value(napi_env env) const {
    return _value;
  }

 private:
  void protect(napi_env env) {
    _iter = env->strong_refs.insert(env->strong_refs.end(), this);
    JSValueProtect(env->context, ToJSValue(_value));
  }

  void unprotect(napi_env env) {
    env->strong_refs.erase(_iter);
    JSValueUnprotect(env->context, ToJSValue(_value));
    env->check_empty();
  }

  napi_value _value{};
  std::shared_ptr<bool> _has_deleted;
  uint32_t _count{};
  std::list<napi_ref>::iterator _iter{};
};

struct napi_threadsafe_function__ {
  napi_env env;
  std::mutex mutex;
  int64_t refcount;

  void *context;

  void* thread_finalize_data;
  napi_finalize thread_finalize_cb;

  napi_value js_value;
  napi_threadsafe_function_call_js call_js_cb;
};

void napi_env__::deinit_refs() {
  for (auto &[hook, args] : cleanup_hooks) {
    for (auto &arg : args) hook(arg);
  }
  cleanup_hooks.clear();
  while (!strong_refs.empty()) {
    napi_ref ref{strong_refs.front()};
    ref->deinit(this);
  }
}

// Warning: Keep in-sync with napi_status enum
static const char* error_messages[] = {
  nullptr,
  "Invalid argument",
  "An object was expected",
  "A string was expected",
  "A string or symbol was expected",
  "A function was expected",
  "A number was expected",
  "A boolean was expected",
  "An array was expected",
  "Unknown failure",
  "An exception is pending",
  "The async work item was cancelled",
  "napi_escape_handle already called on scope",
  "Invalid handle scope usage",
  "Invalid callback scope usage",
  "Thread-safe function queue is full",
  "Thread-safe function handle is closing",
  "A bigint was expected",
};

napi_status napi_get_last_error_info(napi_env env,
                                     const napi_extended_error_info** result) {
  CHECK_ENV(env);
  CHECK_ARG(env, result);

  // you must update this assert to reference the last message
  // in the napi_status enum each time a new error message is added.
  // We don't have a napi_status_last as this would result in an ABI
  // change each time a message was added.
  static_assert(
    std::size(error_messages) == napi_bigint_expected + 1,
    "Count of error messages must match count of error values");
  assert(env->last_error.error_code <= napi_callback_scope_mismatch);

  // Wait until someone requests the last error information to fetch the error
  // message string
  env->last_error.error_message =
    error_messages[env->last_error.error_code];

  *result = &env->last_error;
  return napi_ok;
}

napi_status napi_create_function(napi_env env,
                                 const char* utf8name,
                                 size_t length,
                                 napi_callback cb,
                                 void* callback_data,
                                 napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, result);

  CHECK_NAPI(FunctionInfo::Create(env, utf8name, length, cb, callback_data, result));
  return napi_ok;
}

napi_status napi_define_class(napi_env env,
                              const char* utf8name,
                              size_t length,
                              napi_callback cb,
                              void* data,
                              size_t property_count,
                              const napi_property_descriptor* properties,
                              napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, result);

  napi_value constructor{};
  CHECK_NAPI(ConstructorInfo::Create(env, utf8name, length, cb, data, &constructor));

  int instancePropertyCount{0};
  int staticPropertyCount{0};
  for (size_t i = 0; i < property_count; i++) {
    if ((properties[i].attributes & napi_static) != 0) {
      staticPropertyCount++;
    } else {
      instancePropertyCount++;
    }
  }

  std::vector<napi_property_descriptor> staticDescriptors{};
  std::vector<napi_property_descriptor> instanceDescriptors{};
  staticDescriptors.reserve(staticPropertyCount);
  instanceDescriptors.reserve(instancePropertyCount);

  for (size_t i = 0; i < property_count; i++) {
    if ((properties[i].attributes & napi_static) != 0) {
      staticDescriptors.push_back(properties[i]);
    } else {
      instanceDescriptors.push_back(properties[i]);
    }
  }

  if (staticPropertyCount > 0) {
    CHECK_NAPI(napi_define_properties(env,
                                      constructor,
                                      staticDescriptors.size(),
                                      staticDescriptors.data()));
  }

  if (instancePropertyCount > 0) {
    napi_value prototype{};
    CHECK_NAPI(napi_get_prototype(env, constructor, &prototype));

    CHECK_NAPI(napi_define_properties(env,
                                      prototype,
                                      instanceDescriptors.size(),
                                      instanceDescriptors.data()));
  }

  *result = constructor;
  return napi_ok;
}

napi_status napi_get_property_names(napi_env env,
                                    napi_value object,
                                    napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, result);

  napi_value global{}, object_ctor{}, function{};
  CHECK_NAPI(napi_get_global(env, &global));
  CHECK_NAPI(napi_get_named_property(env, global, "Object", &object_ctor));
  CHECK_NAPI(napi_get_named_property(env, object_ctor, "getOwnPropertyNames", &function));
  CHECK_NAPI(napi_call_function(env, object_ctor, function, 1, &object, result));

  return napi_ok;
}

napi_status napi_set_property(napi_env env,
                              napi_value object,
                              napi_value key,
                              napi_value value) {
  CHECK_ENV(env);
  CHECK_ARG(env, key);
  CHECK_ARG(env, value);

  JSValueRef exception{};
  JSString key_str{ToJSString(env, key, &exception)};
  CHECK_JSC(env, exception);

  JSObjectSetProperty(
    env->context,
    ToJSObject(env, object),
    key_str,
    ToJSValue(value),
    kJSPropertyAttributeNone,
    &exception);
  CHECK_JSC(env, exception);

  return napi_ok;
}

napi_status napi_has_property(napi_env env,
                              napi_value object,
                              napi_value key,
                              bool* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, result);
  CHECK_ARG(env, key);

  JSValueRef exception{};
  JSString key_str{ToJSString(env, key, &exception)};
  CHECK_JSC(env, exception);

  *result = JSObjectHasProperty(
    env->context,
    ToJSObject(env, object),
    key_str);
  return napi_ok;
}

napi_status napi_get_property(napi_env env,
                              napi_value object,
                              napi_value key,
                              napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, key);
  CHECK_ARG(env, result);

  JSValueRef exception{};
  JSString key_str{ToJSString(env, key, &exception)};
  CHECK_JSC(env, exception);

  *result = ToNapi(JSObjectGetProperty(
    env->context,
    ToJSObject(env, object),
    key_str,
    &exception));
  CHECK_JSC(env, exception);

  return napi_ok;
}

napi_status napi_delete_property(napi_env env,
                                 napi_value object,
                                 napi_value key,
                                 bool* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, result);

  JSValueRef exception{};
  JSString key_str{ToJSString(env, key, &exception)};
  CHECK_JSC(env, exception);

  *result = JSObjectDeleteProperty(
    env->context,
    ToJSObject(env, object),
    key_str,
    &exception);
  CHECK_JSC(env, exception);

  return napi_ok;
}

NAPI_EXTERN napi_status napi_has_own_property(napi_env env,
                                              napi_value object,
                                              napi_value key,
                                              bool* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, result);

  napi_value global{}, object_ctor{}, function{}, value{};
  CHECK_NAPI(napi_get_global(env, &global));
  CHECK_NAPI(napi_get_named_property(env, global, "Object", &object_ctor));
  CHECK_NAPI(napi_get_named_property(env, object_ctor, "hasOwnProperty", &function));
  CHECK_NAPI(napi_call_function(env, object_ctor, function, 1, &object, &value));
  *result = JSValueToBoolean(env->context, ToJSValue(value));

  return napi_ok;
}

napi_status napi_set_named_property(napi_env env,
                                    napi_value object,
                                    const char* utf8name,
                                    napi_value value) {
  CHECK_ENV(env);
  CHECK_ARG(env, value);

  JSValueRef exception{};
  JSObjectSetProperty(
    env->context,
    ToJSObject(env, object),
    JSString(utf8name),
    ToJSValue(value),
    kJSPropertyAttributeNone,
    &exception);
  CHECK_JSC(env, exception);

  return napi_ok;
}

napi_status napi_has_named_property(napi_env env,
                                    napi_value object,
                                    const char* utf8name,
                                    bool* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, object);

  *result = JSObjectHasProperty(
    env->context,
    ToJSObject(env, object),
    JSString(utf8name));

  return napi_ok;
}

napi_status napi_get_named_property(napi_env env,
                                    napi_value object,
                                    const char* utf8name,
                                    napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, object);

  JSValueRef exception{};
  *result = ToNapi(JSObjectGetProperty(
    env->context,
    ToJSObject(env, object),
    JSString(utf8name),
    &exception));
  CHECK_JSC(env, exception);

  return napi_ok;
}

napi_status napi_set_element(napi_env env,
                             napi_value object,
                             uint32_t index,
                             napi_value value) {
  CHECK_ENV(env);
  CHECK_ARG(env, value);

  JSValueRef exception{};
  JSObjectSetPropertyAtIndex(
    env->context,
    ToJSObject(env, object),
    index,
    ToJSValue(value),
    &exception);
  CHECK_JSC(env, exception);

  return napi_ok;
}

napi_status napi_has_element(napi_env env,
                             napi_value object,
                             uint32_t index,
                             bool* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, result);

  JSValueRef exception{};
  JSValueRef value{JSObjectGetPropertyAtIndex(
    env->context,
    ToJSObject(env, object),
    index,
    &exception)};
  CHECK_JSC(env, exception);

  *result = !JSValueIsUndefined(env->context, value);
  return napi_ok;
}

napi_status napi_get_element(napi_env env,
                             napi_value object,
                             uint32_t index,
                             napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, result);

  JSValueRef exception{};
  *result = ToNapi(JSObjectGetPropertyAtIndex(
    env->context,
    ToJSObject(env, object),
    index,
    &exception));
  CHECK_JSC(env, exception);

  return napi_ok;
}

napi_status napi_delete_element(napi_env env,
                                napi_value object,
                                uint32_t index,
                                bool* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, result);

  napi_value index_value{ToNapi(JSValueMakeNumber(env->context, index))};

  JSValueRef exception{};
  JSString index_str{ToJSString(env, index_value, &exception)};
  CHECK_JSC(env, exception);

  *result = JSObjectDeleteProperty(
    env->context,
    ToJSObject(env, object),
    index_str,
    &exception);
  CHECK_JSC(env, exception);

  return napi_ok;
}

napi_status napi_define_properties(napi_env env,
                                   napi_value object,
                                   size_t property_count,
                                   const napi_property_descriptor* properties) {
  CHECK_ENV(env);
  if (property_count > 0) {
    CHECK_ARG(env, properties);
  }

  for (size_t i = 0; i < property_count; i++) {
    const napi_property_descriptor* p{properties + i};

    napi_value descriptor{};
    CHECK_NAPI(napi_create_object(env, &descriptor));

    napi_value configurable{};
    CHECK_NAPI(napi_get_boolean(env, (p->attributes & napi_configurable), &configurable));
    CHECK_NAPI(napi_set_named_property(env, descriptor, "configurable", configurable));

    napi_value enumerable{};
    CHECK_NAPI(napi_get_boolean(env, (p->attributes & napi_configurable), &enumerable));
    CHECK_NAPI(napi_set_named_property(env, descriptor, "enumerable", enumerable));

    if (p->getter != nullptr || p->setter != nullptr) {
      if (p->getter != nullptr) {
        napi_value getter{};
        CHECK_NAPI(napi_create_function(env, p->utf8name, NAPI_AUTO_LENGTH, p->getter, p->data, &getter));
        CHECK_NAPI(napi_set_named_property(env, descriptor, "get", getter));
      }
      if (p->setter != nullptr) {
        napi_value setter{};
        CHECK_NAPI(napi_create_function(env, p->utf8name, NAPI_AUTO_LENGTH, p->setter, p->data, &setter));
        CHECK_NAPI(napi_set_named_property(env, descriptor, "set", setter));
      }
    } else if (p->method != nullptr) {
      napi_value method{};
      CHECK_NAPI(napi_create_function(env, p->utf8name, NAPI_AUTO_LENGTH, p->method, p->data, &method));
      CHECK_NAPI(napi_set_named_property(env, descriptor, "value", method));
    } else {
      RETURN_STATUS_IF_FALSE(env, p->value != nullptr, napi_invalid_arg);

      napi_value writable{};
      CHECK_NAPI(napi_get_boolean(env, (p->attributes & napi_writable), &writable));
      CHECK_NAPI(napi_set_named_property(env, descriptor, "writable", writable));

      CHECK_NAPI(napi_set_named_property(env, descriptor, "value", p->value));
    }

    napi_value propertyName{};
    if (p->utf8name == nullptr) {
      propertyName = p->name;
    } else {
      CHECK_NAPI(napi_create_string_utf8(env, p->utf8name, NAPI_AUTO_LENGTH, &propertyName));
    }

    napi_value global{}, object_ctor{}, function{};
    CHECK_NAPI(napi_get_global(env, &global));
    CHECK_NAPI(napi_get_named_property(env, global, "Object", &object_ctor));
    CHECK_NAPI(napi_get_named_property(env, object_ctor, "defineProperty", &function));

    napi_value args[] = { object, propertyName, descriptor };
    CHECK_NAPI(napi_call_function(env, object_ctor, function, 3, args, nullptr));
  }

  return napi_ok;
}

napi_status napi_is_array(napi_env env, napi_value value, bool* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, value);
  CHECK_ARG(env, result);

  *result = JSValueIsArray(
    env->context,
    ToJSValue(value));
  return napi_ok;
}

napi_status napi_get_array_length(napi_env env,
                                  napi_value value,
                                  uint32_t* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, value);
  CHECK_ARG(env, result);

  JSValueRef exception{};
  JSValueRef length = JSObjectGetProperty(
    env->context,
    ToJSObject(env, value),
    JSString("length"),
    &exception);
  CHECK_JSC(env, exception);

  *result = static_cast<uint32_t>(JSValueToNumber(env->context, length, &exception));
  CHECK_JSC(env, exception);

  return napi_ok;
}

napi_status napi_strict_equals(napi_env env,
                               napi_value lhs,
                               napi_value rhs,
                               bool* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, lhs);
  CHECK_ARG(env, rhs);
  CHECK_ARG(env, result);
  *result = JSValueIsStrictEqual(
    env->context,
    ToJSValue(lhs),
    ToJSValue(rhs));
  return napi_ok;
}

napi_status napi_get_prototype(napi_env env,
                               napi_value object,
                               napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, result);

  JSValueRef exception{};
  JSValueRef prototype = JSObjectGetPrototype(env->context, ToJSObject(env, object));
  CHECK_JSC(env, exception);

  *result = ToNapi(prototype);
  return napi_ok;
}

napi_status napi_create_object(napi_env env, napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, result);
  *result = ToNapi(JSObjectMake(env->context, nullptr, nullptr));
  return napi_ok;
}

napi_status napi_create_array(napi_env env, napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, result);

  JSValueRef exception{};
  *result = ToNapi(JSObjectMakeArray(env->context, 0, nullptr, &exception));
  CHECK_JSC(env, exception);

  return napi_ok;
}

napi_status napi_create_array_with_length(napi_env env,
                                          size_t length,
                                          napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, result);

  JSValueRef exception{};
  JSObjectRef array = JSObjectMakeArray(
    env->context,
    0,
    nullptr,
    &exception);
  CHECK_JSC(env, exception);

  JSObjectSetProperty(
    env->context,
    array,
    JSString("length"),
    JSValueMakeNumber(env->context, static_cast<double>(length)),
    kJSPropertyAttributeNone,
    &exception);
  CHECK_JSC(env, exception);

  *result = ToNapi(array);
  return napi_ok;
}

napi_status napi_create_string_latin1(napi_env env,
                                      const char* str,
                                      size_t length,
                                      napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, result);
  *result = ToNapi(JSValueMakeString(
    env->context,
    JSString(str, length)));
  return napi_ok;
}

napi_status napi_create_string_utf8(napi_env env,
                                    const char* str,
                                    size_t length,
                                    napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, result);
  *result = ToNapi(JSValueMakeString(
    env->context,
    JSString(str, length)));
  return napi_ok;
}

napi_status napi_create_string_utf16(napi_env env,
                                     const char16_t* str,
                                     size_t length,
                                     napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, result);
  static_assert(sizeof(char16_t) == sizeof(JSChar));
  *result = ToNapi(JSValueMakeString(
    env->context,
    JSString(reinterpret_cast<const JSChar*>(str), length)));
  return napi_ok;
}

napi_status napi_create_double(napi_env env,
                               double value,
                               napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, result);
  *result = ToNapi(JSValueMakeNumber(env->context, value));
  return napi_ok;
}

napi_status napi_create_int32(napi_env env,
                              int32_t value,
                              napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, result);
  *result = ToNapi(JSValueMakeNumber(env->context, static_cast<double>(value)));
  return napi_ok;
}

napi_status napi_create_uint32(napi_env env,
                               uint32_t value,
                               napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, result);
  *result = ToNapi(JSValueMakeNumber(env->context, static_cast<double>(value)));
  return napi_ok;
}

napi_status napi_create_int64(napi_env env,
                              int64_t value,
                              napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, result);
  *result = ToNapi(JSValueMakeNumber(env->context, static_cast<double>(value)));
  return napi_ok;
}

napi_status napi_get_boolean(napi_env env, bool value, napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, result);
  *result = ToNapi(JSValueMakeBoolean(env->context, value));
  return napi_ok;
}

napi_status napi_create_symbol(napi_env env,
                               napi_value description,
                               napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, result);

  napi_value global{}, symbol_func{};
  CHECK_NAPI(napi_get_global(env, &global));
  CHECK_NAPI(napi_get_named_property(env, global, "Symbol", &symbol_func));
  CHECK_NAPI(napi_call_function(env, global, symbol_func, 1, &description, result));
  return napi_ok;
}

napi_status napi_create_error(napi_env env,
                              napi_value code,
                              napi_value msg,
                              napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, msg);
  CHECK_ARG(env, result);

  JSValueRef exception{};
  JSValueRef args[] = { ToJSValue(msg) };
  napi_value error = ToNapi(JSObjectMakeError(env->context, 1, args, &exception));
  CHECK_JSC(env, exception);

  CHECK_NAPI(napi_set_error_code(env, error, code, nullptr));

  *result = error;
  return napi_ok;
}

napi_status napi_create_type_error(napi_env env,
                                   napi_value code,
                                   napi_value msg,
                                   napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, msg);
  CHECK_ARG(env, result);

  napi_value global{}, error_ctor{}, error{};
  CHECK_NAPI(napi_get_global(env, &global));
  CHECK_NAPI(napi_get_named_property(env, global, "TypeError", &error_ctor));
  CHECK_NAPI(napi_new_instance(env, error_ctor, 1, &msg, &error));
  CHECK_NAPI(napi_set_error_code(env, error, code, nullptr));

  *result = error;
  return napi_ok;
}

napi_status napi_create_range_error(napi_env env,
                                    napi_value code,
                                    napi_value msg,
                                    napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, msg);
  CHECK_ARG(env, result);

  napi_value global{}, error_ctor{}, error{};
  CHECK_NAPI(napi_get_global(env, &global));
  CHECK_NAPI(napi_get_named_property(env, global, "RangeError", &error_ctor));
  CHECK_NAPI(napi_new_instance(env, error_ctor, 1, &msg, &error));
  CHECK_NAPI(napi_set_error_code(env, error, code, nullptr));

  *result = error;
  return napi_ok;
}

napi_status napi_typeof(napi_env env, napi_value value, napi_valuetype* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, value);
  CHECK_ARG(env, result);

  // JSC does not support BigInt
  JSType valueType = JSValueGetType(env->context, ToJSValue(value));
  switch (valueType) {
    case kJSTypeUndefined: *result = napi_undefined; break;
    case kJSTypeNull: *result = napi_null; break;
    case kJSTypeBoolean: *result = napi_boolean; break;
    case kJSTypeNumber: *result = napi_number; break;
    case kJSTypeString: *result = napi_string; break;
    case kJSTypeSymbol: *result = napi_symbol; break;
    default:
      JSObjectRef object{ToJSObject(env, value)};
      if (JSObjectIsFunction(env->context, object)) {
        *result = napi_function;
      } else {
        NativeInfo* info = NativeInfo::Get<NativeInfo>(object);
        if (info != nullptr && info->Type() == NativeType::External) {
          *result = napi_external;
        } else {
          *result = napi_object;
        }
      }
      break;
  }

  return napi_ok;
}

napi_status napi_get_undefined(napi_env env, napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, result);
  *result = ToNapi(JSValueMakeUndefined(env->context));
  return napi_ok;
}

napi_status napi_get_null(napi_env env, napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, result);
  *result = ToNapi(JSValueMakeNull(env->context));
  return napi_ok;
}

napi_status napi_get_cb_info(napi_env env,              // [in] NAPI environment handle
                             napi_callback_info cbinfo, // [in] Opaque callback-info handle
                             size_t* argc,              // [in-out] Specifies the size of the provided argv array
                                                        // and receives the actual count of args.
                             napi_value* argv,          // [out] Array of values
                             napi_value* this_arg,      // [out] Receives the JS 'this' arg for the call
                             void** data) {             // [out] Receives the data pointer for the callback.
  CHECK_ENV(env);
  CHECK_ARG(env, cbinfo);

  if (argv != nullptr) {
    CHECK_ARG(env, argc);

    size_t i{0};
    size_t min{std::min(*argc, static_cast<size_t>(cbinfo->argc))};

    for (; i < min; i++) {
      argv[i] = cbinfo->argv[i];
    }

    if (i < *argc) {
      for (; i < *argc; i++) {
        argv[i] = ToNapi(JSValueMakeUndefined(env->context));
      }
    }
  }

  if (argc != nullptr) {
    *argc = cbinfo->argc;
  }

  if (this_arg != nullptr) {
    *this_arg = cbinfo->thisArg;
  }

  if (data != nullptr) {
    *data = cbinfo->data;
  }

  return napi_ok;
}

napi_status napi_get_new_target(napi_env env,
                                napi_callback_info cbinfo,
                                napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, cbinfo);
  CHECK_ARG(env, result);

  *result = cbinfo->newTarget;
  return napi_ok;
}

napi_status napi_call_function(napi_env env,
                               napi_value recv,
                               napi_value func,
                               size_t argc,
                               const napi_value* argv,
                               napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, recv);
  if (argc > 0) {
    CHECK_ARG(env, argv);
  }

  JSValueRef exception{};
  JSValueRef return_value{JSObjectCallAsFunction(
    env->context,
    ToJSObject(env, func),
    JSValueIsUndefined(env->context, ToJSValue(recv)) ? nullptr : ToJSObject(env, recv),
    argc,
    ToJSValues(argv),
    &exception)};
  CHECK_JSC(env, exception);

  if (result != nullptr) {
    *result = ToNapi(return_value);
  }

  return napi_ok;
}

napi_status napi_get_global(napi_env env, napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, result);
  *result = ToNapi(JSContextGetGlobalObject(env->context));
  return napi_ok;
}

napi_status napi_throw(napi_env env, napi_value error) {
  CHECK_ENV(env);
  napi_status status{napi_set_exception(env, ToJSValue(error))};
  assert(status == napi_pending_exception);
  return napi_ok;
}

napi_status napi_throw_error(napi_env env,
                             const char* code,
                             const char* msg) {
  CHECK_ENV(env);
  napi_value code_value{ToNapi(JSValueMakeString(env->context, JSString(code)))};
  napi_value msg_value{ToNapi(JSValueMakeString(env->context, JSString(msg)))};
  napi_value error{};
  CHECK_NAPI(napi_create_error(env, code_value, msg_value, &error));
  return napi_throw(env, error);
}

napi_status napi_throw_type_error(napi_env env,
                                  const char* code,
                                  const char* msg) {
  CHECK_ENV(env);
  napi_value code_value{ToNapi(JSValueMakeString(env->context, JSString(code)))};
  napi_value msg_value{ToNapi(JSValueMakeString(env->context, JSString(msg)))};
  napi_value error{};
  CHECK_NAPI(napi_create_type_error(env, code_value, msg_value, &error));
  return napi_throw(env, error);
}

napi_status napi_throw_range_error(napi_env env,
                                   const char* code,
                                   const char* msg) {
  CHECK_ENV(env);
  napi_value code_value{ToNapi(JSValueMakeString(env->context, JSString(code)))};
  napi_value msg_value{ToNapi(JSValueMakeString(env->context, JSString(msg)))};
  napi_value error{};
  CHECK_NAPI(napi_create_range_error(env, code_value, msg_value, &error));
  return napi_throw(env, error);
}

napi_status napi_is_error(napi_env env, napi_value value, bool* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, value);
  CHECK_ARG(env, result);

  napi_value global{}, error_ctor{};
  CHECK_NAPI(napi_get_global(env, &global));
  CHECK_NAPI(napi_get_named_property(env, global, "Error", &error_ctor));
  CHECK_NAPI(napi_instanceof(env, value, error_ctor, result));

  return napi_ok;
}

napi_status napi_get_value_double(napi_env env, napi_value value, double* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, value);
  CHECK_ARG(env, result);

  JSValueRef exception{};
  *result = JSValueToNumber(env->context, ToJSValue(value), &exception);
  CHECK_JSC(env, exception);

  return napi_ok;
}

napi_status napi_get_value_int32(napi_env env, napi_value value, int32_t* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, value);
  CHECK_ARG(env, result);

  JSValueRef exception{};
  *result = static_cast<int32_t>(JSValueToNumber(env->context, ToJSValue(value), &exception));
  CHECK_JSC(env, exception);

  return napi_ok;
}

napi_status napi_get_value_uint32(napi_env env, napi_value value, uint32_t* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, value);
  CHECK_ARG(env, result);

  JSValueRef exception{};
  *result = static_cast<uint32_t>(JSValueToNumber(env->context, ToJSValue(value), &exception));
  CHECK_JSC(env, exception);

  return napi_ok;
}

napi_status napi_get_value_int64(napi_env env, napi_value value, int64_t* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, value);
  CHECK_ARG(env, result);

  JSValueRef exception{};
  double number = JSValueToNumber(env->context, ToJSValue(value), &exception);
  CHECK_JSC(env, exception);

  if (std::isfinite(number)) {
    *result = static_cast<int64_t>(number);
  } else {
    *result = 0;
  }

  return napi_ok;
}

napi_status napi_get_value_bool(napi_env env, napi_value value, bool* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, value);
  CHECK_ARG(env, result);
  *result = JSValueToBoolean(env->context, ToJSValue(value));
  return napi_ok;
}

// Copies a JavaScript string into a LATIN-1 string buffer. The result is the
// number of bytes (excluding the null terminator) copied into buf.
// A sufficient buffer size should be greater than the length of string,
// reserving space for null terminator.
// If bufsize is insufficient, the string will be truncated and null terminated.
// If buf is NULL, this method returns the length of the string (in bytes)
// via the result parameter.
// The result argument is optional unless buf is NULL.
napi_status napi_get_value_string_latin1(napi_env env,
                                         napi_value value,
                                         char* buf,
                                         size_t bufsize,
                                         size_t* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, value);

  JSValueRef exception{};
  JSString string{ToJSString(env, value, &exception)};
  CHECK_JSC(env, exception);

  if (buf == nullptr) {
    *result = string.LengthLatin1();
  } else {
    string.CopyToLatin1(buf, bufsize, result);
  }

  return napi_ok;
}

// Copies a JavaScript string into a UTF-8 string buffer. The result is the
// number of bytes (excluding the null terminator) copied into buf.
// A sufficient buffer size should be greater than the length of string,
// reserving space for null terminator.
// If bufsize is insufficient, the string will be truncated and null terminated.
// If buf is NULL, this method returns the length of the string (in bytes)
// via the result parameter.
// The result argument is optional unless buf is NULL.
napi_status napi_get_value_string_utf8(napi_env env,
                                       napi_value value,
                                       char* buf,
                                       size_t bufsize,
                                       size_t* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, value);

  JSValueRef exception{};
  JSString string{ToJSString(env, value, &exception)};
  CHECK_JSC(env, exception);

  if (buf == nullptr) {
    *result = string.LengthUTF8();
  } else {
    string.CopyToUTF8(buf, bufsize, result);
  }

  return napi_ok;
}

// Copies a JavaScript string into a UTF-16 string buffer. The result is the
// number of 2-byte code units (excluding the null terminator) copied into buf.
// A sufficient buffer size should be greater than the length of string,
// reserving space for null terminator.
// If bufsize is insufficient, the string will be truncated and null terminated.
// If buf is NULL, this method returns the length of the string (in 2-byte
// code units) via the result parameter.
// The result argument is optional unless buf is NULL.
napi_status napi_get_value_string_utf16(napi_env env,
                                        napi_value value,
                                        char16_t* buf,
                                        size_t bufsize,
                                        size_t* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, value);

  JSValueRef exception{};
  JSString string{ToJSString(env, value, &exception)};
  CHECK_JSC(env, exception);

  if (buf == nullptr) {
    *result = string.Length();
  } else {
    static_assert(sizeof(char16_t) == sizeof(JSChar));
    string.CopyTo(reinterpret_cast<JSChar*>(buf), bufsize, result);
  }

  return napi_ok;
}

napi_status napi_coerce_to_bool(napi_env env,
                                napi_value value,
                                napi_value* result) {
  CHECK_ARG(env, result);
  *result = ToNapi(JSValueMakeBoolean(env->context,
    JSValueToBoolean(env->context, ToJSValue(value))));
  return napi_ok;
}

napi_status napi_coerce_to_number(napi_env env,
                                  napi_value value,
                                  napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, value);
  CHECK_ARG(env, result);

  JSValueRef exception{};
  double number{JSValueToNumber(env->context, ToJSValue(value), &exception)};
  CHECK_JSC(env, exception);

  *result = ToNapi(JSValueMakeNumber(env->context, number));
  return napi_ok;
}

napi_status napi_coerce_to_object(napi_env env,
                                  napi_value value,
                                  napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, value);
  CHECK_ARG(env, result);

  JSValueRef exception{};
  *result = ToNapi(JSValueToObject(env->context, ToJSValue(value), &exception));
  CHECK_JSC(env, exception);

  return napi_ok;
}

napi_status napi_coerce_to_string(napi_env env,
                                  napi_value value,
                                  napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, value);
  CHECK_ARG(env, result);

  JSValueRef exception{};
  JSString string{ToJSString(env, value, &exception)};
  CHECK_JSC(env, exception);

  *result = ToNapi(JSValueMakeString(env->context, string));
  return napi_ok;
}

napi_status napi_wrap(napi_env env,
                      napi_value js_object,
                      void* native_object,
                      napi_finalize finalize_cb,
                      void* finalize_hint,
                      napi_ref* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, js_object);
  if (result != nullptr) {
    CHECK_ARG(env, finalize_cb);
  }

  WrapperInfo* info{};
  CHECK_NAPI(WrapperInfo::Wrap(env, js_object, &info));
  RETURN_STATUS_IF_FALSE(env, info->Data() == nullptr, napi_invalid_arg);

  info->Data(native_object);

  if (finalize_cb != nullptr) {
    info->AddFinalizer([finalize_cb, finalize_hint](WrapperInfo* info) {
        finalize_cb(info->Env(), info->Data(), finalize_hint);
    });
  }

  if (result != nullptr) {
    CHECK_NAPI(napi_create_reference(env, js_object, 0, result));
  }

  return napi_ok;
}

napi_status napi_unwrap(napi_env env, napi_value js_object, void** result) {
  CHECK_ENV(env);
  CHECK_ARG(env, js_object);

  WrapperInfo* info{};
  CHECK_NAPI(WrapperInfo::Unwrap(env, js_object, &info));
  RETURN_STATUS_IF_FALSE(env, info != nullptr && info->Data() != nullptr, napi_invalid_arg);

  *result = info->Data();
  return napi_ok;
}

napi_status napi_remove_wrap(napi_env env, napi_value js_object, void** result) {
  CHECK_ENV(env);
  CHECK_ARG(env, js_object);

  // Once an object is wrapped, it stays wrapped in order to support finalizer callbacks.

  WrapperInfo* info{};
  CHECK_NAPI(WrapperInfo::Unwrap(env, js_object, &info));
  RETURN_STATUS_IF_FALSE(env, info != nullptr && info->Data() != nullptr, napi_invalid_arg);
  info->Data(nullptr);

  *result = info->Data();
  return napi_ok;
}

napi_status napi_create_external(napi_env env,
                                 void* data,
                                 napi_finalize finalize_cb,
                                 void* finalize_hint,
                                 napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, result);

  CHECK_NAPI(ExternalInfo::Create(env, data, finalize_cb, finalize_hint, result));
  return napi_ok;
}

napi_status napi_get_value_external(napi_env env, napi_value value, void** result) {
  CHECK_ENV(env);
  CHECK_ARG(env, value);
  CHECK_ARG(env, result);

  ExternalInfo* info = NativeInfo::Get<ExternalInfo>(ToJSObject(env, value));
  *result = (info != nullptr && info->Type() == NativeType::External) ? info->Data() : nullptr;
  return napi_ok;
}

// Set initial_refcount to 0 for a weak reference, >0 for a strong reference.
napi_status napi_create_reference(napi_env env,
                                  napi_value value,
                                  uint32_t initial_refcount,
                                  napi_ref* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, value);
  CHECK_ARG(env, result);

  *result = new napi_ref__ { env, value, initial_refcount };

  return napi_ok;
}

// Deletes a reference. The referenced value is released, and may be GC'd
// unless there are other references to it.
napi_status napi_delete_reference(napi_env env, napi_ref ref) {
  CHECK_ENV(env);
  CHECK_ARG(env, ref);

  ref->deinit(env);
  delete ref;

  return napi_ok;
}

// Increments the reference count, optionally returning the resulting count.
// After this call the reference will be a strong reference because its refcount
// is >0, and the referenced object is effectively "pinned". Calling this when
// the refcount is 0 and the target is unavailable results in an error.
napi_status napi_reference_ref(napi_env env, napi_ref ref, uint32_t* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, ref);

  ref->ref(env);
  if (result != nullptr) {
    *result = ref->count();
  }

  return napi_ok;
}

// Decrements the reference count, optionally returning the resulting count.
// If the result is 0 the reference is now weak and the object may be GC'd at
// any time if there are no other references. Calling this when the refcount
// is already 0 results in an error.
napi_status napi_reference_unref(napi_env env, napi_ref ref, uint32_t* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, ref);

  ref->unref(env);
  if (result != nullptr) {
    *result = ref->count();
  }

  return napi_ok;
}

// Attempts to get a referenced value. If the reference is weak, the value
// might no longer be available, in that case the call is still successful but
// the result is NULL.
napi_status napi_get_reference_value(napi_env env,
                                     napi_ref ref,
                                     napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, ref);
  CHECK_ARG(env, result);

  *result = ref->value(env);
  return napi_ok;
}

// Stub implementation of handle scope apis for JSC.
napi_status napi_open_handle_scope(napi_env env,
                                   napi_handle_scope* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, result);
  *result = reinterpret_cast<napi_handle_scope>(1);
  return napi_ok;
}

// Stub implementation of handle scope apis for JSC.
napi_status napi_close_handle_scope(napi_env env,
                                    napi_handle_scope scope) {
  CHECK_ENV(env);
  CHECK_ARG(env, scope);
  return napi_ok;
}

// Stub implementation of handle scope apis for JSC.
napi_status napi_open_escapable_handle_scope(napi_env env,
                                             napi_escapable_handle_scope* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, result);
  *result = reinterpret_cast<napi_escapable_handle_scope>(1);
  return napi_ok;
}

// Stub implementation of handle scope apis for JSC.
napi_status napi_close_escapable_handle_scope(napi_env env,
                                              napi_escapable_handle_scope scope) {
  CHECK_ENV(env);
  CHECK_ARG(env, scope);
  return napi_ok;
}

// Stub implementation of handle scope apis for JSC.
// This one will return escapee value as this is called from leveldown db.
napi_status napi_escape_handle(napi_env env,
                               napi_escapable_handle_scope scope,
                               napi_value escapee,
                               napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, scope);
  CHECK_ARG(env, escapee);
  CHECK_ARG(env, result);
  *result = escapee;
  return napi_ok;
}

napi_status napi_new_instance(napi_env env,
                              napi_value constructor,
                              size_t argc,
                              const napi_value* argv,
                              napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, constructor);
  if (argc > 0) {
    CHECK_ARG(env, argv);
  }
  CHECK_ARG(env, result);

  JSValueRef exception{};
  *result = ToNapi(JSObjectCallAsConstructor(
    env->context,
    ToJSObject(env, constructor),
    argc,
    ToJSValues(argv),
    &exception));
  CHECK_JSC(env, exception);

  return napi_ok;
}

napi_status napi_instanceof(napi_env env,
                            napi_value object,
                            napi_value constructor,
                            bool* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, object);
  CHECK_ARG(env, result);

  JSValueRef exception{};
  *result = JSValueIsInstanceOfConstructor(
    env->context,
    ToJSValue(object),
    ToJSObject(env, constructor),
    &exception);
  CHECK_JSC(env, exception);

  return napi_ok;
}

napi_status napi_is_exception_pending(napi_env env, bool* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, result);

  *result = (env->last_exception != nullptr);
  return napi_ok;
}

napi_status napi_get_and_clear_last_exception(napi_env env,
                                              napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, result);

  if (env->last_exception == nullptr) {
    return napi_get_undefined(env, result);
  } else {
    *result = ToNapi(env->last_exception);
    env->last_exception = nullptr;
  }

  return napi_clear_last_error(env);
}

napi_status napi_is_arraybuffer(napi_env env, napi_value value, bool* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, value);
  CHECK_ARG(env, result);

  if (!JSValueIsObject(env->context, ToJSValue(value))) {
    *result = false;
    return napi_ok;
  }

  JSValueRef exception{};
  JSTypedArrayType type{JSValueGetTypedArrayType(env->context, ToJSValue(value), &exception)};
  CHECK_JSC(env, exception);

  *result = (type == kJSTypedArrayTypeArrayBuffer);
  return napi_ok;
}

napi_status napi_create_arraybuffer(napi_env env,
                                    size_t byte_length,
                                    void** data,
                                    napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, result);

  *data = malloc(byte_length);
  JSValueRef exception{};
  *result = ToNapi(JSObjectMakeArrayBufferWithBytesNoCopy(
    env->context,
    *data,
    byte_length,
    [](void* bytes, void* deallocatorContext) {
      free(bytes);
    },
    nullptr,
    &exception));
  CHECK_JSC(env, exception);

  return napi_ok;
}

napi_status napi_create_external_arraybuffer(napi_env env,
                                             void* external_data,
                                             size_t byte_length,
                                             napi_finalize finalize_cb,
                                             void* finalize_hint,
                                             napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, result);

  CHECK_NAPI(ExternalArrayBufferInfo::Create(env, external_data, byte_length, finalize_cb, finalize_hint, result));
  return napi_ok;
}

napi_status napi_get_arraybuffer_info(napi_env env,
                                      napi_value arraybuffer,
                                      void** data,
                                      size_t* byte_length) {
  CHECK_ENV(env);
  CHECK_ARG(env, arraybuffer);

  JSValueRef exception{};

  if (data != nullptr) {
    *data = JSObjectGetArrayBufferBytesPtr(env->context, ToJSObject(env, arraybuffer), &exception);
    CHECK_JSC(env, exception);
  }

  if (byte_length != nullptr) {
    *byte_length = JSObjectGetArrayBufferByteLength(env->context, ToJSObject(env, arraybuffer), &exception);
    CHECK_JSC(env, exception);
  }

  return napi_ok;
}

napi_status napi_is_typedarray(napi_env env, napi_value value, bool* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, value);
  CHECK_ARG(env, result);

  JSValueRef exception{};
  JSTypedArrayType type{JSValueGetTypedArrayType(env->context, ToJSValue(value), &exception)};
  CHECK_JSC(env, exception);

  *result = (type != kJSTypedArrayTypeNone && type != kJSTypedArrayTypeArrayBuffer);
  return napi_ok;
}

napi_status napi_create_typedarray(napi_env env,
                                   napi_typedarray_type type,
                                   size_t length,
                                   napi_value arraybuffer,
                                   size_t byte_offset,
                                   napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, arraybuffer);
  CHECK_ARG(env, result);

  JSTypedArrayType jsType{};
  switch (type) {
    case napi_int8_array:
      jsType = kJSTypedArrayTypeInt8Array;
      break;
    case napi_uint8_array:
      jsType = kJSTypedArrayTypeUint8Array;
      break;
    case napi_uint8_clamped_array:
      jsType = kJSTypedArrayTypeUint8ClampedArray;
      break;
    case napi_int16_array:
      jsType = kJSTypedArrayTypeInt16Array;
      break;
    case napi_uint16_array:
      jsType = kJSTypedArrayTypeUint16Array;
      break;
    case napi_int32_array:
      jsType = kJSTypedArrayTypeInt32Array;
      break;
    case napi_uint32_array:
      jsType = kJSTypedArrayTypeUint32Array;
      break;
    case napi_float32_array:
      jsType = kJSTypedArrayTypeFloat32Array;
      break;
    case napi_float64_array:
      jsType = kJSTypedArrayTypeFloat64Array;
      break;
    case napi_bigint64_array:
      jsType = kJSTypedArrayTypeBigInt64Array;
      break;
    case napi_biguint64_array:
      jsType = kJSTypedArrayTypeBigUint64Array;
      break;
    default:
      return napi_set_last_error(env, napi_invalid_arg);
  }

  JSValueRef exception{};
  *result = ToNapi(JSObjectMakeTypedArrayWithArrayBufferAndOffset(
    env->context,
    jsType,
    ToJSObject(env, arraybuffer),
    byte_offset,
    length,
    &exception));
  CHECK_JSC(env, exception);

  return napi_ok;
}

napi_status napi_get_typedarray_info(napi_env env,
                                     napi_value typedarray,
                                     napi_typedarray_type* type,
                                     size_t* length,
                                     void** data,
                                     napi_value* arraybuffer,
                                     size_t* byte_offset) {
  CHECK_ENV(env);
  CHECK_ARG(env, typedarray);

  JSValueRef exception{};

  JSObjectRef object{ToJSObject(env, typedarray)};

  if (type != nullptr) {
    JSTypedArrayType typedArrayType{JSValueGetTypedArrayType(env->context, object, &exception)};
    CHECK_JSC(env, exception);

    switch (typedArrayType) {
      case kJSTypedArrayTypeInt8Array:
        *type = napi_int8_array;
        break;
      case kJSTypedArrayTypeUint8Array:
        *type = napi_uint8_array;
        break;
      case kJSTypedArrayTypeUint8ClampedArray:
        *type = napi_uint8_clamped_array;
        break;
      case kJSTypedArrayTypeInt16Array:
        *type = napi_int16_array;
        break;
      case kJSTypedArrayTypeUint16Array:
        *type = napi_uint16_array;
        break;
      case kJSTypedArrayTypeInt32Array:
        *type = napi_int32_array;
        break;
      case kJSTypedArrayTypeUint32Array:
        *type = napi_uint32_array;
        break;
      case kJSTypedArrayTypeFloat32Array:
        *type = napi_float32_array;
        break;
      case kJSTypedArrayTypeFloat64Array:
        *type = napi_float64_array;
        break;
      case kJSTypedArrayTypeBigInt64Array:
        *type = napi_bigint64_array;
      case kJSTypedArrayTypeBigUint64Array:
        *type = napi_biguint64_array;
      default:
        return napi_set_last_error(env, napi_generic_failure);
    }
  }

  if (length != nullptr) {
    *length = JSObjectGetTypedArrayLength(env->context, object, &exception);
    CHECK_JSC(env, exception);
  }

  if (data != nullptr || byte_offset != nullptr) {
    size_t data_byte_offset{JSObjectGetTypedArrayByteOffset(env->context, object, &exception)};
    CHECK_JSC(env, exception);

    if (data != nullptr) {
      *data = static_cast<uint8_t*>(JSObjectGetTypedArrayBytesPtr(env->context, object, &exception)) + data_byte_offset;
      CHECK_JSC(env, exception);
    }

    if (byte_offset != nullptr) {
      *byte_offset = data_byte_offset;
    }
  }

  if (arraybuffer != nullptr) {
    *arraybuffer = ToNapi(JSObjectGetTypedArrayBuffer(env->context, object, &exception));
    CHECK_JSC(env, exception);
  }

  return napi_ok;
}

napi_status napi_create_dataview(napi_env env,
                                 size_t byte_length,
                                 napi_value arraybuffer,
                                 size_t byte_offset,
                                 napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, arraybuffer);
  CHECK_ARG(env, result);

  napi_value global{}, dataview_ctor{};
  CHECK_NAPI(napi_get_global(env, &global));
  CHECK_NAPI(napi_get_named_property(env, global, "DataView", &dataview_ctor));

  napi_value byte_offset_value{}, byte_length_value{};
  napi_create_double(env, static_cast<double>(byte_offset), &byte_offset_value);
  napi_create_double(env, static_cast<double>(byte_length), &byte_length_value);
  napi_value args[] = { arraybuffer, byte_offset_value, byte_length_value };
  CHECK_NAPI(napi_new_instance(env, dataview_ctor, 3, args, result));

  return napi_ok;
}

napi_status napi_is_dataview(napi_env env, napi_value value, bool* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, value);
  CHECK_ARG(env, result);

  napi_value global{}, dataview_ctor{};
  CHECK_NAPI(napi_get_global(env, &global));
  CHECK_NAPI(napi_get_named_property(env, global, "DataView", &dataview_ctor));
  CHECK_NAPI(napi_instanceof(env, value, dataview_ctor, result));

  return napi_ok;
}

napi_status napi_get_dataview_info(napi_env env,
                                   napi_value dataview,
                                   size_t* byte_length,
                                   void** data,
                                   napi_value* arraybuffer,
                                   size_t* byte_offset) {
  CHECK_ENV(env);
  CHECK_ARG(env, dataview);

  if (byte_length != nullptr) {
    napi_value value{};
    double doubleValue{};
    CHECK_NAPI(napi_get_named_property(env, dataview, "byteLength", &value));
    CHECK_NAPI(napi_get_value_double(env, value, &doubleValue));
    *byte_length = static_cast<size_t>(doubleValue);
  }

  if (data != nullptr) {
    napi_value value{};
    CHECK_NAPI(napi_get_named_property(env, dataview, "buffer", &value));
    CHECK_NAPI(napi_get_arraybuffer_info(env, value, data, nullptr));
  }

  if (arraybuffer != nullptr) {
    CHECK_NAPI(napi_get_named_property(env, dataview, "buffer", arraybuffer));
  }

  if (byte_offset != nullptr) {
    napi_value value{};
    double doubleValue{};
    CHECK_NAPI(napi_get_named_property(env, dataview, "byteOffset", &value));
    CHECK_NAPI(napi_get_value_double(env, value, &doubleValue));
    *byte_offset = static_cast<size_t>(doubleValue);
  }

  return napi_ok;
}

napi_status napi_get_version(napi_env env, uint32_t* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, result);
  *result = NAPI_VERSION;
  return napi_ok;
}

napi_status napi_create_promise(napi_env env,
                                napi_deferred* deferred,
                                napi_value* promise) {
  // TODO: Use JSObjectMakeDeferredPromise

  CHECK_ENV(env);
  CHECK_ARG(env, deferred);
  CHECK_ARG(env, promise);

  napi_value global{}, promise_ctor{};
  CHECK_NAPI(napi_get_global(env, &global));
  CHECK_NAPI(napi_get_named_property(env, global, "Promise", &promise_ctor));

  struct Wrapper {
    napi_value resolve{};
    napi_value reject{};

    static napi_value Callback(napi_env env, napi_callback_info cbinfo) {
      Wrapper* wrapper = reinterpret_cast<Wrapper*>(cbinfo->data);
      wrapper->resolve = cbinfo->argv[0];
      wrapper->reject = cbinfo->argv[1];
      return nullptr;
    }
  } wrapper;

  napi_value executor{};
  CHECK_NAPI(napi_create_function(env, "executor", NAPI_AUTO_LENGTH, Wrapper::Callback, &wrapper, &executor));
  CHECK_NAPI(napi_new_instance(env, promise_ctor, 1, &executor, promise));

  napi_value deferred_value{};
  CHECK_NAPI(napi_create_object(env, &deferred_value));
  CHECK_NAPI(napi_set_named_property(env, deferred_value, "resolve", wrapper.resolve));
  CHECK_NAPI(napi_set_named_property(env, deferred_value, "reject", wrapper.reject));

  napi_ref deferred_ref{};
  CHECK_NAPI(napi_create_reference(env, deferred_value, 1, &deferred_ref));
  *deferred = reinterpret_cast<napi_deferred>(deferred_ref);

  return napi_ok;
}

napi_status napi_resolve_deferred(napi_env env,
                                  napi_deferred deferred,
                                  napi_value resolution) {
  CHECK_ENV(env);
  CHECK_ARG(env, deferred);

  napi_ref deferred_ref{reinterpret_cast<napi_ref>(deferred)};
  napi_value undefined{}, deferred_value{}, resolve{};
  CHECK_NAPI(napi_get_undefined(env, &undefined));
  CHECK_NAPI(napi_get_reference_value(env, deferred_ref, &deferred_value));
  CHECK_NAPI(napi_get_named_property(env, deferred_value, "resolve", &resolve));
  CHECK_NAPI(napi_call_function(env, undefined, resolve, 1, &resolution, nullptr));
  CHECK_NAPI(napi_delete_reference(env, deferred_ref));

  return napi_ok;
}

napi_status napi_reject_deferred(napi_env env,
                                 napi_deferred deferred,
                                 napi_value rejection) {
  CHECK_ENV(env);
  CHECK_ARG(env, deferred);

  napi_ref deferred_ref{reinterpret_cast<napi_ref>(deferred)};
  napi_value undefined{}, deferred_value{}, reject{};
  CHECK_NAPI(napi_get_undefined(env, &undefined));
  CHECK_NAPI(napi_get_reference_value(env, deferred_ref, &deferred_value));
  CHECK_NAPI(napi_get_named_property(env, deferred_value, "reject", &reject));
  CHECK_NAPI(napi_call_function(env, undefined, reject, 1, &rejection, nullptr));
  CHECK_NAPI(napi_delete_reference(env, deferred_ref));

  return napi_ok;
}

napi_status napi_is_promise(napi_env env,
                            napi_value promise,
                            bool* is_promise) {
  CHECK_ENV(env);
  CHECK_ARG(env, promise);
  CHECK_ARG(env, is_promise);

  napi_value global{}, promise_ctor{};
  CHECK_NAPI(napi_get_global(env, &global));
  CHECK_NAPI(napi_get_named_property(env, global, "Promise", &promise_ctor));
  CHECK_NAPI(napi_instanceof(env, promise, promise_ctor, is_promise));

  return napi_ok;
}

napi_status napi_run_script(napi_env env,
                            napi_value script,
                            napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, script);
  CHECK_ARG(env, result);

  JSValueRef exception{};

  JSString script_str{ToJSString(env, script, &exception)};
  CHECK_JSC(env, exception);

  *result = ToNapi(JSEvaluateScript(
    env->context, script_str, nullptr, nullptr, 0, &exception));
  CHECK_JSC(env, exception);

  return napi_ok;
}

napi_status napi_adjust_external_memory(napi_env env,
                                        int64_t change_in_bytes,
                                        int64_t* adjusted_value) {
  CHECK_ENV(env);
  CHECK_ARG(env, adjusted_value);

  // TODO: Determine if JSC needs or is able to do anything here
  // For now, we can lie and say that we always adjusted more memory
  *adjusted_value = change_in_bytes;

  return napi_ok;
}

// MARK: - NAPI 5: Date

napi_status napi_create_date(napi_env env,
                             double time,
                             napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, result);

  auto jsTime = JSValueMakeNumber(env->context, time);
  JSValueRef exception {};
  auto jsDate = JSObjectMakeDate(env->context, 1, &jsTime, &exception);
  CHECK_JSC(env, exception);

  *result = ToNapi(jsDate);
  return napi_ok;
}

napi_status napi_is_date(napi_env env,
                         napi_value value,
                         bool* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, value);
  CHECK_ARG(env, result);

  *result = JSValueIsDate(env->context, ToJSValue(value));

  return napi_ok;
}

napi_status napi_get_date_value(napi_env env,
                                napi_value value,
                                double* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, value);
  CHECK_ARG(env, result);

  JSValueRef exception{};
  // we don't piggyback off of napi_get_value_double because that function
  // SHOULDN'T coerce.
  *result = JSValueToNumber(env->context, ToJSValue(value), &exception);
  CHECK_JSC(env, exception);

  return napi_ok;
}

// MARK: - NAPI 5: Finalizer

napi_status napi_add_finalizer(napi_env env,
                               napi_value js_object,
                               void* native_object,
                               napi_finalize finalize_cb,
                               void* finalize_hint,
                               napi_ref* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, js_object);
  add_finalizer(env, js_object, [=]{
    finalize_cb(env, native_object, finalize_hint);
  });
  if (result) {
    napi_ref res;
    CHECK_NAPI(napi_create_reference(env, js_object, 0, &res));
    *result = res;
  }
  return napi_ok;
}

// MARK: - NAPI 6

// Object
napi_status napi_get_all_property_names(napi_env env,
                                        napi_value object,
                                        napi_key_collection_mode key_mode,
                                        napi_key_filter key_filter,
                                        napi_key_conversion key_conversion,
                                        napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, object);
  CHECK_ARG(env, result);

  napi_value array{}, push{}, global{}, object_ctor{};
  CHECK_NAPI(napi_create_array(env, &array));
  CHECK_NAPI(napi_get_global(env, &global));
  CHECK_NAPI(napi_get_named_property(env, global, "Object", &object_ctor));
  CHECK_NAPI(napi_get_named_property(env, array, "push", &push));

  std::vector<napi_value> getter_methods;
  if (!(key_filter & napi_key_skip_strings)) {
    napi_value method{};
    CHECK_NAPI(napi_get_named_property(env, object_ctor, "getOwnPropertyNames", &method));
    getter_methods.push_back(method);
  }
  if (!(key_filter & napi_key_skip_symbols)) {
    napi_value method{};
    CHECK_NAPI(napi_get_named_property(env, object_ctor, "getOwnPropertySymbols", &method));
    getter_methods.push_back(method);
  }

  napi_value current = object;
  while (true) {
    for (napi_value method : getter_methods) {
      napi_value properties{};
      // Object.getOwnProperty[Names|Symbols](current)
      CHECK_NAPI(napi_call_function(env, object_ctor, method, 1, &current, &properties));
      uint32_t length = 0;
      CHECK_NAPI(napi_get_array_length(env, properties, &length));
      for (uint32_t i = 0; i != length; ++i) {
        napi_value key{};
        CHECK_NAPI(napi_get_element(env, properties, i, &key));
        // TODO: coerce to number if napi_key_keep_numbers
        // TODO: filter writable/enumerable/configurable
#if 0
        napi_value descriptor{};
        std::array<napi_value, 2> args { current, key };
        // Object.getOwnPropertyDescriptor(current, key)
        CHECK_NAPI(napi_call_function(env, object_ctor, getOwnPropertyDescriptor, 2, args.data(), &descriptor));
#endif
        CHECK_NAPI(napi_call_function(env, array, push, 1, &key, NULL));
      }
    }
    if (key_mode == napi_key_own_only) break;
    napi_value next{};
    CHECK_NAPI(napi_get_prototype(env, current, &next));
    napi_valuetype next_type;
    CHECK_NAPI(napi_typeof(env, next, &next_type));
    if (next_type == napi_null) break;
    current = next;
  };

  *result = array;

  return napi_ok;
}

static napi_status create_bigint_string(napi_env env,
                                        std::string string,
                                        napi_value* result) {
  CHECK_ENV(env);
  CHECK_ARG(env, result);

  napi_value global{}, bigint_ctor{}, js_string{};
  CHECK_NAPI(napi_get_global(env, &global));
  CHECK_NAPI(napi_get_named_property(env, global, "BigInt", &bigint_ctor));
  CHECK_NAPI(napi_create_string_utf8(env, string.data(), string.size(), &js_string));
  CHECK_NAPI(napi_new_instance(env, bigint_ctor, 1, &js_string, result));

  return napi_ok;
}

static napi_status bigint_to_string(napi_env env, napi_value value, std::string &string) {
  CHECK_ENV(env);
  CHECK_ARG(env, value);

  JSValueRef exception{};
  JSString js_string{ToJSString(env, value, &exception)};
  CHECK_JSC(env, exception);

  char buf[js_string.LengthUTF8()];
  js_string.CopyToUTF8(buf, sizeof(buf), nullptr);
  string = std::string { buf };
  return napi_ok;
}

// BigInt
napi_status napi_create_bigint_int64(napi_env env,
                                     int64_t value,
                                     napi_value* result) {
  return create_bigint_string(env, std::to_string(value), result);
}

napi_status napi_create_bigint_uint64(napi_env env, uint64_t value, napi_value* result) {
  return create_bigint_string(env, std::to_string(value), result);
}

napi_status napi_get_value_bigint_int64(napi_env env,
                                        napi_value value,
                                        int64_t* result,
                                        bool* lossless) {
  std::string string;
  CHECK_NAPI(bigint_to_string(env, value, string));
  errno = 0;
  auto ret = std::strtoll(string.data(), nullptr, 10);
  *lossless = errno != ERANGE;
  *result = ret;
  return napi_ok;
}

napi_status napi_get_value_bigint_uint64(napi_env env, napi_value value, uint64_t* result, bool* lossless) {
  std::string string;
  CHECK_NAPI(bigint_to_string(env, value, string));
  errno = 0;
  auto ret = std::strtoull(string.data(), nullptr, 10);
  *lossless = errno != ERANGE;
  *result = ret;
  return napi_ok;
}

napi_status napi_create_bigint_words(napi_env env,
                                     int sign_bit,
                                     size_t word_count,
                                     const uint64_t* words,
                                     napi_value* result) {
  throw std::runtime_error("TODO");
}

napi_status napi_get_value_bigint_words(napi_env env,
                                        napi_value value,
                                        int* sign_bit,
                                        size_t* word_count,
                                        uint64_t* words) {
  throw std::runtime_error("TODO");
}

// MARK: - NAPI 7: Detatchable ArrayBuffer

napi_status napi_detach_arraybuffer(napi_env env, napi_value arraybuffer) {
  throw std::runtime_error("unsupported");
}

napi_status napi_is_detached_arraybuffer(napi_env env, napi_value value, bool* result) {
  throw std::runtime_error("unsupported");
}

// MARK: - NAPI 8

napi_status napi_object_freeze(napi_env env,
                               napi_value object) {
  napi_value global{}, object_ctor{}, freeze{};
  CHECK_NAPI(napi_get_global(env, &global));
  CHECK_NAPI(napi_get_named_property(env, global, "Object", &object_ctor));
  CHECK_NAPI(napi_get_named_property(env, object_ctor, "freeze", &freeze));
  CHECK_NAPI(napi_call_function(env, object_ctor, freeze, 1, &object, nullptr));
  return napi_ok;
}

napi_status napi_object_seal(napi_env env,
                             napi_value object) {
  napi_value global{}, object_ctor{}, seal{};
  CHECK_NAPI(napi_get_global(env, &global));
  CHECK_NAPI(napi_get_named_property(env, global, "Object", &object_ctor));
  CHECK_NAPI(napi_get_named_property(env, object_ctor, "seal", &seal));
  CHECK_NAPI(napi_call_function(env, object_ctor, seal, 1, &object, nullptr));
  return napi_ok;
}

napi_status napi_type_tag_object(napi_env env,
                                 napi_value value,
                                 const napi_type_tag* type_tag) {
  bool newly_created = false;
  napi_value tag_map;
  if (env->tag_map) {
    tag_map = ToNapi(env->tag_map);
  } else {
    newly_created = true;
    napi_value global{}, map_ctor{};
    CHECK_NAPI(napi_get_global(env, &global));
    // need to use a WeakMap, otherwise tagging an object retains it forever
    CHECK_NAPI(napi_get_named_property(env, global, "WeakMap", &map_ctor));
    CHECK_NAPI(napi_new_instance(env, map_ctor, 0, nullptr, &tag_map));
    JSValueRef tag_map_jsc = ToJSValue(tag_map);
    JSValueProtect(env->context, tag_map_jsc);
    env->tag_map = tag_map_jsc;
  }

  if (!newly_created) {
    napi_value map_has{}, has_result{};
    CHECK_NAPI(napi_get_named_property(env, tag_map, "has", &map_has));
    CHECK_NAPI(napi_call_function(env, tag_map, map_has, 1, &value, &has_result));
    bool has_bool = true;
    CHECK_NAPI(napi_get_value_bool(env, has_result, &has_bool));
    if (has_bool) return napi_invalid_arg;
  }

  napi_value map_set{};
  CHECK_NAPI(napi_get_named_property(env, tag_map, "set", &map_set));

  napi_value arraybuf;
  void *data;
  CHECK_NAPI(napi_create_arraybuffer(env, sizeof(*type_tag), &data, &arraybuf));
  memcpy(data, type_tag, sizeof(*type_tag));
  napi_value args[] = { value, arraybuf };
  CHECK_NAPI(napi_call_function(env, tag_map, map_set, 2, args, nullptr));

  return napi_ok;
}

napi_status napi_check_object_type_tag(napi_env env,
                                       napi_value value,
                                       const napi_type_tag* type_tag,
                                       bool* result) {
  JSValueRef map = env->tag_map;
  if (!map) {
    *result = false;
    return napi_ok;
  }

  napi_value tag_map = ToNapi(map);
  napi_value map_get{}, get_result{};
  CHECK_NAPI(napi_get_named_property(env, tag_map, "get", &map_get));
  CHECK_NAPI(napi_call_function(env, tag_map, map_get, 1, &value, &get_result));

  bool is_arraybuf = false;
  CHECK_NAPI(napi_is_arraybuffer(env, get_result, &is_arraybuf));
  if (!is_arraybuf) {
    *result = false;
    return napi_ok;
  }

  void *data;
  size_t len;
  CHECK_NAPI(napi_get_arraybuffer_info(env, get_result, &data, &len));

  *result = len == sizeof(*type_tag) && memcmp(data, type_tag, len) == 0;

  return napi_ok;
}

// MARK: - Node+Fatal

void napi_fatal_error(const char* location,
                      size_t location_len,
                      const char* message,
                      size_t message_len) {
  auto location_str = std::string { location, location_len };
  auto message_str = std::string { message, message_len };
  throw std::runtime_error(location_str + ": " + message_str);
}

napi_status napi_fatal_exception(napi_env env,
                                 napi_value err) {
  // TODO: this should directly trigger 'uncaughtException'
  // ...but there isn't much we can do since there's no `process` in JSC
  return napi_throw(env, err);
}

// MARK: - Node+Threadsafe

napi_status napi_create_threadsafe_function(napi_env env,
                                            napi_value func,
                                            napi_value async_resource,
                                            napi_value async_resource_name,
                                            size_t max_queue_size,
                                            size_t initial_thread_count,
                                            void* thread_finalize_data,
                                            napi_finalize thread_finalize_cb,
                                            void* context,
                                            napi_threadsafe_function_call_js call_js_cb,
                                            napi_threadsafe_function* result) {
  napi_threadsafe_function fn = new napi_threadsafe_function__{};
  fn->env = env;
  fn->js_value = func;
  fn->refcount = initial_thread_count;
  fn->thread_finalize_data = thread_finalize_data;
  fn->thread_finalize_cb = thread_finalize_cb;
  fn->context = context;
  fn->call_js_cb = call_js_cb;
  *result = fn;
  return napi_ok;
}

napi_status napi_get_threadsafe_function_context(napi_threadsafe_function func,
                                                 void** result) {
  if (!func) return napi_invalid_arg;
  *result = func->context;
  return napi_ok;
}

// called on js thread
void release_threadsafe_function(void *context) {
  auto fn = static_cast<napi_threadsafe_function>(context);
  fn->env->all_tsfns.erase(fn);
  napi_unref_threadsafe_function(fn->env, fn);
  fn->thread_finalize_cb(fn->env, fn->thread_finalize_data, nullptr);
  delete fn;
}

struct tsfn_call_context {
  napi_threadsafe_function func;
  void *data;
};

// called inside env
void _call_threadsafe_function(void *context) {
  auto ctx_ptr = static_cast<tsfn_call_context *>(context);
  auto ctx = *ctx_ptr;
  delete ctx_ptr;
  auto func = ctx.func;
  if (func->js_value) {
    napi_value undefined{};
    napi_get_undefined(func->env, &undefined);
    napi_call_function(func->env, undefined, func->js_value, 0, nullptr, nullptr);
  } else {
    func->call_js_cb(func->env, func->js_value, func->context, ctx.data);
  }
}

napi_status napi_call_threadsafe_function(napi_threadsafe_function func,
                                          void* data,
                                          napi_threadsafe_function_call_mode is_blocking) {
  func->env->executor.dispatch_async(func->env->executor.context,
                                     _call_threadsafe_function,
                                     new tsfn_call_context { func, data });
  return napi_ok;
}

napi_status napi_acquire_threadsafe_function(napi_threadsafe_function func) {
  std::lock_guard mutex(func->mutex);
  if (func->refcount == -1) return napi_closing;
  ++func->refcount;
  return napi_ok;
}

napi_status napi_release_threadsafe_function(napi_threadsafe_function func,
                                             napi_threadsafe_function_release_mode mode) {
  bool closing = false;
  do {
    std::lock_guard mutex(func->mutex);
    if (func->refcount == 0) { // already closed
      return napi_closing;
    } else if (mode == napi_tsfn_abort) {
      closing = true;
      func->refcount = 0;
    } else if (--func->refcount == 0) {
      closing = true;
    }
  } while (0);
  if (closing) {
    func->env->executor.dispatch_async(func->env->executor.context, release_threadsafe_function, func);
  }
  return napi_ok;
}

napi_status napi_ref_threadsafe_function(napi_env env, napi_threadsafe_function func) {
  env->strong_tsfns.insert(func);
  return napi_ok;
}

napi_status napi_unref_threadsafe_function(napi_env env, napi_threadsafe_function func) {
  auto it = env->strong_tsfns.find(func);
  if (it != env->strong_tsfns.end()) {
    env->strong_tsfns.erase(it);
    env->check_empty();
  }
  return napi_ok;
}

// MARK: - Node+Version

const static napi_node_version node_api_version {
  .major = 1,
  .minor = 0,
  .patch = 0,
  .release = "1"
};

napi_status napi_get_node_version(napi_env env, const napi_node_version** version) {
  *version = &node_api_version;
  return napi_ok;
}

// MARK: - Node+Cleanup

napi_status napi_add_env_cleanup_hook(napi_env env, napi_cleanup_hook fun, void* arg) {
  CHECK_ENV(env);
  CHECK_ARG(env, fun);
  env->cleanup_hooks[fun].insert(arg);
  return napi_ok;
}

napi_status napi_remove_env_cleanup_hook(napi_env env, napi_cleanup_hook fun, void* arg) {
  CHECK_ENV(env);
  CHECK_ARG(env, fun);
  auto &set = env->cleanup_hooks[fun];
  set.erase(arg);
  if (set.empty()) env->cleanup_hooks.erase(fun);
  return napi_ok;
}

// MARK: - Node+AsyncCleanup

napi_status napi_add_async_cleanup_hook(napi_env env,
                                        napi_async_cleanup_hook hook,
                                        void* arg,
                                        napi_async_cleanup_hook_handle* remove_handle) {
  throw std::runtime_error("unsupported");
}

napi_status napi_remove_async_cleanup_hook(napi_async_cleanup_hook_handle remove_handle) {
  throw std::runtime_error("unsupported");
}

// MARK: - Node+Buffer

napi_status napi_create_buffer(napi_env env,
                               size_t length,
                               void** data,
                               napi_value* result) {
  throw std::runtime_error("unsupported");
}

napi_status napi_create_external_buffer(napi_env env,
                                        size_t length,
                                        void* data,
                                        napi_finalize finalize_cb,
                                        void* finalize_hint,
                                        napi_value* result) {
  throw std::runtime_error("unsupported");
}

napi_status napi_create_buffer_copy(napi_env env,
                                    size_t length,
                                    const void* data,
                                    void** result_data,
                                    napi_value* result) {
  throw std::runtime_error("unsupported");
}

napi_status napi_is_buffer(napi_env env,
                           napi_value value,
                           bool* result) {
  throw std::runtime_error("unsupported");
}

napi_status napi_get_buffer_info(napi_env env,
                                 napi_value value,
                                 void** data,
                                 size_t* length) {
  throw std::runtime_error("unsupported");
}
