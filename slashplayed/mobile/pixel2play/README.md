# Pixel2Play 150M – Core ML conversion experiment

This isolated job downloads the actual 150M checkpoint (about 2.2 GB, includes training state) and reconstructs the inference path using PyTorch modules and strict tensor shape checks, including EfficientNet image encoding, RoPE, RMSNorm, causal policy mask and a separate autoregressive decoder. Based on the MIT-licensed original at https://github.com/elefant-ai/open-p2p/tree/a329d98cbe62119679a254d71bea6446773541bc and MIT checkpoint at https://huggingface.co/elefantai/open-p2p/tree/bbe1a35/150M. See upstream license. No original assets are checked into this repository.

The initial export reduces 200-frame history to 4, omits text conditioning (uses learned no-text token), and uses greedy rather than stochastic sampling. It validates explicit dense attention against SDPA and evaluates actual compiled Core ML predictions on macOS. This DOES NOT establish parity with the entire original inference pipeline, game skill, latency, ANE placement or phone RAM feasibility. It does not yet change the iOS game input route. If conversion fails, no model artifact is uploaded. The earlier Laya iOS device kit is unaffected.

## Remaining gates after this job

- Compare output/action sequences with the pinned original PyTorch reference on identical frames and actions.
- Benchmark both packages on iPhone, with the game active.
- Add direct Metal readback in the existing renderer path, a rolling frame/action buffer and sequential decoding of the 8 action slots. Laya remains the supervisor; allowlisted movement, camera and safe action mapping only, plus manual override and cancellation.
- Verify against an authorized game test environment. Do not claim autonomous questing or WoW coverage from generic gameplay pretraining.


The next commit adds an optional native Swift runtime and a throttled readback hook. The runtime accepts the exporter manifest only when both macOS validation reports pass and proposes whitelisted movement commands when the Laya target-search supervisor permits it. Remaining gates still apply: actual model export/parity, native build, device latency and gameplay. The first on-device loop uses one frame per second with letterboxing, no camera/mouse execution, and discards stale proposals. No claim that the full original action mapping or full 200-frame context is implemented.
