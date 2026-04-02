// Copyright 2024 The Lynx Authors. All rights reserved.
// Licensed under the Apache License Version 2.0 that can be found in the
// LICENSE file in the root directory of this source tree.

#import "TasmDispatcher.h"
#import <LynxDevtool/LynxRecorderViewController.h>
#import "AppDelegate.h"
#import "DemoTemplateResourceFetcher.h"
#import "LynxRecorderDefaultActionCallback.h"
#import "LynxViewShellViewController.h"

@implementation TasmDispatcher {
  NSString *_latestQuery;
  NSMutableDictionary *_latestParams;
}

static TasmDispatcher *_instance = nil;
static NSMapTable<NSString *, __kindof UIViewController *> *_dispatchedViewControllers = nil;
static NSString *const kRecentSchemasStorageKey = @"recentSchemas";
static NSUInteger const kMaxRecentSchemasCount = 50;

+ (instancetype)sharedInstance {
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    _instance = [[self alloc] init];
    _dispatchedViewControllers = [NSMapTable weakToWeakObjectsMapTable];
  });
  return _instance;
}

- (void)generateLatestParams {
  if (_latestQuery == nil) {
    _latestParams = nil;
    return;
  }
  _latestParams = [[NSMutableDictionary alloc] init];
  for (NSString *param in [_latestQuery componentsSeparatedByString:@"&"]) {
    NSArray *elts = [param componentsSeparatedByString:@"="];
    if ([elts count] < 2) continue;
    [_latestParams setObject:[elts lastObject] forKey:[elts firstObject]];
  }
}

- (void)openTargetUrlSingleTop:(NSString *)sourceUrl {
  UINavigationController *vc =
      ((AppDelegate *)([UIApplication sharedApplication].delegate)).navigationController;
  [vc popViewControllerAnimated:NO];
  [self openTargetUrl:sourceUrl];
}

// sourceUrl: file://lynx?local://homepage.lynx.bundle
// processedUrl: local://homepage.lynx.bundle
- (void)openTargetUrl:(NSString *)sourceUrl {
  NSData *data = nil;
  NSString *url = nil;

  LocalBundleResult localRes = [DemoTemplateResourceFetcher readLocalBundleFromResource:sourceUrl];
  if (localRes.isLocalScheme) {
    data = localRes.data;
    url = localRes.url;
    _latestQuery = localRes.query;
  } else if (localRes.isLynxRecorderSchema) {
    url = localRes.url;
  } else {
    NSString *encodeUrl = [sourceUrl
        stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet
                                                               URLFragmentAllowedCharacterSet]];
    NSURL *source = [NSURL URLWithString:encodeUrl];
    if ([source.scheme isEqualToString:@"http"] || [source.scheme isEqualToString:@"https"]) {
      _latestQuery = source.query;
      url = sourceUrl;
      [self saveRecentUrl:sourceUrl];
    }
  }

  if (url.length == 0) {
    [self showUnsupportedUrlAlert:sourceUrl];
    return;
  }

  [self generateLatestParams];

  BOOL animated = YES;
  if ([[_latestParams allKeys] containsObject:@"animated"]) {
    animated = [[_latestParams objectForKey:@"animated"] boolValue];
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    UINavigationController *vc =
        ((AppDelegate *)([UIApplication sharedApplication].delegate)).navigationController;

    if (localRes.isLynxRecorderSchema) {
      LynxRecorderViewController *tbVC = [[LynxRecorderViewController alloc] init];
      tbVC.url = url;
      tbVC.sourceUrl = sourceUrl;
      __weak typeof(self) weakSelf = self;
      NSString *recentSourceUrl = [sourceUrl copy];
      tbVC.onReplayReady = ^{
        [weakSelf saveRecentUrl:recentSourceUrl];
      };
      [tbVC registerLynxRecorderActionCallback:[[LynxRecorderDefaultActionCallback alloc] init]];
      [vc pushViewController:tbVC animated:animated];
    } else {
      LynxViewShellViewController *shellVC = [LynxViewShellViewController new];
      shellVC.navigationController = (UINavigationController *)vc;
      shellVC.url = url;
      shellVC.data = data;
      shellVC.params = self->_latestParams;
      [vc pushViewController:shellVC animated:animated];
    }
  });
}

- (void)showUnsupportedUrlAlert:(NSString *)sourceUrl {
  dispatch_async(dispatch_get_main_queue(), ^{
    NSString *message =
        @"Enter a valid http(s) bundle URL, a file://lynx local bundle URL, or a file://lynxrecorder URL.";
    if (sourceUrl.length > 0) {
      message = [NSString stringWithFormat:@"%@\n\nInput: %@", message, sourceUrl];
    }

    UIAlertController *alertController =
        [UIAlertController alertControllerWithTitle:@"Unsupported URL"
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:@"OK"
                                                        style:UIAlertActionStyleDefault
                                                      handler:nil]];

    UINavigationController *vc =
        ((AppDelegate *)([UIApplication sharedApplication].delegate)).navigationController;
    UIViewController *presentingVC = vc.topViewController ?: vc;
    [presentingVC presentViewController:alertController animated:YES completion:nil];
  });
}

- (void)saveRecentUrl:(NSString *)sourceUrl {
  if (sourceUrl.length == 0) {
    return;
  }

  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSString *rawValue = [defaults objectForKey:kRecentSchemasStorageKey];
  NSMutableArray<NSString *> *recentUrls = [NSMutableArray array];

  if ([rawValue isKindOfClass:[NSString class]] && rawValue.length > 0) {
    NSData *jsonData = [rawValue dataUsingEncoding:NSUTF8StringEncoding];
    NSArray *storedUrls = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
    if ([storedUrls isKindOfClass:[NSArray class]]) {
      for (id item in storedUrls) {
        if ([item isKindOfClass:[NSString class]]) {
          [recentUrls addObject:item];
        }
      }
    }
  }

  [recentUrls removeObject:sourceUrl];
  [recentUrls insertObject:sourceUrl atIndex:0];
  if (recentUrls.count > kMaxRecentSchemasCount) {
    [recentUrls removeObjectsInRange:NSMakeRange(kMaxRecentSchemasCount,
                                                 recentUrls.count - kMaxRecentSchemasCount)];
  }

  NSData *jsonData = [NSJSONSerialization dataWithJSONObject:recentUrls options:0 error:nil];
  if (jsonData != nil) {
    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    [defaults setObject:jsonString forKey:kRecentSchemasStorageKey];
    [defaults synchronize];
  }
}

@end
