#pragma once

#include "base.h"
#include <functional>

void JSAddFinalizer(JSGlobalContextRef ctx, JSValueRef value, std::function<void(void)> finalizer);
