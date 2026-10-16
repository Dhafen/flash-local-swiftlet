import Foundation
import Testing
@testable import SwiftletCore

@Suite struct BoundedQPackReferenceTests {
    static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("fixtures")

    @Test(arguments: ["tiny-model", "tiny-model-q4", "tiny-model-q35"])
    func tablePlacementMatchesTheUnchangedCPUReference(modelName: String) throws {
        let source = Self.fixtures.appendingPathComponent(modelName)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".qpack")
        defer { try? FileManager.default.removeItem(at: output) }
        var packer = QpackRepacker(checkpointDir: source, outputDir: output)
        packer.log = { _ in }
        try packer.repack()
        let control = try QwenCPUModel(modelDir: source)
        let bounded = try QwenCPUModel(modelDir: output, referenceTableTileRows: 7)
        #expect(bounded.embed.isEmpty && bounded.lmHead.isEmpty)
        let a = QwenCPUModel.DecodeState(), b = QwenCPUModel.DecodeState()
        var worst: Float = 0
        for token in [1, 5, 9, 3, 7] {
            let expected = try control.step([token], state: a)
            let actual = try bounded.step([token], state: b)
            #expect(actual.count == expected.count)
            for (x, y) in zip(actual, expected) { worst = max(worst, abs(x - y)) }
            #expect(worst <= 0.00001)
            #expect(actual.indices.max(by: { actual[$0] < actual[$1] }) == expected.indices.max(by: { expected[$0] < expected[$1] }))
        }
        let expected = try control.forward(tokens: [1, 5, 9], captureLayers: true)
        let actual = try bounded.forward(tokens: [1, 5, 9], captureLayers: true)
        #expect(actual.embed == expected.embed)
        #expect(actual.layerOutputs == expected.layerOutputs)
        #expect(actual.greedy == expected.greedy)
        #expect(zip(actual.logits, expected.logits).allSatisfy { abs($0 - $1) <= 0.00001 })
        print("QPACK_CPU_REFERENCE model=\(modelName) residentEmbedding=false residentHead=false rawCheckpointControl=true sameGreedy=true maxAbs=\(worst) syntheticOnly=true")
    }

    @Test func packedRowSlicesMatchRawCheckpointAcrossExpertBoundaries() throws {
        let source = Self.fixtures.appendingPathComponent("tiny-model-q4")
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".qpack")
        defer { try? FileManager.default.removeItem(at: output) }
        var packer = QpackRepacker(checkpointDir: source, outputDir: output)
        packer.log = { _ in }; try packer.repack()
        let raw = try Checkpoint(dir: source)
        let packed = try Checkpoint(dir: output, readPackedExpertSlices: true)
        let config = try QwenConfig(url: source.appendingPathComponent("config.json"))
        for layer in 0..<config.numHiddenLayers {
            for projection in ["gate_proj", "up_proj", "down_proj"] {
                let name = "model.layers.\(layer).mlp.switch_mlp.\(projection)"
                let rows = projection == "down_proj" ? config.hiddenSize : config.moeIntermediateSize
                for range in [0..<rows, (rows - 1)..<(rows + 2),
                              (config.numExperts - 1) * rows..<config.numExperts * rows] {
                    let actual = try packed.moduleWeightSlice(name, rowRange: range)
                    let expected = try raw.moduleWeightSlice(name, rowRange: range)
                    #expect(actual == expected)
                }
                #expect(throws: Checkpoint.Error.self) { try packed.moduleWeight(name) }
                #expect(throws: Checkpoint.Error.self) { try packed.moduleWeightSlice(name, rowRange: -1..<0) }
                #expect(throws: Checkpoint.Error.self) { try packed.moduleWeightSlice(name, rowRange: 0..<(config.numExperts * rows + 1)) }
            }
        }
    }

    @Test func diagnosticBoundsRefuseWorkBeforeStateMutation() throws {
        let directory = Self.fixtures.appendingPathComponent("tiny-model-q4")
        #expect(throws: Checkpoint.Error.self) { try QwenCPUModel(modelDir: directory, referenceTableTileRows: 0) }
        let model = try QwenCPUModel(modelDir: directory, referenceTableTileRows: 7)
        let state = QwenCPUModel.DecodeState()
        #expect(throws: Checkpoint.Error.self) { try model.step(Array(repeating: 1, count: 9), state: state) }
        #expect(state.position == 0)
        model.retainAllLayers = true
        #expect(throws: Checkpoint.Error.self) { try model.step([1], state: state) }
        #expect(state.position == 0)
        model.retainAllLayers = false
        #expect(throws: Checkpoint.Error.self) { try model.step([model.config.vocabSize], state: state) }
        state.position = 64
        #expect(throws: ContextWindowError.self) { try model.step([1], state: state) }
        #expect(state.position == 64)
    }

    @Test func mixedEightBitRoutersAndBF16ScalesMatchRawCPU() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        try Self.makeMixedSynthetic(in: source)
        let output = root.appendingPathComponent("mixed.qpack")
        var packer = QpackRepacker(checkpointDir: source, outputDir: output)
        packer.log = { _ in }; try packer.repack()
        let raw = try QwenCPUModel(modelDir: source)
        let bounded = try QwenCPUModel(modelDir: output, referenceTableTileRows: 7)
        let a = QwenCPUModel.DecodeState(), b = QwenCPUModel.DecodeState()
        #expect(raw.ckpt.quantSpec(for: "model.layers.0.mlp.gate")?.bits == 8)
        #expect(raw.ckpt.quantSpec(for: "model.layers.0.mlp.switch_mlp.gate_proj")?.bits == 4)
        var worst: Float = 0
        for token in [1, 5, 9, 3, 7] {
            let expected = try raw.step([token], state: a)
            let actual = try bounded.step([token], state: b)
            #expect(actual.count == expected.count)
            for (x, y) in zip(actual, expected) { worst = max(worst, abs(x - y)) }
            #expect(worst <= 0.00001)
            #expect(actual.indices.max(by: { actual[$0] < actual[$1] }) == expected.indices.max(by: { expected[$0] < expected[$1] }))
        }
        print("QPACK_CPU_REFERENCE model=synthetic-mixed-bf16 routerBits=8 expertBits=4 rawCheckpointControl=true sameGreedy=true maxAbs=\(worst) syntheticOnly=true")
    }

    /// Rewrites the existing untrained fixture, never trained model bytes.
    /// Integer code values are retained when expanding routers from 4 to 8
    /// bits; BF16 rounding applies to both independent comparison paths.
    private static func makeMixedSynthetic(in directory: URL) throws {
        let original = fixtures.appendingPathComponent("tiny-model-q4")
        let checkpoint = try Checkpoint(dir: original)
        var config = try Checkpoint.readConfig(inDirectory: original)
        var quant = config["quantization"] as! [String: Any]
        var header: [String: Any] = [:]
        var body = Data()
        for name in checkpoint.tensorNames.sorted() {
            let tensor = try checkpoint.rawTensor(name)
            var shape = tensor.info.shape, dtype = tensor.info.dtype, data = tensor.bytes
            if dtype == "F32" {
                var converted = Data()
                data.withUnsafeBytes { raw in
                    for offset in stride(from: 0, to: raw.count, by: 4) {
                        let bits = raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian
                        var bf16 = UInt16(bits >> 16).littleEndian
                        withUnsafeBytes(of: &bf16) { converted.append(contentsOf: $0) }
                    }
                }
                dtype = "BF16"; data = converted
            } else if dtype == "U32" && (name.hasSuffix(".mlp.gate.weight") || name.hasSuffix(".mlp.shared_expert_gate.weight")) {
                var converted = Data()
                data.withUnsafeBytes { raw in
                    for offset in stride(from: 0, to: raw.count, by: 4) {
                        let old = raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian
                        for group in 0..<2 {
                            var word: UInt32 = 0
                            for element in 0..<4 {
                                word |= ((old >> UInt32((group * 4 + element) * 4)) & 15) << UInt32(element * 8)
                            }
                            var little = word.littleEndian
                            withUnsafeBytes(of: &little) { converted.append(contentsOf: $0) }
                        }
                    }
                }
                shape[shape.count - 1] *= 2
                quant[String(name.dropLast(7))] = ["bits": 8, "group_size": 32]
                data = converted
            }
            header[name] = ["shape": shape, "dtype": dtype, "data_offsets": [body.count, body.count + data.count]]
            body.append(data)
        }
        config["quantization"] = quant
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: config, options: [.sortedKeys])
            .write(to: directory.appendingPathComponent("config.json"))
        let metadata = try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])
        var length = UInt64(metadata.count).littleEndian
        var file = withUnsafeBytes(of: &length) { Data($0) }
        file.append(metadata); file.append(body)
        try file.write(to: directory.appendingPathComponent("model.safetensors"))
    }
}
