#ifndef task_reflection_h
#define task_reflection_h

#ifdef __cplusplus
#define EXTERN_C extern "C"
#else
#define EXTERN_C
#endif

_Pragma("clang assume_nonnull begin")

typedef struct AsyncTask AsyncTask;

// Run `work` with `task` as the current task
// WARNING: This has side effects; upon return, the "current" task
// will be set to nil. Don't call this inside an existing Task.
EXTERN_C void node_swift_as_current_task(AsyncTask *task, void (*work)(void *), void *ctx);

_Pragma("clang assume_nonnull end")

#endif /* task_reflection_h */
