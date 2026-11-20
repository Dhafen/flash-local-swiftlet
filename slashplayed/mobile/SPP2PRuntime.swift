import Foundation

// Upstream uses categorical sampling (temperature 1 by default), not argmax.
// Keep the whole legal vocabulary, including no-op, and never force movement.
enum SPP2PAction {
    static func sample(_ logits: [Double], uniform: Double) -> Int? {
        guard let peak = logits.max(), peak.isFinite,
              logits.allSatisfy({ $0.isFinite }), uniform >= 0, uniform < 1 else { return nil }
        let weights = logits.map { exp($0 - peak) }
        let total = weights.reduce(0,+)
        guard total.isFinite, total > 0 else { return nil }
        var remaining = uniform * total
        for (i, weight) in weights.enumerated() {
            remaining -= weight
            if remaining < 0 { return i }
        }
        return weights.lastIndex(where: { $0 > 0 })
    }
    // Pinned upstream action_mapping.py keyboard IDs; retain exactly one
    // supported movement, not arbitrary keys or clicks.
    static let moves = [6:"LEFT",7:"RIGHT",8:"STRAFE_RIGHT",10:"STRAFE_LEFT",
                        11:"FORWARD",12:"BACK",14:"BACK",15:"FORWARD",16:"LEFT",17:"RIGHT"]
    static let executedIDs: [String:Int32] = ["FORWARD":11,"BACK":12,"LEFT":6,"RIGHT":7,
                                              "STRAFE_LEFT":10,"STRAFE_RIGHT":8]
    static func movement(_ ids: [Int]) -> String {
        ids.prefix(4).compactMap { moves[$0] }.first ?? "WAIT"
    }
}

#if os(iOS)
import CoreML

// Optional 4-frame policy. Model export must have produced its validation manifest.
@objc(SPP2PBridge)
final class SPP2PBridge: NSObject, @unchecked Sendable {
    static let shared = SPP2PBridge()
    private let queue = DispatchQueue(label: "sp.pixel2play.inference", qos: .utility)
    private var models: (MLModel, MLModel)?
    private var frames: [Data] = []
    private var actions: [[Int32]] = []
    private var awaitingFeedback = false
    private var inputs: (image: MLMultiArray, history: MLMultiArray, prefix: MLMultiArray)?
    private let size = 3 * 192 * 192
    private let vocab = [20,20,20,20,4,4,23,17]
    private let noop: [Int32] = [0,0,0,0,0,0,11,8]
    private static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SPModels/Pixel2Play", isDirectory: true)
    }
    struct Manifest: Decodable {
        let schema: Int
        let frames: Int
        let vocab_sizes: [Int]
        let weights_used: Int
        let validation: [String: [Metrics]]
        struct Metrics: Decodable { let nrmse: Double }
    }
    enum PortError: Error { case model, shape, output }
    @objc class func available() -> Bool {
        let folder = Self.folder
        return ["manifest.json","policy.mlpackage","decoder.mlpackage"].allSatisfy {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
    }
    @objc class func resetHistory() {
        shared.queue.async {
            shared.frames.removeAll()
            shared.actions.removeAll()
            shared.awaitingFeedback = false
        }
    }
    @objc(recordMove:)
    class func recordMove(_ command: String) {
        shared.queue.async {
            guard shared.awaitingFeedback, !shared.actions.isEmpty,
                  let id = SPP2PAction.executedIDs[command] else { return }
            shared.actions[shared.actions.count - 1][0] = id
            shared.awaitingFeedback = false
        }
    }
    private func load() throws -> (MLModel, MLModel) {
        if let models { return models }
        let m = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: Self.folder.appendingPathComponent("manifest.json")))
        guard m.schema == 1, m.frames == 4, m.vocab_sizes == vocab, m.weights_used >= 100_000_000,
              ["policy","decoder"].allSatisfy({ key in
                  guard let values = m.validation[key], values.count >= 2 else { return false }
                  return values.allSatisfy { $0.nrmse.isFinite && (0...0.08).contains($0.nrmse) }
              }) else { throw PortError.model }
        let cfg = MLModelConfiguration()
        cfg.computeUnits = .cpuAndNeuralEngine
        func open(_ name: String) throws -> MLModel {
            let compiled = try MLModel.compileModel(at: Self.folder.appendingPathComponent(name + ".mlpackage"))
            return try MLModel(contentsOf: compiled, configuration: cfg)
        }
        let loaded = (try open("policy"), try open("decoder"))
        models = loaded
        return loaded
    }
    @objc(predictFrame:completion:)
    class func predictFrame(_ frame: Data, completion: @escaping @Sendable (String) -> Void) {
        shared.queue.async {
            do {
                completion(try shared.predict(frame))
            } catch {
                let e = error as NSError
                NSLog("Pixel2Play experiment: %@ %ld", e.domain, e.code)
                completion("ERR:P2P")
            }
        }
    }
    private func predict(_ frame: Data) throws -> String {
        guard frame.count == size else { throw PortError.shape }
        let (policy, decoder) = try load()
        awaitingFeedback = false
        frames.append(frame)
        actions.append(noop)
        if frames.count > 4 { frames.removeFirst(); actions.removeFirst() }
        guard frames.count == 4 else { return "WARMUP" }
        if inputs == nil {
            inputs = (try MLMultiArray(shape: [4,3,192,192], dataType: .float32),
                      try MLMultiArray(shape: [4,8], dataType: .int32),
                      try MLMultiArray(shape: [1,8], dataType: .int32))
        }
        guard let (image, history, prefix) = inputs else { throw PortError.shape }
        let dest = image.dataPointer.bindMemory(to: Float32.self, capacity: image.count)
        for i in 0..<4 {
            frames[i].withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                for j in 0..<size { dest[i*size+j] = Float32(raw[j]) / 255 }
            }
            for j in 0..<8 { history[i*8+j] = NSNumber(value: actions[i][j]) }
        }
        let p = try MLDictionaryFeatureProvider(dictionary: ["frames":image,"action_history":history])
        guard let ctx = try policy.prediction(from: p).featureValue(for:"context")?.multiArrayValue,
              ctx.count == 1024 else { throw PortError.output }
        for i in 0..<8 { prefix[i] = NSNumber(value: noop[i]) }
        // Decode in the checkpoint's autoregressive order; padded logits are never choices.
        var generated: [Int] = []
        // Only the four keyboard slots can affect the movement adapter.
        // Mouse slots are causally later and cannot change these logits.
        for slot in 0..<4 {
            let d = try MLDictionaryFeatureProvider(dictionary: ["context":ctx,"prefix":prefix])
            guard let logits = try decoder.prediction(from:d).featureValue(for:"logits")?.multiArrayValue,
                  logits.count == 8*23 else { throw PortError.output }
            let scores = (0..<vocab[slot]).map { c in
                logits[[0, NSNumber(value:slot), NSNumber(value:c)]].doubleValue
            }
            guard let index = SPP2PAction.sample(scores, uniform: Double.random(in: 0..<1)) else {
                throw PortError.output
            }
            prefix[slot] = NSNumber(value:index)
            generated.append(index)
        }
        awaitingFeedback = true
        return SPP2PAction.movement(generated)
    }
}
#endif
