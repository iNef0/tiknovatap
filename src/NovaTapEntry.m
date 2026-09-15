//
//  NovaTapEntry.m
//  NovaTap - Entry Point and Dynamic Injection Bootstrapper
//

#import <UIKit/UIKit.h>
#import "NovaTapHUD.h"
#import "NovaTapEngine.h"

__attribute__((constructor))
static void NovaTap_Initialize(void) {
    NSLog(@"[NovaTap] Dynamic library loaded into process memory. Initializing PAC-resilient subsystem...");

    // Register application did finish launching listener
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        NSLog(@"[NovaTap] Application launched. Presenting HUD overlay...");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[NovaTapHUD sharedHUD] showHUD];
        });
    }];

    // Fallback if app already launched
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([UIApplication sharedApplication].keyWindow) {
            [[NovaTapHUD sharedHUD] showHUD];
        }
    });
}
