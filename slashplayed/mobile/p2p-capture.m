// Optional P2P framebuffer readback. Copies at most one completed frame per
// second; no screen recording permission, no file, no network. The module is
// included after spevent.m, where the atomic capture request is declared.
#if !TARGET_OS_VISION
static atomic_bool sp_p2p_inflight;
static _Atomic(uint64_t) sp_p2p_last_ms;
static void sp_p2p_capture(id<MTLCommandBuffer> cb, id<MTLTexture> tex) {
    if (!atomic_load(&sp_p2p_capture_enabled)) return;
    MTLPixelFormat fmt = tex.pixelFormat;
    BOOL bgra = fmt == MTLPixelFormatBGRA8Unorm || fmt == MTLPixelFormatBGRA8Unorm_sRGB;
    if (!bgra && fmt != MTLPixelFormatRGBA8Unorm && fmt != MTLPixelFormatRGBA8Unorm_sRGB) return;
    size_t w = tex.width, h = tex.height;
    if (w < 192 || h < 196 || w > 4096 || h > 4096) return;
    NSTimeInterval started = NSProcessInfo.processInfo.systemUptime;
    uint64_t ms = (uint64_t)(started * 1000), previous = atomic_load(&sp_p2p_last_ms);
    if (ms < previous + 1000 || !atomic_compare_exchange_strong(&sp_p2p_last_ms, &previous, ms)) return;
    bool expected = false;
    if (!atomic_compare_exchange_strong(&sp_p2p_inflight, &expected, true)) return;
    unsigned epoch = atomic_load(&sp_p2p_capture_epoch);
    size_t stride = ((w * 4 + 255) / 256) * 256, bytes = stride * h;
    id<MTLBuffer> buf = [cb.device newBufferWithLength:bytes options:MTLResourceStorageModeShared];
    id<MTLBlitCommandEncoder> enc = buf ? [cb blitCommandEncoder] : nil;
    if (!enc) { atomic_store(&sp_p2p_inflight, false); return; }
    [enc copyFromTexture:tex sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0)
              sourceSize:MTLSizeMake(w,h,1) toBuffer:buf destinationOffset:0
       destinationBytesPerRow:stride destinationBytesPerImage:bytes];
    [enc endEncoding];
    [cb addCompletedHandler:^(id<MTLCommandBuffer> done) {
        if (done.status != MTLCommandBufferStatusCompleted ||
            !atomic_load(&sp_p2p_capture_enabled) || atomic_load(&sp_p2p_capture_epoch) != epoch) {
            atomic_store(&sp_p2p_inflight,false);
            return;
        }
        // Preserve aspect ratio with black bars; cut the telemetry strip.
        NSMutableData *sample = [NSMutableData dataWithLength:3*192*192];
        uint8_t *out = sample.mutableBytes;
        const uint8_t *src = buf.contents;
        double scale = MIN(192.0/w,192.0/(h-4));
        double dw = w*scale, dh = (h-4)*scale;
        for (int y=0;y<192;y++) for (int x=0;x<192;x++) {
            double sx=(x+0.5-(192-dw)/2)/scale, sy=(y+0.5-(192-dh)/2)/scale;
            if (sx<0 || sx>=w || sy<0 || sy>=h-4) continue;
            const uint8_t *p=src+(size_t)sy*stride+(size_t)sx*4;
            size_t i=y*192+x;
            out[i]=p[bgra?2:0]; out[192*192+i]=p[1]; out[2*192*192+i]=p[bgra?0:2];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (atomic_load(&sp_p2p_capture_enabled) && atomic_load(&sp_p2p_capture_epoch)==epoch) {
                sp_p2p_latest_frame = sample;
                sp_p2p_latest_at = started;
            }
        });
        atomic_store(&sp_p2p_inflight,false);
    }];
}
#endif
