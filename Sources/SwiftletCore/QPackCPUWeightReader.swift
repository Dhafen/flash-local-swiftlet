import Foundation

/// Diagnostic-only access to selected expert rows. No mmap of routed weights,
/// full-stack dequantization, cache or GPU allocation is available here.
final class QPackCPUWeightReader {
    private let reader: QpackExpertReader
    init(directory: URL) throws {
        _ = try Qpack.verify(containerDir: directory)
        reader = try QpackExpertReader(containerDir: directory)
        guard (1...(16 << 20)).contains(reader.layout.expertStride),
              (1...1024).contains(reader.layout.expertCount), (1...128).contains(reader.layout.layerCount) else {
            throw Checkpoint.Error.badShape("reference expert stride exceeds 16 MiB")
        }
        for section in reader.layout.sections {
            guard section.offset >= 0, section.size > 0, section.size <= reader.layout.expertStride,
                  section.offset <= reader.layout.expertStride - section.size,
                  (1...2).contains(section.shape.count), section.shape.allSatisfy({ (1...131072).contains($0) }),
                  ["U32", "F32", "F16", "BF16"].contains(section.dtype) else {
                throw Checkpoint.Error.badShape("reference section bounds")
            }
            var expected = section.dtype == "U32" || section.dtype == "F32" ? 4 : 2
            for dimension in section.shape {
                let next = expected.multipliedReportingOverflow(by: dimension)
                guard !next.overflow else { throw Checkpoint.Error.badShape("reference section shape overflow") }
                expected = next.partialValue
            }
            guard expected == section.size else { throw Checkpoint.Error.badShape("reference section size") }
        }
    }
    private func components(_ path: String) -> [Substring] {
        let name = path.hasPrefix("language_model.") ? String(path.dropFirst(15)) : path
        return name.split(separator: ".")
    }
    func handles(_ path: String) -> Bool {
        let p = components(path)
        return p.count == 6 && p[0] == "model" && p[1] == "layers"
            && p[3] == "mlp" && p[4] == "switch_mlp"
    }
    func rows(_ path: String, range: Range<Int>, quant: Checkpoint.QuantSpec?) throws -> [Float] {
        let p = components(path)
        guard handles(path), let layer = Int(p[2]), (0..<reader.layout.layerCount).contains(layer),
              let w = reader.section(String(p[5]) + ".weight"), w.shape.count == 2,
              w.shape.allSatisfy({ $0 > 0 }) else { throw Checkpoint.Error.badShape(path) }
        let rowsPerExpert = w.shape[0]
        let (totalRows, overflow) = rowsPerExpert.multipliedReportingOverflow(by: reader.layout.expertCount)
        guard !overflow, range.lowerBound >= 0, range.upperBound <= totalRows else {
            throw Checkpoint.Error.badShape("reference expert row range")
        }
        let packed = w.dtype == "U32"
        let scale = reader.section(String(p[5]) + ".scales")
        let bias = reader.section(String(p[5]) + ".biases")
        let input: Int
        if packed {
            guard let q = quant, q.mode == Checkpoint.affineMode, q.bits == 4 || q.bits == 8,
                  q.groupSize > 0, let scale, let bias,
                  scale.shape.count == 2, bias.shape == scale.shape,
                  scale.shape[0] == rowsPerExpert, scale.dtype == bias.dtype else {
                throw Checkpoint.Error.badShape("reference affine layout")
            }
            let result = w.shape[1].multipliedReportingOverflow(by: 32 / q.bits)
            guard !result.overflow, result.partialValue % q.groupSize == 0,
                  scale.shape[1] == result.partialValue / q.groupSize else {
                throw Checkpoint.Error.badShape("reference affine groups")
            }
            input = result.partialValue
        } else { input = w.shape[1] }
        let count = range.count.multipliedReportingOverflow(by: input)
        guard !count.overflow, count.partialValue <= (64 << 20) / 4 else {
            throw Checkpoint.Error.badShape("reference row slice exceeds 64 MiB")
        }
        var output = [Float](repeating: 0, count: count.partialValue)
        guard !range.isEmpty else { return output }
        var blob = Data(count: reader.layout.expertStride)
        var loadedExpert = -1
        for row in range {
            let expert = row / rowsPerExpert, localRow = row % rowsPerExpert
            if loadedExpert != expert {
                try blob.withUnsafeMutableBytes { try reader.readExpert(layer: layer, expert: expert, into: $0.baseAddress!) }
                loadedExpert = expert
            }
            try blob.withUnsafeBytes { raw in
                for column in 0..<input {
                    let value: Float
                    if packed, let q = quant, let scale, let bias {
                        let wordIndex = localRow * w.shape[1] + column / (32 / q.bits)
                        let offset = w.offset + wordIndex * 4
                        guard offset >= w.offset, offset + 4 <= w.offset + w.size,
                              offset + 4 <= raw.count else { throw Checkpoint.Error.badShape(path) }
                        let word = raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian
                        let shift = (column % (32 / q.bits)) * q.bits
                        let integer = (word >> UInt32(shift)) & UInt32((1 << q.bits) - 1)
                        let group = localRow * scale.shape[1] + column / q.groupSize
                        value = try scalar(raw, section: scale, element: group) * Float(integer)
                            + scalar(raw, section: bias, element: group)
                    } else {
                        value = try scalar(raw, section: w, element: localRow * input + column)
                    }
                    output[(row - range.lowerBound) * input + column] = value
                }
            }
        }
        return output
    }
    private func scalar(_ raw: UnsafeRawBufferPointer, section: Qpack.Section, element: Int) throws -> Float {
        let stride = section.dtype == "F32" ? 4 : 2
        guard ["F32", "F16", "BF16"].contains(section.dtype), element >= 0,
              element < section.size / stride, section.offset >= 0,
              section.offset <= raw.count - section.size else { throw Checkpoint.Error.badShape(section.name) }
        let offset = section.offset + element * stride
        if section.dtype == "F32" {
            return Float(bitPattern: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian)
        }
        let word = raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self).littleEndian
        return section.dtype == "F16" ? Float(Float16(bitPattern: word)) : Float(bitPattern: UInt32(word) << 16)
    }
}
