import Foundation
import Metal
import Testing
@testable import SwiftletCore

@Suite struct GroupedExpertTests {
    /// Separately stored expert blobs with nonzero offsets, different weights
    /// and all supported scale dtypes. Tiny untrained test weights only.
    static func linear(_ engine: MetalEngine, index: Int, dtype: UInt32,
                       input: Int = 256, output: Int = 40) -> MetalShardStore.GPULinear {
        var rng = MetalKernelTests.Rand(UInt64(1927 + index))
        let words = (0..<output * input / 8).map { _ in rng.next32() }
        let scales = (0..<output * input / 64).map { _ in rng.float() * 0.1 }
        let biases = (0..<output * input / 64).map { _ in rng.float() * 0.05 }
        let pad = 4 * (index % 7 + 1)
        var blob = Data(repeating: 0xAB, count: pad)
        words.withUnsafeBytes { blob.append(contentsOf: $0) }
        func append(_ values: [Float]) {
            if dtype == 0 {
                values.withUnsafeBytes { blob.append(contentsOf: $0) }
            } else if dtype == 1 {
                let converted = values.map { Float16($0) }
                converted.withUnsafeBytes { blob.append(contentsOf: $0) }
            } else {
                let converted = values.map(MetalKernelTests.bf16)
                converted.withUnsafeBytes { blob.append(contentsOf: $0) }
            }
        }
        let sOff = blob.count
        append(scales)
        let bOff = blob.count
        append(biases)
        let buffer = engine.makeBuffer(blob)
        return .init(wBuffer: buffer, sBuffer: buffer, bBuffer: buffer,
            outDim: output, inDim: input, isQuantized: true, groupSize: 64,
            bits: 4, scalesType: dtype, wOff: pad, sOff: sOff, bOff: bOff)
    }

    static func compare(_ engine: MetalEngine, _ jobs: [MetalEngine.IndependentGEMV],
                        expectedGroupedDispatches: Int) throws {
        let xCount = jobs.map { $0.xOff + $0.linear.inDim }.max() ?? 1
        let yCount = (jobs.map { $0.yOff + $0.linear.outDim }.max() ?? 1) + 9
        var rng = MetalKernelTests.Rand(2718)
        let x = engine.makeBuffer((0..<xCount).map { _ in rng.float() })
        let original = engine.makeBuffer([Float](repeating: -987, count: yCount))
        let grouped = engine.makeBuffer([Float](repeating: -987, count: yCount))
        let originalCount = try MetalKernelTests.runEncoded(engine) { enc in
            for job in jobs {
                try engine.encodeGemv(enc, job.linear, x: x, xOff: job.xOff, y: original, yOff: job.yOff)
            }
        }
        let groupedCount = try MetalKernelTests.runEncoded(engine) { enc in
            try engine.encodeIndependentGEMVs(enc, jobs, x: x, y: grouped)
        }
        #expect(originalCount == jobs.count)
        #expect(groupedCount == expectedGroupedDispatches)
        let a = UnsafeBufferPointer(start: original.contents().bindMemory(to: Float.self, capacity: yCount), count: yCount)
        let b = UnsafeBufferPointer(start: grouped.contents().bindMemory(to: Float.self, capacity: yCount), count: yCount)
        #expect(a.map(\.bitPattern) == b.map(\.bitPattern), "grouped output or untouched sentinel changed")
    }

    @Test(arguments: [UInt32(0), UInt32(1), UInt32(2)], [1, 3, 8, 16, 17])
    func independentInt4IsBitwiseIdentical(dtype: UInt32, count: Int) throws {
        let engine = try MetalEngine()
        let jobs = (0..<count).map { index in
            MetalEngine.IndependentGEMV(
                linear: Self.linear(engine, index: index, dtype: dtype, output: 35 + index % 5),
                xOff: 3 + index * 263, yOff: 2 + index * 45)
        }
        try Self.compare(engine, jobs, expectedGroupedDispatches: (count + 15) / 16)
    }

    @Test func ornithExpertProjectionGeometryIsBitwiseIdentical() throws {
        let engine = try MetalEngine()
        let jobs = (0..<16).map { index in
            MetalEngine.IndependentGEMV(
                linear: Self.linear(engine, index: index, dtype: 2, input: 2048, output: 512),
                xOff: 7, yOff: index * 512 + 3)
        }
        try Self.compare(engine, jobs, expectedGroupedDispatches: 1)
    }

    @Test func unsupportedLayoutsUseOriginalPath() throws {
        let engine = try MetalEngine()
        let linears = [
            MetalKernelTests.quantizedLinear(engine, bits: 4, pad: 0),
            MetalKernelTests.quantizedLinear(engine, bits: 8, pad: 0),
            MetalKernelTests.quantizedLinear(engine, bits: 4, pad: 2),
            MetalKernelTests.plainLinear(engine, dtype: 2),
        ]
        let jobs = linears.enumerated().map {
            MetalEngine.IndependentGEMV(linear: $0.element, xOff: 2, yOff: 1 + $0.offset * 55)
        }
        try Self.compare(engine, jobs, expectedGroupedDispatches: jobs.count)
        try Self.compare(engine, [], expectedGroupedDispatches: 0)
    }

    @Test(arguments: [2, 8])
    func wholeQpackDecodePreservesLogitsRoutesKVAndContinuation(topK: Int) throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("grouped-experts-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        try fm.copyItem(at: MetalModelTests.fixturesDir.appendingPathComponent("tiny-model-q4"), to: source)
        let configURL = source.appendingPathComponent("config.json")
        var config = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: Any])
        // The tiny fixture already has eight experts. Exercise top-8 without
        // downloading trained weights or changing any existing test fixture.
        config["num_experts_per_tok"] = topK
        try JSONSerialization.data(withJSONObject: config).write(to: configURL)
        let packed = root.appendingPathComponent("model.qpack")
        var repacker = QpackRepacker(checkpointDir: source, outputDir: packed)
        repacker.log = { _ in }
        try repacker.repack()
        let original = try QwenMetalModel(modelDir: packed, cacheBudgetGB: 0.0005)
        let grouped = try QwenMetalModel(modelDir: packed, cacheBudgetGB: 0.0005)
        #expect(!original.groupExpertDispatches, "experimental optimization must stay opt-in")
        grouped.groupExpertDispatches = true
        original.prefillMode = .tokenMajor
        grouped.prefillMode = .tokenMajor
        var routesA: [[Int]] = [], routesB: [[Int]] = []
        original.routedExpertObserver = { _, experts in routesA.append(experts) }
        grouped.routedExpertObserver = { _, experts in routesB.append(experts) }
        let aState = QwenCPUModel.DecodeState(), bState = QwenCPUModel.DecodeState()
        for token in [1, 5, 9, 42, 7, 99] {
            let a = try original.step([token], state: aState)
            let b = try grouped.step([token], state: bState)
            #expect(a.map(\.bitPattern) == b.map(\.bitPattern), "decode logits diverged")
            #expect(routesA == routesB, "routing changed")
            MetalModelTests.expectMatchingKV(aState, bState, label: "grouped experts")
            let saved = original.lastStepMetrics.computeDispatchesEncoded - grouped.lastStepMetrics.computeDispatchesEncoded
            #expect(saved == 8 * (4 * topK - 3))
            #expect(original.lastStepMetrics.commandBuffersCommitted == grouped.lastStepMetrics.commandBuffersCommitted)
            #expect(grouped.lastStepMetrics.commandBufferErrors == 0)
        }
        let cache = try #require(grouped.expertCache)
        if topK == 8 {
            #expect(cache.evictions > 0, "must cover evicted/reloaded expert buffers")
        }
        // Exercise the existing layer-major prefill with the flag set, then
        // switch back to single-token decode without changing the state.
        original.prefillMode = .layerMajor(chunkTokens: 4)
        grouped.prefillMode = .layerMajor(chunkTokens: 4)
        let a = try original.step([2, 3, 4], state: aState)
        let b = try grouped.step([2, 3, 4], state: bState)
        #expect(a.map(\.bitPattern) == b.map(\.bitPattern))
        let aNext = try original.step([11], state: aState)
        let bNext = try grouped.step([11], state: bState)
        #expect(aNext.map(\.bitPattern) == bNext.map(\.bitPattern))
        #expect(routesA == routesB)
        print("GROUPED_QPACK topK=\(topK) bitwise=true routing=true dispatchesSavedPerDecode=\(8 * (4 * topK - 3)) physicalPhone=false")
    }
}
