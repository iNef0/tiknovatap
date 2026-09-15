//
//  NovaTapEngine.m
//  NovaTap - Enterprise Live Engagement Engine
//

#import "NovaTapEngine.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>

static inline double NovaTap_RandomUniform(double min, double max) {
    double r = (double)arc4random() / (double)UINT32_MAX;
    return min + r * (max - min);
}

// Box-Muller transform for 2D Bivariate Gaussian Jitter
static CGPoint NovaTap_GenerateGaussianPoint(CGPoint center, double sigma, double maxRadius) {
    double u1 = (double)arc4random() / (double)UINT32_MAX;
    double u2 = (double)arc4random() / (double)UINT32_MAX;
    if (u1 <= 1e-7) u1 = 1e-7;

    double z0 = sqrt(-2.0 * log(u1)) * cos(2.0 * M_PI * u2);
    double z1 = sqrt(-2.0 * log(u1)) * sin(2.0 * M_PI * u2);

    double dx = z0 * sigma;
    double dy = z1 * sigma;

    // Strict clamping to max radius
    double dist = sqrt(dx * dx + dy * dy);
    if (dist > maxRadius) {
        dx = (dx / dist) * maxRadius;
        dy = (dy / dist) * maxRadius;
    }

    return CGPointMake(center.x + dx, center.y + dy);
}

@interface NovaTapEngine ()

@property (nonatomic, assign, readwrite) NovaTapState state;
@property (nonatomic, assign, readwrite) NSUInteger currentCount;
@property (nonatomic, strong) dispatch_queue_t serialQueue;
@property (nonatomic, assign) BOOL shouldStop;
@property (nonatomic, assign) NSUInteger burstCounter;
@property (nonatomic, assign) NSUInteger burstLimit;
@property (nonatomic, assign) NSUInteger tapsSinceLastMacroRest;
@property (nonatomic, assign) NSUInteger nextMacroRestThreshold;

@end

@implementation NovaTapEngine

+ (instancetype)sharedEngine {
    static NovaTapEngine *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _state = NovaTapStateIdle;
        _currentCount = 0;
        _targetQuota = 10000;
        _speedMode = NovaTapSpeedModeSafe;
        _shouldStop = YES;
        _burstCounter = 0;
        _burstLimit = (NSUInteger)NovaTap_RandomUniform(25, 40);
        _tapsSinceLastMacroRest = 0;
        _nextMacroRestThreshold = (NSUInteger)NovaTap_RandomUniform(450, 600);

        _serialQueue = dispatch_queue_create("com.novatap.bgqueue", DISPATCH_QUEUE_SERIAL);

        [self setupLifecycleObservers];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Lifecycle Observers

- (void)setupLifecycleObservers {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

    [center addObserver:self
               selector:@selector(handleAppDidEnterBackground:)
                   name:UIApplicationDidEnterBackgroundNotification
                 object:nil];

    [center addObserver:self
               selector:@selector(handleAudioInterruption:)
                   name:AVAudioSessionInterruptionNotification
                 object:nil];
}

- (void)handleAppDidEnterBackground:(NSNotification *)notification {
    if (self.state == NovaTapStateRunning || self.state == NovaTapStateResting) {
        [self pauseTapping];
    }
}

- (void)handleAudioInterruption:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    if (!userInfo) return;

    NSNumber *typeValue = userInfo[AVAudioSessionInterruptionTypeKey];
    if (!typeValue) return;

    AVAudioSessionInterruptionType interruptionType = [typeValue unsignedIntegerValue];

    if (interruptionType == AVAudioSessionInterruptionTypeBegan) {
        if (self.state == NovaTapStateRunning) {
            [self pauseTapping];
        }
    } else if (interruptionType == AVAudioSessionInterruptionTypeEnded) {
        NSNumber *optionValue = userInfo[AVAudioSessionInterruptionOptionKey];
        if (optionValue) {
            AVAudioSessionInterruptionOptions options = [optionValue unsignedIntegerValue];
            if (options & AVAudioSessionInterruptionOptionShouldResume) {
                // Resume safely if previously interrupted
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    if (self.state == NovaTapStatePaused) {
                        [self resumeTapping];
                    }
                });
            }
        }
    }
}

#pragma mark - State Controls

- (void)startTapping {
    if (self.state == NovaTapStateRunning) return;

    if (self.currentCount >= self.targetQuota && self.targetQuota > 0) {
        self.currentCount = 0;
    }

    self.shouldStop = NO;
    self.state = NovaTapStateRunning;

    dispatch_async(dispatch_get_main_queue(), ^{
        [UIApplication sharedApplication].idleTimerDisabled = YES;
    });

    [self notifyStateChange:NovaTapStateRunning];

    dispatch_async(self.serialQueue, ^{
        [self engineLoop];
    });
}

- (void)pauseTapping {
    self.shouldStop = YES;
    self.state = NovaTapStatePaused;

    dispatch_async(dispatch_get_main_queue(), ^{
        [UIApplication sharedApplication].idleTimerDisabled = NO;
    });

    [self notifyStateChange:NovaTapStatePaused];
}

- (void)resumeTapping {
    if (self.state != NovaTapStatePaused) return;
    [self startTapping];
}

- (void)resetCounter {
    [self pauseTapping];
    self.currentCount = 0;
    self.burstCounter = 0;
    self.tapsSinceLastMacroRest = 0;
    self.state = NovaTapStateIdle;
    [self notifyCountUpdate];
    [self notifyStateChange:NovaTapStateIdle];
}

- (void)setTargetQuota:(NSUInteger)targetQuota {
    _targetQuota = targetQuota;
    [self notifyCountUpdate];
}

- (void)notifyStateChange:(NovaTapState)newState {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(novaTapStateDidChange:)]) {
            [self.delegate novaTapStateDidChange:newState];
        }
    });
}

- (void)notifyCountUpdate {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(novaTapDidUpdateCount:target:)]) {
            [self.delegate novaTapDidUpdateCount:self.currentCount target:self.targetQuota];
        }
    });
}

- (void)notifyQuotaCompleted {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(novaTapDidCompleteQuota:)]) {
            [self.delegate novaTapDidCompleteQuota:self.currentCount];
        }
    });
}

#pragma mark - Execution Loop & Anti-Ban Cadence

- (void)engineLoop {
    while (!self.shouldStop) {
        @autoreleasepool {
            // 1. Quota Check
            if (self.targetQuota > 0 && self.currentCount >= self.targetQuota) {
                self.shouldStop = YES;
                self.state = NovaTapStateCompleted;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [UIApplication sharedApplication].idleTimerDisabled = NO;
                });
                [self notifyStateChange:NovaTapStateCompleted];
                [self notifyQuotaCompleted];
                break;
            }

            // 2. Macro-Rest Check (every 450 - 600 taps)
            if (self.tapsSinceLastMacroRest >= self.nextMacroRestThreshold) {
                self.tapsSinceLastMacroRest = 0;
                self.nextMacroRestThreshold = (NSUInteger)NovaTap_RandomUniform(450, 600);
                self.state = NovaTapStateResting;
                [self notifyStateChange:NovaTapStateResting];

                double macroRestDuration = NovaTap_RandomUniform(8.0, 14.0);
                [NSThread sleepForTimeInterval:macroRestDuration];

                if (self.shouldStop) break;
                self.state = NovaTapStateRunning;
                [self notifyStateChange:NovaTapStateRunning];
            }

            // 3. Burst Cadence Check (every 25 - 40 taps, rest 2.0s - 4.0s)
            if (self.burstCounter >= self.burstLimit) {
                self.burstCounter = 0;
                self.burstLimit = (NSUInteger)NovaTap_RandomUniform(25, 40);
                self.state = NovaTapStateResting;
                [self notifyStateChange:NovaTapStateResting];

                double breathingRest = NovaTap_RandomUniform(2.0, 4.0);
                [NSThread sleepForTimeInterval:breathingRest];

                if (self.shouldStop) break;
                self.state = NovaTapStateRunning;
                [self notifyStateChange:NovaTapStateRunning];
            }

            // 4. Calculate coordinates with Bivariate Gaussian Jitter
            CGPoint targetPoint = [self calculateClampedTargetPoint];

            // 5. Touch Dwell Simulation: TouchDown -> Dwell Time (35ms - 70ms) -> TouchUp
            double dwellSeconds = NovaTap_RandomUniform(0.035, 0.070);

            // Dispatch synthetic touch sequence to Main Thread safely
            dispatch_sync(dispatch_get_main_queue(), ^{
                [self executeDualDispatchTouchAtPoint:targetPoint dwellTime:dwellSeconds];
            });

            // 6. Update counts
            self.currentCount++;
            self.burstCounter++;
            self.tapsSinceLastMacroRest++;
            [self notifyCountUpdate];

            // 7. Non-linear Micro-Delays between taps (Enforcing hard ceiling of 6-7 taps/s)
            double delaySeconds;
            if (self.speedMode == NovaTapSpeedModeSafe) {
                // Safe Mode: 200ms - 320ms (~3-5 taps/s)
                delaySeconds = NovaTap_RandomUniform(0.200, 0.320);
            } else {
                // Standard Mode: 145ms - 220ms (max ~6.8 taps/s ceiling)
                delaySeconds = NovaTap_RandomUniform(0.145, 0.220);
            }

            [NSThread sleepForTimeInterval:delaySeconds];
        }
    }
}

#pragma mark - Viewport Clamping

- (CGPoint)calculateClampedTargetPoint {
    __block CGRect screenBounds = CGRectZero;
    dispatch_sync(dispatch_get_main_queue(), ^{
        screenBounds = [UIScreen mainScreen].bounds;
    });

    CGFloat width = screenBounds.size.width;
    CGFloat height = screenBounds.size.height;

    // Safe Interaction Zone:
    // Center-right viewport: X from 55% to 85%
    // Y excludes top 15% (Host Info/Status) and bottom 20% (Chat/Gifts): Y from 25% to 75%
    CGFloat minX = width * 0.55;
    CGFloat maxX = width * 0.82;
    CGFloat minY = height * 0.25;
    CGFloat maxY = height * 0.72;

    CGPoint nominalCenter = CGPointMake(NovaTap_RandomUniform(minX, maxX), NovaTap_RandomUniform(minY, maxY));

    // Box-Muller Gaussian jitter with sigma = 12px, clamped to +/- 26px
    CGPoint randomizedPoint = NovaTap_GenerateGaussianPoint(nominalCenter, 12.0, 26.0);

    // Final boundary clamp
    if (randomizedPoint.x < minX) randomizedPoint.x = minX;
    if (randomizedPoint.x > maxX) randomizedPoint.x = maxX;
    if (randomizedPoint.y < minY) randomizedPoint.y = minY;
    if (randomizedPoint.y > maxY) randomizedPoint.y = maxY;

    return randomizedPoint;
}

#pragma mark - Dual-Strategy Touch Dispatching

- (void)executeDualDispatchTouchAtPoint:(CGPoint)point dwellTime:(double)dwellTime {
    @try {
        UIWindow *keyWindow = nil;
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w.isKeyWindow) {
                keyWindow = w;
                break;
            }
        }
        if (!keyWindow) {
            keyWindow = [UIApplication sharedApplication].windows.firstObject;
        }
        if (!keyWindow) return;

        UIViewController *rootVC = keyWindow.rootViewController;
        UIViewController *liveVC = [self findLiveRoomViewControllerFrom:rootVC];
        UIView *targetContainer = nil;

        if (liveVC) {
            targetContainer = liveVC.view;
        } else {
            targetContainer = keyWindow;
        }

        // 1. Gesture Collision & Transition Safety:
        // Check for any active UIPanGestureRecognizer (room switching swipe)
        if ([self isPanGestureActiveInView:targetContainer]) {
            // Abort current tap cycle to prevent gesture conflict or crash
            return;
        }

        // Strategy 1: Primary Dispatch via Registered UITapGestureRecognizer
        BOOL gestureDispatched = [self dispatchViaTapGestureInView:targetContainer atPoint:point];

        // Strategy 2: Fallback to Responder touchesEnded:withEvent:
        if (!gestureDispatched) {
            [self dispatchViaDirectResponderInView:targetContainer atPoint:point dwellTime:dwellTime];
        }
    } @catch (NSException *exception) {
        // Defensive zero-crash barrier
    }
}

- (BOOL)isPanGestureActiveInView:(UIView *)view {
    if (!view) return NO;

    for (UIGestureRecognizer *gr in view.gestureRecognizers) {
        if ([gr isKindOfClass:[UIPanGestureRecognizer class]]) {
            UIGestureRecognizerState state = gr.state;
            if (state == UIGestureRecognizerStateBegan || state == UIGestureRecognizerStateChanged) {
                return YES;
            }
        }
    }

    for (UIView *subview in view.subviews) {
        if ([self isPanGestureActiveInView:subview]) {
            return YES;
        }
    }

    return NO;
}

- (BOOL)dispatchViaTapGestureInView:(UIView *)view atPoint:(CGPoint)point {
    if (!view) return NO;

    // Search for UITapGestureRecognizer that handles like/double-tap in live room
    for (UIGestureRecognizer *gr in view.gestureRecognizers) {
        if ([gr isKindOfClass:[UITapGestureRecognizer class]]) {
            UITapGestureRecognizer *tapGR = (UITapGestureRecognizer *)gr;
            if (tapGR.isEnabled) {
                // Safely invoke targets using private / runtime selectors
                Ivar targetsIvar = class_getInstanceVariable([UIGestureRecognizer class], "_targets");
                if (targetsIvar) {
                    id targetList = object_getIvar(tapGR, targetsIvar);
                    if ([targetList isKindOfClass:[NSMutableArray class]] || [targetList isKindOfClass:[NSArray class]]) {
                        for (id targetObj in (NSArray *)targetList) {
                            Ivar targetIvar = class_getInstanceVariable([targetObj class], "_target");
                            Ivar actionIvar = class_getInstanceVariable([targetObj class], "_action");
                            if (targetIvar && actionIvar) {
                                id target = object_getIvar(targetObj, targetIvar);
                                SEL action = (SEL)ptrdiff_t_getIvar(targetObj, actionIvar);
                                if (target && action && [target respondsToSelector:action]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                                    [target performSelector:action withObject:tapGR];
#pragma clang diagnostic pop
                                    return YES;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Traverse subviews for player/lynx containers
    for (UIView *subview in view.subviews) {
        if ([self dispatchViaTapGestureInView:subview atPoint:point]) {
            return YES;
        }
    }

    return NO;
}

static inline ptrdiff_t ptrdiff_t_getIvar(id object, Ivar ivar) {
    ptrdiff_t val = 0;
    object_getInstanceVariable(object, ivar_getName(ivar), (void **)&val);
    return val;
}

- (void)dispatchViaDirectResponderInView:(UIView *)container atPoint:(CGPoint)point dwellTime:(double)dwellTime {
    UIView *hitView = [container hitTest:point withEvent:nil];
    if (!hitView) {
        hitView = container;
    }

    UITouch *syntheticTouch = [[UITouch alloc] init];
    UIEvent *syntheticEvent = [[UIEvent alloc] init];

    // Simulate Touch Down
    if ([hitView respondsToSelector:@selector(touchesBegan:withEvent:)]) {
        [hitView touchesBegan:[NSSet setWithObject:syntheticTouch] withEvent:syntheticEvent];
    }

    // Simulate Dwell Duration
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(dwellTime * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try {
            if ([hitView respondsToSelector:@selector(touchesEnded:withEvent:)]) {
                [hitView touchesEnded:[NSSet setWithObject:syntheticTouch] withEvent:syntheticEvent];
            }
        } @catch (NSException *e) {
            // Defensive recovery
        }
    });
}

#pragma mark - Hierarchy Introspection

- (UIViewController *)findLiveRoomViewControllerFrom:(UIViewController *)vc {
    if (!vc) return nil;

    Class liveRoomVCClass = objc_getClass("IESLiveRoomViewController");
    Class playerViewClass = objc_getClass("IESLivePlayerView");

    if (liveRoomVCClass && [vc isKindOfClass:liveRoomVCClass]) {
        return vc;
    }

    // Check presented VC
    if (vc.presentedViewController) {
        UIViewController *found = [self findLiveRoomViewControllerFrom:vc.presentedViewController];
        if (found) return found;
    }

    // Check child VCs
    for (UIViewController *child in vc.childViewControllers) {
        UIViewController *found = [self findLiveRoomViewControllerFrom:child];
        if (found) return found;
    }

    // Check if view contains IESLivePlayerView
    if (playerViewClass && [self viewContainsClass:vc.view targetClass:playerViewClass]) {
        return vc;
    }

    return nil;
}

- (BOOL)viewContainsClass:(UIView *)view targetClass:(Class)cls {
    if (!view || !cls) return NO;
    if ([view isKindOfClass:cls]) return YES;
    for (UIView *subview in view.subviews) {
        if ([self viewContainsClass:subview targetClass:cls]) return YES;
    }
    return NO;
}

@end
