import Foundation
import Testing
@testable import SwiftletCore

/// Placement only: the exact same attention kernels read the exact same f32
/// GPU rows. The optional CPU copy must not influence any logit or route.
@Suite struct KVMirrorPlacementTests {
    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("fixtures")

    @Test(arguments: ["tiny-model", "tiny-model-q4", "tiny-model-q35"])
    func omittedMirrorPreservesAllLogitBitsAndGPUKV(modelName: String) throws {
        let dir = Self.fixtures.appendingPathComponent(modelName)
        let baseline = try QwenMetalModel(modelDir: dir)
        let unmirrored = try QwenMetalModel(modelDir: dir, retainCPUKVMirror: false)
        let left = QwenCPUModel.DecodeState(), right = QwenCPUModel.DecodeState()
        let prompt = [1, 5, 9, 42, 7, 99, 3, 17, 64, 2, 23, 88, 101, 54, 12, 71, 33]
        for mode in [QwenMetalModel.PrefillMode.tokenMajor, .layerMajor(chunkTokens: 4)] {
            baseline.prefillMode = mode
            unmirrored.prefillMode = mode
            let a = try baseline.step(prompt, state: left)
            let b = try unmirrored.step(prompt, state: right)
            #expect(a.map(\.bitPattern) == b.map(\.bitPattern))
            for token in [8, 36, 95] {
                let a = try baseline.step([token], state: left)
                let b = try unmirrored.step([token], state: right)
                #expect(a.map(\.bitPattern) == b.map(\.bitPattern))
            }
            #expect(!left.kv.isEmpty)
            #expect(right.kv.isEmpty)
            #expect(left.position == right.position)
            for layer in 0..<baseline.config.numHiddenLayers where !baseline.config.isLinearLayer(layer) {
                let a = try #require(baseline.attentionKVCacheRows(layer: layer, count: left.position))
                let b = try #require(unmirrored.attentionKVCacheRows(layer: layer, count: right.position))
                #expect(a.k.map(\.bitPattern) == b.k.map(\.bitPattern))
                #expect(a.v.map(\.bitPattern) == b.v.map(\.bitPattern))
            }
        }
        print("ORNITH_KV_PLACEMENT model=\(modelName) allLogitBitsEqual=true gpuKVBitsEqual=true cpuMirrorEmpty=true syntheticOnly=true")
    }

    @Test func foreignStateFailsBeforeGPUWorkAndFreshStateCanRestart() throws {
        let model = try QwenMetalModel(modelDir: Self.fixtures.appendingPathComponent("tiny-model-q35"),
                                       retainCPUKVMirror: false)
        let first = QwenCPUModel.DecodeState()
        _ = try model.step([1, 5, 9], state: first)
        let second = QwenCPUModel.DecodeState()
        _ = try model.step([42], state: second)
        #expect(throws: QwenMetalModel.RuntimeError.self) { try model.step([7], state: first) }
        #expect(model.lastStepMetrics.commandBuffersCommitted == 0)
        #expect(first.position == 3)
        _ = try model.step([9], state: second)
        #expect(second.position == 2)
        #expect(second.kv.isEmpty)
    }
}
