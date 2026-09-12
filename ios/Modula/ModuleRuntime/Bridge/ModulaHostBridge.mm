#import "ModulaHostBridge.h"
#import "Modula-Swift.h"

@implementation ModulaHostBridge {
  id _eventObserver;
}
RCT_EXPORT_MODULE(NativeModulaHost)
+ (BOOL)requiresMainQueueSetup { return YES; }
// Codegen providers may exist before their JS event emitter is installed.
// Observe only after installation; an empty std::function must never be invoked.
- (void)setEventEmitterCallback:(EventEmitterCallbackWrapper *)callback {
  [super setEventEmitterCallback:callback];
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self->_eventObserver) return;
    __weak ModulaHostBridge *weakSelf = self;
    self->_eventObserver = [[NSNotificationCenter defaultCenter] addObserverForName:@"ModulaHostEvent" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
      ModulaHostBridge *bridge = weakSelf;
      if (bridge && bridge->_eventEmitterCallback && [notification.object isKindOfClass:NSString.class]) {
        [bridge emitOnHostEvent:(NSString *)notification.object];
      }
    }];
  });
}
- (void)request:(NSString *)json resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
  dispatch_async(dispatch_get_main_queue(), ^{
    [[ModulaBridge shared] request:json completion:^(NSString *result) { resolve(result); }];
  });
}
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:(const facebook::react::ObjCTurboModule::InitParams &)params {
  return std::make_shared<facebook::react::NativeModulaHostSpecJSI>(params);
}
- (void)dealloc {
  if (_eventObserver) [[NSNotificationCenter defaultCenter] removeObserver:_eventObserver];
}
@end
