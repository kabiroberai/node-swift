#ifndef cf_stubs_h
#define cf_stubs_h

#include <stdlib.h>

#if defined(__APPLE__)

#include <mach/message.h>
#include <sys/event.h>

static inline struct kevent64_s node_swift_create_event_descriptor_for_mach_port(mach_port_t port) {
    struct kevent64_s ev;
    EV_SET64(&ev, port, EVFILT_MACHPORT, EV_ADD|EV_CLEAR, MACH_RCV_MSG, 0, 0, 0, 0);
    return ev;
}

typedef mach_port_t dispatch_runloop_handle_t;

#elif defined(__linux__)
typedef int dispatch_runloop_handle_t;
#elif defined(__unix__)
typedef uint64_t dispatch_runloop_handle_t;
#elif defined(_WIN32)
typedef void *dispatch_runloop_handle_t;
#else
#define NODE_SWIFT_NO_GCD_RUNLOOP
#endif

#ifndef NODE_SWIFT_NO_GCD_RUNLOOP
dispatch_runloop_handle_t _dispatch_get_main_queue_port_4CF(void);
void _dispatch_main_queue_callback_4CF(void);
#endif

#endif /* cf_stubs_h */
