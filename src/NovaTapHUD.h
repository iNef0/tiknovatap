//
//  NovaTapHUD.h
//  NovaTap - Floating Glassmorphism Arabic HUD
//

#import <UIKit/UIKit.h>
#import "NovaTapEngine.h"

NS_ASSUME_NONNULL_BEGIN

@interface NovaTapHUD : NSObject <NovaTapEngineDelegate>

@property (nonatomic, strong, readonly) UIWindow *overlayWindow;
@property (nonatomic, assign, readonly) BOOL isMinimized;

+ (instancetype)sharedHUD;
- (void)showHUD;
- (void)hideHUD;
- (void)toggleMinimize;

@end

NS_ASSUME_NONNULL_END
