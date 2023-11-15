#ifndef node_context_h
#define node_context_h

_Pragma("clang assume_nonnull begin")

// all thread-specific
const void * _Nullable node_swift_context_peek(void);
const void * _Nullable node_swift_context_pop(void);
void node_swift_context_push(const void *value);

_Pragma("clang assume_nonnull end")

#endif /* node_context_h */
