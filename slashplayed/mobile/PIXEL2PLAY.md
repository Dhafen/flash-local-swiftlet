# Pixel2Play 150M – porting notes (not a shipped inference engine)

Pinned upstream: https://github.com/elefant-ai/open-p2p/tree/a329d98cbe62119679a254d71bea6446773541bc
Weights: https://huggingface.co/elefantai/open-p2p/tree/main/150M (MIT)

The upstream 150M policy consumes 192x192 RGB uint8 frames, uses a convolutional image tokenizer, a 10-layer 1024-wide causal transformer with 200-frame history, a separate autoregressive action decoder, and Gemma-derived optional text embeddings. Upstream inference.py has both KV-cache and full-history modes. Its desktop Linux/Windows runner is not an iOS runtime. Do not rename a Torch checkpoint to .mlpackage or claim a stub is the model.

Port gates:
1. Reproduce upstream random-weight inference, then load the real 150M checkpoint using the pinned source configuration (not the deprecated checkpoint YAML). No-text inference first.
2. Export image encoder, causal policy and action decoder as fixed-shape Core ML or implement equivalent MLX; replace unsupported flex attention / dynamic cache operations and sampling. Keep image normalization, action vocabulary and autoregressive ordering identical.
3. Compare raw logits and reconstructed actions with the reference on fixed frames and RNG seeds. Validate cache reset and 200-step rolling window.
4. On-device Metal capture uses the existing presented-drawable hook in sphover.m. Only add a throttled readback after valid exports exist; no desktop streaming. Respect orientation and prevent overlap with manual input. Route actions through existing manual input abstraction and preserve explicit stop/cancellation.
5. Benchmark game FPS, peak RAM, inference latency and thermal behavior on the actual phone; only then enable Pixel2Play policy by default. WoW is not an upstream validated game.

Current experiment ships Laya only. No claim of working Pixel2Play integration, independent navigation, quest completion or on-device benchmarks yet.
