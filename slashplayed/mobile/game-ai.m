// Experimental opt-in combat assistant. Local Apple Vision + Apple's on-device
// Foundation Models bridge; no frame is stored or uploaded. All actions run on main.
#import <ReplayKit/ReplayKit.h>
#import <Vision/Vision.h>
#import <CoreMedia/CoreMedia.h>
#import <ImageIO/ImageIO.h>

@interface SPGameAIController : NSObject
@property(nonatomic, readonly) BOOL active;
@property(nonatomic, readonly) BOOL starting;
@property(nonatomic, copy) BOOL (^action)(NSString *, CGPoint, NSTimeInterval);
@property(nonatomic, copy) void (^releaseInput)(void);
@property(nonatomic, copy) void (^status)(NSString *);
- (void)start;
- (void)stop;
- (void)invalidateDecision;
@end

@implementation SPGameAIController {
    BOOL _active, _starting, _stopping, _ownsCapture;
    NSUInteger _run, _captureRun;
    BOOL _busy;
    NSTimeInterval _nextFrame, _lastFrame;
}
- (BOOL)active { return _active; }
- (BOOL)starting { return _starting && _active; }

- (void)invalidateDecision {
    Class bridge = NSClassFromString(@"SPGameAIModel");
    SEL selector = NSSelectorFromString(@"resetDecision");
    if ([bridge respondsToSelector:selector]) ((void (*)(id, SEL))objc_msgSend)(bridge, selector);
}

// Summarize the full video frame (BGRA or NV12) without storing any frame.
// The coarse grid is used only for change detection, never semantic claims.
static NSArray<NSNumber *> *sp_ai_luminance(CVPixelBufferRef buffer) {
    NSMutableArray<NSNumber *> *result = [NSMutableArray arrayWithCapacity:96];
    if (CVPixelBufferLockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly) != kCVReturnSuccess) return result;
    OSType format = CVPixelBufferGetPixelFormatType(buffer);
    BOOL planar = CVPixelBufferIsPlanar(buffer) && CVPixelBufferGetPlaneCount(buffer) > 0 &&
        (format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange || format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange);
    BOOL bgra = format == kCVPixelFormatType_32BGRA;
    size_t width = planar ? CVPixelBufferGetWidthOfPlane(buffer, 0) : CVPixelBufferGetWidth(buffer);
    size_t height = planar ? CVPixelBufferGetHeightOfPlane(buffer, 0) : CVPixelBufferGetHeight(buffer);
    size_t stride = planar ? CVPixelBufferGetBytesPerRowOfPlane(buffer, 0) : CVPixelBufferGetBytesPerRow(buffer);
    const uint8_t *base = planar ? CVPixelBufferGetBaseAddressOfPlane(buffer, 0) : CVPixelBufferGetBaseAddress(buffer);
    if ((planar || bgra) && base && width && height && stride >= width * (bgra ? 4 : 1)) {
        for (size_t y = 0; y < 8; ++y) for (size_t x = 0; x < 12; ++x) {
            const uint8_t *p = base + ((2*y+1)*height/16)*stride + ((2*x+1)*width/24)*(bgra ? 4 : 1);
            unsigned value = planar ? p[0] : (29*p[0] + 150*p[1] + 77*p[2])/256;
            [result addObject:@(value / 16)];
        }
    }
    CVPixelBufferUnlockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
    return result;
}

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
    [self invalidateDecision];
    [self haltCapture];
    if (self.status) self.status(@"AI OFF");
}
- (void)fail:(NSString *)reason {
    [self stop];
    if (self.status) self.status(reason);
}
- (void)finish:(NSString *)answer points:(NSArray<NSValue *> *)points labels:(NSArray<NSString *> *)labels observation:(NSString *)observation captured:(NSTimeInterval)captured run:(NSUInteger)run {
    if (!_active || _run != run) return;
    if ([answer isEqualToString:@"ERROR"] || [answer isEqualToString:@"UNAVAILABLE"]) {
        [self fail:@"AI MODEL!"];
        return;
    }
    NSString *display = @"AI WAIT";
    // Don't execute a decision made on an old frame.
    if (self.action && NSProcessInfo.processInfo.systemUptime - captured <= 8.0) {
        NSSet *keys = [NSSet setWithArray:@[@"ATTACK", @"TARGET", @"FORWARD", @"BACK", @"LEFT", @"RIGHT"]];
        BOOL executed = NO;
        if ([keys containsObject:answer]) executed = self.action(answer, CGPointZero, captured);
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
                        executed = self.action(parts[0], points[index - 1].CGPointValue, captured);
                }
            }
        }
        if (executed) {
            display = [@"AI " stringByAppendingString:[[answer componentsSeparatedByString:@" "] firstObject]];
            Class bridge = NSClassFromString(@"SPGameAIModel");
            SEL record = NSSelectorFromString(@"recordAction:observation:");
            if ([bridge respondsToSelector:record])
                ((void (*)(id, SEL, NSString *, NSString *))objc_msgSend)(bridge, record, answer, observation);
        }
    }
    if (NSProcessInfo.processInfo.systemUptime - captured > 8.0) display = @"AI SLOW";
    if (self.status) self.status(display);
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
        if (_captureRun != run) return;
        _lastFrame = NSProcessInfo.processInfo.systemUptime;
        if (_busy || _lastFrame < _nextFrame) return;
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
    NSMutableArray<NSDictionary *> *observedLabels = [NSMutableArray array];
    NSMutableArray<NSValue *> *points = [NSMutableArray array];
    NSMutableArray<NSString *> *labels = [NSMutableArray array];
    if (ok) for (VNRecognizedTextObservation *observation in request.results) {
        VNRecognizedText *text = [[observation topCandidates:1] firstObject];
        if (text.confidence < 0.45 || text.string.length < 2) continue;
        CGRect rect = observation.boundingBox;
        CGPoint point = CGPointMake(CGRectGetMidX(rect), 1 - CGRectGetMidY(rect));
        [points addObject:[NSValue valueWithCGPoint:point]];
        [labels addObject:[text.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]];
        [observedLabels addObject:@{@"id": @(points.count), @"x": @(point.x), @"y": @(point.y),
            @"text": [text.string substringToIndex:MIN(text.string.length, 120)]}];
        if (observedLabels.count >= 25) break;
    }
    // Whole-image classification is generic, not a WoW-trained detector.
    VNClassifyImageRequest *classification = [VNClassifyImageRequest new];
    NSMutableArray<NSString *> *tags = [NSMutableArray array];
    if ([handler performRequests:@[classification] error:NULL]) {
        for (VNClassificationObservation *label in classification.results) {
            if (label.confidence < 0.08) continue;
            [tags addObject:label.identifier];
            if (tags.count >= 5) break;
        }
    }
    NSDictionary *payload = @{@"labels": observedLabels, @"visualTags": tags, @"luminance": sp_ai_luminance(buffer)};
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:NULL];
    NSString *observation = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"";
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->_active || self->_run != run) return;
        if (!ok || !observation.length || !points.count) {
            [self finish:@"WAIT" points:points labels:labels observation:observation captured:captured run:run];
            if (self.status) self.status(@"AI NO TEXT");
            return;
        }
        if (self.status) self.status(@"AI THINK");
        Class bridge = NSClassFromString(@"SPGameAIModel");
        SEL selector = NSSelectorFromString(@"decide:completion:");
        if (![bridge respondsToSelector:selector]) { [self fail:@"AI MODEL!"]; return; }
        void (^completion)(NSString *) = ^(NSString *answer) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self finish:answer points:points labels:labels observation:observation captured:captured run:run]; });
        };
        ((void (*)(id, SEL, NSString *, void (^)(NSString *)))objc_msgSend)(bridge, selector, observation, completion);
    });
}
- (void)watchCapture:(NSUInteger)run {
    __weak SPGameAIController *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        SPGameAIController *strong = weak;
        if (!strong || !strong->_active || strong->_run != run) return;
        NSTimeInterval elapsed;
        @synchronized(strong) { elapsed = NSProcessInfo.processInfo.systemUptime - strong->_lastFrame; }
        if (elapsed > 15.0) { [strong fail:@"AI NO VID"]; return; }
        [strong watchCapture:run];
    });
}
- (void)start {
    if (_active || _starting || _stopping) return;
    Class bridge = NSClassFromString(@"SPGameAIModel");
    SEL ready = NSSelectorFromString(@"ready");
    RPScreenRecorder *recorder = RPScreenRecorder.sharedRecorder;
    if (![bridge respondsToSelector:ready] || !((BOOL (*)(id, SEL))objc_msgSend)(bridge, ready)) {
        if (self.status) self.status(@"AI MODEL!");
        return;
    }
    if (!recorder.isAvailable || recorder.isRecording) {
        if (self.status) self.status(@"AI CAP!");
        return;
    }
    [self invalidateDecision];
    _active = YES;
    _starting = YES;
    NSUInteger run = ++_run;
    @synchronized(self) { _captureRun = 0; _busy = NO; }
    if (self.status) self.status(@"AI ON…");
    recorder.microphoneEnabled = NO;
    __weak SPGameAIController *weak = self;
    [recorder startCaptureWithHandler:^(CMSampleBufferRef sample, RPSampleBufferType type, NSError *error) {
        SPGameAIController *strong = weak;
        if (!strong) return;
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (strong->_active && strong->_run == run) [strong fail:@"AI CAP!"];
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
                if (strong->_active && strong->_run == run) [strong fail:@"AI CAP!"];
                return;
            }
            strong->_ownsCapture = YES;
            if (!strong->_active || strong->_run != run) { [strong haltCapture]; return; }
            @synchronized(strong) {
                strong->_captureRun = run;
                strong->_nextFrame = 0;
                strong->_lastFrame = NSProcessInfo.processInfo.systemUptime;
            }
            if (strong.status) strong.status(@"AI VIDEO");
            [strong watchCapture:run];
        });
    }];
    // No session timeout: the same button toggles off. Lifecycle/errors still fail closed.
}
@end
