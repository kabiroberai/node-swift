#include <node_context.h>
#include <stdlib.h>

#define thread_local __thread

struct node_context {
    const void *value;
    struct node_context *next;
};

static thread_local struct node_context *node_context_head = NULL;

const void *node_context_peek(void) {
    if (!node_context_head) return NULL;
    return node_context_head->value;
}

const void *node_context_pop(void) {
    if (!node_context_head) return NULL;
    struct node_context *old_head = node_context_head;
    node_context_head = old_head->next;
    const void *value = old_head->value;
    free(old_head);
    return value;
}

void node_context_push(const void *value) {
    struct node_context *ctx = malloc(sizeof(ctx));
    ctx->value = value;
    ctx->next = node_context_head;
    node_context_head = ctx;
}
