# Independent expert GEMV prototype

`QwenMetalModel.groupExpertDispatches` defaults to false. This branch adds a
testable decode/token-major QPack optimization; the shipped app is not pinned
to this branch. Layer-major prefill keeps its existing implementation.

For eight selected int4 experts, gate/up are sixteen independent projections
in one Metal grid, followed by the existing batched SiLU kernel and one grid
for eight independent down projections. Their expert-chain dispatch count is
32 before grouping and three after. Shared expert, routing and weighted
accumulation retain their previous implementations and ordering.

The kernel copies the existing fast int4 row arithmetic, including F32
accumulation and simdgroup reduction. It binds the existing cache buffers;
it does not copy/repack weights, lower precision, prune experts, change
top-k, or change quantization. Unsupported layouts retain original GEMVs.
All sixteen declared resource slots are bound, with a maximum of sixteen
projections per dispatch and original GEMV for a one-projection tail.

Validation covers separate blobs, nonzero offsets, F32/F16/BF16 scales,
mixed output sizes, distinct/shared inputs, one/sixteen/seventeen jobs,
fallback layouts and full synthetic QPack models with top-2 and top-8.
Full-model comparisons require bitwise logits, identical routing and KV,
continued decoding after eviction and after layer-major prefill, and exactly
the expected dispatch reduction. Existing controls run unchanged with the
feature off. Blocking lifecycle suites run separately with serialized
scheduling, retaining their assertions and deadlines.

Only small untrained fixtures run in CI. Passing these controls does not
establish trained Ornith parity, phone speed, memory peaks, sustained
temperature behavior, or model quality. Those require the physical iPhone
and the installed pinned checkpoint before integration/default activation.
