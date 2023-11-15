#include <node_context.h>
#include <stdlib.h>

struct context_list {
    const void *value;
    struct context_list *next;
};

static __thread struct context_list *list_head = NULL;

const void *node_swift_context_peek(void) {
    if (!list_head) return NULL;
    return list_head->value;
}

const void *node_swift_context_pop(void) {
    if (!list_head) return NULL;
    struct context_list *old_head = list_head;
    list_head = old_head->next;
    const void *value = old_head->value;
    free(old_head);
    return value;
}

void node_swift_context_push(const void *value) {
    struct context_list *ctx = malloc(sizeof(*ctx));
    ctx->value = value;
    ctx->next = list_head;
    list_head = ctx;
}
