#ifndef cf_stubs_h
#define cf_stubs_h

#ifdef __APPLE__

#include <mach/message.h>
#include <sys/event.h>

mach_port_t _dispatch_get_main_queue_port_4CF(void);
void _dispatch_main_queue_callback_4CF(void);

static inline struct kevent64_s node_swift_create_event_descriptor_for_portset(mach_port_t port) {
    struct kevent64_s ev;
    EV_SET64(&ev, port, EVFILT_MACHPORT, EV_ADD|EV_CLEAR, MACH_RCV_MSG, 0, 0, 0, 0);
    return ev;
}

#endif /* __APPLE__ */

#endif /* cf_stubs_h */
