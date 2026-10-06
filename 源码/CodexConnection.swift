import AppKit
import SQLite3

struct CodexThreadSummary {
    let id: String
    let title: String
    let cwd: String
    let rollout: URL
    let turnID: String
    let turnStatus: String
    let startedAt: Double

    var activity: CodexActivity {
        switch turnStatus {
        case "inProgress": return .working
        case "completed": return .completed
        case "failed": return .failed
        case "interrupted": return .interrupted
        default: return .idle
        }
    }
}

struct CodexSnapshot {
    let connected: Bool
    let threads: [CodexThreadSummary]
    let selected: CodexThreadSummary?
    let activity: CodexActivity
    let message: String
}

func codexThreadURL(_ id: String) -> URL? {
    guard UUID(uuidString: id) != nil else { return nil }
    return URL(string: "codex://threads/\(id)")
}

// Do not replay a completed historical turn on launch, or replay it every poll.
struct CodexAnimationLink {
    private var observedActiveTurn: String?
    private var selectedKey: String?
    private(set) var activity: CodexActivity = .idle

    mutating func update(_ snapshot: CodexSnapshot, enabled: Bool) -> CodexActivity? {
        let key = snapshot.selected.map { $0.id + "/" + $0.turnID }
        if key != selectedKey { observedActiveTurn = nil; selectedKey = key }
        let next: CodexActivity
        if !enabled { next = .idle; observedActiveTurn = nil }
        else if !snapshot.connected { next = .disconnected; observedActiveTurn = nil }
        else if snapshot.selected?.turnStatus == "inProgress" {
            observedActiveTurn = key
            next = snapshot.activity
        } else if let key = key, key == observedActiveTurn { next = snapshot.activity }
        else { next = .idle }
        guard next != activity else { return nil }
        activity = next
        return next
    }
}

enum CodexReadError: LocalizedError {
    case unavailable(String), incompatible(String)
    case sqlite(file: String, code: Int32, detail: String)

    var retryable: Bool {
        if case let .sqlite(_, code, _) = self {
            return [SQLITE_BUSY, SQLITE_LOCKED, SQLITE_SCHEMA, SQLITE_INTERRUPT].contains(code & 0xff)
        }
        return false
    }

    var errorDescription: String? {
        switch self {
        case let .unavailable(detail): return "无法读取本地 Codex 记录：\(detail)"
        case let .incompatible(detail): return "本地记录缺少必要字段：\(detail)。请检查 Codex 版本。"
        case let .sqlite(file, code, detail):
            if retryable { return "本地任务记录暂时繁忙，正在重试（\(file)，SQLite \(code)）。" }
            return "读取 \(file) 失败（SQLite \(code)）：\(detail)"
        }
    }
}

// Read-only connections: never writes Codex databases, prompts, config, or credentials.
private final class ReadOnlyDatabase {
    private var database: OpaquePointer?
    private let filename: String
    init(_ url: URL) throws {
        filename = url.lastPathComponent
        let result = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        guard result == SQLITE_OK else {
            let error = failure(result)
            if let database = database { sqlite3_close(database) }
            database = nil
            throw error
        }
        sqlite3_extended_result_codes(database, 1)
        sqlite3_busy_timeout(database, 100)
    }
    deinit { sqlite3_close(database) }

    private func failure(_ code: Int32) -> CodexReadError {
        let detail = sqlite3_errmsg(database).map { String(cString: $0) } ?? "读取失败"
        return .sqlite(file: filename, code: code, detail: detail)
    }

    func columns(_ table: String) throws -> Set<String> {
        Set(try query("PRAGMA table_info(\(table))").compactMap { $0["name"] })
    }

    func query(_ sql: String, values: [String] = []) throws -> [[String: String]] {
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepared == SQLITE_OK else { throw failure(prepared) }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient)
        }
        var rows: [[String: String]] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else {
                throw failure(result)
            }
            var row: [String: String] = [:]
            for column in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, column))
                row[name] = sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
            }
            rows.append(row)
        }
        return rows
    }
}

struct CodexEventTracker {
    private(set) var pending: [String: (name: String, since: Date)] = [:]
    private(set) var reviewing = false

    mutating func consume(_ data: Data, turnStartedAt: Double) {
        guard let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = record["payload"] as? [String: Any] else { return }
        let timestamp = record["timestamp"] as? String ?? ""
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp)
        if let date = date, date.timeIntervalSince1970 + 1 < turnStartedAt { return }
        let kind = payload["type"] as? String ?? ""
        // Extract only lifecycle metadata. Never stores arguments, text, reasoning, or outputs.
        if kind == "task_started" || kind == "task_complete" || kind == "turn_aborted" {
            pending.removeAll()
            reviewing = false
        } else if kind == "function_call" || kind == "custom_tool_call" {
            if let id = payload["call_id"] as? String, let name = payload["name"] as? String,
               id.count < 256, name.count < 256 {
                pending[id] = (name, date ?? Date())
            }
        } else if kind == "function_call_output" || kind == "custom_tool_call_output" {
            if let id = payload["call_id"] as? String { pending.removeValue(forKey: id) }
        }
        let itemType = (payload["item"] as? [String: Any])?["type"] as? String ?? ""
        if kind == "entered_review_mode" || itemType == "EnteredReviewMode" { reviewing = true }
        if kind == "exited_review_mode" || itemType == "ExitedReviewMode" { reviewing = false }
    }

    func activity(at now: Date) -> CodexActivity {
        if reviewing || pending.values.contains(where: { $0.name.lowercased().contains("review") }) { return .review }
        if pending.values.contains(where: { now.timeIntervalSince($0.since) >= 1.5 }) { return .waiting }
        return .working
    }
}

private final class CodexEventTail {
    private var file: URL?
    private var turnID = ""
    private var offset: UInt64 = 0
    private var remainder = Data()
    private var tracker = CodexEventTracker()

    func activity(for thread: CodexThreadSummary, at now: Date) -> CodexActivity {
        do {
            let handle = try FileHandle(forReadingFrom: thread.rollout)
            defer { try? handle.close() }
            let size = try handle.seekToEnd()
            var skipFirstLine = false
            if file != thread.rollout || turnID != thread.turnID || size < offset {
                file = thread.rollout
                turnID = thread.turnID
                tracker = CodexEventTracker()
                remainder = Data()
                offset = size > 262_144 ? size - 262_144 : 0
                skipFirstLine = offset > 0
            }
            if size - offset > 4_194_304 {
                offset = size - 262_144
                remainder = Data()
                tracker = CodexEventTracker()
                skipFirstLine = true
            }
            try handle.seek(toOffset: offset)
            let data = try handle.read(upToCount: Int(size - offset)) ?? Data()
            offset += UInt64(data.count)
            remainder.append(data)
            // A single very large tool payload is not needed for lifecycle tracking.
            if remainder.count > 4_194_304 { remainder = Data(); tracker = CodexEventTracker(); return .working }
            let lines = remainder.split(separator: 10, omittingEmptySubsequences: false)
            remainder = lines.last.map { Data($0) } ?? Data()
            for (index, line) in lines.dropLast().enumerated() where !(skipFirstLine && index == 0) {
                tracker.consume(Data(line), turnStartedAt: thread.startedAt)
            }
            return tracker.activity(at: now)
        } catch { return .working }
    }
}

final class CodexHistoryReader {
    let codexHome: URL
    var followingThreadID: String?
    private let tail = CodexEventTail()
    private var lastSnapshot: CodexSnapshot?

    init(codexHome: URL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODEX_HOME"] ??
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path)) {
        self.codexHome = codexHome
    }

    private func databaseURL(_ prefix: String) throws -> URL {
        let files = try FileManager.default.contentsOfDirectory(at: codexHome, includingPropertiesForKeys: nil)
        let candidates = files.compactMap { url -> (Int, URL)? in
            let name = url.lastPathComponent
            guard name.hasPrefix(prefix), name.hasSuffix(".sqlite"),
                  let version = Int(name.dropFirst(prefix.count).dropLast(".sqlite".count)) else { return nil }
            return (version, url)
        }
        guard let newest = candidates.max(by: { $0.0 < $1.0 }) else { throw CodexReadError.unavailable("找不到 \(prefix)*.sqlite") }
        return newest.1
    }

    func snapshot(clientRunning: Bool, at now: Date = Date()) -> CodexSnapshot {
        for attempt in 0..<3 {
            do {
                let snapshot = try readSnapshot(clientRunning: clientRunning, at: now)
                lastSnapshot = snapshot
                return snapshot
            } catch {
                if let error = error as? CodexReadError, error.retryable, attempt < 2 {
                    Thread.sleep(forTimeInterval: Double(attempt + 1) * 0.05)
                    continue
                }
                let retained = lastSnapshot
                let suffix = retained == nil ? "" : "\n以下为上次成功读取的任务，当前状态尚未确认。"
                return CodexSnapshot(connected: false, threads: retained?.threads ?? [], selected: retained?.selected,
                    activity: .disconnected, message: error.localizedDescription + suffix + "\n将自动重试，也可点击重新连接。")
            }
        }
        preconditionFailure("bounded retry loop always returns")
    }

    private func readSnapshot(clientRunning: Bool, at now: Date) throws -> CodexSnapshot {
            let metadata = try ReadOnlyDatabase(databaseURL("state_"))
            let history = try ReadOnlyDatabase(databaseURL("thread_history_"))
            let columns = try metadata.columns("threads")
            let missing = Set(["id", "rollout_path", "archived", "agent_path"]).subtracting(columns)
            guard missing.isEmpty, columns.contains("title") || columns.contains("name") else {
                throw CodexReadError.incompatible("threads：\(missing.sorted().joined(separator: ",")) / title 或 name")
            }
            let titleColumns = ["name", "title"].filter { columns.contains($0) }.map { "NULLIF(\($0),'')" }
            let title = "COALESCE(\((titleColumns + ["'Codex 任务'"]).joined(separator: ",")))"
            let order = ["recency_at_ms", "updated_at_ms", "updated_at*1000", "created_at_ms", "created_at*1000"]
                .filter { columns.contains(String($0.split(separator: "*")[0])) }
            guard !order.isEmpty else { throw CodexReadError.incompatible("threads：任务时间字段") }
            let ordering = order.count == 1 ? order[0] : "COALESCE(\(order.joined(separator: ",")))"
            let select = "SELECT id, \(title) AS title, \(columns.contains("cwd") ? "cwd" : "''") AS cwd, rollout_path FROM threads"
            let source = columns.contains("thread_source") ? " AND (thread_source='user' OR thread_source IS NULL)" : ""
            let sql = "\(select) WHERE archived=0 AND agent_path IS NULL\(source) ORDER BY \(ordering) DESC LIMIT 20"
            var rows = try metadata.query(sql)
            if let id = followingThreadID, !rows.contains(where: { $0["id"] == id }) {
                rows += try metadata.query("\(select) WHERE id=? AND archived=0 AND agent_path IS NULL", values: [id])
            }
            let turnColumns = try history.columns("thread_turns")
            let missingTurns = Set(["thread_id", "turn_id", "status"]).subtracting(turnColumns)
            guard missingTurns.isEmpty, turnColumns.contains("rollout_ordinal") || turnColumns.contains("started_at") else {
                throw CodexReadError.incompatible("thread_turns：\(missingTurns.sorted().joined(separator: ",")) / 轮次时间字段")
            }
            let turnOrder = turnColumns.contains("rollout_ordinal") ? "rollout_ordinal" : "started_at"
            let started = turnColumns.contains("started_at") ? "started_at" : "0"
            var threads: [CodexThreadSummary] = []
            let homePrefix = codexHome.resolvingSymlinksInPath().path + "/"
            for row in rows {
                guard let id = row["id"], let path = row["rollout_path"],
                      URL(fileURLWithPath: path).resolvingSymlinksInPath().path.hasPrefix(homePrefix) else { continue }
                let turn = try history.query("SELECT turn_id,status,\(started) AS started_at FROM thread_turns WHERE thread_id=? ORDER BY \(turnOrder) DESC LIMIT 1", values: [id]).first
                if let status = turn?["status"], !["inProgress", "completed", "failed", "interrupted", "idle"].contains(status) {
                    throw CodexReadError.incompatible("thread_turns：无法识别的 status")
                }
                threads.append(CodexThreadSummary(id: id, title: row["title"] ?? "Codex 任务", cwd: row["cwd"] ?? "",
                    rollout: URL(fileURLWithPath: path), turnID: turn?["turn_id"] ?? "",
                    turnStatus: turn?["status"] ?? "idle", startedAt: Double(turn?["started_at"] ?? "0") ?? 0))
            }
            let selected: CodexThreadSummary?
            if let id = followingThreadID { selected = threads.first { $0.id == id } }
            else { selected = threads.filter { $0.turnStatus == "inProgress" }.max { $0.startedAt < $1.startedAt } ?? threads.first }
            let activity: CodexActivity
            if !clientRunning { activity = .disconnected }
            else if let selected = selected, selected.turnStatus == "inProgress" { activity = tail.activity(for: selected, at: now) }
            else { activity = selected?.activity ?? .idle }
            return CodexSnapshot(connected: clientRunning, threads: threads, selected: selected, activity: activity,
                message: clientRunning ? "本地任务记录与事件 · 只读连接" : "Codex 未运行；保留最近任务入口")
    }
}

final class LocalCodexConnection {
    private let queue = DispatchQueue(label: "org.foreveryoungpet.codex-reader", qos: .utility)
    private let reader: CodexHistoryReader
    private var timer: DispatchSourceTimer?
    var onSnapshot: ((CodexSnapshot) -> Void)?

    init(reader: CodexHistoryReader = CodexHistoryReader()) { self.reader = reader }
    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1, leeway: .milliseconds(150))
        timer.setEventHandler { [weak self] in
            self?.poll()
        }
        self.timer = timer
        timer.resume()
    }
    private func poll() {
        let running = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.openai.codex" }
        let snapshot = reader.snapshot(clientRunning: running)
        DispatchQueue.main.async { [weak self] in self?.onSnapshot?(snapshot) }
    }
    func refresh() { queue.async { [weak self] in self?.poll() } }
    func freshSnapshot(_ completion: @escaping(CodexSnapshot)->Void) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let running = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.openai.codex" }
            let snapshot = self.reader.snapshot(clientRunning:running)
            DispatchQueue.main.async { completion(snapshot) }
        }
    }
    func follow(_ threadID: String?) { queue.async { [weak self] in self?.reader.followingThreadID = threadID } }
    func stop() { timer?.cancel(); timer = nil }
    deinit { stop() }
}
