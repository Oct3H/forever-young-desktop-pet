import AppKit
import WebKit

enum WorkspacePage: String { case tasks, races, horse, integrations, tools }

// Extend the module list and command handler together; tabs do not divide all available space.
struct WorkspaceModule {
    let id: String
    let titleKey: String
    let icon: String
    var object: [String: String] { ["id": id, "titleKey": titleKey, "icon": icon] }
    static let builtIn = [WorkspaceModule(id: "tasks", titleKey: "tasks", icon: "terminal"),
                          WorkspaceModule(id: "races", titleKey: "races", icon: "trophy"),
                          WorkspaceModule(id: "horse", titleKey: "horse", icon: "sparkles"),
                          WorkspaceModule(id:"integrations",titleKey:"integrations",icon:"terminal"),WorkspaceModule(id:"tools",titleKey:"tools",icon:"sparkles")]
}

final class InformationCard: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let panel: NSPanel
    let webView: WKWebView
    private let defaults: UserDefaults
    private var loaded = false
    private(set) var loadCount = 0
    private var page: WorkspacePage = .tasks
    private var codex: CodexSnapshot?
    private var following: String?
    private var codexEnabled = true
    private var checkedAt = Date()
    private var races: RaceQueryResult?
    private var horse: RacingOverview?
    private var horseError: String?
    private var integrationData: [String:Any] = ["primary":"auto","selected":"codex","sources":[]]
    private var companionData: [String:Any] = [:]
    private var officialData: [String:Any] = [:]
    private var period: RacePeriod = .nextWeek
    private var raceError: String?
    private(set) var cacheNotice: String?
    private(set) var displayedRaceCount = 0
    private(set) var displayedThreadCount = 0
    private var reconnect: () -> Void = {}
    private var follow: (String?) -> Void = { _ in }
    private var openThread: (String) -> Void = { _ in }
    private var clearCache: () -> Void = {}
    private var query: (RacePeriod, Bool) -> Void = { _, _ in }
    private var openRace: (URL) -> Void = { _ in }
    var onPage: ((WorkspacePage) -> Void)?
    var onOpenCodex: (() -> Void)?
    var onToggleCodex: (() -> Void)?
    var onQueryHorse: ((Bool) -> Void)?
    var onPreferences: (() -> Void)?
    var onPrimary: ((String)->Void)?
    var onLinkedAction: ((String,LinkedSource,String?,String?)->Void)?
    var onTools: (([String:Any])->Void)?
    var onCodexCompose: ((String)->Void)?
    var onOfficialConnect: (() -> Void)?

    init(title: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        panel = NSPanel(contentRect: NSRect(x: 100, y: 100, width: 590, height: 760),
                        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = title
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.minSize = NSSize(width: 320, height: 360)
        panel.appearance = NSAppearance(named: .aqua)
        panel.backgroundColor = .white
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: panel.contentView!.bounds, configuration: configuration)
        super.init()
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        configuration.userContentController.add(self, name: "pet")
        panel.contentView!.addSubview(webView)
        if let ui = Bundle.main.resourceURL?.appendingPathComponent("UI") {
            webView.loadFileURL(ui.appendingPathComponent("index.html"), allowingReadAccessTo: ui)
        }
    }

    func selectPage(_ page: WorkspacePage) { self.page = page; publish() }

    private func publish() {
        guard loaded else { return }
        let selectedID = codex?.selected?.id ?? ""
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"] ??
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
        let threads = (codex?.threads ?? []).map { thread -> [String: Any] in
            ["id": thread.id, "title": thread.title, "cwd": thread.cwd,
             "activity": thread.id == selectedID ? (codex?.activity.rawValue ?? "idle") : thread.activity.rawValue]
        }
        var raceData: [String: Any] = ["period": period.rawValue, "status": "loading"]
        if let error = raceError { raceData["status"] = "error"; raceData["error"] = error }
        else if let notice = cacheNotice {
            raceData["status"] = notice.contains("已清理") ? "cleared" : "clearing"
            raceData["clearedCount"] = notice.split(separator: "（").last?.split(separator: " ").first.flatMap { Int($0) } ?? 0
        } else if let result = races {
            let source = result.dataSource ?? (result.cached ? (result.warning == nil ? .localCache : .fallbackCache) : .online)
            let sourceKey: String
            switch source {
            case .online: sourceKey = "online"
            case .localCache: sourceKey = "localCache"
            case .fallbackCache: sourceKey = "fallbackCache"
            case .mixed: sourceKey = "mixed"
            }
            func raceObject(_ race: JRARace) -> [String: Any] {
                ["date": race.date.timeIntervalSince1970 * 1000, "name": race.name, "venue": race.venue,
                 "course": race.course, "winner": race.winner, "jockey": race.jockey,
                 "pageURL": race.pageURL.absoluteString, "resultURL": race.resultURL?.absoluteString ?? ""]
            }
            raceData.merge(["status": "ready", "rangeStart": result.range.lowerBound.timeIntervalSince1970 * 1000,
                            "rangeEnd": result.range.upperBound.timeIntervalSince1970 * 1000,
                            "items": result.races.map(raceObject), "source": sourceKey,
                            "fetchedAt": result.fetchedAt.timeIntervalSince1970 * 1000, "warning": result.warning ?? "",
                            "calendarURL": result.sourceURLs.first?.absoluteString ?? "",
                            "international": result.international.map { $0.object },
                            "internationalChecks": result.internationalChecks.map { $0.object },
                            "internationalWarnings": result.internationalWarnings,
                            "internationalAvailable": result.internationalAvailable,
                            "domesticAvailable": result.domesticAvailable]) { _, new in new }
            if let next = result.nextRace { raceData["nextRace"] = raceObject(next) }
        }
        var horseData: [String: Any] = ["status": "loading"]
        if let error = horseError { horseData = ["status": "error", "error": error] }
        else if let horse = horse {
            horseData = ["status": "ready", "upcoming": horse.upcoming.map { $0.object },
                         "history": horse.history.map { $0.object }, "historyAvailable": horse.historyAvailable,
                         "checks": horse.checks.map { $0.object }, "warnings": horse.warnings]
        }
        let payload: [String: Any] = [
            "version": 1, "page": page.rawValue,
            "preferences": ["style": defaults.string(forKey: "uiStyle") ?? "anime", "language": defaults.string(forKey: "uiLanguage") ?? "zh"],
            "modules": WorkspaceModule.builtIn.map { $0.object },
            "codex": ["connected": codex?.connected ?? false, "enabled": codexEnabled,
                      "activity": codex?.activity.rawValue ?? "disconnected", "threads": threads,
                      "selectedID": selectedID, "followingID": following ?? "", "home": home,
                      "message": codex?.message ?? "", "checkedAt": checkedAt.timeIntervalSince1970 * 1000,
                      "clientRunning": NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.openai.codex" }],
            "tools":companionData,"races": raceData, "horse": horseData, "integrations":integrationData, "official":officialData
        ]
        webView.callAsyncJavaScript("window.petUI.update(data)", arguments: ["data": payload], in: nil, in: .page) { _ in }
    }

    func renderCodex(_ snapshot: CodexSnapshot?, following: String?, enabled: Bool,
                     reconnect: @escaping () -> Void = {}, follow: @escaping (String?) -> Void,
                     open: @escaping (String) -> Void) {
        codex = snapshot; self.following = following; codexEnabled = enabled; checkedAt = Date()
        self.reconnect = reconnect; self.follow = follow; openThread = open
        displayedThreadCount = snapshot?.threads.count ?? 0
        publish()
    }

    func renderRaces(_ result: RaceQueryResult?, period: RacePeriod, error: String? = nil,
                     notice: String? = nil, clearCache: @escaping () -> Void = {},
                     query: @escaping (RacePeriod, Bool) -> Void, open: @escaping (URL) -> Void) {
        races = result; self.period = period; raceError = error; cacheNotice = notice
        self.clearCache = clearCache; self.query = query; openRace = open
        displayedRaceCount = result?.races.count ?? 0
        publish()
    }

    func renderHorse(_ result: RacingOverview?, error: String? = nil) {
        horse = result; horseError = error; publish()
    }
    func renderIntegrations(_ data: [String:Any], official: [String:Any]) { integrationData = data; officialData = official; publish() }

    func renderCompanion(_ data: [String:Any]) {
        companionData = data
        guard loaded else { return }
        webView.callAsyncJavaScript("window.petTools?.update(data)",arguments:["data":data],in:nil,in:.page) { _ in }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.name == "pet",
              let object = message.body as? [String: Any], let command = object["command"] as? String else { return }
        switch command {
        case "toolSetting", "timer", "historyJump", "clearHistory", "audition", "exportCalendar", "diagnose": onTools?(object)
        case "ready": loaded = true; publish()
        case "preferences":
            if let style = object["style"] as? String, ["anime", "minimal"].contains(style) { defaults.set(style, forKey: "uiStyle") }
            if let language = object["language"] as? String, ["zh", "ja", "en"].contains(language) { defaults.set(language, forKey: "uiLanguage") }
            onPreferences?()
        case "page":
            if let value = object["page"] as? String, let page = WorkspacePage(rawValue: value) { selectPage(page); onPage?(page) }
        case "reconnect": reconnect()
        case "openCodex": onOpenCodex?()
        case "toggleCodex": onToggleCodex?()
        case "primary": if let value = object["value"] as? String, ["auto","codex","vscode","pycharm"].contains(value) { onPrimary?(value) }
        case "linkedAction":
            if let action = object["action"] as? String, let value = object["source"] as? String, let source = LinkedSource(rawValue:value),
               (source == .codex ? ["run","test","review","stop"] : ["run","chooseRun","runFile","build","test","stop","openProblems","openConsole"]).contains(action) {
                onLinkedAction?(action,source,object["instance"] as? String,object["expectedToken"] as? String)
            }
        case "officialConnect": onOfficialConnect?()
        case "codexCompose":
            let presets = ["run":"请检查这个项目的现有运行配置，再运行项目并报告结果。", "test":"请检查项目现有测试配置并运行测试，报告结果。", "review":"请检查当前未提交的改动，报告发现的问题。"]
            onCodexCompose?(presets[object["preset"] as? String ?? ""] ?? "")
        case "follow":
            if let id = object["id"] as? String, codex?.threads.contains(where: { $0.id == id }) == true { follow(id) }
            else if object["id"] == nil { follow(nil) }
        case "openThread":
            if let id = object["id"] as? String, codex?.threads.contains(where: { $0.id == id }) == true, codexThreadURL(id) != nil { openThread(id) }
        case "query":
            if let value = object["period"] as? String, let period = RacePeriod(rawValue: value) { query(period, object["refresh"] as? Bool ?? false) }
        case "clearCache": clearCache()
        case "queryHorse": onQueryHorse?(object["refresh"] as? Bool ?? false)
        case "openRace":
            if let string = object["url"] as? String, let url = URL(string: string), RacingParse.allowed(url), allowedRaceURLs.contains(url) { openRace(url) }
        default: break
        }
    }

    private var allowedRaceURLs: Set<URL> {
        var result = Set<URL>()
        if let races = races {
            result.formUnion(races.sourceURLs)
            for race in races.races + (races.nextRace.map { [$0] } ?? []) {
                result.insert(race.pageURL)
                if let url = race.resultURL { result.insert(url) }
            }
            for race in races.international { result.insert(race.source); if let url = race.runnersSource { result.insert(url) } }
            result.formUnion(races.internationalChecks.map { $0.url })
        }
        if let horse = horse {
            result.formUnion(horse.checks.map { $0.url })
            for race in horse.upcoming { result.insert(race.source); if let url = race.runnersSource { result.insert(url) } }
        }
        return result
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let ui = Bundle.main.resourceURL!.appendingPathComponent("UI").path + "/"
        let allowed = navigationAction.request.url.map { $0.isFileURL && $0.path.hasPrefix(ui) } ?? false
        decisionHandler(allowed ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loadCount += 1 }

    func show(near frame: NSRect) {
        if !panel.isVisible {
            let screen = NSScreen.screens.first { $0.visibleFrame.intersects(frame) }?.visibleFrame ?? NSScreen.main!.visibleFrame
            var x = frame.minX - panel.frame.width - 12
            if x < screen.minX { x = frame.maxX + 12 }
            x = max(screen.minX, min(x, screen.maxX - panel.frame.width))
            let y = max(screen.minY, min(frame.minY, screen.maxY - panel.frame.height))
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func capture(to url: URL) throws {
        var result: Result<NSImage, Error>?
        webView.takeSnapshot(with: nil) { image, error in
            if let image = image { result = .success(image) }
            else { result = .failure(error ?? CocoaError(.fileWriteUnknown)) }
        }
        let deadline = Date(timeIntervalSinceNow: 5)
        while result == nil && Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)) }
        guard let result = result, let data = try result.get().tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url)
    }
}
