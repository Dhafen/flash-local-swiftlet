import Foundation
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
    private var pending: String?
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
            shared.pending = nil
        }
    }
    @objc(recordMove:)
    class func recordMove(_ command: String) {
        shared.queue.async {
            guard shared.pending == command, !shared.actions.isEmpty else { return }
            let ids: [String:Int32] = ["FORWARD":11,"BACK":12,"LEFT":6,"RIGHT":7]
            if let id = ids[command] { shared.actions[shared.actions.count - 1][0] = id }
            shared.pending = nil
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
        frames.append(frame)
        actions.append(noop)
        if frames.count > 4 { frames.removeFirst(); actions.removeFirst() }
        guard frames.count == 4 else { return "WARMUP" }
        let image = try MLMultiArray(shape: [4,3,192,192], dataType: .float32)
        let history = try MLMultiArray(shape: [4,8], dataType: .int32)
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
        let prefix = try MLMultiArray(shape: [1,8], dataType: .int32)
        for i in 0..<8 { prefix[i] = NSNumber(value: noop[i]) }
        // Decode in the checkpoint's autoregressive order; padded logits are never choices.
        var generated: [Int] = []
        for slot in 0..<8 {
            let d = try MLDictionaryFeatureProvider(dictionary: ["context":ctx,"prefix":prefix])
            guard let logits = try decoder.prediction(from:d).featureValue(for:"logits")?.multiArrayValue,
                  logits.count == 8*23 else { throw PortError.output }
            var index = 0
            var value = -Double.infinity
            for c in 0..<vocab[slot] {
                let score = logits[[0, NSNumber(value:slot), NSNumber(value:c)]].doubleValue
                guard score.isFinite else { throw PortError.output }
                if score > value { index = c; value = score }
            }
            prefix[slot] = NSNumber(value:index)
            generated.append(index)
        }
        // Movement only: do not run arbitrary keys or clicks. The native Laya
        // supervisor checks fresh game state, and the input layer supports one key.
        let allowed = [11:"FORWARD",12:"BACK",6:"LEFT",7:"RIGHT",14:"BACK",15:"FORWARD",16:"LEFT",17:"RIGHT"]
        let result = generated.prefix(4).compactMap { allowed[$0] }.first ?? "WAIT"
        pending = result
        return result
    }
}
#endif
