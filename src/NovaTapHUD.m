//
//  NovaTapHUD.m
//  NovaTap - Floating Glassmorphism Arabic HUD
//

#import "NovaTapHUD.h"
#import "NovaTapEngine.h"

@interface NovaTapHUDWindow : UIWindow
@end

@implementation NovaTapHUDWindow
// Pass touches through transparent regions of the window
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self || hitView == self.rootViewController.view) {
        return nil;
    }
    return hitView;
}
@end

@interface NovaTapHUDViewController : UIViewController
@property (nonatomic, weak) NovaTapHUD *hudManager;
@end

@implementation NovaTapHUDViewController
- (BOOL)shouldAutorotate {
    return NO;
}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}
@end

@interface NovaTapHUD ()

@property (nonatomic, strong, readwrite) UIWindow *overlayWindow;
@property (nonatomic, strong) UIView *containerCard;
@property (nonatomic, strong) UIView *minimizedBubble;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *counterLabel;
@property (nonatomic, strong) UIProgressView *progressBar;
@property (nonatomic, strong) UIButton *playPauseButton;
@property (nonatomic, strong) UIButton *speedModeButton;
@property (nonatomic, strong) UIButton *minimizeButton;
@property (nonatomic, strong) UIButton *resetButton;
@property (nonatomic, strong) UILabel *bubbleLabel;

@property (nonatomic, assign, readwrite) BOOL isMinimized;
@property (nonatomic, strong) UIImpactFeedbackGenerator *hapticFeedback;

@end

@implementation NovaTapHUD

+ (instancetype)sharedHUD {
    static NovaTapHUD *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _isMinimized = NO;
        _hapticFeedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [NovaTapEngine sharedEngine].delegate = self;
    }
    return self;
}

#pragma mark - UI Setup

- (void)showHUD {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.overlayWindow) {
            self.overlayWindow.hidden = NO;
            return;
        }

        UIWindowScene *activeScene = nil;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                activeScene = (UIWindowScene *)scene;
                break;
            }
        }

        if (activeScene) {
            self.overlayWindow = [[NovaTapHUDWindow alloc] initWithWindowScene:activeScene];
        } else {
            self.overlayWindow = [[NovaTapHUDWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        }

        self.overlayWindow.windowLevel = UIWindowLevelAlert - 1.0;
        self.overlayWindow.backgroundColor = [UIColor clearColor];

        NovaTapHUDViewController *rootVC = [[NovaTapHUDViewController alloc] init];
        rootVC.hudManager = self;
        rootVC.view.backgroundColor = [UIColor clearColor];
        self.overlayWindow.rootViewController = rootVC;

        [self buildExpandedCardInView:rootVC.view];
        [self buildMinimizedBubbleInView:rootVC.view];

        self.overlayWindow.hidden = NO;
    });
}

- (void)hideHUD {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.overlayWindow.hidden = YES;
    });
}

- (UIColor *)navyColor {
    // Deep Midnight Navy: #0A1128 with alpha for glassmorphism
    return [UIColor colorWithRed:10.0/255.0 green:17.0/255.0 blue:40.0/255.0 alpha:0.94];
}

- (UIColor *)maroonColor {
    // Deep Maroon: #5C061C
    return [UIColor colorWithRed:92.0/255.0 green:6.0/255.0 blue:28.0/255.0 alpha:1.0];
}

- (void)buildExpandedCardInView:(UIView *)parentView {
    CGFloat cardWidth = 280.0;
    CGFloat cardHeight = 220.0;
    CGFloat startX = [UIScreen mainScreen].bounds.size.width - cardWidth - 16.0;
    CGFloat startY = 120.0; // Avoid top status & BHTikTok controls

    self.containerCard = [[UIView alloc] initWithFrame:CGRectMake(startX, startY, cardWidth, cardHeight)];
    self.containerCard.backgroundColor = [self navyColor];
    self.containerCard.layer.cornerRadius = 18.0;
    self.containerCard.layer.borderWidth = 1.5;
    self.containerCard.layer.borderColor = [self maroonColor].CGColor;
    self.containerCard.layer.shadowColor = [UIColor blackColor].CGColor;
    self.containerCard.layer.shadowOffset = CGSizeMake(0, 4);
    self.containerCard.layer.shadowOpacity = 0.4;
    self.containerCard.layer.shadowRadius = 8.0;
    self.containerCard.clipsToBounds = NO;

    // Draggable Pan Gesture
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleCardPan:)];
    [self.containerCard addGestureRecognizer:pan];

    // 1. Header Bar (Title + Minimize Button)
    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(50, 12, 180, 24)];
    self.titleLabel.text = @"نوفاتاب ⚡ NovaTap";
    self.titleLabel.font = [UIFont boldSystemFontOfSize:15.0];
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.containerCard addSubview:self.titleLabel];

    self.minimizeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.minimizeButton.frame = CGRectMake(cardWidth - 40, 10, 30, 30);
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightBold];
    UIImage *minIcon = [UIImage systemImageNamed:@"minus" withConfiguration:config];
    [self.minimizeButton setImage:minIcon forState:UIControlStateNormal];
    self.minimizeButton.tintColor = [UIColor colorWithWhite:0.85 alpha:1.0];
    [self.minimizeButton addTarget:self action:@selector(toggleMinimize) forControlEvents:UIControlEventTouchUpInside];
    [self.containerCard addSubview:self.minimizeButton];

    // 2. Real-time Counter & Quota
    self.counterLabel = [[UILabel alloc] initWithFrame:CGRectMake(14, 46, cardWidth - 28, 28)];
    self.counterLabel.text = @"العداد: 0 / 10,000 (0.0%)";
    self.counterLabel.font = [UIFont monospacedDigitSystemFontOfSize:14.0 weight:UIFontWeightSemibold];
    self.counterLabel.textColor = [UIColor whiteColor];
    self.counterLabel.textAlignment = NSTextAlignmentCenter;
    [self.containerCard addSubview:self.counterLabel];

    // Progress Bar
    self.progressBar = [[UIProgressView alloc] initWithFrame:CGRectMake(16, 80, cardWidth - 32, 4)];
    self.progressBar.progressTintColor = [self maroonColor];
    self.progressBar.trackTintColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    self.progressBar.progress = 0.0;
    self.progressBar.layer.cornerRadius = 2.0;
    self.progressBar.clipsToBounds = YES;
    [self.containerCard addSubview:self.progressBar];

    // 3. Play / Pause Button (Primary Action)
    self.playPauseButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.playPauseButton.frame = CGRectMake(16, 96, cardWidth - 32, 42);
    self.playPauseButton.backgroundColor = [self maroonColor];
    self.playPauseButton.layer.cornerRadius = 12.0;
    [self.playPauseButton setTitle:@"▶ تشغيل التكبيس" forState:UIControlStateNormal];
    [self.playPauseButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.playPauseButton.titleLabel.font = [UIFont boldSystemFontOfSize:15.0];
    [self.playPauseButton addTarget:self action:@selector(playPauseAction) forControlEvents:UIControlEventTouchUpInside];
    [self.containerCard addSubview:self.playPauseButton];

    // 4. Mode Switcher (آمن / قياسي) & Reset Button
    CGFloat subButtonWidth = (cardWidth - 40) / 2.0;

    self.speedModeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.speedModeButton.frame = CGRectMake(16, 150, subButtonWidth, 36);
    self.speedModeButton.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0];
    self.speedModeButton.layer.cornerRadius = 8.0;
    [self.speedModeButton setTitle:@"السرعة: آمن 🛡️" forState:UIControlStateNormal];
    [self.speedModeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.speedModeButton.titleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    [self.speedModeButton addTarget:self action:@selector(toggleSpeedMode) forControlEvents:UIControlEventTouchUpInside];
    [self.containerCard addSubview:self.speedModeButton];

    self.resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.resetButton.frame = CGRectMake(cardWidth - 16 - subButtonWidth, 150, subButtonWidth, 36);
    self.resetButton.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0];
    self.resetButton.layer.cornerRadius = 8.0;
    [self.resetButton setTitle:@"إعادة ضبط ↺" forState:UIControlStateNormal];
    [self.resetButton setTitleColor:[UIColor colorWithRed:255/255.0 green:100/255.0 blue:100/255.0 alpha:1.0] forState:UIControlStateNormal];
    self.resetButton.titleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    [self.resetButton addTarget:self action:@selector(resetCounterAction) forControlEvents:UIControlEventTouchUpInside];
    [self.containerCard addSubview:self.resetButton];

    // Quota Quick Toggle Label
    UILabel *hintLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 192, cardWidth - 32, 18)];
    hintLabel.text = @"الهدف: 10,000 نقرة | حماية ProMotion 120Hz";
    hintLabel.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightRegular];
    hintLabel.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
    hintLabel.textAlignment = NSTextAlignmentCenter;
    [self.containerCard addSubview:hintLabel];

    [parentView addSubview:self.containerCard];
}

- (void)buildMinimizedBubbleInView:(UIView *)parentView {
    CGFloat bubbleSize = 54.0;
    CGFloat startX = [UIScreen mainScreen].bounds.size.width - bubbleSize - 12.0;
    CGFloat startY = 160.0;

    self.minimizedBubble = [[UIView alloc] initWithFrame:CGRectMake(startX, startY, bubbleSize, bubbleSize)];
    self.minimizedBubble.backgroundColor = [self navyColor];
    self.minimizedBubble.layer.cornerRadius = bubbleSize / 2.0;
    self.minimizedBubble.layer.borderWidth = 2.0;
    self.minimizedBubble.layer.borderColor = [self maroonColor].CGColor;
    self.minimizedBubble.layer.shadowColor = [UIColor blackColor].CGColor;
    self.minimizedBubble.layer.shadowOffset = CGSizeMake(0, 3);
    self.minimizedBubble.layer.shadowOpacity = 0.5;
    self.minimizedBubble.layer.shadowRadius = 6.0;
    self.minimizedBubble.hidden = YES;

    self.bubbleLabel = [[UILabel alloc] initWithFrame:self.minimizedBubble.bounds];
    self.bubbleLabel.text = @"⚡";
    self.bubbleLabel.font = [UIFont systemFontOfSize:22.0];
    self.bubbleLabel.textAlignment = NSTextAlignmentCenter;
    [self.minimizedBubble addSubview:self.bubbleLabel];

    UITapGestureRecognizer *tapBubble = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleMinimize)];
    [self.minimizedBubble addGestureRecognizer:tapBubble];

    UIPanGestureRecognizer *panBubble = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleBubblePan:)];
    [self.minimizedBubble addGestureRecognizer:panBubble];

    [parentView addSubview:self.minimizedBubble];
}

#pragma mark - Actions

- (void)playPauseAction {
    NovaTapEngine *engine = [NovaTapEngine sharedEngine];
    if (engine.state == NovaTapStateRunning) {
        [engine pauseTapping];
        [self.playPauseButton setTitle:@"▶ تشغيل التكبيس" forState:UIControlStateNormal];
        self.playPauseButton.backgroundColor = [self maroonColor];
    } else {
        // Haptic Feedback strictly on session start
        [self.hapticFeedback prepare];
        [self.hapticFeedback impactOccurred];

        [engine startTapping];
        [self.playPauseButton setTitle:@"⏸ إيقاف مؤقت" forState:UIControlStateNormal];
        self.playPauseButton.backgroundColor = [UIColor colorWithRed:30/255.0 green:120/255.0 blue:60/255.0 alpha:1.0];
    }
}

- (void)toggleSpeedMode {
    NovaTapEngine *engine = [NovaTapEngine sharedEngine];
    if (engine.speedMode == NovaTapSpeedModeSafe) {
        engine.speedMode = NovaTapSpeedModeStandard;
        [self.speedModeButton setTitle:@"السرعة: قياسي 🚀" forState:UIControlStateNormal];
    } else {
        engine.speedMode = NovaTapSpeedModeSafe;
        [self.speedModeButton setTitle:@"السرعة: آمن 🛡️" forState:UIControlStateNormal];
    }
}

- (void)resetCounterAction {
    [[NovaTapEngine sharedEngine] resetCounter];
    [self.playPauseButton setTitle:@"▶ تشغيل التكبيس" forState:UIControlStateNormal];
    self.playPauseButton.backgroundColor = [self maroonColor];
}

- (void)toggleMinimize {
    self.isMinimized = !self.isMinimized;
    [UIView animateWithDuration:0.25 animations:^{
        if (self.isMinimized) {
            self.containerCard.alpha = 0.0;
            self.minimizedBubble.alpha = 1.0;
            self.minimizedBubble.hidden = NO;
        } else {
            self.containerCard.alpha = 1.0;
            self.minimizedBubble.alpha = 0.0;
            self.containerCard.hidden = NO;
        }
    } completion:^(BOOL finished) {
        if (self.isMinimized) {
            self.containerCard.hidden = YES;
        } else {
            self.minimizedBubble.hidden = YES;
        }
    }];
}

#pragma mark - Drag Gestures

- (void)handleCardPan:(UIPanGestureRecognizer *)pan {
    CGPoint translation = [pan translationInView:self.overlayWindow];
    CGRect frame = self.containerCard.frame;
    frame.origin.x += translation.x;
    frame.origin.y += translation.y;

    // Constrain to screen bounds
    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    frame.origin.x = MAX(8.0, MIN(screenSize.width - frame.size.width - 8.0, frame.origin.x));
    frame.origin.y = MAX(44.0, MIN(screenSize.height - frame.size.height - 44.0, frame.origin.y));

    self.containerCard.frame = frame;
    [pan setTranslation:CGPointZero inView:self.overlayWindow];
}

- (void)handleBubblePan:(UIPanGestureRecognizer *)pan {
    CGPoint translation = [pan translationInView:self.overlayWindow];
    CGRect frame = self.minimizedBubble.frame;
    frame.origin.x += translation.x;
    frame.origin.y += translation.y;

    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    frame.origin.x = MAX(8.0, MIN(screenSize.width - frame.size.width - 8.0, frame.origin.x));
    frame.origin.y = MAX(44.0, MIN(screenSize.height - frame.size.height - 44.0, frame.origin.y));

    self.minimizedBubble.frame = frame;
    [pan setTranslation:CGPointZero inView:self.overlayWindow];
}

#pragma mark - NovaTapEngineDelegate

- (void)novaTapDidUpdateCount:(NSUInteger)currentCount target:(NSUInteger)targetCount {
    double progress = targetCount > 0 ? ((double)currentCount / (double)targetCount) : 0.0;
    if (progress > 1.0) progress = 1.0;

    double percent = progress * 100.0;
    self.counterLabel.text = [NSString stringWithFormat:@"العداد: %lu / %lu (%.1f%%)",
                              (unsigned long)currentCount,
                              (unsigned long)targetCount,
                              percent];
    self.progressBar.progress = (float)progress;

    if (self.isMinimized) {
        self.bubbleLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)currentCount];
        self.bubbleLabel.font = [UIFont boldSystemFontOfSize:11.0];
    }
}

- (void)novaTapStateDidChange:(NovaTapState)newState {
    switch (newState) {
        case NovaTapStateRunning:
            [self.playPauseButton setTitle:@"⏸ إيقاف مؤقت" forState:UIControlStateNormal];
            self.playPauseButton.backgroundColor = [UIColor colorWithRed:30/255.0 green:120/255.0 blue:60/255.0 alpha:1.0];
            break;
        case NovaTapStatePaused:
        case NovaTapStateIdle:
            [self.playPauseButton setTitle:@"▶ تشغيل التكبيس" forState:UIControlStateNormal];
            self.playPauseButton.backgroundColor = [self maroonColor];
            break;
        case NovaTapStateResting:
            [self.playPauseButton setTitle:@"⏳ فترة راحة ذكية..." forState:UIControlStateNormal];
            self.playPauseButton.backgroundColor = [UIColor colorWithRed:160/255.0 green:120/255.0 blue:20/255.0 alpha:1.0];
            break;
        case NovaTapStateCompleted:
            [self.playPauseButton setTitle:@"✔ اكتمل الهدف" forState:UIControlStateNormal];
            self.playPauseButton.backgroundColor = [UIColor colorWithRed:40/255.0 green:160/255.0 blue:60/255.0 alpha:1.0];
            break;
    }
}

- (void)novaTapDidCompleteQuota:(NSUInteger)totalTaps {
    // Haptic feedback strictly on quota completion
    [self.hapticFeedback prepare];
    [self.hapticFeedback impactOccurred];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🎉 تم إكمال الهدف بنجاح"
                                                                   message:[NSString stringWithFormat:@"وصل العداد إلى %lu نقرة وفق معايير الأمان المبرمجة.", (unsigned long)totalTaps]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"حسناً" style:UIAlertActionStyleDefault handler:nil]];

    [self.overlayWindow.rootViewController presentViewController:alert animated:YES completion:nil];
}

@end
