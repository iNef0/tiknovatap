//
//  NovaTapEngine.h
//  NovaTap - Enterprise Live Engagement Engine
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NovaTapSpeedMode) {
    NovaTapSpeedModeSafe = 0,     // 3 - 5 taps/sec with conservative micro-rests
    NovaTapSpeedModeStandard = 1  // 6 - 7 taps/sec strict ceiling
};

typedef NS_ENUM(NSInteger, NovaTapState) {
    NovaTapStateIdle,
    NovaTapStateRunning,
    NovaTapStatePaused,
    NovaTapStateResting,
    NovaTapStateCompleted
};

@protocol NovaTapEngineDelegate <NSObject>
@optional
- (void)novaTapDidUpdateCount:(NSUInteger)currentCount target:(NSUInteger)targetCount;
- (void)novaTapStateDidChange:(NovaTapState)newState;
- (void)novaTapDidCompleteQuota:(NSUInteger)totalTaps;
@end

@interface NovaTapEngine : NSObject

@property (nonatomic, weak, nullable) id<NovaTapEngineDelegate> delegate;
@property (nonatomic, assign, readonly) NovaTapState state;
@property (nonatomic, assign, readonly) NSUInteger currentCount;
@property (nonatomic, assign) NSUInteger targetQuota;
@property (nonatomic, assign) NovaTapSpeedMode speedMode;

+ (instancetype)sharedEngine;

- (void)startTapping;
- (void)pauseTapping;
- (void)resumeTapping;
- (void)resetCounter;
- (void)setTargetQuota:(NSUInteger)targetQuota;

@end

NS_ASSUME_NONNULL_END
