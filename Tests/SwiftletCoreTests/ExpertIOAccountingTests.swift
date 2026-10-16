import Foundation
import Metal
import Testing
@testable import SwiftletCore

@Suite struct ExpertIOAccountingTests {
    @Test func concurrentMissesCountReturnedBytesAndHotHitsIssueNoReads() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let root = try ExpertCacheMetalTests.makeContainer()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try ExpertCache(containerDir: root, device: device, budgetBytes: 16 * 32_768)
        _ = try cache.buffers(layer: 0, experts: [0, 1, 2, 3])
        let cold = cache.ioStatistics
        #expect(cold.readCalls == 4)
        #expect(cold.returnedBytes == 4 * UInt64(ExpertCacheMetalTests.stride))
        #expect(cold.summedReadSeconds >= 0)
        let hot = try cache.buffers(layer: 0, experts: [3, 2, 1, 0])
        #expect(cache.hits == 4 && cache.misses == 4)
        #expect(cache.ioStatistics == cold)
        for (i, buffer) in hot.enumerated() {
            #expect(buffer.contents().load(as: UInt8.self) == UInt8(3 - i))
        }
        _ = try cache.buffers(layer: 1, experts: Array(0..<16))
        #expect(cache.evictions == 4)
        #expect(cache.ioStatistics.readCalls == 20)
        #expect(cache.ioStatistics.returnedBytes == 20 * UInt64(ExpertCacheMetalTests.stride))
        print("ORNITH_EXPERT_IO returnedBytesCounted=true hotHitsReadZero=true concurrentReadsCounted=true syntheticOnly=true")
    }
}
