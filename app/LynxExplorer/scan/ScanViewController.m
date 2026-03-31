// Copyright 2024 The Lynx Authors. All rights reserved.
// Licensed under the Apache License Version 2.0 that can be found in the
// LICENSE file in the root directory of this source tree.

#import "ScanViewController.h"
#import "TasmDispatcher.h"

@interface ScanViewController ()

@property(nonatomic, strong) AVCaptureSession *captureSession;
@property(nonatomic, strong) AVCaptureVideoPreviewLayer *captureLayer;
@property(nonatomic, strong) UIView *sanFrameView;
@property(nonatomic, strong) UILabel *simulatorHintLabel;
@property(nonatomic, strong) UIView *topBarView;
@property(nonatomic, strong) UIButton *backButton;
@property(nonatomic, strong) UILabel *titleLabel;

@end

@implementation ScanViewController

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = [UIColor blackColor];
  self.edgesForExtendedLayout = UIRectEdgeAll;
  [self setupTopBar];

  [self prepareForScan];
}

- (void)setupTopBar {
  self.topBarView = [[UIView alloc] initWithFrame:CGRectZero];
  self.topBarView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.96];
  [self.view addSubview:self.topBarView];

  self.backButton = [UIButton buttonWithType:UIButtonTypeSystem];
  UIImage *backImage = [UIImage imageNamed:@"back_light"];
  [self.backButton setImage:backImage forState:UIControlStateNormal];
  self.backButton.tintColor = [UIColor whiteColor];
  [self.backButton addTarget:self
                      action:@selector(backButtonTapped)
            forControlEvents:UIControlEventTouchUpInside];
  [self.topBarView addSubview:self.backButton];

  self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
  self.titleLabel.text = @"Scan";
  self.titleLabel.textAlignment = NSTextAlignmentCenter;
  self.titleLabel.textColor = [UIColor whiteColor];
  self.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
  [self.topBarView addSubview:self.titleLabel];
}

- (void)prepareForScan {
#if !(TARGET_IPHONE_SIMULATOR)
  _captureSession = [[AVCaptureSession alloc] init];
  [_captureSession setSessionPreset:AVCaptureSessionPresetHigh];
  AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
  AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:nil];
  AVCaptureMetadataOutput *output = [[AVCaptureMetadataOutput alloc] init];
  if (output && input && device) {
    [output setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
    [_captureSession addInput:input];
    [_captureSession addOutput:output];
    output.metadataObjectTypes = @[
      AVMetadataObjectTypeQRCode, AVMetadataObjectTypeEAN13Code, AVMetadataObjectTypeEAN8Code,
      AVMetadataObjectTypeCode128Code
    ];
  }

  _captureLayer = [AVCaptureVideoPreviewLayer layerWithSession:_captureSession];
  _captureLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
  _captureLayer.frame = self.view.bounds;
#else
  self.view.backgroundColor = [UIColor systemBackgroundColor];
  self.simulatorHintLabel = [[UILabel alloc] initWithFrame:CGRectZero];
  self.simulatorHintLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.simulatorHintLabel.text =
      @"QR scanning is unavailable in iOS Simulator.\nUse a real device or paste the URL.";
  self.simulatorHintLabel.textAlignment = NSTextAlignmentCenter;
  self.simulatorHintLabel.numberOfLines = 0;
  self.simulatorHintLabel.textColor = [UIColor secondaryLabelColor];
  [self.view addSubview:self.simulatorHintLabel];

  [NSLayoutConstraint activateConstraints:@[
    [self.simulatorHintLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
    [self.simulatorHintLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    [self.simulatorHintLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor
                                                                        constant:24],
    [self.simulatorHintLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor
                                                                      constant:-24],
  ]];
#endif
}

- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  CGFloat topInset = 0;
  if (@available(iOS 11.0, *)) {
    topInset = self.view.safeAreaInsets.top;
  }
  CGFloat barHeight = 44;
  CGFloat topBarHeight = topInset + barHeight;
  CGFloat width = CGRectGetWidth(self.view.bounds);
  CGFloat height = CGRectGetHeight(self.view.bounds);

  self.topBarView.frame = CGRectMake(0, 0, width, topBarHeight);
  self.backButton.frame = CGRectMake(8, topInset + 6, 44, 32);
  self.titleLabel.frame = CGRectMake(60, topInset, width - 120, barHeight);
  self.captureLayer.frame = CGRectMake(0, topBarHeight, width, MAX(height - topBarHeight, 0));
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  [self.navigationController setNavigationBarHidden:YES animated:NO];
  if (self.captureLayer && self.captureLayer.superlayer == nil) {
    [self.view.layer insertSublayer:self.captureLayer atIndex:0];
  }
  [self.captureSession startRunning];
}

- (void)viewDidDisappear:(BOOL)animated {
  [super viewDidDisappear:animated];

  [self.captureLayer removeFromSuperlayer];
  [self.captureSession stopRunning];
}

- (void)backButtonTapped {
  [self.navigationController popViewControllerAnimated:YES];
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput
    didOutputMetadataObjects:(NSArray *)metadataObjects
              fromConnection:(AVCaptureConnection *)connection {
  [_captureLayer removeFromSuperlayer];
  [_captureSession stopRunning];
  if (metadataObjects.count > 0) {
    AVMetadataMachineReadableCodeObject *metadataObject = [metadataObjects objectAtIndex:0];
    NSString *result = metadataObject.stringValue;
    [self pushLynxViewShellVCWithUrl:result];
  }
}

- (void)pushLynxViewShellVCWithUrl:(NSString *)url {
  [[TasmDispatcher sharedInstance] openTargetUrl:url];
}

@end
