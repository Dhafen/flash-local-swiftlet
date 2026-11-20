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
        // The original model resizes the full rectangle to 192x192, without
        // letterboxing. Use area averaging (not the upstream Hamming kernel)
        // to approximate antialiased downsampling; omit the hidden strip.
        NSMutableData *sample = [NSMutableData dataWithLength:3*192*192];
        NSTimeInterval resizeStarted = NSProcessInfo.processInfo.systemUptime;
        uint8_t *out = sample.mutableBytes;
        const uint8_t *src = buf.contents;
        const size_t visibleH = h - 4;
        for (size_t y=0;y<192;y++) for (size_t x=0;x<192;x++) {
            size_t x0=x*w/192, x1=(x+1)*w/192;
            size_t y0=y*visibleH/192, y1=(y+1)*visibleH/192;
            unsigned red=0, green=0, blue=0, count=0;
            for (size_t sy=y0;sy<y1;sy++) for (size_t sx=x0;sx<x1;sx++) {
                const uint8_t *p=src+sy*stride+sx*4;
                red+=p[bgra?2:0]; green+=p[1]; blue+=p[bgra?0:2]; ++count;
            }
            if (!count) continue;
            size_t i=y*192+x;
            out[i]=red/count; out[192*192+i]=green/count; out[2*192*192+i]=blue/count;
        }
        NSTimeInterval resized = NSProcessInfo.processInfo.systemUptime;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (atomic_load(&sp_p2p_capture_enabled) && atomic_load(&sp_p2p_capture_epoch)==epoch) {
                sp_p2p_latest_frame = sample;
                sp_p2p_latest_at = started;
                static NSTimeInterval lastMetrics;
                if (started - lastMetrics >= 10.0) {
                    lastMetrics = started;
                    sp_stub_log([[NSString stringWithFormat:@"AI capture: %zux%zu %zu bytes, GPU wait %.1fms, resize %.1fms",
                        w, h, bytes, 1000*(resizeStarted-started), 1000*(resized-resizeStarted)] UTF8String]);
                }
            }
        });
        atomic_store(&sp_p2p_inflight,false);
    }];
}
#endif
