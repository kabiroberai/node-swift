#include "task_reflection.h"
#include <cinttypes>

// this is swift ABI

namespace SpecialPointerAuthDiscriminators {
const uint16_t TaskResumeFunction = 0x2c42; // = 11330
const uint16_t TaskResumeContext = 0x753a; // = 30010
};

#if __has_feature(ptrauth_calls)
#include <ptrauth.h>
#define __ptrauth_swift_task_resume_function                                   \
  __ptrauth(ptrauth_key_function_pointer, 1,                                   \
            SpecialPointerAuthDiscriminators::TaskResumeFunction)
#define __ptrauth_swift_task_resume_context                                    \
  __ptrauth(ptrauth_key_process_independent_data, 1,                           \
            SpecialPointerAuthDiscriminators::TaskResumeContext)
#else
#define __ptrauth_swift_task_resume_function
#define __ptrauth_swift_task_resume_context
#endif

using TaskContinuationFunction =
    __attribute__((swiftasynccall))
    void (__attribute__((swift_async_context)) void *);

struct HeapObject {
    void *metadata;
    uintptr_t refCounts;
};

struct alignas(2 * alignof(void *)) Job: public HeapObject {
    void *SchedulerPrivate[2];
    uint32_t Flags;
    uint32_t Id;
    void *Voucher;
    void *Reserved;
    TaskContinuationFunction *__ptrauth_swift_task_resume_function ResumeTask;
};

struct AsyncTask: public Job {
    void *__ptrauth_swift_task_resume_context ResumeContext;
};

class ExecutorRef {
    HeapObject *Identity;
    uintptr_t Implementation;
};

__attribute__((swiftcall)) EXTERN_C ExecutorRef swift_task_getCurrentExecutor(void);
__attribute__((swiftcall)) EXTERN_C void swift_job_run(Job *job, ExecutorRef executor);
__attribute__((swiftcall)) EXTERN_C Job *swift_task_suspend(void);

// our own stuff

static __thread struct {
    void (*work)(void *);
    void *ctx;
} closure = { nullptr, nullptr };

__attribute__((swiftasynccall)) static void node_swift_resume_trampoline(__attribute__((swift_async_context)) void *ctx) {
    closure.work(closure.ctx);
    swift_task_suspend();
}

// see explanation in NodeExecutor.enqueue
EXTERN_C void node_swift_as_current_task(AsyncTask *task, void (*work)(void *), void *ctx) {
    auto actualResume = task->ResumeTask;
    auto actualContext = task->ResumeContext;
    task->ResumeTask = &node_swift_resume_trampoline;
    task->ResumeContext = nullptr;
    closure = { work, ctx };
    swift_job_run(task, swift_task_getCurrentExecutor());
    closure = { nullptr, nullptr };
    task->ResumeTask = actualResume;
    // even if we didn't null out ResumeContext we need to restore
    // it here because there's no reason swift_task_suspend can't
    // null it out itself (even though as of Swift 5.6 it doesn't)
    task->ResumeContext = actualContext;
}
