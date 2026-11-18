// Experimental opt-in combat assistant. Local Apple Vision + Apple's on-device
// Foundation Models bridge; no frame is stored or uploaded. All actions run on main.
#import <ReplayKit/ReplayKit.h>
#import <Vision/Vision.h>
#import <CoreMedia/CoreMedia.h>
#import <ImageIO/ImageIO.h>

@interface SPGameAIController : NSObject
@property(nonatomic, readonly) BOOL active;
@property(nonatomic, copy) void (^action)(NSString *, CGPoint);
@property(nonatomic, copy) void (^releaseInput)(void);
@property(nonatomic, copy) void (^status)(NSString *);
- (void)start;
- (void)stop;
@end

@implementation SPGameAIController {
    BOOL _active, _starting, _stopping, _ownsCapture;
    NSUInteger _run, _captureRun;
    BOOL _busy;
    NSTimeInterval _nextFrame;
}
- (BOOL)active { return _active; }

- (void)haltCapture {
    if (!_ownsCapture || _stopping) return;
    _ownsCapture = NO;
    _stopping = YES;
    __weak SPGameAIController *weak = self;
    [RPScreenRecorder.sharedRecorder stopCaptureWithHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SPGameAIController *strong = weak;
            if (strong) strong->_stopping = NO;
        });
    }];
}
- (void)stop {
    if (!_active) return;
    _active = NO;
    ++_run;
    @synchronized(self) { _captureRun = 0; _busy = NO; }
    if (self.releaseInput) self.releaseInput();
    [self haltCapture];
    if (self.status) self.status(@"AI OFF");
}
- (void)fail:(NSString *)reason {
    [self stop];
    if (self.status) self.status(reason);
}
- (void)finish:(NSString *)answer points:(NSArray<NSValue *> *)points labels:(NSArray<NSString *> *)labels captured:(NSTimeInterval)captured run:(NSUInteger)run {
    if (!_active || _run != run) return;
    if ([answer isEqualToString:@"ERROR"] || [answer isEqualToString:@"UNAVAILABLE"]) {
        [self fail:@"AI!"];
        return;
    }
    // Don't execute a decision made on an old frame.
    if (self.action && NSProcessInfo.processInfo.systemUptime - captured <= 8.0) {
        NSSet *keys = [NSSet setWithArray:@[@"ATTACK", @"TARGET", @"FORWARD", @"BACK", @"LEFT", @"RIGHT"]];
        if ([keys containsObject:answer]) self.action(answer, CGPointZero);
        else {
            NSArray<NSString *> *parts = [answer componentsSeparatedByString:@" "];
            if (parts.count == 2 && ([parts[0] isEqualToString:@"CLICK"] || [parts[0] isEqualToString:@"INTERACT"])) {
                NSInteger index = parts[1].integerValue;
                if (index >= 1 && index <= (NSInteger)points.count && index <= (NSInteger)labels.count) {
                    NSString *label = labels[index - 1].lowercaseString;
                    // Restrict left clicks to descriptive quest/loot controls; never arbitrary UI.
                    NSSet *allowed = [NSSet setWithArray:@[@"accept", @"accept quest", @"complete quest", @"continue", @"loot", @"loot all", @"take all"]];
                    BOOL allowedClick = [parts[0] isEqualToString:@"CLICK"] && [allowed containsObject:label];
                    BOOL blocked = [label containsString:@"trade"] || [label containsString:@"buy"] ||
                        [label containsString:@"sell"] || [label containsString:@"delete"] ||
                        [label containsString:@"settings"] || [label containsString:@"password"] ||
                        [label containsString:@"auction"] || [label containsString:@"mail"] ||
                        [label containsString:@"logout"] || [label containsString:@"exit"];
                    if (!blocked && (allowedClick || [parts[0] isEqualToString:@"INTERACT"]))
                        self.action(parts[0], points[index - 1].CGPointValue);
                }
            }
        }
    }
    @synchronized(self) {
        if (_captureRun == run) {
            _busy = NO;
            _nextFrame = NSProcessInfo.processInfo.systemUptime + 1.5;
        }
    }
}
- (void)inspect:(CMSampleBufferRef)sample run:(NSUInteger)run {
    CVPixelBufferRef buffer = CMSampleBufferGetImageBuffer(sample);
    if (!buffer) return;
    @synchronized(self) {
        if (_captureRun != run || _busy || NSProcessInfo.processInfo.systemUptime < _nextFrame) return;
        _busy = YES;
    }
    NSTimeInterval captured = NSProcessInfo.processInfo.systemUptime;
    NSNumber *orientation = (__bridge NSNumber *)CMGetAttachment(sample, (__bridge CFStringRef)RPVideoSampleOrientationKey, NULL);
    NSInteger value = orientation ? orientation.integerValue : kCGImagePropertyOrientationUp;
    CGImagePropertyOrientation exif = (value >= 1 && value <= 8) ? (CGImagePropertyOrientation)value : kCGImagePropertyOrientationUp;
    // ReplayKit delivers buffers on its capture queue; OCR remains off main.
    VNRecognizeTextRequest *request = [VNRecognizeTextRequest new];
    request.recognitionLevel = VNRequestTextRecognitionLevelFast;
    request.usesLanguageCorrection = NO;
    request.regionOfInterest = CGRectMake(0, 0.24, 1, 0.76); // omit the chat end of the screen
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCVPixelBuffer:buffer orientation:exif options:@{}];
    NSError *error = nil;
    BOOL ok = [handler performRequests:@[request] error:&error];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    NSMutableArray<NSValue *> *points = [NSMutableArray array];
    NSMutableArray<NSString *> *labels = [NSMutableArray array];
    if (ok) for (VNRecognizedTextObservation *observation in request.results) {
        VNRecognizedText *text = [[observation topCandidates:1] firstObject];
        if (text.confidence < 0.45 || text.string.length < 2) continue;
        CGRect rect = observation.boundingBox;
        CGPoint point = CGPointMake(CGRectGetMidX(rect), 1 - CGRectGetMidY(rect));
        [points addObject:[NSValue valueWithCGPoint:point]];
        [labels addObject:[text.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]];
        [lines addObject:[NSString stringWithFormat:@"%lu (%.2f,%.2f) %@", (unsigned long)points.count, point.x, point.y, text.string]];
        if (lines.count >= 25) break;
    }
    NSString *observation = [lines componentsJoinedByString:@"\n"];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->_active || self->_run != run) return;
        if (!ok || observation.length < 12) { [self finish:@"WAIT" points:points labels:labels captured:captured run:run]; return; }
        Class bridge = NSClassFromString(@"SPGameAIModel");
        SEL selector = NSSelectorFromString(@"decide:completion:");
        if (![bridge respondsToSelector:selector]) { [self fail:@"AI!"]; return; }
        void (^completion)(NSString *) = ^(NSString *answer) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self finish:answer points:points labels:labels captured:captured run:run]; });
        };
        ((void (*)(id, SEL, NSString *, void (^)(NSString *)))objc_msgSend)(bridge, selector, observation, completion);
    });
}
- (void)start {
    if (_active || _starting || _stopping) return;
    Class bridge = NSClassFromString(@"SPGameAIModel");
    SEL ready = NSSelectorFromString(@"ready");
    RPScreenRecorder *recorder = RPScreenRecorder.sharedRecorder;
    if (![bridge respondsToSelector:ready] ||
        !((BOOL (*)(id, SEL))objc_msgSend)(bridge, ready) ||
        !recorder.isAvailable || recorder.isRecording) {
        if (self.status) self.status(@"AI!");
        return;
    }
    _active = YES;
    _starting = YES;
    NSUInteger run = ++_run;
    @synchronized(self) { _captureRun = 0; _busy = NO; }
    if (self.status) self.status(@"AI ON");
    recorder.microphoneEnabled = NO;
    __weak SPGameAIController *weak = self;
    [recorder startCaptureWithHandler:^(CMSampleBufferRef sample, RPSampleBufferType type, NSError *error) {
        SPGameAIController *strong = weak;
        if (!strong) return;
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (strong->_active && strong->_run == run) [strong fail:@"AI!"];
            });
            return;
        }
        if (type == RPSampleBufferTypeVideo && sample) [strong inspect:sample run:run];
    } completionHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SPGameAIController *strong = weak;
            if (!strong) return;
            strong->_starting = NO;
            if (error) {
                if (strong->_active && strong->_run == run) [strong fail:@"AI!"];
                return;
            }
            strong->_ownsCapture = YES;
            if (!strong->_active || strong->_run != run) { [strong haltCapture]; return; }
            @synchronized(strong) { strong->_captureRun = run; strong->_nextFrame = 0; }
        });
    }];
    // No session timeout: the same button toggles off. Lifecycle/errors still fail closed.
}
@end
