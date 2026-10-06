import AppKit

final class RacingFixtureProtocol: URLProtocol {
    static var pages: [String: Data] = [:]
    static var offline = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard !Self.offline, let data = Self.pages[request.url!.absoluteString] else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

func runRacingChecks(directory: URL) async throws -> [String] {
    func read(_ name: String) throws -> Data { try Data(contentsOf: directory.appendingPathComponent(name)) }
    let principalURL = URL(string: "https://www.jairs.jp/2026_world_principal_race_schedule.pdf")!
    let news = URL(string: "https://jra.jp/news/202610/100204.html")!
    var history = try RacingParse.history(read("jbis.html"))
    try require(history.count == 16 && history[0].date == "2026-09-18" && history[0].place == "1" && history.last?.date == "2023-10-14", "JBIS full record and last row")
    let principal = try RacingParse.principal(read("calendar.pdf"), year: 2026, source: principalURL)
    try require(principal.count >= 60 && principal.contains { $0.date == "2026-10-04" && $0.name == "オペラ賞" && $0.zone == "Europe/Paris" }, "positioned PDF rows and venue zones")
    try require(!principal.contains { $0.name.contains("G2") || $0.name.contains("デイ") }, "G2 and event aggregates excluded")
    var bc = try RacingParse.breedersCup(read("bc.html"), year: 2026)
    try require(bc.count == 14 && bc.allSatisfy { $0.provisionalTime }, "all 14 BC G1 events; provisional time kept")
    try RacingParse.contenders(read("entries.html"), year: 2026, races: &bc, history: &history)
    let classic = bc.first { $0.foreverYoung }!
    try require(classic.entryStatus == "candidate" && classic.japaneseRunners.contains("Forever Young"), "official contender is not a declared starter")
    try require(RacingParse.day(classic.start!, zone: "Asia/Shanghai") == "2026-11-01" &&
                RacingParse.day(classic.start!, zone: "Asia/Tokyo") == "2026-11-01" &&
                RacingParse.day(classic.start!, zone: classic.zone) == "2026-10-31", "race date crosses day in Beijing / Tokyo; venue retains Oct 31")
    try require(RacingParse.time("2026-10-31", hour: 18, minute: 16, zone: "America/New_York")!.timeIntervalSince1970 == classic.start!.timeIntervalSince1970,
                "scheduled post time converted using DST-aware venue zone")
    var arc = try RacingParse.overseas(read("overseas.html"), year: 2026).first { $0.name == "凱旋門賞" }!
    try RacingParse.enrich(read("arc-declared.html"), source: news, race: &arc)
    try require(arc.japaneseRunners == ["アドマイヤテラ", "メイショウタバル"] && arc.entryStatus == "declared" && !arc.foreverYoung, "Japanese-trained declaration; Forever Young not falsely entered in Arc")
    try require(RacingParse.day(arc.start!, zone: "Europe/Paris") == "2026-10-04", "JRA Japanese post time mapped to French venue")
    do { _ = try RacingParse.history(Data("<html>maintenance</html>".utf8)); throw IntegrationCheckError.failed("false empty history") } catch JRAError.invalidPage { }
    do { _ = try RacingParse.principal(read("calendar.pdf"), year: 2027, source: principalURL); throw IntegrationCheckError.failed("old year accepted") } catch JRAError.wrongYear { }
    try require(!RacingParse.allowed(URL(string: "https://jra.jp.evil.test")!) && !RacingParse.allowed(URL(string: "https://attacker@jra.jp")!), "source URL boundary")
    let suite = FileManager.default.temporaryDirectory.appendingPathComponent("forever-young-racing-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: suite) }
    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [RacingFixtureProtocol.self]
    let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
    RacingFixtureProtocol.pages = [principalURL.absoluteString:try read("calendar.pdf"), RacingParse.overseasURL.absoluteString:try read("overseas.html"),
        RacingParse.bcURL.absoluteString:try read("bc.html"), RacingParse.contendersURL.absoluteString:try read("entries.html"),
        RacingParse.historyURL.absoluteString:try read("jbis.html"), RacingParse.newsURL.absoluteString:try read("overseas-home.html"), news.absoluteString:try read("arc-declared.html")]
    RacingFixtureProtocol.offline = false
    let provider = RacingProvider(directory: suite, session: session)
    let now = JRAProvider.calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 12))!
    let online = try await provider.overview(at: now, refresh: true)
    try require(online.upcoming.count == 1 && online.upcoming[0].englishName == "Breeders' Cup Classic" && online.historyAvailable, "rolling month and complete source-backed history")
    let domestic = JRAProvider(cacheDirectory: suite.appendingPathComponent("domestic"), session: session)
    let combined = try await CombinedRaceProvider(jra: domestic, racing: provider).query(.nextWeek, at: now, refresh: false)
    try require(!combined.domesticAvailable && combined.international.contains { $0.name == "凱旋門賞" }, "international data remains usable when domestic source fails")
    let cached = try await provider.overview(at: now.addingTimeInterval(10), refresh: false)
    try require(cached.checks.allSatisfy { $0.mode == "localCache" }, "5 minute local cache")
    RacingFixtureProtocol.offline = true
    let offline = try await provider.overview(at: now.addingTimeInterval(400), refresh: true)
    try require(offline.history.count == 16 && offline.checks.allSatisfy { $0.mode == "fallbackCache" && $0.fetchedAt == now }, "offline cache retains original timestamps")
    RacingFixtureProtocol.offline = false
    RacingFixtureProtocol.pages[RacingParse.historyURL.absoluteString] = Data("<html>maintenance</html>".utf8)
    let changed = try await provider.overview(at: now.addingTimeInterval(500), refresh: true)
    try require(changed.history.count == 16 && changed.checks.first { $0.url == RacingParse.historyURL }?.mode == "fallbackCache", "changed page preserves previous valid history")
    try Data("keep".utf8).write(to: suite.appendingPathComponent("unrelated.txt"))
    let count = try await provider.clearCache()
    try require(count >= 6 && FileManager.default.fileExists(atPath: suite.appendingPathComponent("unrelated.txt").path), "manual clear is scoped to owned source caches")
    RacingFixtureProtocol.offline = true
    let missing = try await provider.overview(at: now, refresh: true)
    try require(!missing.historyAvailable && missing.upcoming.isEmpty && !missing.warnings.isEmpty, "no-cache offline state is unknown, not empty confirmed schedule")
    return ["full 16-row JBIS record", "JAIRS principal G1 PDF and G2 exclusion", "14 BC G1 races",
            "contender / declaration distinction and Japanese-trained flags", "Beijing / Tokyo / venue times and DST",
            "official-source and year validation", "30-day schedule", "partial-source failures", "cache, offline timestamps and malformed-page fallback", "scoped cache clearing"]
}

extension InformationCard {
    func checkRacingUI(directory: URL) throws -> [String] {
        var history = try RacingParse.history(Data(contentsOf: directory.appendingPathComponent("jbis.html")))
        var races = try RacingParse.breedersCup(Data(contentsOf: directory.appendingPathComponent("bc.html")), year: 2026)
        try RacingParse.contenders(Data(contentsOf: directory.appendingPathComponent("entries.html")), year: 2026, races: &races, history: &history)
        let overview = RacingOverview(races: races, upcoming: races.filter { $0.foreverYoung }, history: history,
            checks: [SourceCheck(url: RacingParse.historyURL, fetchedAt: Date(), mode: "online")], warnings: [], historyAvailable: true)
        renderHorse(overview); selectPage(.horse)
        show(near: NSRect(x: 900, y: 80, width: 192, height: 208))
        try awaitUI("document.querySelectorAll('[data-uma-panel=horse] .fy-history-row').length===16")
        for style in ["anime", "minimal"] {
            try setPreferenceForCheck("data-ui-style", value: style)
            panel.setContentSize(NSSize(width: 320, height: 700))
            for language in ["zh", "ja", "en"] {
                try setPreferenceForCheck("data-ui-language", value: language)
                let expected = language == "en" ? "Oct 31" : language == "ja" ? "11月1日" : "11月1日"
                try awaitUI("document.querySelector('[data-ui-surface]:not([hidden]) .fy-clock').textContent.includes('\(expected)')")
                try require(try evaluateForCheck("document.documentElement.scrollWidth<=innerWidth") as? Bool == true, "horse module fits 320px \(style)/\(language)")
            }
        }
        panel.setContentSize(NSSize(width: 590, height: 760)); try setPreferenceForCheck("data-ui-style", value: "anime")
        try setPreferenceForCheck("data-ui-language", value: "zh")
        try capture(to: directory.appendingPathComponent("horse-module.png"))
        try clickForCheck("[data-open-modules]")
        try awaitUI("document.querySelector('[data-ui-surface]:not([hidden]) .fy-module-menu [data-module=horse]')!==null")
        return ["native WebKit third module with full record", "six style/language layouts at 320px", "language-dependent race clock", "extensible module menu"]
    }
}
