#import "ModulaHostBridge.h"
// The generated Swift header declares the CallKit/PushKit delegate bridges.
#import <CallKit/CallKit.h>
#import <PushKit/PushKit.h>
#import "Modula-Swift.h"

// Host events are no longer broadcast through the shared `onHostEvent` emitter: every
// surface receives its own lifecycle/appearance updates as new root props set natively on
// that surface (ModuleRuntimeController.deliver). The codegen emitter stays in the spec
// for contract compatibility but is never fired.
@implementation ModulaHostBridge
RCT_EXPORT_MODULE(NativeModulaHost)
+ (BOOL)requiresMainQueueSetup { return YES; }
- (void)request:(NSString *)json resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
  dispatch_async(dispatch_get_main_queue(), ^{
    [[ModulaBridge shared] request:json completion:^(NSString *result) { resolve(result); }];
  });
}
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:(const facebook::react::ObjCTurboModule::InitParams &)params {
  return std::make_shared<facebook::react::NativeModulaHostSpecJSI>(params);
}
@end
