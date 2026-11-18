// Experimental opt-in combat assistant. Local Apple Vision + Apple's on-device
// Foundation Models bridge; no frame is stored or uploaded. All actions run on main.
#import <ReplayKit/ReplayKit.h>
#import <Vision/Vision.h>
#import <CoreMedia/CoreMedia.h>
#import <ImageIO/ImageIO.h>

@interface SPGameAIController : NSObject
@property(nonatomic, readonly) BOOL active;
@property(nonatomic, copy) void (^action)(NSString *);
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
    [self haltCapture];
    if (self.status) self.status(@"AI");
}
- (void)fail:(NSString *)reason {
    [self stop];
    if (self.status) self.status(reason);
}
- (void)finish:(NSString *)answer run:(NSUInteger)run {
    if (!_active || _run != run) return;
    if ([answer isEqualToString:@"ERROR"] || [answer isEqualToString:@"UNAVAILABLE"]) {
        [self fail:@"AI!"];
        return;
    }
    if (([answer isEqualToString:@"ATTACK"] || [answer isEqualToString:@"TARGET"]) && self.action)
        self.action(answer);
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
    if (ok) for (VNRecognizedTextObservation *observation in request.results) {
        VNRecognizedText *text = [[observation topCandidates:1] firstObject];
        if (text.confidence < 0.45 || text.string.length < 2) continue;
        CGRect rect = observation.boundingBox;
        [lines addObject:[NSString stringWithFormat:@"(%.2f,%.2f) %@", CGRectGetMidX(rect), CGRectGetMidY(rect), text.string]];
        if (lines.count >= 25) break;
    }
    NSString *observation = [lines componentsJoinedByString:@"\n"];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->_active || self->_run != run) return;
        if (!ok || observation.length < 12) { [self finish:@"WAIT" run:run]; return; }
        Class bridge = NSClassFromString(@"SPGameAIModel");
        SEL selector = NSSelectorFromString(@"decide:completion:");
        if (![bridge respondsToSelector:selector]) { [self fail:@"AI!"]; return; }
        void (^completion)(NSString *) = ^(NSString *answer) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self finish:answer run:run]; });
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
    if (self.status) self.status(@"STOP");
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
    // Time-box the first real-device experiment. No unattended endless loop.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        SPGameAIController *strong = weak;
        if (strong && strong->_active && strong->_run == run) [strong stop];
    });
}
@end
