// Copyright 2024 The Lynx Authors. All rights reserved.
// Licensed under the Apache License Version 2.0 that can be found in the
// LICENSE file in the root directory of this source tree.

#import "LynxViewShellViewController.h"
#import <Lynx/LynxEnv.h>
#import <Lynx/LynxError.h>
#import <Lynx/LynxProviderRegistry.h>
#import <Lynx/LynxView.h>
#import <Lynx/LynxViewClient.h>
#import "DemoGenericResourceFetcher.h"
#import "DemoMediaResourceFetcher.h"
#import "DemoTemplateResourceFetcher.h"
#import "LynxExplorerInput.h"
#import "LynxSettingManager.h"
#import "UIHelper.h"

const NSString *const kParamHiddenNav = @"hidden_nav";
const NSString *const kParamFullScreen = @"fullscreen";
const NSString *const kParamTitle = @"title";
const NSString *const kParamTitleColor = @"title_color";
const NSString *const kParamBarColor = @"bar_color";
const NSString *const kParamBackButtonStyle = @"back_button_style";
NSString *const kBackButtonStyleLight = @"light";
NSString *const kBackButtonStyleDark = @"dark";
NSString *const kBackButtonImageLight = @"back_light";
NSString *const kBackButtonImageDark = @"back_dark";

@interface LynxViewShellViewController () <LynxViewLifecycle> {
  LynxExtraTiming *extraTiming;
}

@property(nonatomic, assign) BOOL fullScreen;
@property(nonatomic, copy) NSString *backButtonImageName;
@property(nonatomic, copy) NSString *navTitle;
@property(nonatomic, strong) UIColor *titleColor;
@property(nonatomic, strong) UIColor *barColor;
@property(nonatomic, strong) UIView *previousViewControllerView;
@property(nonatomic, copy) NSString *frontendTheme;
@property(nonatomic, strong) LynxView *lynxView;
@property(nonatomic, assign) BOOL hasCompletedInitialLoad;
@property(nonatomic, strong) UIView *statusBackgroundView;
@property(nonatomic, strong) UIView *navigationBarView;
@property(nonatomic, strong) UIButton *navigationBackButton;
@property(nonatomic, strong) UIButton *navigationReloadButton;
@property(nonatomic, strong) UILabel *navigationTitleLabel;
@property(nonatomic, strong) UIView *loadFailureView;
@property(nonatomic, strong) UILabel *loadFailureTitleLabel;
@property(nonatomic, strong) UILabel *loadFailureMessageLabel;
@property(nonatomic, strong) UILabel *loadFailureMetadataLabel;

@end

@implementation LynxViewShellViewController

- (id)init {
  if (self = [super init]) {
    self.hiddenNav = NO;
    self.fullScreen = NO;
    self.backButtonImageName = kBackButtonImageLight;
    self.navTitle = @"";
    self.titleColor = [UIColor blackColor];
    self.barColor = [UIColor whiteColor];
    self.frontendTheme = kBackButtonStyleLight;
    self.hasCompletedInitialLoad = NO;
  }

  return self;
}

- (void)dealloc {
  if (self.lynxView != nil) {
    [self.lynxView removeLifecycleClient:self];
  }
}

- (void)viewDidLoad {
  [super viewDidLoad];
  extraTiming = [[LynxExtraTiming alloc] init];
  extraTiming.openTime = [[NSDate date] timeIntervalSince1970] * 1000;
  // Do any additional setup after loading the view.
  extraTiming.containerInitStart = [[NSDate date] timeIntervalSince1970] * 1000;
  [self parseParameters];
  [self initNavigation];
  extraTiming.containerInitEnd = [[NSDate date] timeIntervalSince1970] * 1000;
  extraTiming.prepareTemplateStart = [[NSDate date] timeIntervalSince1970] * 1000;
  extraTiming.prepareTemplateEnd = [[NSDate date] timeIntervalSince1970] * 1000;
  [self setupLoadFailureView];
  [self loadLynxViewWithUrl:self.url templateData:self.data];
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  [self.navigationController setNavigationBarHidden:YES animated:NO];
}

- (LynxTemplateData *)getGlobalPropsFromParams {
  NSMutableDictionary *params = [NSMutableDictionary dictionary];
  for (NSString *key in self.params) {
    id value = self.params[key];

    // 1. remove redundant '_'
    NSUInteger leadingUnderline = 0;
    while (leadingUnderline < key.length && [key characterAtIndex:leadingUnderline] == '_') {
      leadingUnderline++;
    }
    NSString *trimmedKey = [key substringFromIndex:leadingUnderline];
    if (trimmedKey.length == 0) {
      [params setObject:value forKey:key];
      continue;
    }

    // 2. split by underscores and convert to camel case
    NSArray<NSString *> *parts = [trimmedKey componentsSeparatedByString:@"_"];
    NSMutableString *propsKey = [NSMutableString stringWithString:parts[0]];

    for (NSUInteger i = 1; i < parts.count; i++) {
      NSString *part = parts[i];
      if (part.length == 0) {
        continue;
      }
      NSString *capitalizedPart =
          [part stringByReplacingCharactersInRange:NSMakeRange(0, 1)
                                        withString:[part substringToIndex:1].uppercaseString];
      [propsKey appendString:capitalizedPart];
    }
    [params setObject:value forKey:propsKey];
  }

  LynxTemplateData *globalProps = [[LynxTemplateData alloc] initWithDictionary:params];
  return globalProps;
}

- (void)loadLynxViewWithUrl:(NSString *)url templateData:(NSData *)data {
  self.hasCompletedInitialLoad = NO;
  [self hideLoadFailureView];
  CGRect screenFrame = self.view.frame;
  CGRect statusRect = [[UIApplication sharedApplication] statusBarFrame];
  CGRect navRect = self.navigationController.navigationBar.frame;

  // Specify LynxView width and height according to the query parameters.
  CGSize screenSize = CGSizeZero;
  if ([[_params allKeys] containsObject:@"height"] && [[_params allKeys] containsObject:@"width"]) {
    NSNumber *width = [_params objectForKey:@"width"];    // Physical pixel
    NSNumber *height = [_params objectForKey:@"height"];  // Physical pixel
    CGFloat realScale = [[UIScreen mainScreen] scale];
    screenSize = CGSizeMake([width intValue] / realScale, [height intValue] / realScale);
  } else {
    screenSize = screenFrame.size;
  }
  LynxThreadStrategyForRender threadStrategy =
      [LynxSettingManager sharedDataHandler].threadStrategy;

  LynxView *lynxView = [[LynxView alloc] initWithBuilderBlock:^(LynxViewBuilder *builder) {
    builder.config =
        [[LynxConfig alloc] initWithProvider:[LynxEnv sharedInstance].config.templateProvider];
    builder.screenSize = screenSize;
    builder.fontScale = 1.0;
    builder.fetcher = nil;
    // for homepage only
    [builder.config registerUI:LynxExplorerInput.class withName:@"explorer-input"];
    // Add fetchers
    builder.enableGenericResourceFetcher = true;
    builder.genericResourceFetcher = [[DemoGenericResourceFetcher alloc] init];
    builder.templateResourceFetcher = [[DemoTemplateResourceFetcher alloc] init];
    builder.mediaResourceFetcher = [[DemoMediaResourceFetcher alloc] init];
    [builder setThreadStrategyForRender:threadStrategy];
  }];
  self.lynxView = lynxView;
  [lynxView addLifecycleClient:self];
  lynxView.preferredLayoutWidth = screenSize.width;
  [lynxView setExtraTiming:extraTiming];

  if (self.fullScreen) {
    lynxView.preferredLayoutHeight = screenSize.height;
  } else if (self.hiddenNav) {
    lynxView.preferredLayoutHeight = screenSize.height - statusRect.size.height;
  } else {
    lynxView.preferredLayoutHeight =
        screenSize.height - statusRect.size.height - navRect.size.height;
  }
  lynxView.layoutWidthMode = LynxViewSizeModeExact;
  lynxView.layoutHeightMode = LynxViewSizeModeExact;
  [self.view addSubview:lynxView];

  CGRect screenRect = [[UIScreen mainScreen] bounds];
  CGFloat screenWidth = screenRect.size.width;
  CGFloat screenHeight = screenRect.size.height;
  UIEdgeInsets safeAreaInsets = [self currentSafeAreaInsets];
  LynxTemplateData *globalProps = [self getGlobalPropsFromParams];
  [globalProps updateBool:[self isNotchScreen] forKey:@"isNotchScreen"];
  [globalProps updateDouble:screenHeight forKey:@"screenHeight"];
  [globalProps updateDouble:screenWidth forKey:@"screenWidth"];
  [globalProps updateDouble:safeAreaInsets.top forKey:@"safeAreaTop"];
  [globalProps updateDouble:safeAreaInsets.bottom forKey:@"safeAreaBottom"];
  NSString *theme = @"Light";
  if ([UIScreen mainScreen].traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
    theme = @"Dark";
  }
  [globalProps updateObject:theme forKey:@"theme"];
  [globalProps updateObject:self.frontendTheme forKey:@"frontendTheme"];

  // Add the preferred theme from user defaults
  NSString *preferredTheme = [self getStorageItem:@"preferredTheme"];
  if (preferredTheme) {
    [globalProps updateObject:preferredTheme forKey:@"preferredTheme"];
  }

  [lynxView updateGlobalPropsWithTemplateData:globalProps];

  LynxTemplateData *initData =
      [[LynxTemplateData alloc] initWithDictionary:@{@"mockData" : @"Hello Lynx Explorer"}];
  if (self.data) {
    [lynxView loadTemplate:data withURL:url initData:initData];
  } else {
    [lynxView loadTemplateFromURL:url initData:initData];
  }
  [lynxView triggerLayout];

  CGRect lynxViewFrame;
  if (self.fullScreen) {
    lynxViewFrame =
        CGRectMake(0, 0, lynxView.intrinsicContentSize.width, lynxView.intrinsicContentSize.height);
  } else if (self.hiddenNav) {
    lynxViewFrame = CGRectMake(0, statusRect.size.height, lynxView.intrinsicContentSize.width,
                               lynxView.intrinsicContentSize.height);
  } else {
    lynxViewFrame =
        CGRectMake(0, statusRect.size.height + navRect.size.height,
                   lynxView.intrinsicContentSize.width, lynxView.intrinsicContentSize.height);
  }
  lynxView.frame = lynxViewFrame;
  self.loadFailureView.frame = [self contentFrameForCurrentPage];
}

- (void)parseParameters {
  NSArray *paramKeys = [self.params allKeys];
  if ([paramKeys containsObject:kParamHiddenNav]) {
    self.hiddenNav = [[self.params objectForKey:kParamHiddenNav] boolValue];
  }
  if ([paramKeys containsObject:kParamFullScreen]) {
    self.fullScreen = [[self.params objectForKey:kParamFullScreen] boolValue];
  }
  if ([paramKeys containsObject:kParamTitle]) {
    id title = [self.params objectForKey:kParamTitle];
    if ([title isKindOfClass:[NSString class]]) {
      self.navTitle = [title stringByRemovingPercentEncoding];
    }
  }
  if ([paramKeys containsObject:kParamTitleColor]) {
    id titleColor = [self.params objectForKey:kParamTitleColor];
    if ([titleColor isKindOfClass:[NSString class]]) {
      self.titleColor = [UIHelper colorWithHexString:titleColor];
    }
  }
  if ([paramKeys containsObject:kParamBarColor]) {
    id barColor = [self.params objectForKey:kParamBarColor];
    if ([barColor isKindOfClass:[NSString class]]) {
      self.barColor = [UIHelper colorWithHexString:barColor];
    }
  }
  if ([paramKeys containsObject:kParamBackButtonStyle]) {
    id style = [self.params objectForKey:kParamBackButtonStyle];
    if ([style isKindOfClass:[NSString class]] && [style isEqualToString:kBackButtonStyleDark]) {
      self.backButtonImageName = kBackButtonImageDark;
      self.frontendTheme = kBackButtonStyleDark;
    }
  }

  if (self.fullScreen) {
    // fullScreen forces hiddenNav
    self.hiddenNav = YES;
  }
}

- (void)initNavigation {
  [self.navigationController setNavigationBarHidden:YES animated:NO];
  UIScreenEdgePanGestureRecognizer *edgePanGesture =
      [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self
                                                        action:@selector(handleEdgePanGesture:)];
  edgePanGesture.edges = UIRectEdgeLeft;
  self.view.backgroundColor = self.barColor;
  [self.view addGestureRecognizer:edgePanGesture];
  if (self.fullScreen) {
    return;
  }

  CGSize screenSize = [UIScreen mainScreen].bounds.size;
  CGFloat statusH = [UIApplication sharedApplication].statusBarFrame.size.height;
  CGFloat navH = self.navigationController.navigationBar.frame.size.height;
  // create status view
  UIView *statusView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, screenSize.width, statusH)];
  statusView.backgroundColor = self.barColor;
  [self.view addSubview:statusView];
  self.statusBackgroundView = statusView;

  if (self.hiddenNav) {
    return;
  }
  // create custom navigation bar
  UIView *barView = [[UIView alloc] initWithFrame:CGRectMake(0, statusH, screenSize.width, navH)];
  barView.backgroundColor = self.barColor;
  CGFloat actionWidth = 64;

  UIButton *goBackButton = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, actionWidth, navH)];
  UIImage *backImage = [self scaleImage:[UIImage imageNamed:self.backButtonImageName]
                                   size:CGSizeMake(24, 24)];
  [goBackButton setImage:backImage forState:UIControlStateNormal];
  [goBackButton addTarget:self
                   action:@selector(backButtonTapped)
         forControlEvents:UIControlEventTouchUpInside];
  UILabel *titleLabel =
      [[UILabel alloc] initWithFrame:CGRectMake(actionWidth, 0,
                                                screenSize.width - 2 * actionWidth, navH)];
  titleLabel.text = self.navTitle;
  titleLabel.textColor = self.titleColor;
  titleLabel.textAlignment = NSTextAlignmentCenter;

  UIButton *reloadButton =
      [[UIButton alloc] initWithFrame:CGRectMake(screenSize.width - actionWidth, 0, actionWidth,
                                                 navH)];
  [reloadButton setTitle:@"Reload" forState:UIControlStateNormal];
  [reloadButton setTitleColor:self.titleColor forState:UIControlStateNormal];
  reloadButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
  [reloadButton addTarget:self
                   action:@selector(reloadButtonTapped)
         forControlEvents:UIControlEventTouchUpInside];

  [barView addSubview:goBackButton];
  [barView addSubview:titleLabel];
  [barView addSubview:reloadButton];
  [self.view addSubview:barView];

  self.navigationBarView = barView;
  self.navigationBackButton = goBackButton;
  self.navigationReloadButton = reloadButton;
  self.navigationTitleLabel = titleLabel;
  [self updateNavigationAppearanceForFailureState:NO];
}

- (BOOL)shouldAutorotate {
  return NO;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
  if ([self.params.allKeys containsObject:@"orientation"]) {
    NSString *orientation = self.params[@"orientation"];
    if ([orientation isEqualToString:@"portrait"]) {
      return UIInterfaceOrientationMaskPortrait;
    } else if ([orientation isEqualToString:@"landscape"]) {
      return UIInterfaceOrientationMaskLandscape;
    }
  }
  return UIInterfaceOrientationMaskAllButUpsideDown;
}

- (void)viewWillLayoutSubviews {
  [super viewWillLayoutSubviews];
  [self setNavigationStatus];
  self.loadFailureView.frame = [self contentFrameForCurrentPage];
}

- (void)setNavigationStatus {
  [self.navigationController setNavigationBarHidden:YES animated:NO];
}

- (void)handleEdgePanGesture:(UIScreenEdgePanGestureRecognizer *)gesture {
  UIGestureRecognizerState state = gesture.state;
  CGPoint translation = [gesture translationInView:self.view];
  CGFloat progress = translation.x / self.view.bounds.size.width;
  progress = fminf(fmaxf(progress, 0.0), 1.0);

  switch (state) {
    case UIGestureRecognizerStateBegan:
      if (self.navigationController.viewControllers.count > 1) {
        UIViewController *previousVC = [self.navigationController.viewControllers
            objectAtIndex:self.navigationController.viewControllers.count - 2];
        self.previousViewControllerView = previousVC.view;
        [self.view.superview insertSubview:self.previousViewControllerView belowSubview:self.view];
        self.previousViewControllerView.frame = CGRectMake(0, 0, 0, self.view.bounds.size.height);
      }
      break;
    case UIGestureRecognizerStateChanged: {
      if (self.previousViewControllerView && translation.x >= 0) {
        CGRect previousFrame = self.previousViewControllerView.frame;
        previousFrame.size.width = self.view.bounds.size.width * progress;
        self.previousViewControllerView.frame = previousFrame;

        CGRect currentFrame = self.view.frame;
        currentFrame.origin.x = translation.x;
        self.view.frame = currentFrame;
      }
      break;
    }
    case UIGestureRecognizerStateEnded: {
      if (self.previousViewControllerView) {
        // get velocity of gesture
        CGPoint velocity = [gesture velocityInView:self.view];
        CGFloat flingVelocity = 1000;

        if (velocity.x >= flingVelocity || progress > 0.5) {
          [UIView animateWithDuration:0.15
              animations:^{
                CGRect previousFrame = self.previousViewControllerView.frame;
                previousFrame.size.width = self.view.bounds.size.width;
                self.previousViewControllerView.frame = previousFrame;

                CGRect currentFrame = self.view.frame;
                currentFrame.origin.x = self.view.bounds.size.width;
                self.view.frame = currentFrame;
              }
              completion:^(BOOL finished) {
                [self.navigationController popViewControllerAnimated:NO];
              }];
        } else {
          [UIView animateWithDuration:0.15
              animations:^{
                CGRect previousFrame = self.previousViewControllerView.frame;
                previousFrame.size.width = 0;
                self.previousViewControllerView.frame = previousFrame;

                CGRect currentFrame = self.view.frame;
                currentFrame.origin.x = 0;
                self.view.frame = currentFrame;
              }
              completion:^(BOOL finished) {
                [self.previousViewControllerView removeFromSuperview];
                self.previousViewControllerView = nil;
              }];
        }
      }
      break;
    }
    default:
      break;
  }
}

- (void)backButtonTapped {
  [self.navigationController popViewControllerAnimated:YES];
}

- (void)reloadButtonTapped {
  [self reloadCurrentPage];
}

- (void)reloadCurrentPage {
  if (self.lynxView != nil) {
    [self.lynxView removeLifecycleClient:self];
  }
  [self.lynxView removeFromSuperview];
  self.lynxView = nil;
  extraTiming = [[LynxExtraTiming alloc] init];
  extraTiming.openTime = [[NSDate date] timeIntervalSince1970] * 1000;
  extraTiming.containerInitStart = extraTiming.openTime;
  extraTiming.containerInitEnd = extraTiming.openTime;
  extraTiming.prepareTemplateStart = extraTiming.openTime;
  extraTiming.prepareTemplateEnd = extraTiming.openTime;
  [self loadLynxViewWithUrl:self.url templateData:self.data];
}

- (UIColor *)failureBackgroundColor {
  return [self shouldUseDarkFailureAppearance] ? [UIColor colorWithWhite:0.0 alpha:1.0]
                                               : UIColor.whiteColor;
}

- (UIColor *)failurePanelColor {
  return [self shouldUseDarkFailureAppearance] ? [UIColor colorWithWhite:0.12 alpha:1.0]
                                               : [UIColor colorWithWhite:0.96 alpha:1.0];
}

- (UIColor *)failureInlinePanelColor {
  return [self shouldUseDarkFailureAppearance] ? [UIColor colorWithWhite:0.18 alpha:1.0]
                                               : [UIColor colorWithWhite:0.93 alpha:1.0];
}

- (UIColor *)failurePrimaryTextColor {
  return [self shouldUseDarkFailureAppearance] ? UIColor.whiteColor : UIColor.blackColor;
}

- (UIColor *)failureSecondaryTextColor {
  return [self shouldUseDarkFailureAppearance] ? [UIColor colorWithWhite:0.82 alpha:1.0]
                                               : [UIColor colorWithWhite:0.25 alpha:1.0];
}

- (UIColor *)failureTertiaryTextColor {
  return [self shouldUseDarkFailureAppearance] ? [UIColor colorWithWhite:0.62 alpha:1.0]
                                               : [UIColor colorWithWhite:0.45 alpha:1.0];
}

- (UIColor *)failureAccentColor {
  return [UIColor colorWithRed:1.0 green:0.231 blue:0.188 alpha:1.0];
}

- (BOOL)shouldUseDarkFailureAppearance {
  NSString *preferredTheme = [self getStorageItem:@"preferredTheme"];
  if ([preferredTheme isEqualToString:@"Dark"]) {
    return YES;
  }
  if ([preferredTheme isEqualToString:@"Light"]) {
    return NO;
  }
  if ([self.frontendTheme isEqualToString:kBackButtonStyleDark]) {
    return YES;
  }
  if ([self.frontendTheme isEqualToString:kBackButtonStyleLight]) {
    return NO;
  }
  if (@available(iOS 13.0, *)) {
    return self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
  }
  return NO;
}

- (void)updateNavigationAppearanceForFailureState:(BOOL)isFailureVisible {
  UIColor *backgroundColor = isFailureVisible ? [self failureBackgroundColor] : self.barColor;
  UIColor *foregroundColor = isFailureVisible ? [self failurePrimaryTextColor] : self.titleColor;
  NSString *backImageName = isFailureVisible
                                ? ([self shouldUseDarkFailureAppearance] ? kBackButtonImageDark
                                                                         : kBackButtonImageLight)
                                : self.backButtonImageName;

  self.view.backgroundColor = backgroundColor;
  self.statusBackgroundView.backgroundColor = backgroundColor;
  self.navigationBarView.backgroundColor = backgroundColor;
  self.navigationTitleLabel.textColor = foregroundColor;
  [self.navigationReloadButton setTitleColor:foregroundColor forState:UIControlStateNormal];
  UIImage *backImage = [self scaleImage:[UIImage imageNamed:backImageName] size:CGSizeMake(24, 24)];
  [self.navigationBackButton setImage:backImage forState:UIControlStateNormal];
}

- (CGRect)contentFrameForCurrentPage {
  CGRect bounds = self.view.bounds;
  if (self.fullScreen) {
    return bounds;
  }

  CGFloat topInset = [UIApplication sharedApplication].statusBarFrame.size.height;
  if (!self.hiddenNav) {
    topInset += self.navigationController.navigationBar.frame.size.height;
  }

  return CGRectMake(0, topInset, CGRectGetWidth(bounds), MAX(CGRectGetHeight(bounds) - topInset, 0));
}

- (void)setupLoadFailureView {
  if (self.loadFailureView != nil) {
    return;
  }

  UIView *failureView = [[UIView alloc] initWithFrame:CGRectZero];
  failureView.hidden = YES;
  failureView.backgroundColor = [self failureBackgroundColor];
  failureView.userInteractionEnabled = YES;

  UIColor *surfaceColor = [self failurePanelColor];
  UIColor *inlinePanelColor = [self failureInlinePanelColor];
  UIColor *primaryTextColor = [self failurePrimaryTextColor];
  UIColor *subtleTextColor = [self failureSecondaryTextColor];
  UIColor *secondaryTextColor = [self failureTertiaryTextColor];
  UIColor *accentColor = [self failureAccentColor];

  UIView *panelView = [[UIView alloc] initWithFrame:CGRectZero];
  panelView.translatesAutoresizingMaskIntoConstraints = NO;
  panelView.backgroundColor = surfaceColor;
  panelView.layer.cornerRadius = 28;

  UIView *badgeView = [[UIView alloc] initWithFrame:CGRectZero];
  badgeView.translatesAutoresizingMaskIntoConstraints = NO;
  badgeView.backgroundColor = [accentColor colorWithAlphaComponent:0.14];
  badgeView.layer.cornerRadius = 28;

  UILabel *badgeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
  badgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
  badgeLabel.text = @"!";
  badgeLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightSemibold];
  badgeLabel.textAlignment = NSTextAlignmentCenter;
  badgeLabel.textColor = accentColor;

  UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
  titleLabel.text = @"Couldn't load bundle";
  titleLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightSemibold];
  titleLabel.textAlignment = NSTextAlignmentCenter;
  titleLabel.textColor = primaryTextColor;
  titleLabel.numberOfLines = 0;

  UILabel *messageLabel = [[UILabel alloc] initWithFrame:CGRectZero];
  messageLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
  messageLabel.textAlignment = NSTextAlignmentCenter;
  messageLabel.textColor = subtleTextColor;
  messageLabel.numberOfLines = 0;

  UILabel *metadataLabel = [[UILabel alloc] initWithFrame:CGRectZero];
  metadataLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
  metadataLabel.textAlignment = NSTextAlignmentCenter;
  metadataLabel.textColor = secondaryTextColor;
  metadataLabel.numberOfLines = 0;

  UIButton *retryButton = [UIButton buttonWithType:UIButtonTypeSystem];
  [retryButton setTitle:@"Retry" forState:UIControlStateNormal];
  retryButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
  [retryButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
  retryButton.backgroundColor = accentColor;
  retryButton.layer.cornerRadius = 14;
  [retryButton addTarget:self action:@selector(reloadButtonTapped) forControlEvents:UIControlEventTouchUpInside];

  UIButton *backButton = [UIButton buttonWithType:UIButtonTypeSystem];
  [backButton setTitle:@"Back" forState:UIControlStateNormal];
  backButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
  [backButton setTitleColor:primaryTextColor forState:UIControlStateNormal];
  backButton.backgroundColor = inlinePanelColor;
  backButton.layer.cornerRadius = 14;
  [backButton addTarget:self action:@selector(backButtonTapped) forControlEvents:UIControlEventTouchUpInside];

  UIStackView *buttonStack = [[UIStackView alloc] initWithArrangedSubviews:@[ backButton, retryButton ]];
  buttonStack.axis = UILayoutConstraintAxisHorizontal;
  buttonStack.alignment = UIStackViewAlignmentFill;
  buttonStack.distribution = UIStackViewDistributionFillEqually;
  buttonStack.spacing = 14;

  UIStackView *contentStack =
      [[UIStackView alloc]
          initWithArrangedSubviews:@[
            badgeView, titleLabel, messageLabel, metadataLabel, buttonStack
          ]];
  contentStack.axis = UILayoutConstraintAxisVertical;
  contentStack.alignment = UIStackViewAlignmentFill;
  contentStack.spacing = 18;
  contentStack.translatesAutoresizingMaskIntoConstraints = NO;

  [badgeView addSubview:badgeLabel];
  [panelView addSubview:contentStack];
  [failureView addSubview:panelView];
  [self.view addSubview:failureView];

  [NSLayoutConstraint activateConstraints:@[
    [panelView.centerYAnchor constraintEqualToAnchor:failureView.centerYAnchor],
    [panelView.leadingAnchor constraintEqualToAnchor:failureView.leadingAnchor constant:20],
    [panelView.trailingAnchor constraintEqualToAnchor:failureView.trailingAnchor constant:-20],
    [panelView.topAnchor constraintGreaterThanOrEqualToAnchor:failureView.topAnchor constant:24],
    [panelView.bottomAnchor constraintLessThanOrEqualToAnchor:failureView.bottomAnchor constant:-24],
    [contentStack.topAnchor constraintEqualToAnchor:panelView.topAnchor constant:28],
    [contentStack.leadingAnchor constraintEqualToAnchor:panelView.leadingAnchor constant:22],
    [contentStack.trailingAnchor constraintEqualToAnchor:panelView.trailingAnchor constant:-22],
    [contentStack.bottomAnchor constraintEqualToAnchor:panelView.bottomAnchor constant:-22],
    [badgeView.heightAnchor constraintEqualToConstant:56],
    [badgeView.widthAnchor constraintEqualToConstant:56],
    [badgeView.centerXAnchor constraintEqualToAnchor:contentStack.centerXAnchor],
    [badgeLabel.centerXAnchor constraintEqualToAnchor:badgeView.centerXAnchor],
    [badgeLabel.centerYAnchor constraintEqualToAnchor:badgeView.centerYAnchor],
    [retryButton.heightAnchor constraintEqualToConstant:50],
    [backButton.heightAnchor constraintEqualToConstant:50],
  ]];

  self.loadFailureView = failureView;
  self.loadFailureTitleLabel = titleLabel;
  self.loadFailureMessageLabel = messageLabel;
  self.loadFailureMetadataLabel = metadataLabel;
}

- (NSString *)primaryFailureMessageForError:(NSError *)error {
  if ([error isKindOfClass:[LynxError class]]) {
    LynxError *lynxError = (LynxError *)error;
    if (lynxError.summaryMessage.length > 0) {
      return lynxError.summaryMessage;
    }
    if (lynxError.rootCause.length > 0) {
      return lynxError.rootCause;
    }
  }
  NSString *message = error.localizedDescription ?: @"The page could not be loaded.";
  NSString *lowercaseMessage = message.lowercaseString;
  if ([lowercaseMessage containsString:@"timed out"] ||
      [lowercaseMessage containsString:@"offline"] ||
      [lowercaseMessage containsString:@"could not connect"] ||
      [lowercaseMessage containsString:@"network"]) {
    return @"The bundle server is unavailable. Check that the URL is reachable from this device and try again.";
  }
  if ([lowercaseMessage containsString:@"decode"] || [lowercaseMessage containsString:@"template"] ||
      [lowercaseMessage containsString:@"bundle"]) {
    return @"The URL responded, but the content could not be loaded as a Lynx bundle.";
  }
  return message;
}

- (NSString *)failureMetadataTextForError:(NSError *)error {
  if ([error isKindOfClass:[LynxError class]]) {
    LynxError *lynxError = (LynxError *)error;
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    [parts addObject:[NSString stringWithFormat:@"Lynx Error %ld", (long)lynxError.errorCode]];
    NSInteger subCode = [lynxError getSubCode];
    if (subCode > 0) {
      [parts addObject:[NSString stringWithFormat:@"Subcode %ld", (long)subCode]];
    }
    if (lynxError.level.length > 0) {
      [parts addObject:lynxError.level.uppercaseString];
    }
    return [parts componentsJoinedByString:@"  ·  "];
  }

  return [NSString stringWithFormat:@"%@  ·  %ld", error.domain ?: @"Error", (long)error.code];
}

- (void)performUIUpdateOnMainThread:(dispatch_block_t)block {
  if (block == nil) {
    return;
  }
  if ([NSThread isMainThread]) {
    block();
  } else {
    dispatch_async(dispatch_get_main_queue(), block);
  }
}

- (void)showLoadFailureViewWithError:(NSError *)error {
  __weak typeof(self) weakSelf = self;
  [self performUIUpdateOnMainThread:^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) {
      return;
    }
    strongSelf.loadFailureTitleLabel.text = @"Couldn't load bundle";
    strongSelf.loadFailureMessageLabel.text = [strongSelf primaryFailureMessageForError:error];
    strongSelf.loadFailureMetadataLabel.text = [strongSelf failureMetadataTextForError:error];
    strongSelf.loadFailureView.hidden = NO;
    strongSelf.loadFailureView.frame = [strongSelf contentFrameForCurrentPage];
    [strongSelf.view bringSubviewToFront:strongSelf.loadFailureView];
    strongSelf.lynxView.hidden = YES;
    [strongSelf updateNavigationAppearanceForFailureState:YES];
  }];
}

- (void)hideLoadFailureView {
  __weak typeof(self) weakSelf = self;
  [self performUIUpdateOnMainThread:^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) {
      return;
    }
    strongSelf.loadFailureView.hidden = YES;
    strongSelf.loadFailureMessageLabel.text = @"";
    strongSelf.loadFailureMetadataLabel.text = @"";
    strongSelf.lynxView.hidden = NO;
    [strongSelf updateNavigationAppearanceForFailureState:NO];
  }];
}

#pragma mark - LynxViewLifecycle

- (void)lynxViewDidStartLoading:(LynxView *)view {
  __weak typeof(self) weakSelf = self;
  [self performUIUpdateOnMainThread:^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf || view != strongSelf.lynxView) {
      return;
    }
    strongSelf.hasCompletedInitialLoad = NO;
    [strongSelf hideLoadFailureView];
  }];
}

- (void)lynxView:(LynxView *)view didLoadFinishedWithUrl:(NSString *)url {
  __weak typeof(self) weakSelf = self;
  [self performUIUpdateOnMainThread:^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf || view != strongSelf.lynxView) {
      return;
    }
    strongSelf.hasCompletedInitialLoad = YES;
    [strongSelf hideLoadFailureView];
  }];
}

- (void)lynxView:(LynxView *)view didRecieveError:(NSError *)error {
  __weak typeof(self) weakSelf = self;
  [self performUIUpdateOnMainThread:^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf || view != strongSelf.lynxView || strongSelf.hasCompletedInitialLoad) {
      return;
    }
    [strongSelf showLoadFailureViewWithError:error];
  }];
}

- (UIImage *)scaleImage:(UIImage *)image size:(CGSize)size {
  UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
  [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
  UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
  UIGraphicsEndImageContext();
  return newImage;
}

- (BOOL)isNotchScreen {
  if (@available(iOS 11.0, *)) {
    UIEdgeInsets safeAreaInsets = [self currentSafeAreaInsets];
    return safeAreaInsets.top > 20;
  }

  return NO;
}

- (UIEdgeInsets)currentSafeAreaInsets {
  if (@available(iOS 11.0, *)) {
    UIWindow *window = UIApplication.sharedApplication.keyWindow;
    if (window == nil && UIApplication.sharedApplication.windows.count > 0) {
      window = UIApplication.sharedApplication.windows.firstObject;
    }
    if (window != nil) {
      return window.safeAreaInsets;
    }
  }
  return UIEdgeInsetsZero;
}

- (NSString *)getStorageItem:(NSString *)key {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  return [defaults objectForKey:key];
}

@end
