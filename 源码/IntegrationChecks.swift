import AppKit

enum IntegrationCheckError: Error { case failed(String) }
func require(_ value: Bool, _ message: String) throws {
    if !value { throw IntegrationCheckError.failed(message) }
}

func runCodexAnimationChecks() throws -> [String] {
    var pet = PetRuntime()
    pet.handle(.pointer(dx: 300, dy: 0), at: 0)
    for state in [CodexActivity.working, .waiting, .review, .completed, .failed, .interrupted] {
        pet.handle(.codexState(state), at: 1_000)
        let frame = pet.frame(at: 1_100)
        try require(frame.row == state.animationRow && frame.mode == "codex-" + state.rawValue, "Codex state \(state)")
    }
    pet.handle(.codexState(.working), at: 2_000)
    pet.handle(.hover(true, allowJump: true), at: 2_001)
    try require(pet.frame(at: 2_002).mode == "jumping", "hover preempts Codex animation")
    try require(pet.frame(at: 3_000).mode == "codex-working", "work resumes after one jump")
    pet.handle(.greet(duration: 2_912), at: 3_001)
    try require(pet.frame(at: 4_000).mode == "waving", "click preempts Codex animation")
    pet.handle(.drag(-10), at: 4_001)
    try require(pet.frame(at: 4_002).mode == "dragging-left", "drag preempts Codex animation")
    pet.handle(.drag(nil), at: 4_003)
    try require(pet.frame(at: 4_004).mode == "codex-working", "release resumes Codex animation")
    pet.handle(.codexState(.completed), at: 5_000)
    try require(pet.frame(at: 6_000).mode == "looking", "completion returns to gaze after one wave")

    let id = "01a0fae6-ac9f-7820-ad67-8d7a422d5752"
    func snapshot(_ status: String, _ activity: CodexActivity, _ turn: String = "turn") -> CodexSnapshot {
        let thread = CodexThreadSummary(id: id, title: "测试任务", cwd: "/tmp", rollout: URL(fileURLWithPath: "/tmp/test.jsonl"),
            turnID: turn, turnStatus: status, startedAt: 0)
        return CodexSnapshot(connected: true, threads: [thread], selected: thread, activity: activity, message: "fixture")
    }
    var link = CodexAnimationLink()
    try require(link.update(snapshot("completed", .completed), enabled: true) == nil, "no historical celebration on launch")
    try require(link.update(snapshot("inProgress", .working, "new"), enabled: true) == .working, "new turn starts working")
    try require(link.update(snapshot("inProgress", .waiting, "new"), enabled: true) == .waiting, "tool wait transition")
    try require(link.update(snapshot("completed", .completed, "new"), enabled: true) == .completed, "real completion transition")
    try require(link.update(snapshot("completed", .completed, "new"), enabled: true) == nil, "no repeated completion on poll")
    try require(link.update(snapshot("completed", .completed, "other"), enabled: true) == .idle, "pinning old turn does not celebrate")
    try require(link.update(snapshot("inProgress", .working), enabled: false) == nil, "disabled connection has no work animation")
    try require(codexThreadURL(id)?.absoluteString == "codex://threads/" + id && codexThreadURL("../../evil") == nil,
                "validated local task deep link")
    try require(LocalPetCommand.parse(Data("{\"version\":1,\"state\":\"review\"}".utf8)) == .review &&
        LocalPetCommand.parse(Data("{\"version\":2,\"state\":\"review\"}".utf8)) == nil &&
        LocalPetCommand.parse(Data("{\"version\":1,\"state\":\"execute\"}".utf8)) == nil, "typed local command input")
    return ["six Codex activity animations", "hover, greeting and drag retain priority; resume work",
            "completion plays once then resumes gaze", "no historical or repeated completion",
            "disabled animation link", "validated task URLs and versioned local status input"]
}

// In-process fixture transport. No test traffic leaves the machine.
final class FixtureJRAProtocol: URLProtocol {
    static var fixture = Data()
    static var offline = false
    static var requests: [URL] = []
    static var holdResponse = false
    static var responseStarted: (() -> Void)?
    static var releaseResponse: (() -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request.url!)
        if Self.offline {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        } else {
            let deliver = {
                let response = HTTPURLResponse(url: self.request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: Self.fixture)
                self.client?.urlProtocolDidFinishLoading(self)
            }
            if Self.holdResponse {
                Self.releaseResponse = deliver
                let started = Self.responseStarted
                Self.responseStarted = nil
                started?()
            } else { deliver() }
        }
    }
    override func stopLoading() {}
}

struct FixtureRaceProvider: RaceInformationProviding {
    let year: JRAYear
    let now: Date
    func clearCache() async throws -> Int { 0 }
    func query(_ period: RacePeriod, at ignored: Date, refresh: Bool) async throws -> RaceQueryResult {
        let range = period.range(at: now)
        let races = year.races.filter { !$0.isJump }
        return RaceQueryResult(period: period, range: range, races: races.filter { range.contains($0.date) },
            fetchedAt: year.fetchedAt, sourceURLs: [year.sourceURL], cached: false, warning: nil,
            nextRace: races.first { $0.date > range.upperBound })
    }
}

func runProviderChecks(directory: URL) async throws -> [String] {
    let bytes = try Data(contentsOf: directory.appendingPathComponent("jra-g1-official.html"))
    let date = JRAProvider.calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 12))!
    let official = URL(string: "https://jra.jp/datafile/seiseki/replay/g1.html")!
    let year = try JRAProvider.parse(bytes, expectedYear: 2026, sourceURL: official, fetchedAt: date)
    try require(year.races.filter { !$0.isJump }.count == 24 && year.races.filter { $0.isJump }.count == 2, "official 24 flat / 2 jump rows")
    let sprint = year.races.first { $0.name == "スプリンターズS" }
    try require(sprint?.venue == "中山" && sprint?.course == "芝1,200メートル" && sprint?.winner == "ピューロマジック" &&
        sprint?.resultURL?.path.hasSuffix("sprint2026.html") == true, "real Japanese text and result links")
    do {
        _ = try JRAProvider.parse(bytes, expectedYear: 2027, sourceURL: official, fetchedAt: date)
        throw IntegrationCheckError.failed("wrong year accepted")
    } catch JRAError.wrongYear { }
    do {
        _ = try JRAProvider.parse(Data("<html>maintenance</html>".utf8), expectedYear: 2026, sourceURL: official, fetchedAt: date)
        throw IntegrationCheckError.failed("invalid page accepted as zero races")
    } catch JRAError.invalidPage { }
    try require(!JRAProvider.isOfficial(URL(string: "https://jra.jp.evil.test")!), "official host boundary")
    let cross = RacePeriod.nextWeek.range(at: JRAProvider.calendar.date(from: DateComponents(year: 2026, month: 12, day: 29))!)
    try require(JRAProvider.calendar.component(.year, from: cross.upperBound) == 2027, "Japan timezone cross-year window")

    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("forever-young-check-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: temporary) }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FixtureJRAProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    FixtureJRAProtocol.fixture = bytes
    FixtureJRAProtocol.offline = false
    FixtureJRAProtocol.requests = []
    let provider = JRAProvider(cacheDirectory: temporary, session: session)
    let past = try await provider.query(.pastWeek, at: date, refresh: true)
    try require(past.races.count == 1 && past.races.first?.name == "スプリンターズS" && !past.cached, "past seven days includes September 27")
    let next = try await provider.query(.nextWeek, at: date, refresh: false)
    try require(next.races.isEmpty && next.nextRace?.name == "秋華賞" && next.cached && FixtureJRAProtocol.requests.count == 1,
                "empty future week, explicit next race, five-minute cache")
    FixtureJRAProtocol.offline = true
    let offline = try await provider.query(.pastWeek, at: date, refresh: true)
    try require(offline.cached && offline.warning != nil && offline.fetchedAt == past.fetchedAt && offline.races == past.races,
                "offline cache retains timestamp and warns")
    do {
        _ = try await JRAProvider(cacheDirectory: temporary.appendingPathComponent("empty"), session: session).query(.pastWeek, at: date, refresh: true)
        throw IntegrationCheckError.failed("offline no-cache fabricated zero")
    } catch let error as URLError { try require(error.code == .notConnectedToInternet, "offline transport error") }
    FixtureJRAProtocol.offline = false
    do {
        _ = try await provider.query(.nextWeek, at: cross.lowerBound, refresh: true)
        throw IntegrationCheckError.failed("unpublished year fabricated zero")
    } catch JRAError.wrongYear { }
    try require(FixtureJRAProtocol.requests.contains { $0.path.contains("2027/g1.html") }, "cross-year fetches both years")

    try require(past.dataSource == .online && next.dataSource == .localCache && offline.dataSource == .fallbackCache,
        "online, fresh cache and failed-query cache distinguished")
    let unrelated = temporary.appendingPathComponent("keep.txt")
    try Data("unrelated file".utf8).write(to: unrelated)
    let folder = temporary.appendingPathComponent("g1-1900.json")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let requestCount = FixtureJRAProtocol.requests.count
    let removed = try await provider.clearCache()
    try require(removed == 1 && !FileManager.default.fileExists(atPath: temporary.appendingPathComponent("g1-2026.json").path) &&
        FileManager.default.fileExists(atPath: unrelated.path) && FileManager.default.fileExists(atPath: folder.path), "clear removes only owned JSON files")
    let clearedAgain = try await provider.clearCache()
    try require(FixtureJRAProtocol.requests.count == requestCount && clearedAgain == 0, "clear does not reconnect or recreate cache")
    let afterClear = try await provider.query(.pastWeek, at: date, refresh: false)
    try require(!afterClear.cached && FixtureJRAProtocol.requests.count == requestCount + 1, "next query fetches again after clearing")
    FixtureJRAProtocol.holdResponse = true
    var inFlight: Task<RaceQueryResult, Error>?
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        FixtureJRAProtocol.responseStarted = { continuation.resume() }
        inFlight = Task { try await provider.query(.pastWeek, at: date, refresh: true) }
    }
    _ = try await provider.clearCache()
    FixtureJRAProtocol.holdResponse = false
    let deliver = FixtureJRAProtocol.releaseResponse
    FixtureJRAProtocol.releaseResponse = nil
    deliver?()
    _ = try await inFlight!.value
    try require(!FileManager.default.fileExists(atPath: temporary.appendingPathComponent("g1-2026.json").path), "in-flight response cannot recreate cleared cache")

    let fixtureHome = directory.appendingPathComponent("codex-fixture")
    let reader = CodexHistoryReader(codexHome: fixtureHome)
    let snapshot = reader.snapshot(clientRunning: true, at: date)
    try require(snapshot.connected && snapshot.threads.count == 4 && snapshot.selected?.id == "active" && snapshot.activity == .waiting,
                "read-only native task selection, root threads only and tool wait")
    reader.followingThreadID = "done"
    try require(reader.snapshot(clientRunning: true).activity == .completed, "pin completed task")
    reader.followingThreadID = "failed"
    try require(reader.snapshot(clientRunning: true).activity == .failed, "failed turn")
    reader.followingThreadID = "interrupted"
    try require(reader.snapshot(clientRunning: true).activity == .interrupted, "interrupted turn")
    try require(reader.snapshot(clientRunning: false).activity == .disconnected, "Codex shutdown disconnects")
    try require(!CodexHistoryReader(codexHome: temporary).snapshot(clientRunning: true).connected, "missing history fails closed")
    let empty = directory.appendingPathComponent("incompatible-fixture")
    try require(!CodexHistoryReader(codexHome: empty).snapshot(clientRunning: true).connected, "schema change fails closed")

    // Keep events split across reads to verify the incremental reader, not just the decoder.
    reader.followingThreadID = "active"
    let rollout = fixtureHome.appendingPathComponent("active.jsonl")
    let original = try Data(contentsOf: rollout)
    defer { try? original.write(to: rollout) }
    let handle = try FileHandle(forWritingTo: rollout)
    try handle.seekToEnd()
    let output = "{\"timestamp\":\"2026-10-03T02:59:59Z\",\"type\":\"response_item\",\"payload\":{\"type\":\"custom_tool_call_output\",\"call_id\":\"call-test\"}}\n"
    let cut = output.count / 2
    try handle.write(contentsOf: Data(output.prefix(cut).utf8))
    try require(reader.snapshot(clientRunning: true, at: date).activity == .waiting, "partial JSON preserves previous state")
    try handle.write(contentsOf: Data(output.dropFirst(cut).utf8))
    try require(reader.snapshot(clientRunning: true, at: date).activity == .working, "completed tool restores work")
    try handle.write(contentsOf: Data("{\"timestamp\":\"2026-10-03T03:00:00Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"entered_review_mode\"}}\n".utf8))
    try require(reader.snapshot(clientRunning: true, at: date).activity == .review, "explicit review lifecycle")
    try handle.close()
    return ["Shift_JIS official JRA table: 24 G1 + 2 excluded J-G1", "Japanese names, venue, course, winner and official links",
            "invalid page and wrong year fail closed", "Japan seven-day and cross-year windows",
            "fresh cache avoids network; offline warning preserves source time; no-cache errors",
            "online/fresh/fallback source labels", "cache clear is scoped, repeatable and offline; next query fetches again",
            "in-flight response cannot recreate cleared cache",
            "Codex root selection, pinning, completed/failed/interrupted and disconnection",
            "missing/incompatible database fails closed", "incremental partial JSONL and tool completion/review events"]
}
