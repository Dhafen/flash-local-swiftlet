import Foundation
import Metal

extension MetalEngine {
    /// Independent projections. Each job retains its own original dot-product
    /// order and output range. The caller must provide disjoint output ranges
    /// and must not make a job's input depend on another job in the group.
    struct IndependentGEMV {
        let linear: MetalShardStore.GPULinear
        let xOff: Int
        let yOff: Int
    }

    /// Groups up to 16 QPack int4 projections per dispatch, with no weight
    /// repacking/copy. The existing fast GEMV's arithmetic is retained per row.
    /// Non-QPack/split buffers, int8/plain weights, and unaligned weights keep
    /// the original dispatch path. Sixteen weight slots plus x/y/params fit
    /// ordinary Metal buffer bindings; no argument-buffer tier is assumed.
    func encodeIndependentGEMVs(
        _ enc: MTLComputeCommandEncoder,
        _ jobs: [IndependentGEMV], x: MTLBuffer, y: MTLBuffer
    ) throws {
        guard !jobs.isEmpty else { return }
        let canGroup = Self.fastGemvEnabled && jobs.allSatisfy {
            let l = $0.linear
            return l.isQuantized && l.bits == 4 && l.wOff % 4 == 0
                && l.groupSize > 0 && l.groupSize % 8 == 0
                && l.inDim > 0 && l.inDim % l.groupSize == 0 && l.outDim > 0
                && l.wBuffer === l.sBuffer && l.wBuffer === l.bBuffer
        }
        guard canGroup else {
            for job in jobs {
                try encodeGemv(enc, job.linear, x: x, xOff: job.xOff, y: y, yOff: job.yOff)
            }
            return
        }
        for first in stride(from: 0, to: jobs.count, by: 16) {
            let group = Array(jobs[first..<min(first + 16, jobs.count)])
            if group.count == 1 {
                let job = group[0]
                try encodeGemv(enc, job.linear, x: x, xOff: job.xOff, y: y, yOff: job.yOff)
                continue
            }
            let params = group.map { job in
                let l = job.linear
                return GemvParams(
                    wOff: UInt64(l.wOff), sOff: UInt64(l.sOff), bOff: UInt64(l.bOff),
                    outDim: UInt32(l.outDim), inDim: UInt32(l.inDim),
                    groupSize: UInt32(l.groupSize), bits: UInt32(l.bits),
                    scalesType: l.scalesType, yOff: UInt32(job.yOff), xOff: UInt32(job.xOff))
            }
            enc.setComputePipelineState(try pipeline("gemv_affine_fast_independent"))
            enc.setBuffer(x, offset: 0, index: 0)
            // All statically declared resource slots must have valid bindings,
            // even when the dispatch's z extent uses fewer than sixteen.
            for index in 0..<16 {
                enc.setBuffer(group[min(index, group.count - 1)].linear.wBuffer,
                              offset: 0, index: index + 1)
            }
            enc.setBuffer(y, offset: 0, index: 17)
            params.withUnsafeBytes {
                enc.setBytes($0.baseAddress!, length: $0.count, index: 18)
            }
            dispatchThreads(
                enc,
                threads: MTLSize(width: 32, height: group.map { $0.linear.outDim }.max()!, depth: group.count),
                threadsPerThreadgroup: MTLSize(width: 32, height: 1, depth: 1))
        }
    }
}
