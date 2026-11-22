// Optional readback of three rows from the already visible player health bar.
#if !TARGET_OS_VISION
static atomic_bool sp_ai_health_inflight;
static _Atomic(uint64_t) sp_ai_health_last_ms;

static void sp_health_capture(id<MTLCommandBuffer> cb, id<MTLTexture> texture) {
    unsigned epoch = atomic_load(&sp_ai_health_capture_epoch);
    unsigned interval = atomic_load(&sp_ai_health_interval_ms);
    if (!interval) return;
    uint64_t ms = (uint64_t)(NSProcessInfo.processInfo.systemUptime * 1000);
    uint64_t previous = atomic_load(&sp_ai_health_last_ms);
    if (ms < previous + interval) return;
    uint64_t boundsAt = atomic_load(&sp_ai_health_bounds_ms);
    if (!sp_ai_health_bounds_fresh(boundsAt, ms)) return;
    uint64_t bounds = atomic_load(&sp_ai_health_bounds);
    if (!bounds) return;
    MTLPixelFormat fmt = texture.pixelFormat;
    BOOL bgra = fmt == MTLPixelFormatBGRA8Unorm || fmt == MTLPixelFormatBGRA8Unorm_sRGB;
    if (!bgra && fmt != MTLPixelFormatRGBA8Unorm && fmt != MTLPixelFormatRGBA8Unorm_sRGB) return;
    size_t x = (bounds >> 48) * texture.width / 4095;
    size_t y = ((bounds >> 32) & 4095) * texture.height / 4095;
    size_t right = ((bounds >> 16) & 4095) * texture.width / 4095;
    size_t bottom = (bounds & 4095) * texture.height / 4095;
    if (right <= x || bottom <= y) return;
    size_t width = right - x, barHeight = bottom - y;
    if (width < 48 || width > 1024 || barHeight < 12 || barHeight > 128) return;
    y += barHeight / 5;  // Off the middle row, where Wolkara draws the text.
    NSProcessInfoThermalState thermal = NSProcessInfo.processInfo.thermalState;
    unsigned liveInterval = sp_ai_health_capture_interval_ms((unsigned)thermal, true, false, true);
    if (!liveInterval || ms < previous + liveInterval) return;
    if (!atomic_compare_exchange_strong(&sp_ai_health_last_ms, &previous, ms)) return;
    bool expected = false;
    if (!atomic_compare_exchange_strong(&sp_ai_health_inflight, &expected, true)) return;
    size_t stride = (width * 4 + 255) & ~(size_t)255;
    id<MTLBuffer> data = [cb.device newBufferWithLength:stride * SP_HEALTH_SCAN_ROWS options:MTLResourceStorageModeShared];
    id<MTLBlitCommandEncoder> blit = data ? [cb blitCommandEncoder] : nil;
    if (!blit) { atomic_store(&sp_ai_health_inflight, false); return; }
    [blit copyFromTexture:texture sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(x,y,0)
                sourceSize:MTLSizeMake(width,SP_HEALTH_SCAN_ROWS,1) toBuffer:data destinationOffset:0
    destinationBytesPerRow:stride destinationBytesPerImage:stride * SP_HEALTH_SCAN_ROWS];
    [blit endEncoding];
    [cb addCompletedHandler:^(id<MTLCommandBuffer> done) {
        if (done.status == MTLCommandBufferStatusCompleted && atomic_load(&sp_ai_health_interval_ms) &&
            NSProcessInfo.processInfo.thermalState < NSProcessInfoThermalStateCritical &&
            atomic_load(&sp_ai_health_capture_epoch) == epoch) {
            uint8_t result = sp_ai_visible_health(data.contents, width, stride, bgra);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (atomic_load(&sp_ai_health_interval_ms) && atomic_load(&sp_ai_health_capture_epoch) == epoch &&
                    NSProcessInfo.processInfo.thermalState < NSProcessInfoThermalStateCritical) {
                    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
                    sp_ai_finish_health_comparison(now);
                    sp_ai_health_visual_result = result;
                    sp_ai_health_visual_at = (double)ms / 1000;
                    sp_ai_health_comparison_pending = YES;
                    sp_ai_finish_health_comparison(now);
                    sp_stub_log([[NSString stringWithFormat:@"AI visual health diagnostic: %u crop-bytes=%zu",
                        (unsigned)result, stride * SP_HEALTH_SCAN_ROWS] UTF8String]);
                }
            });
        }
        atomic_store(&sp_ai_health_inflight, false);
    }];
}
#endif
