import Foundation
#if os(iOS)
import CoreML

// Laya is a fixed-shape typed-choice encoder, not a text generator.
// Pre-tokenized inputs are generated with the checkpoint's original tokenizer.
final class SPLayaRuntime: @unchecked Sendable {
    static let shared = SPLayaRuntime()
    private let queue = DispatchQueue(label: "sp.laya.inference", qos: .userInitiated)
    private var model: MLModel?
    private var entries: [String: Entry] = [:]
    struct Entry: Decodable {
        let ids: [Int32]
        let markers: [Int32]
    }
    struct Manifest: Decodable {
        let schema: Int
        let entries: [String: Entry]
    }
    enum Failure: Error { case missing, malformed, invalidOutput }
    static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SPModels/Laya", isDirectory: true)
    }
    static func assetsPresent() -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: folder.appendingPathComponent("choices.json").path) &&
            (fm.fileExists(atPath: folder.appendingPathComponent("laya.mlpackage").path) ||
             fm.fileExists(atPath: folder.appendingPathComponent("laya.mlmodelc").path))
    }
    private func load() throws {
        if model != nil { return }
        let fm = FileManager.default
        let folder = Self.folder
        guard Self.assetsPresent() else { throw Failure.missing }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: folder.appendingPathComponent("choices.json")))
        guard manifest.schema == 1, manifest.entries.count == 36 else { throw Failure.malformed }
        let precompiled = folder.appendingPathComponent("laya.mlmodelc")
        var compiled = precompiled
        if !fm.fileExists(atPath: precompiled.path) {
            compiled = try MLModel.compileModel(at: folder.appendingPathComponent("laya.mlpackage"))
            // Reuse the compiled model on later app launches, but still work if copying fails.
            try? fm.copyItem(at: compiled, to: precompiled)
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        let loaded = try MLModel(contentsOf: compiled, configuration: configuration)
        entries = manifest.entries
        model = loaded
    }
    private func array(_ values: [Int32], count: Int, fill: Int32) throws -> MLMultiArray {
        let result = try MLMultiArray(shape: [1, NSNumber(value: count)], dataType: .int32)
        for index in 0..<count { result[index] = NSNumber(value: index < values.count ? values[index] : fill) }
        return result
    }
    func decide(key: String, candidate: String, completion: @escaping @Sendable (String) -> Void) {
        queue.async {
            do {
                try self.load()
                guard let entry = self.entries[key], let model = self.model,
                      !entry.ids.isEmpty, entry.ids.count <= 512, entry.markers.count == 2,
                      entry.markers.allSatisfy({ $0 >= 0 && Int($0) < entry.ids.count && entry.ids[Int($0)] == 50284 })
                else { throw Failure.malformed }
                let input = try MLDictionaryFeatureProvider(dictionary: [
                    "input_ids": try self.array(entry.ids, count: 512, fill: 50283),
                    "attention_mask": try self.array([Int32](repeating: 1, count: entry.ids.count), count: 512, fill: 0),
                    "marker_pos": try self.array(entry.markers, count: 5, fill: 0)
                ])
                guard let logits = try model.prediction(from: input).featureValue(for: "logits")?.multiArrayValue,
                      logits.count >= 2 else { throw Failure.invalidOutput }
                let a = logits[0].doubleValue
                let b = logits[1].doubleValue
                guard a.isFinite, b.isFinite else { throw Failure.invalidOutput }
                // The two real alternatives are action and WAIT; ignore padded logits.
                completion(a > b ? candidate : "WAIT")
            } catch {
                let e = error as NSError
                NSLog("Laya runtime failure: %@ %ld", e.domain, e.code)
                completion("ERR:LAYA")
            }
        }
    }
}
#endif
