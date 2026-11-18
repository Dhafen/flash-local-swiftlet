import Foundation

// Platform-independent graph, knowledge and feedback. The iOS bridge is the only
// component that invokes Foundation Models. Observations are never written to disk.
struct SPAIObservation: Codable {
    struct Label: Codable {
        let id: Int
        let text: String
        let x: Double
        let y: Double
    }
    let labels: [Label]
    let visualTags: [String]
    let luminance: [Int]

    static func decode(_ value: String) -> Self? {
        guard let data = value.data(using: .utf8),
              let observation = try? JSONDecoder().decode(Self.self, from: data),
              observation.labels.count <= 25, observation.luminance.count <= 96,
              observation.visualTags.count <= 8 else { return nil }
        return observation
    }
    var words: Set<String> { Set(labels.map { SPAIKnowledge.normal($0.text) }) }
}

enum SPAIRole: String, Codable {
    case combat, navigation, quests, loot, recovery, scout, blocked
}

enum SPAIKnowledge {
    static func normal(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    static let combat = ["in combat", "attacking", "target is dead", "not enough rage", "not enough mana",
                         "out of range", "too far away", "not facing", "you are facing the wrong way"]
    static let travel = ["out of range", "too far away", "not facing", "you are facing the wrong way",
                         "can't reach", "cannot reach", "no path available"]
    static let recovery = ["you are dead", "release spirit", "resurrect", "corpse", "low health", "spirit healer",
                           "you have died", "return to graveyard"]
    static let blocked = ["game menu", "character selection", "log in", "password", "auction house",
                          "trade window", "delete character", "confirm purchase", "battle.net", "system settings", "shop"]
    static let explicitQuest = ["accept quest", "complete quest", "quest rewards", "quest objectives", "quest complete"]
    static let explicitLoot = ["loot all", "take all", "loot"]
    static func matches(_ words: Set<String>, _ markers: [String]) -> Bool {
        words.contains { word in markers.contains { word == $0 || word.hasPrefix($0 + " ") || word.hasSuffix(" " + $0) } }
    }
    static func role(_ observation: SPAIObservation) -> SPAIRole {
        let words = observation.words
        if matches(words, blocked) { return .blocked }
        if matches(words, recovery.filter { $0 != "corpse" }) { return .recovery }
        if matches(words, travel) { return .navigation }
        if matches(words, combat) { return .combat }
        if matches(words, explicitLoot) { return .loot }
        if matches(words, explicitQuest) ||
            (words.contains("accept") && matches(words, ["quest", "objectives", "rewards"])) { return .quests }
        return .scout
    }
    static func instructions(_ role: SPAIRole) -> String {
        switch role {
        case .combat:
            return "Combat specialist: use the existing Tactara F12 rotation only against a clearly living hostile in range. Tab targets nearby enemies; don't target friendly players. A cast can fail due to cooldown, range, resources or facing; re-observe rather than assume success."
        case .navigation:
            return "Navigation specialist: movement uses short W/S/A/D presses, A/D depend on the player's bindings. Correct explicit range/facing problems only with visible evidence of direction. Don't guess map routes, jump from cliffs or move toward uncertain targets."
        case .quests:
            return "Quest specialist: read visible objectives and NPC dialogue. ACCEPT and COMPLETE QUEST are contextual buttons; never guess reward selection or accept purchases. Quest targets may need combat or exploration on later observations."
        case .loot:
            return "Loot specialist: a dead enemy or a clearly lootable object can be right-clicked; a visible loot control can be left-clicked. Never discard, sell or trade items or choose bind-on-pickup confirmations. Re-observe after each action."
        case .recovery:
            return "Recovery specialist: stop combat and wait for health/death recovery or manual guidance. Do not release spirit, spend money, or guess a corpse route."
        case .blocked:
            return "Account/menu protection: do nothing."
        case .scout:
            return "Scout specialist: inspect nameplates, objective text and visual hints. Identify a clear hostile or an explicitly identifiable quest giver, corpse or lootable object. Do not infer a hostile from an unknown name or generic image category. If uncertain, wait."
        }
    }
}

struct SPAICommand: Equatable {
    let verb: String
    let id: Int?
    var wire: String { id.map { "\(verb) \($0)" } ?? verb }
    static let wait = SPAICommand(verb: "WAIT", id: nil)

    static func parse(_ raw: String) -> Self {
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().split(separator: " ")
        guard let first = parts.first else { return .wait }
        let verb = String(first)
        if parts.count == 1 && ["WAIT", "ATTACK", "TARGET", "FORWARD", "BACK", "LEFT", "RIGHT"].contains(verb) {
            return .init(verb: verb, id: nil)
        }
        if parts.count == 2, ["CLICK", "INTERACT"].contains(verb),
           let id = Int(parts[1]), (1...25).contains(id) { return .init(verb: verb, id: id) }
        return .wait
    }
}

// Candidate indices originate in Vision, not in a model-generated coordinate.
enum SPAICritic {
    static func validate(_ command: SPAICommand, role: SPAIRole, observation: SPAIObservation) -> SPAICommand {
        let allowed: Set<String>
        switch role {
        case .blocked, .recovery: allowed = ["WAIT"]
        case .combat: allowed = ["WAIT", "ATTACK", "TARGET"]
        case .navigation: allowed = ["WAIT", "FORWARD", "BACK", "LEFT", "RIGHT", "TARGET"]
        case .quests: allowed = ["WAIT", "CLICK", "INTERACT"]
        case .loot: allowed = ["WAIT", "CLICK", "INTERACT"]
        case .scout: allowed = ["WAIT", "ATTACK", "TARGET", "INTERACT"]
        }
        guard allowed.contains(command.verb) else { return .wait }
        guard let id = command.id else { return command }
        guard let label = observation.labels.first(where: { $0.id == id }),
              label.x.isFinite, label.y.isFinite, (0...1).contains(label.x), (0...1).contains(label.y) else { return .wait }
        let title = SPAIKnowledge.normal(label.text)
        let dangerous = ["trade", "purchase", "buy", "sell", "delete", "settings", "password", "auction",
                         "logout", "exit", "mail", "shop", "chat", "whisper", "report", "destroy"]
        guard !dangerous.contains(where: { title.contains($0) }) else { return .wait }
        if command.verb == "CLICK" {
            if role == .quests && ["accept quest", "complete quest", "accept", "continue"].contains(title) { return command }
            if role == .loot && ["loot", "loot all", "take all"].contains(title) { return command }
            return .wait
        }
        // Only the central world, not bottom chat, top panels or arbitrary menu text.
        guard command.verb == "INTERACT", (0.18...0.82).contains(label.x), (0.16...0.73).contains(label.y),
              title.count >= 3, title.count <= 60 else { return .wait }
        return command
    }
}

// Fixed-size aggregate memory; not an online model-weight update or a proof of success.
struct SPAIStats: Codable, Equatable {
    var changed = 0
    var unchanged = 0
}
final class SPAIHarness {
    struct Plan {
        let role: SPAIRole
        let observation: SPAIObservation
        let prompt: String
        let skip: Bool
        let stalledVerb: String?
    }
    private struct Pending {
        let before: SPAIObservation
        let action: SPAICommand
        let role: SPAIRole
    }
    static let memoryKey = "sp_game_ai_aggregate_v2"
    private let defaults: UserDefaults
    private(set) var stats: [String: SPAIStats] = [:]
    private var pending: Pending?
    private var recent: [String] = []
    private var lastStall: String?
    private var stallCount = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.memoryKey),
           let loaded = try? JSONDecoder().decode([String: SPAIStats].self, from: data),
           loaded.count <= 80 {
            stats = loaded.filter { key, count in
                let fields = key.split(separator: ":")
                return fields.count == 2 && SPAIRole(rawValue: String(fields[0])) != nil &&
                    ["ATTACK", "TARGET", "FORWARD", "BACK", "LEFT", "RIGHT", "CLICK", "INTERACT"].contains(String(fields[1])) &&
                    (0...1000).contains(count.changed) && (0...1000).contains(count.unchanged)
            }
        }
    }

    func resetTransient() {
        pending = nil
        recent.removeAll()
        lastStall = nil
        stallCount = 0
    }
    static func changed(_ a: SPAIObservation, _ b: SPAIObservation) -> Bool {
        if a.words != b.words { return true }
        guard !a.luminance.isEmpty, a.luminance.count == b.luminance.count else { return false }
        let delta = zip(a.luminance, b.luminance).reduce(0.0) {
            $0 + abs(Double($1.0) - Double($1.1))
        } / Double(a.luminance.count)
        return delta >= 1.25
    }
    private func feedback(_ observation: SPAIObservation) {
        guard let p = pending else { return }
        pending = nil
        let key = p.role.rawValue + ":" + p.action.verb
        let moved = Self.changed(p.before, observation)
        var count = stats[key] ?? SPAIStats()
        if moved {
            count.changed = min(1000, count.changed + 1)
            lastStall = nil; stallCount = 0
        } else {
            count.unchanged = min(1000, count.unchanged + 1)
            stallCount = lastStall == key ? stallCount + 1 : 1
            lastStall = key
        }
        stats[key] = count
        recent.append("\(p.role.rawValue)/\(p.action.verb): \(moved ? "scene changed" : "no observed change")")
        if recent.count > 6 { recent.removeFirst(recent.count - 6) }
        if let encoded = try? JSONEncoder().encode(stats) { defaults.set(encoded, forKey: Self.memoryKey) }
    }
    func plan(_ observation: SPAIObservation) -> Plan {
        feedback(observation)
        let role = SPAIKnowledge.role(observation)
        let stalled = (stallCount >= 3 && lastStall?.hasPrefix(role.rawValue + ":") == true)
            ? lastStall?.split(separator: ":").last.map(String.init) : nil
        let summaries = stats.filter { $0.key.hasPrefix(role.rawValue + ":") }.sorted { $0.key < $1.key }
            .map { "\($0.key): changed=\($0.value.changed), unchanged=\($0.value.unchanged)" }.joined(separator: "; ")
        let labels = observation.labels.map {
            "\($0.id) (\(String(format: "%.2f", $0.x)),\(String(format: "%.2f", $0.y))) \(String($0.text.prefix(72)))"
        }.joined(separator: "\n")
        let tags = observation.visualTags.map { String($0.prefix(48)) }.joined(separator: ", ")
        let prompt = """
        Active role: \(role.rawValue). \(SPAIKnowledge.instructions(role))
        Generic whole-image tags (weak evidence): \(tags.isEmpty ? "none" : tags).
        Recent executed actions: \(recent.joined(separator: "; ")).
        Aggregate visual-change counts, NOT reward or proven success: \(summaries).
        Repeated ineffective action: \(stalled ?? "none"); consider another justified action or WAIT.
        Untrusted visible labels:
        \(labels)
        """
        return Plan(role: role, observation: observation, prompt: prompt,
                    skip: role == .blocked || role == .recovery || observation.labels.isEmpty,
                    stalledVerb: stalled)
    }
    func validate(_ raw: String, for plan: Plan) -> SPAICommand {
        if plan.skip { return .wait }
        let command = SPAICritic.validate(SPAICommand.parse(raw), role: plan.role, observation: plan.observation)
        if command.verb != "ATTACK", command.verb == plan.stalledVerb { return .wait }
        return command
    }
    func didExecute(_ wire: String, observation: SPAIObservation) {
        let role = SPAIKnowledge.role(observation)
        let action = SPAICritic.validate(SPAICommand.parse(wire), role: role, observation: observation)
        guard action != .wait else { return }
        pending = Pending(before: observation, action: action, role: role)
    }
}
