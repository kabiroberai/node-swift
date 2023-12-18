#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import "NodeManagedValue.h"

@interface JSManagedValue (Private)
// no public way to observe finalization unfortunately
- (void)disconnectValue;
@end

@interface NodeManagedValue : JSManagedValue
@property (nonatomic, copy, nullable) void (^didFinalize)(void);
@end

@implementation NodeManagedValue
- (instancetype)initWithValue:(JSValue *)value {
  self = [super initWithValue:value];
  return self;
}

- (void)disconnectValue {
  [super disconnectValue];
  if (_didFinalize) {
    auto finalizer = _didFinalize;
    _didFinalize = nil;
    finalizer();
  }
}
@end

void JSAddFinalizer(JSGlobalContextRef ctx, JSValueRef value, std::function<void(void)> finalizer) {
  auto global = JSContextGetGlobalContext(ctx);
  auto jsContext = [JSContext contextWithJSGlobalContextRef:global];
  auto jsValue = [JSValue valueWithJSValueRef:value inContext:jsContext];
  auto managed = [[NodeManagedValue alloc] initWithValue:jsValue];
  // keep `managed` alive until the finalizer is called
  auto bridged = CFBridgingRetain(managed);
  managed.didFinalize = ^{
    finalizer();
    CFBridgingRelease(bridged);
  };
}
