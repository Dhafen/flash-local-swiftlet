import Foundation

@main
struct SPAIGraphTests {
    static func label(_ text: String, _ id: Int = 1, _ x: Double = 0.5, _ y: Double = 0.45) -> SPAIObservation.Label {
        .init(id: id, text: text, x: x, y: y)
    }
    static func frame(_ labels: [SPAIObservation.Label], _ light: Int = 8) -> SPAIObservation {
        .init(labels: labels, visualTags: ["landscape"], luminance: Array(repeating: light, count: 96))
    }
    static func main() throws {
        let suite = "sp-ai-test-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let h = SPAIHarness(defaults: defaults)
        let combat = frame([label("In combat")])
        let travel = frame([label("Out of range")])
        let loot = frame([label("Loot All")])
        let quest = frame([label("Complete Quest")])
        let blocked = frame([label("Game Menu"), label("Complete Quest", 2)])
        let dead = frame([label("You are dead")])
        precondition(h.plan(combat).role == .combat)
        precondition(h.plan(travel).role == .navigation)
        precondition(h.plan(loot).role == .loot)
        precondition(h.plan(quest).role == .quests)
        precondition(h.plan(blocked).skip)
        precondition(h.plan(dead).role == .recovery)
        precondition(h.validate("ATTACK", for: h.plan(blocked)) == .wait)
        precondition(h.validate("CLICK 1", for: h.plan(quest)).wire == "CLICK 1")
        precondition(h.validate("CLICK 22", for: h.plan(loot)) == .wait)
        precondition(h.validate("FORWARD", for: h.plan(travel)).wire == "FORWARD")
        precondition(h.validate("ATTACK", for: h.plan(travel)) == .wait)
        precondition(h.validate("INTERACT 1", for: h.plan(frame([label("Trade Merchant")]))) == .wait)
        precondition(h.validate("INTERACT 1", for: h.plan(frame([label("NPC", 1, 0.04, 0.45)]))) == .wait)
        precondition(h.validate("ATTACK now", for: h.plan(combat)) == .wait)
        let data = try JSONEncoder().encode(combat)
        precondition(SPAIObservation.decode(String(decoding: data, as: UTF8.self))?.labels.count == 1)
        precondition(!SPAIHarness.changed(combat, combat))
        precondition(SPAIHarness.changed(combat, frame([label("In combat")], 13)))
        precondition(SPAIHarness.changed(combat, loot))
        for _ in 0..<3 {
            h.didExecute("FORWARD", observation: travel)
            _ = h.plan(travel)
        }
        precondition(h.validate("FORWARD", for: h.plan(travel)) == .wait)
        precondition(h.stats["navigation:FORWARD"]?.unchanged == 3)
        h.didExecute("TARGET", observation: travel)
        h.resetTransient() // manual input invalidates feedback
        _ = h.plan(combat)
        precondition(h.stats["navigation:TARGET"] == nil)
        h.didExecute("ATTACK", observation: combat)
        _ = h.plan(frame([label("In combat")], 13))
        precondition(h.stats["combat:ATTACK"]?.changed == 1)
        let reloaded = SPAIHarness(defaults: defaults)
        precondition(reloaded.stats == h.stats)
        let encoded = String(decoding: defaults.data(forKey: SPAIHarness.memoryKey)!, as: UTF8.self)
        precondition(!encoded.contains("Out of range") && !encoded.contains("In combat"))
        print("AI graph routing, critic, feedback, persistence and invalidation passed")
    }
}
