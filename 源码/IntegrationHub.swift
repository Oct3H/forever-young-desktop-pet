import AppKit

enum LinkedSource: String, CaseIterable, Codable {
    case codex, vscode, pycharm
    var label: String { switch self { case .codex: return "Codex"; case .vscode: return "VS Code"; case .pycharm: return "PyCharm" } }
    var bundleID: String { switch self { case .codex: return "com.openai.codex"; case .vscode: return "com.microsoft.VSCode"; case .pycharm: return "com.jetbrains.pycharm.ce" } }
}

struct LinkedEvent: Codable {
    let version: Int
    let source: LinkedSource
    let instance: String
    let sequence: Int
    let sentAt: Double
    let state: CodexActivity
    let runID: String
    let title: String
    let project: String
    let activeCount: Int
    var metadata: [String:String]? = nil
    var actions: [String]? = nil
    var supportedActions: [String] { actions ?? (source == .vscode ? ["run","build","test","stop"] : source == .pycharm ? ["run","test","stop"] : []) }
    var animation: CodexActivity { activeCount > 0 && state.isTransient ? .working : state }
    var key: String { source.rawValue + ":" + instance }
    var object: [String: Any] { ["source":source.rawValue,"label":source.label,"instance":instance,"state":state.rawValue,"title":title,"project":project,"activeCount":activeCount,"sentAt":sentAt,"actions":supportedActions,"metadata":metadata ?? [:]] }
    static func parse(_ data: Data, now: Date = Date()) -> LinkedEvent? {
        guard data.count <= 65_536, let event = try? JSONDecoder().decode(Self.self, from: data), event.version == 1,
              UUID(uuidString: event.instance) != nil, event.sequence >= 0, event.activeCount >= 0, event.activeCount < 1000,
              abs(now.timeIntervalSince1970 * 1000 - event.sentAt) < 40_000,
              event.title.utf8.count <= 2048, event.project.utf8.count <= 4096, event.runID.utf8.count <= 256,
              event.actions.map({$0.count <= 8 && $0.allSatisfy { ["run","chooseRun","runFile","build","test","stop","openProblems","openConsole"].contains($0) }}) ?? true else { return nil }
        guard event.metadata.map({$0.count <= 20 && $0.allSatisfy { $0.key.utf8.count <= 64 && $0.value.utf8.count <= 4096 }}) ?? true else { return nil }
        return event
    }
}

struct PetNotice {
    let event: LinkedEvent
    let priority: Int
    let expires: Date
}

/// All three inputs remain subscribed. Primary affects animation and tie-breaking only.
final class IntegrationHub {
    private(set) var events: [String: LinkedEvent] = [:]
    private(set) var queue: [PetNotice] = []
    var primary = "auto"
    var frontmost: LinkedSource?
    private var seen: [String: Int] = [:]
    private var transitions: [String: String] = [:]
    private var changedAt: [String:Double] = [:]
    private(set) var revision = 0
    var onChange: (() -> Void)?
    var onTransition: ((LinkedEvent) -> Void)?

    var selectedSource: LinkedSource? {
        if let fixed = LinkedSource(rawValue: primary) { return fixed }
        if let frontmost = frontmost, latest(frontmost) != nil { return frontmost }
        return events.values.filter { $0.activeCount > 0 }.max { (changedAt[$0.key] ?? 0) < (changedAt[$1.key] ?? 0) }?.source ??
            (latest(.codex).map { $0.state != .disconnected } == true ? .codex : events.values.filter { $0.state != .disconnected }.max { $0.sentAt < $1.sentAt }?.source)
    }
    func latest(_ source: LinkedSource) -> LinkedEvent? {
        let all = events.values.filter { $0.source == source }
        return all.filter { $0.activeCount > 0 }.max { (changedAt[$0.key] ?? 0) < (changedAt[$1.key] ?? 0) } ?? all.max { $0.sentAt < $1.sentAt }
    }
    var selected: LinkedEvent? { selectedSource.flatMap { latest($0) } }
    func receive(_ event: LinkedEvent, now: Date = Date(), notify: Bool = true) {
        guard seen[event.key].map({ event.sequence > $0 }) ?? true else { return }
        seen[event.key] = event.sequence
        let previous = events[event.key]
        events[event.key] = event
        let transition = event.runID + ":" + event.state.rawValue
        if transitions[event.key] != transition {
            transitions[event.key] = transition
            changedAt[event.key] = event.sentAt
            // Startup/heartbeat snapshots must not replay previous completions.
            if notify && !(previous == nil && (event.state.isTransient || event.state == .idle || event.state == .disconnected)) {
                onTransition?(event)
                let severity = event.state == .failed ? 100 : event.state.isTransient ? 90 : 70
                let priority = severity
                if !event.state.isTransient { queue.removeAll { $0.event.key == event.key && !$0.event.state.isTransient } }
                queue.append(PetNotice(event: event, priority: priority, expires: now.addingTimeInterval(120)))
                if queue.count > 30 { queue.removeFirst() }
            }
        }
        if previous?.state != event.state || previous?.title != event.title || previous?.activeCount != event.activeCount || previous?.metadata != event.metadata {
            revision += 1; onChange?()
        }
    }
    func takeNotice(now: Date = Date()) -> PetNotice? {
        queue.removeAll { $0.expires < now }
        func priority(_ index: Int) -> Int { queue[index].priority + (queue[index].event.source == selectedSource ? 5 : 0) }
        guard let index = queue.indices.max(by: { priority($0) == priority($1) ? $0 > $1 : priority($0) < priority($1) }) else { return nil }
        return queue.remove(at: index)
    }
    func expire(now: Date = Date()) {
        queue.removeAll { $0.expires < now }
        let stale = events.filter { $0.value.source != .codex && now.timeIntervalSince1970 * 1000 - $0.value.sentAt > 35_000 }
        guard !stale.isEmpty else { return }
        for (key, _) in stale { events.removeValue(forKey:key); transitions.removeValue(forKey:key); changedAt.removeValue(forKey:key) }
        revision += 1; onChange?()
    }
    var object: [String: Any] { ["primary":primary,"selected":selectedSource?.rawValue ?? "codex","sources":LinkedSource.allCases.map { source -> [String: Any] in
        var value = latest(source)?.object ?? ["source":source.rawValue,"label":source.label,"state":"disconnected","title":"","activeCount":0]
        value["connected"] = latest(source).map { $0.state != .disconnected } ?? false; return value
    }] }
}

/// Atomic, user-local JSON mailbox. No server, shell commands, or arbitrary plugin loading.
final class IDEBridge {
    static var defaultRoot: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/ForeverYoungPet/Bridge") }
    let root: URL
    var onEvent: ((LinkedEvent) -> Void)?
    private var timer: Timer?
    private var sequences: [String: Int] = [:]
    init(root: URL = IDEBridge.defaultRoot) { self.root = root }
    func start() throws {
        for name in ["events","commands","acks"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true, attributes:[.posixPermissions:0o700])
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats:true) { [weak self] _ in self?.poll() }
        poll()
    }
    func poll(now: Date = Date()) {
        guard let files = try? FileManager.default.contentsOfDirectory(at:root.appendingPathComponent("events"), includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey]) else { return }
        for url in files.prefix(100) where url.pathExtension == "json" {
            guard let values = try? url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey]), values.isRegularFile == true,
                  values.isSymbolicLink != true, (values.fileSize ?? 0) <= 65_536,
                  let data = try? Data(contentsOf:url), let event = LinkedEvent.parse(data,now:now), event.source != .codex,
                  sequences[event.key].map({event.sequence > $0}) ?? true else { continue }
            sequences[event.key] = event.sequence; onEvent?(event)
        }
    }
    func command(_ action: String, target: LinkedEvent, expectedToken: String? = nil) throws {
        guard target.supportedActions.contains(action), target.source != .codex,
              Date().timeIntervalSince1970 * 1000 - target.sentAt < 35_000 else { throw CocoaError(.validationMissingMandatoryProperty) }
        let id = UUID().uuidString
        var object: [String: Any] = ["version":1,"id":id,"source":target.source.rawValue,"instance":target.instance,"action":action,"sentAt":Date().timeIntervalSince1970 * 1000]
        if let expectedToken = expectedToken { object["expectedToken"] = expectedToken }
        let url = root.appendingPathComponent("commands/\(target.instance)-\(id).json")
        try JSONSerialization.data(withJSONObject:object).write(to:url,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
    }
    func stop() { timer?.invalidate(); timer = nil }
}
