import AppKit
import UniformTypeIdentifiers
import AVFoundation

let cellWidth = 192
let cellHeight = 208
let petSize = NSSize(width: 192, height: 208)
func nowMilliseconds() -> Double { ProcessInfo.processInfo.systemUptime * 1000 }
func restartOfficialVoice(_ player: AVAudioPlayer) -> Bool {
    player.stop()
    player.currentTime = 0
    return player.play()
}

struct PetAssets {
    let frames: [[NSImage]]
    let voiceURL: URL

    init(resources: URL) throws {
        enum AssetError: Error { case invalidAtlas, invalidFrame }
        let atlasURL = resources.appendingPathComponent("spritesheet.png")
        guard let source = CGImageSourceCreateWithURL(atlasURL as CFURL, nil),
              let atlas = CGImageSourceCreateImageAtIndex(source, 0, nil),
              atlas.width == 1536, atlas.height == 2288 else { throw AssetError.invalidAtlas }
        var images: [[NSImage]] = []
        let counts = PetRuntime.durations.map { $0.count } + [8, 8]
        for row in 0..<11 {
            var rowImages: [NSImage] = []
            for column in 0..<counts[row] {
                guard let crop = atlas.cropping(to: CGRect(x: column * cellWidth, y: row * cellHeight,
                                                         width: cellWidth, height: cellHeight)) else {
                    throw AssetError.invalidFrame
                }
                rowImages.append(NSImage(cgImage: crop, size: NSSize(width: cellWidth, height: cellHeight)))
            }
            images.append(rowImages)
        }
        frames = images
        voiceURL = resources.appendingPathComponent("official-voice.mp3")
    }
}

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PetView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    private var breathHeight = 0.0
    var greet: (() -> Void)?
    var moved: (() -> Void)?
    var dragged: ((Double) -> Void)?
    private var pressPoint: NSPoint?
    private var pressOrigin: NSPoint?
    private var lastDragPoint: NSPoint?
    private(set) var isDragging = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    func breathe(at now: Double, active: Bool) {
        let backingScale = window?.backingScaleFactor ?? 2
        let height = active ? (sin(now / 4_500 * 2 * .pi) * backingScale).rounded() / backingScale : 0
        if height != breathHeight { breathHeight = height; needsDisplay = true }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)
        let scale = bounds.width / Double(cellWidth)
        let interpolation: NSImageInterpolation = abs(scale.rounded() - scale) < 0.001 ? .none : .high
        let destination = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height + breathHeight)
        image?.draw(in: destination, from: .zero, operation: .sourceOver, fraction: 1,
                    respectFlipped: true, hints: [.interpolation: interpolation])
    }
    override func mouseDown(with event: NSEvent) {
        pressPoint = window?.convertPoint(toScreen: event.locationInWindow)
        pressOrigin = window?.frame.origin
        lastDragPoint = pressPoint
        isDragging = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let point = pressPoint, let origin = pressOrigin, let window = window else { return }
        let current = window.convertPoint(toScreen: event.locationInWindow)
        let dx = current.x - point.x
        let dy = current.y - point.y
        if hypot(dx, dy) > 4 { isDragging = true }
        if isDragging {
            let step = current.x - (lastDragPoint?.x ?? point.x)
            lastDragPoint = current
            window.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
            dragged?(step)
        }
    }
    override func mouseUp(with event: NSEvent) {
        guard pressPoint != nil else { return }
        if isDragging { moved?() } else { greet?() }
        pressPoint = nil
        pressOrigin = nil
        lastDragPoint = nil
        isDragging = false
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: PetPanel!
    private var petView: PetView!
    private var assets: PetAssets!
    private var player: AVAudioPlayer!
    private var voices: VoiceLibrary?
    private var voicePriority = 0
    private var voiceID = "official"
    private var greetingUsesAudio = true
    private var voiceToggleItem: NSMenuItem?
    private var automaticVoiceItem: NSMenuItem?
    private var runtime = PetRuntime()
    private var timer: Timer?
    private var statusItem: NSStatusItem!
    private var latestFrame: SpriteFrame?
    private var voiceStarts = 0
    private var voiceError: String?
    private var diagnosticURL: URL?
    private var nextDiagnosticTime: Double = 0
    private var sizeItems: [NSMenuItem] = []
    private var displayScale = 1.0
    private let defaults: UserDefaults
    private let codexConnection = LocalCodexConnection()
    private var codexSnapshot: CodexSnapshot?
    private let integrations = IntegrationHub()
    private let ideBridge = IDEBridge()
    private let officialCodex = OfficialCodex()
    private let localCodexInstance = UUID().uuidString
    private var localCodexSequence = 0
    private var officialStates: [String:LinkedEvent] = [:]
    private var composingThread: CodexThreadSummary?
    private lazy var tools = CompanionTools(defaults: defaults)
    private lazy var reminders = RaceReminders(defaults: defaults)
    private var parkedOrigin: NSPoint?
    private var pendingToolAlerts: [(String,String,Date)] = []
    private var nextReminderRefresh = 0.0
    private var reminderTask: Task<Void,Never>?
    private var nextIntegrationTick: Double = 0
    private var codexAnimationLink = CodexAnimationLink()
    private var codexEnabled = true
    private var codexStatusItem: NSMenuItem?
    private var codexToggleItem: NSMenuItem?
    private var codexCard: InformationCard?
    private var codexCardFingerprint = ""
    private var stateObserver: NSObjectProtocol?
    private var externalStateUntil: Double = 0
    private var appliedCodexState: CodexActivity = .idle
    private let racingProvider = RacingProvider()
    private var bubbles: PetBubbles?
    private var horseTask: Task<Void, Never>?
    private var horseQueryID = UUID()
    private var workspacePage: WorkspacePage = .tasks
    private var nextDataRefresh = Double.greatestFiniteMagnitude
    private let raceProvider: RaceInformationProviding
    private var raceCard: InformationCard?
    private var raceTask: Task<Void, Never>?
    private var raceQueryID = UUID()
    private var selectedRacePeriod: RacePeriod = .nextWeek

    init(defaults: UserDefaults = .standard, raceProvider: RaceInformationProviding? = nil) {
        self.defaults = defaults
        self.raceProvider = raceProvider ?? CombinedRaceProvider(racing: racingProvider)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            guard let resources = Bundle.main.resourceURL else { throw CocoaError(.fileNoSuchFile) }
            assets = try PetAssets(resources: resources)
            voices = try VoiceLibrary(resources: resources)
            player = try AVAudioPlayer(contentsOf: assets.voiceURL)
            player.numberOfLoops = 0
            player.prepareToPlay()
            if let index = CommandLine.arguments.firstIndex(of: "--diagnostics"),
               index + 1 < CommandLine.arguments.count {
                diagnosticURL = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            }
            createPanel()
            createMenus()
            startCodexConnection()
            startTools()
            startIntegrations()
            let timer = Timer(timeInterval: 1 / 60, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            tick()
            panel.orderFrontRegardless()
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法加载青春永驻桌宠"
            alert.informativeText = "请保留完整的 .app 文件。\n\(error.localizedDescription)"
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    private func createPanel() {
        let savedScale = defaults.double(forKey: "displayScale")
        displayScale = [1.0, 1.25, 1.5, 2.0].contains(savedScale) ? savedScale : 1.0
        let size = NSSize(width: petSize.width * displayScale, height: petSize.height * displayScale)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        var origin = NSPoint(x: screen.maxX - size.width - 40, y: screen.minY + 30)
        if let x = defaults.object(forKey: "petX") as? Double,
           let y = defaults.object(forKey: "petY") as? Double {
            let saved = NSRect(origin: NSPoint(x: x, y: y), size: size)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(saved) }) { origin = saved.origin }
        }
        panel = PetPanel(contentRect: NSRect(origin: origin, size: size),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "フォーエバーヤング · Desktop v3.7"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        bubbles = PetBubbles(defaults: defaults)
        bubbles?.onWorkspace = { [weak self] in self?.showTaskCard() }
        bubbles?.onOpenCodex = { [weak self] in
            guard let self = self else { return }
            if let id = self.codexSnapshot?.selected?.id { self.dispatch(.openCodexThread(id)) }
            else { self.openCodexApplication() }
        }
        bubbles?.onBeginCompose = { [weak self] in
            guard let self = self else { return }
            self.composingThread = self.codexSnapshot?.selected
            self.bubbles?.composeTarget = self.composingThread.map { "Codex · " + $0.title + " · " + $0.cwd } ?? "Codex · 请先选择跟随任务"
        }
        bubbles?.onSend = { [weak self] text, completion in self?.sendToTrackedCodex(text,completion:completion) }
        bubbles?.onRun = { [weak self] in self?.showIntegrations() }
        bubbles?.onLinks = { [weak self] in self?.showIntegrations() }
        petView = PetView(frame: NSRect(origin: .zero, size: size))
        petView.autoresizingMask = [.width, .height]
        petView.toolTip = "点击问候 · 拖动移动 · 右键打开菜单"
        petView.setAccessibilityElement(true)
        petView.setAccessibilityRole(.button)
        petView.setAccessibilityLabel("青春永驻桌宠")
        petView.greet = { [weak self] in
            guard let self = self else { return }
            self.greet(); self.codexConnection.refresh()
            self.bubbles?.showActions(near:self.panel.frame)
            if self.integrations.queue.isEmpty { self.bubbles?.showClickStatus(self.integrations.selected) }
        }
        petView.dragged = { [weak self] delta in
            guard let self = self else { return }
            self.player.stop()
            self.dispatch(.drag(delta))
            self.tick()
        }
        petView.moved = { [weak self] in
            guard let self = self else { return }
            self.dispatch(.drag(nil))
            self.rememberPosition()
            self.tick()
        }
        panel.contentView = petView
    }

    private func createMenus() {
        let menu = NSMenu()
        let title = NSMenuItem(title: "フォーエバーヤング · 桌面版 v3.7", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        addItem("鼠标互动", action: #selector(mouseMode), menu: menu)
        let actions = NSMenuItem(title: "动作预览", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let names = ["待机", "向右跑", "向左跑", "挥手", "跳跃", "失落", "等待", "工作", "检查"]
        for (row, name) in names.enumerated() {
            let item = addItem(name, action: #selector(previewAction(_:)), menu: submenu)
            item.tag = row
        }
        actions.submenu = submenu
        menu.addItem(actions)
        addItem("播放角色招呼（随机）", action: #selector(greet), menu: menu)
        voiceToggleItem = addItem("角色语音", action: #selector(toggleVoice), menu: menu)
        voiceToggleItem?.state = defaults.object(forKey:"voiceEnabled") as? Bool == false ? .off : .on
        automaticVoiceItem = addItem("自动状态语音", action: #selector(toggleAutomaticVoice), menu: menu)
        automaticVoiceItem?.state = defaults.object(forKey:"automaticVoiceEnabled") as? Bool == false ? .off : .on
        menu.addItem(.separator())
        addItem("Forever Young 参赛计划／战绩", action: #selector(showHorse), menu: menu)
        addItem("打开工作台（界面／语言设置）", action: #selector(showCodexTasks), menu: menu)
        codexStatusItem = addItem("Codex：正在连接…", action: #selector(showCodexTasks), menu: menu)
        addItem("Codex 任务卡片／选择跟随任务", action: #selector(showCodexTasks), menu: menu)
        addItem("打开当前 Codex 任务", action: #selector(openSelectedTask), menu: menu)
        addItem("重新连接 Codex", action: #selector(reconnectCodex), menu: menu)
        addItem("Codex / VS Code / PyCharm 联动", action:#selector(showIntegrations), menu:menu)
        codexToggleItem = addItem("联动状态动作（全部来源）", action: #selector(toggleCodex), menu: menu)
        codexToggleItem?.state = .on
        addItem("国内 / 国际 GⅠ · 过去七天", action: #selector(queryPastRaces), menu: menu)
        addItem("国内 / 国际 GⅠ · 未来七天", action: #selector(queryNextRaces), menu: menu)
        addItem("清理赛事本地缓存", action: #selector(clearRaceCache), menu: menu)
        menu.addItem(.separator())
        let sizeMenu = NSMenuItem(title: "显示尺寸", action: nil, keyEquivalent: "")
        let sizes = NSMenu()
        for percent in [100, 125, 150, 200] {
            let label = percent == 100 ? "100% · 原尺寸清晰显示" : "\(percent)%"
            let item = addItem(label, action: #selector(resizePet(_:)), menu: sizes)
            item.tag = percent
            item.state = abs(displayScale * 100 - Double(percent)) < 0.1 ? .on : .off
            sizeItems.append(item)
        }
        sizeMenu.submenu = sizes
        menu.addItem(sizeMenu)
        menu.addItem(.separator())
        addItem("显示／隐藏桌宠", action: #selector(toggleVisibility), menu: menu)
        addItem("重置位置", action: #selector(resetPosition), menu: menu)
        addItem("退出桌宠", action: #selector(quit), menu: menu)
        petView.menu = menu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "🐎"
        statusItem.button?.toolTip = "フォーエバーヤング v3.7 · Codex · IDE · GⅠ"
        statusItem.menu = menu
    }

    @discardableResult
    private func addItem(_ title: String, action: Selector, menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func tick() {
        let now = nowMilliseconds()
        if externalStateUntil > 0 && now >= externalStateUntil {
            externalStateUntil = 0
            applyCodexState(codexEnabled ? integrations.selected?.animation ?? .idle : .idle)
        }
        if panel.isVisible {
            let point = NSEvent.mouseLocation
            let rect = panel.frame
            // AppKit screen y goes upward; the sprite direction convention goes downward.
            runtime.handle(.pointer(dx: point.x - rect.midX, dy: rect.midY - point.y), at: now)
            runtime.handle(.hover(rect.contains(point), allowJump: !petView.isDragging), at: now)
            if greetingUsesAudio { runtime.synchronizeGreeting(audioTime: player.currentTime * 1000, playing: player.isPlaying, at: now) }
            let frame = runtime.frame(at: now)
            petView.breathe(at: now, active: frame.mode == "looking" || frame.mode.hasPrefix("idle"))
            if frame != latestFrame {
                petView.image = assets.frames[frame.row][frame.column]
                latestFrame = frame
                petView.setAccessibilityValue(frame.mode == "looking" ? "正在看着鼠标" :
                    frame.mode == "jumping" ? "正在跳跃" : frame.mode == "waving" ? "正在挥手" :
                    frame.mode.hasPrefix("dragging") ? "正在跑步" : "正在陪伴")
            }
        } else {
            runtime.handle(.hover(false, allowJump: false), at: now)
        }
        bubbles?.tick(near: panel.frame, visible: panel.isVisible, dragging: petView.isDragging)
        tools.tick(); reminders.tick()
        if now >= nextIntegrationTick {
            nextIntegrationTick = now + 500
            let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
            let front: LinkedSource? = bundle == LinkedSource.codex.bundleID ? .codex : bundle == LinkedSource.vscode.bundleID ? .vscode : bundle.hasPrefix("com.jetbrains.pycharm") ? .pycharm : nil
            if integrations.frontmost != front { integrations.frontmost = front; integrationsChanged() }
            integrations.expire()
            if tools.mode == "normal" && codexEnabled && panel.isVisible && !petView.isDragging && bubbles?.canPresentNotice == true, let notice = integrations.takeNotice() {
                bubbles?.showNotice(notice.event); bubbles?.position(near:panel.frame)
                playStatusVoice(notice.event, at:now)
            }
        }
        if (defaults.bool(forKey:"raceReminders") || defaults.bool(forKey:"entryReminders")) && now >= nextReminderRefresh {
            nextReminderRefresh = now + 900_000
            refreshReminderData()
        }
        pendingToolAlerts.removeAll { Date().timeIntervalSince($0.2) > 120 }
        if tools.mode != "meeting" && panel.isVisible && !petView.isDragging && (integrations.queue.isEmpty || tools.mode == "focus") && bubbles?.canPresentNotice == true,
           let index = pendingToolAlerts.firstIndex(where:{ tools.mode == "normal" || $0.0.hasPrefix("rest") }) {
            let alert = pendingToolAlerts.remove(at:index); bubbles?.showMessage(toolAlertText(alert.0,title:alert.1)); bubbles?.position(near:panel.frame)
        }
        if now >= nextDataRefresh && codexCard?.panel.isVisible == true {
            if workspacePage == .horse { queryHorse(refresh: true, show: false) }
            else if workspacePage == .races { queryRaces(selectedRacePeriod, refresh: true, show: false) }
            else { nextDataRefresh = now + 300_000 }
        }
        if diagnosticURL != nil && now >= nextDiagnosticTime {
            writeDiagnostics()
            nextDiagnosticTime = now + 100
        }
    }

    @objc private func greet() {
        guard integrations.queue.isEmpty, bubbles?.canPresentNotice != false,
              !player.isPlaying || voicePriority == 0 else { return }
        if !tools.allowsVoice("click",automatic:false) {
            greetingUsesAudio = false
            dispatch(.greet(duration:700)); tick(); return
        }
        if let voices = voices, let cue = voices.select("click",hour:Calendar.current.component(.hour,from:Date())) {
            _ = playVoice(cue,context:"click",key:nil,at:nowMilliseconds(),wave:true)
            tick(); return
        }
        if restartOfficialVoice(player) {
            dispatch(.greet(duration: player.duration * 1000))
            voiceStarts += 1
            voiceError = nil
        } else { voiceError = "Audio output failed to start" }
        tick()
    }
    @discardableResult
    private func playVoice(_ cue: VoiceCue, context: String, key: String?, at now: Double, wave: Bool) -> Bool {
        do {
            guard let next = try voices?.player(for:cue) else { return false }
            player.stop()
            runtime.synchronizeGreeting(audioTime:0,playing:false,at:now)
            next.volume = tools.volume
            player = next
            guard restartOfficialVoice(next) else { voiceError = "Audio output failed to start"; return false }
            voiceID = cue.id; voicePriority = VoiceLibrary.priority(context)
            greetingUsesAudio = true
            voiceStarts += 1; voiceError = nil
            voices?.didPlay(context,key:key,now:now)
            if wave { dispatch(.greet(duration:next.duration * 1000)) }
            return true
        } catch { voiceError = error.localizedDescription; return false }
    }
    private func playStatusVoice(_ event: LinkedEvent, at now: Double) {
        guard tools.allowsVoice(event.state.rawValue,automatic:true), let voices = voices else { return }
        let context = event.state.rawValue
        let key = event.key + ":" + event.runID + ":" + context
        guard voices.allowsAutomatic(context,key:key,now:now,busyPriority:player.isPlaying ? voicePriority : 0),
              let cue = voices.select(context,hour:Calendar.current.component(.hour,from:Date())) else { return }
        _ = playVoice(cue,context:context,key:key,at:now,wave:false)
    }
    @objc private func toggleVoice() {
        let enabled = defaults.object(forKey:"voiceEnabled") as? Bool == false
        defaults.set(enabled,forKey:"voiceEnabled"); voiceToggleItem?.state = enabled ? .on : .off
        if !enabled { player.stop(); voicePriority = 0 }; refreshTools()
    }
    @objc private func toggleAutomaticVoice() {
        let enabled = defaults.object(forKey:"automaticVoiceEnabled") as? Bool == false
        defaults.set(enabled,forKey:"automaticVoiceEnabled"); automaticVoiceItem?.state = enabled ? .on : .off
        if !enabled && voicePriority > 10 { player.stop(); voicePriority = 0 }; refreshTools()
    }
    private func dispatch(_ command: PetCommand) {
        switch command {
        case let .queryRaces(period, refresh): queryRaces(period, refresh: refresh)
        case .clearRaceCache: clearRaceCache()
        case .showCodexTasks: showTaskCard()
        case let .openCodexThread(id):
            if let url = codexThreadURL(id) { NSWorkspace.shared.open(url) }
        default: runtime.handle(command, at: nowMilliseconds())
        }
    }

    private func startCodexConnection() {
        codexEnabled = defaults.object(forKey: "codexLinked") as? Bool ?? true
        codexToggleItem?.state = codexEnabled ? .on : .off
        codexConnection.follow(defaults.string(forKey: "followingCodexThread"))
        codexConnection.onSnapshot = { [weak self] snapshot in self?.receiveCodex(snapshot) }
        codexConnection.start()
        stateObserver = DistributedNotificationCenter.default().addObserver(
            forName: LocalPetCommand.notification, object: nil, queue: .main) { [weak self] notification in
                guard let self = self, self.codexEnabled,
                      let json = notification.userInfo?["command"] as? String,
                      let state = LocalPetCommand.parse(Data(json.utf8)) else { return }
                self.externalStateUntil = nowMilliseconds() + 15_000
                self.applyCodexState(state)
                self.tick()
            }
    }

    private func applyCodexState(_ state: CodexActivity) {
        guard state != appliedCodexState else { return }
        appliedCodexState = state
        dispatch(.codexState(state))
    }

    private func receiveCodex(_ snapshot: CodexSnapshot) {
        let previousID = codexSnapshot?.selected?.id
        var merged = snapshot
        if let id = snapshot.selected?.id, let event = officialStates[id],
           officialCodex.activeTurns[id] != nil || Date().timeIntervalSince1970*1000 - event.sentAt < 5_000 {
            merged = CodexSnapshot(connected:true,threads:snapshot.threads,selected:snapshot.selected,activity:event.state,message:officialCodex.message)
        }
        codexSnapshot = merged
        localCodexSequence += 1
        var event = LinkedEvent(version:1,source:.codex,instance:localCodexInstance,sequence:localCodexSequence,sentAt:Date().timeIntervalSince1970*1000,state:merged.activity,
                                runID:(merged.selected?.id ?? "") + (officialCodex.activeTurns[merged.selected?.id ?? ""] ?? merged.selected?.turnID ?? ""),title:merged.selected?.title ?? "Codex",project:merged.selected?.cwd ?? "",activeCount:[CodexActivity.working,.waiting,.review].contains(merged.activity) ? 1 : 0)
        event.metadata = ["threadID":merged.selected?.id ?? "","pluginVersion":"built-in 3.7","runtime":officialCodex.object["transport"] as? String ?? ""]
        integrations.receive(event,notify:previousID == merged.selected?.id || !merged.activity.isTransient)
        _ = codexAnimationLink.update(merged, enabled:codexEnabled)
        if externalStateUntil == 0 { applyCodexState(codexEnabled ? integrations.selected?.animation ?? .idle : .idle) }
        codexStatusItem?.title = "Codex：" + (codexEnabled ? merged.activity.label : "动画暂停")
        codexStatusItem?.toolTip = snapshot.selected?.title ?? snapshot.message
        let fingerprint = snapshot.message + snapshot.activity.rawValue + (snapshot.selected?.id ?? "") +
            snapshot.threads.map { $0.id + $0.title + $0.turnStatus }.joined()
        if codexCard?.panel.isVisible == true && fingerprint != codexCardFingerprint { renderTaskCard() }
        codexCardFingerprint = fingerprint
    }

    private func renderTaskCard() {
        codexCard?.renderCodex(codexSnapshot, following: defaults.string(forKey: "followingCodexThread"), enabled: codexEnabled,
            reconnect: { [weak self] in self?.reconnectCodex() },
            follow: { [weak self] id in
                guard let self = self else { return }
                self.defaults.set(id, forKey: "followingCodexThread")
                self.codexConnection.follow(id)
                self.codexConnection.refresh()
                self.renderTaskCard()
            }, open: { [weak self] id in self?.dispatch(.openCodexThread(id)) })
    }

    private func workspace() -> InformationCard {
        if let card = codexCard { return card }
        let card = InformationCard(title: "フォーエバーヤング · Project Desk", defaults: defaults)
        codexCard = card
        raceCard = card
        card.onPage = { [weak self] page in
            guard let self = self else { return }
            self.workspacePage = page
            switch page {
            case .tasks: self.showTaskCard()
            case .races: self.queryRaces(self.selectedRacePeriod, refresh: false)
            case .horse: self.queryHorse(refresh: false)
            case .integrations: self.showIntegrations()
            case .tools: self.refreshReminderData(); self.refreshTools(); card.show(near:self.panel.frame)
            }
        }
        card.onOpenCodex = { [weak self] in self?.openCodexApplication() }
        card.onQueryHorse = { [weak self] refresh in self?.queryHorse(refresh: refresh) }
        card.onPreferences = { [weak self] in self?.bubbles?.preferencesChanged(); self?.integrationsChanged() }
        card.onPrimary = { [weak self] value in
            guard let self = self else { return }; self.defaults.set(value,forKey:"primaryIntegration"); self.integrations.primary = value; self.integrationsChanged()
        }
        card.onLinkedAction = { [weak self] action,source,instance,token in self?.runLinkedAction(action,source:source,instance:instance,expectedToken:token) }
        card.onCodexCompose = { [weak self] preset in self?.bubbles?.compose(preset:preset) }
        card.onOfficialConnect = { [weak self] in self?.officialCodex.connect { _ in self?.integrationsChanged() } }
        card.onToggleCodex = { [weak self] in self?.toggleCodex() }
        card.onTools = { [weak self] object in self?.handleToolCommand(object) }
        refreshTools()
        renderTaskCard()
        renderRaceCard(nil, period: selectedRacePeriod)
        return card
    }

    private func startIntegrations() {
        integrations.primary = defaults.string(forKey:"primaryIntegration") ?? "auto"
        integrations.onTransition = { [weak self] event in self?.tools.receive(event) }
        integrations.onChange = { [weak self] in self?.integrationsChanged() }
        ideBridge.onEvent = { [weak self] event in self?.integrations.receive(event) }
        do { try ideBridge.start() } catch { bubbles?.showMessage("本地 IDE 通道无法创建，请查看使用说明。") }
        officialCodex.onEvent = { [weak self] id, event in
            guard let self = self else { return }; self.officialStates[id] = event
            if let snapshot = self.codexSnapshot { self.receiveCodex(snapshot) }
        }
        officialCodex.onChange = { [weak self] in self?.integrationsChanged() }
        if !CommandLine.arguments.contains(where: { $0.contains("test") }) { officialCodex.connect { [weak self] _ in self?.integrationsChanged() } }
        integrationsChanged()
    }
    private func integrationsChanged() {
        tools.reconcile(instances:Set(integrations.events.values.filter { $0.activeCount > 0 }.map { $0.key }))
        if externalStateUntil == 0 { applyCodexState(codexEnabled ? integrations.selected?.animation ?? .idle : .idle) }
        codexCard?.renderIntegrations(integrations.object,official:officialCodex.object)
        refreshTools()
    }
    @objc private func showIntegrations() {
        let card = workspace(); workspacePage = .integrations; card.selectPage(.integrations)
        integrationsChanged(); card.show(near:panel.frame)
    }
    private func sendToTrackedCodex(_ text: String, completion: @escaping(Result<Void,Error>)->Void) {
        guard let captured = composingThread else { completion(.failure(CodexRPCError.unavailable("请先在 Codex 任务页选择要跟随的任务。"))); return }
        codexConnection.freshSnapshot { [weak self] snapshot in
            guard let self = self else { return }
            guard snapshot.connected, let current = snapshot.threads.first(where:{$0.id == captured.id}) else { completion(.failure(CodexRPCError.unavailable("目标任务已不可用。请重新选择任务。"))); return }
            self.officialCodex.send(text,to:current,activeElsewhere:current.turnStatus == "inProgress") { result in
                if case .success = result { self.defaults.set(current.id,forKey:"followingCodexThread"); self.codexConnection.follow(current.id); self.codexConnection.refresh() }
                completion(result); self.integrationsChanged()
            }
        }
    }
    private func runLinkedAction(_ action: String, source explicitSource: LinkedSource? = nil, instance: String? = nil, expectedToken: String? = nil) {
        let source = explicitSource ?? integrations.selectedSource
        if source == .codex {
            if action == "stop" {
                guard let thread = codexSnapshot?.selected else { showTaskCard(); return }
                officialCodex.interrupt(thread) { [weak self] result in if case let .failure(error) = result { self?.bubbles?.showMessage(error.localizedDescription) } }
            } else {
                let preset = action == "test" ? "请检查项目现有测试配置并运行测试，报告结果。" : action == "review" ? "请检查当前未提交的改动，报告发现的问题。" : "请检查这个项目的现有运行配置，再运行项目并报告结果。"
                bubbles?.compose(preset:preset)
            }
        } else if let source = source {
            let target = instance == nil ? integrations.latest(source) : integrations.events[source.rawValue+":"+instance!]
            guard let target = target else { showIntegrations(); return }
            do {
                if ["run","runFile","build","test"].contains(action) && expectedToken == nil { showIntegrations(); return }
                try ideBridge.command(action,target:target,expectedToken:expectedToken)
                let language = defaults.string(forKey:"uiLanguage") ?? "zh"
                let hint = action == "stop"
                    ? ["zh":"请在 IDE 确认要停止的任务。","ja":"IDE で停止するタスクを確認してください。","en":"Confirm the task to stop in the IDE."]
                    : ["zh":"已请求操作；首次选定目标后可重复运行。","ja":"操作を要求しました。選択した対象は再利用します。","en":"Action requested. Selected targets are remembered."]
                bubbles?.showMessage("\(target.source.label) · \(hint[language] ?? hint["zh"]!)")
                NSWorkspace.shared.runningApplications.first { app in
                    app.bundleIdentifier == target.source.bundleID || (target.source == .pycharm && app.bundleIdentifier?.hasPrefix("com.jetbrains.pycharm") == true)
                }?.activate(options:[])
            }
            catch { bubbles?.showMessage("IDE 联动未连接或指令未送达。") }
        } else { showIntegrations() }
    }

    private func showTaskCard() {
        let card = workspace()
        workspacePage = .tasks
        card.selectPage(.tasks)
        renderTaskCard()
        card.show(near: panel.frame)
    }

    private func queryRaces(_ period: RacePeriod, refresh: Bool, show: Bool = true) {
        raceTask?.cancel()
        let queryID = UUID()
        raceQueryID = queryID
        selectedRacePeriod = period
        let card = workspace()
        workspacePage = .races
        nextDataRefresh = nowMilliseconds() + 300_000
        card.selectPage(.races)
        renderRaceCard(nil, period: period)
        if show { raceCard?.show(near: panel.frame) }
        raceTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let result = try await self.raceProvider.query(period, at: Date(), refresh: refresh)
                guard !Task.isCancelled, self.raceQueryID == queryID else { return }
                self.updateReminderRaces(result)
                self.renderRaceCard(result, period: period)
            } catch {
                guard !Task.isCancelled, self.raceQueryID == queryID else { return }
                self.renderRaceCard(nil, period: period, error: "查询失败：\(error.localizedDescription)")
            }
        }
    }

    private func renderRaceCard(_ result: RaceQueryResult?, period: RacePeriod, error: String? = nil, notice: String? = nil) {
        raceCard?.renderRaces(result, period: period, error: error, notice: notice,
            clearCache: { [weak self] in self?.dispatch(.clearRaceCache) },
            query: { [weak self] period, refresh in self?.dispatch(.queryRaces(period, refresh: refresh)) },
            open: { url in if RacingParse.allowed(url) { NSWorkspace.shared.open(url) } })
    }

    @objc private func clearRaceCache() {
        reminderTask?.cancel(); reminders.clearData(); nextReminderRefresh = nowMilliseconds()+900_000; refreshTools()
        horseTask?.cancel(); horseQueryID = UUID()
        nextDataRefresh = nowMilliseconds() + 300_000
        workspacePage = .races
        raceTask?.cancel()
        let queryID = UUID()
        raceQueryID = queryID
        let card = workspace()
        card.selectPage(.races)
        renderRaceCard(nil, period: selectedRacePeriod, notice: "正在清理赛事本地缓存…")
        raceCard?.show(near: panel.frame)
        raceTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let count = try await self.raceProvider.clearCache()
                guard !Task.isCancelled, self.raceQueryID == queryID else { return }
                self.codexCard?.renderHorse(nil, error: "cacheCleared")
                self.renderRaceCard(nil, period: self.selectedRacePeriod,
                    notice: "本地缓存已清理（\(count) 个文件）。当前未联网；点击查询或刷新官网可获取新数据。")
            } catch {
                guard !Task.isCancelled, self.raceQueryID == queryID else { return }
                self.renderRaceCard(nil, period: self.selectedRacePeriod, error: "缓存清理失败：\(error.localizedDescription)")
            }
        }
    }

    private func openCodexApplication() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
    @objc private func showHorse() { queryHorse(refresh: false) }
    private func queryHorse(refresh: Bool, show: Bool = true) {
        horseTask?.cancel()
        let id = UUID(); horseQueryID = id
        workspacePage = .horse; nextDataRefresh = nowMilliseconds() + 300_000
        let card = workspace(); card.selectPage(.horse)
        card.renderHorse(nil)
        if show { card.show(near: panel.frame) }
        horseTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let result = try await self.racingProvider.overview(refresh: refresh)
                guard !Task.isCancelled, self.horseQueryID == id else { return }
                self.reminders.update(result.races+result.upcoming,checks:result.checks); self.refreshTools()
                card.renderHorse(result)
            } catch {
                guard !Task.isCancelled, self.horseQueryID == id else { return }
                card.renderHorse(nil, error: error.localizedDescription)
            }
        }
    }

    private func startTools() {
        tools.onChange = { [weak self] in self?.refreshTools() }
        tools.onAlert = { [weak self] state,title in self?.pendingToolAlerts.append((state,title,Date())) }
        reminders.onAlert = { [weak self] state,title in self?.tools.addReminder(state,title:title) }
        updatePark()
    }
    private func refreshTools() {
        var object = tools.object; object["races"] = reminders.object
        object["diagnostics"] = integrations.object; object["official"] = officialCodex.object
        object["codexRecordConnected"] = codexSnapshot?.connected ?? false
        codexCard?.renderCompanion(object)
    }
    private func handleToolCommand(_ object: [String:Any]) {
        switch object["command"] as? String {
        case "toolSetting":
            if let key = object["key"] as? String, let value = object["value"] { tools.set(key,value:value); player.volume = tools.volume
                if tools.mode == "meeting" || (tools.mode == "focus" && voicePriority > 10) || tools.quiet() || defaults.object(forKey:"voiceEnabled") as? Bool == false { player.stop() }
                updatePark(); nextReminderRefresh = 0; bubbles?.preferencesChanged(); refreshTools()
            }
        case "timer": if let action = object["action"] as? String { tools.timerCommand(action,minutes:object["minutes"] as? Int ?? 25) }
        case "clearHistory": tools.clearHistory()
        case "audition":
            let context = object["context"] as? String ?? "click"
            guard ["click","working","completed","failed","interrupted"].contains(context), integrations.queue.isEmpty,
                  let cue = voices?.select(context,hour:Calendar.current.component(.hour,from:Date())) else { return }
            // Audition is an explicit user action; it bypasses quiet hours, but respects volume.
            _ = playVoice(cue,context:context,key:nil,at:nowMilliseconds(),wave:false)
        case "diagnose": codexConnection.refresh(); ideBridge.poll(); officialCodex.connect { [weak self] _ in self?.refreshTools() }; refreshTools()
        case "historyJump":
            guard let id = object["id"] as? String, let record = tools.history.first(where:{$0.id == id}) else { return }
            if record.source == "codex", let url = codexThreadURL(record.threadID) { NSWorkspace.shared.open(url) }
            else if let source = LinkedSource(rawValue:record.source), let event = integrations.events.values.first(where:{$0.source == source && $0.project == record.project && $0.state != .disconnected}) { runLinkedAction(object["action"] as? String == "openProblems" ? "openProblems":"openConsole",source:source,instance:event.instance) }
            else { showIntegrations() }
        case "exportCalendar":
            let id = object["id"] as? String
            let selected = reminders.races.filter { id == nil || RaceReminders.identity($0) == id }
            guard !selected.isEmpty else { return }
            let dialog = NSSavePanel(); dialog.nameFieldStringValue = "Forever-Young-races.ics"; dialog.allowedContentTypes = [.init(filenameExtension:"ics")!]
            if dialog.runModal() == .OK, let url = dialog.url { do { try RaceReminders.calendar(selected,language:defaults.string(forKey:"uiLanguage") ?? "zh").write(to:url,atomically:true,encoding:.utf8) } catch { bubbles?.showMessage(error.localizedDescription) } }
        default: break
        }
    }
    private func updatePark() {
        guard panel != nil else { return }
        if defaults.bool(forKey:"edgePark") {
            if parkedOrigin == nil { parkedOrigin = panel.frame.origin }
            let screen = NSScreen.screens.first(where:{$0.visibleFrame.intersects(panel.frame)})?.visibleFrame ?? NSScreen.main!.visibleFrame
            panel.setFrameOrigin(NSPoint(x:screen.maxX-panel.frame.width+min(90,panel.frame.width/2),y:max(screen.minY,min(panel.frame.minY,screen.maxY-panel.frame.height))))
        } else if let origin = parkedOrigin { panel.setFrameOrigin(origin); parkedOrigin = nil }
    }
    private func refreshReminderData() {
        guard reminderTask == nil else { return }
        reminderTask = Task { @MainActor [weak self] in
            guard let self = self else { return }; defer { self.reminderTask = nil }
            if let result = try? await self.raceProvider.query(.nextWeek,at:Date(),refresh:true), !Task.isCancelled { self.updateReminderRaces(result) }
            if let overview = try? await self.racingProvider.overview(refresh:true), !Task.isCancelled { self.reminders.update(overview.races+overview.upcoming,checks:overview.checks); self.refreshTools() }
        }
    }
    private func updateReminderRaces(_ result: RaceQueryResult) {
        var races = result.international
        for race in result.races + (result.nextRace.map { [$0] } ?? []) {
            races.append(WorldRace(date:RacingParse.day(race.date),name:race.name,venue:race.venue,course:race.course,zone:"Asia/Tokyo",source:race.pageURL))
        }
        reminders.update(races,checks:result.internationalChecks); refreshTools()
    }
    private func toolAlertText(_ state: String, title: String) -> String {
        let language = defaults.string(forKey:"uiLanguage") ?? "zh"
        let messages = ["zh":["restStart":"专注时间结束，休息五分钟吧。","restEnd":"休息结束。下一轮由你开始。","raceStart":"即将开赛：","raceDeclared":"出走信息已正式确认："],
                        "ja":["restStart":"集中タイム終了。5分休憩しましょう。","restEnd":"休憩終了。次のタイマーは手動で開始。","raceStart":"まもなく発走：","raceDeclared":"出走が正式に確定："],
                        "en":["restStart":"Focus session ended. Take a five-minute break.","restEnd":"Break ended. Start the next session when ready.","raceStart":"Race starts soon: ","raceDeclared":"Entry officially declared: "]]
        return (messages[language]?[state] ?? state)+title
    }

    @objc private func reconnectCodex() { codexCardFingerprint = ""; codexConnection.refresh() }

    @objc private func showCodexTasks() { dispatch(.showCodexTasks) }
    @objc private func openSelectedTask() {
        if let id = codexSnapshot?.selected?.id { dispatch(.openCodexThread(id)) }
        else { showTaskCard() }
    }
    @objc private func toggleCodex() {
        codexEnabled.toggle()
        defaults.set(codexEnabled, forKey: "codexLinked")
        codexToggleItem?.state = codexEnabled ? .on : .off
        externalStateUntil = 0
        if let snapshot = codexSnapshot { receiveCodex(snapshot) }
        if codexCard?.panel.isVisible == true { renderTaskCard() }
        tick()
    }
    @objc private func queryPastRaces() { dispatch(.queryRaces(.pastWeek, refresh: false)) }
    @objc private func queryNextRaces() { dispatch(.queryRaces(.nextWeek, refresh: false)) }
    @objc private func mouseMode() { player.stop(); dispatch(.preview(nil)); tick() }
    @objc private func previewAction(_ sender: NSMenuItem) {
        player.stop()
        dispatch(.preview(sender.tag))
        tick()
    }
    @objc private func toggleVisibility() {
        if panel.isVisible { panel.orderOut(nil); player.stop() }
        else { panel.orderFrontRegardless(); tick() }
    }
    @objc private func resetPosition() {
        guard let rect = NSScreen.main?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: rect.maxX - panel.frame.width - 40, y: rect.minY + 30))
        rememberPosition()
    }
    @objc private func resizePet(_ sender: NSMenuItem) {
        displayScale = Double(sender.tag) / 100
        let centerX = panel.frame.midX
        let size = NSSize(width: petSize.width * displayScale, height: petSize.height * displayScale)
        panel.setFrame(NSRect(x: centerX - size.width / 2, y: panel.frame.minY,
                              width: size.width, height: size.height), display: true)
        for item in sizeItems { item.state = item.tag == sender.tag ? .on : .off }
        defaults.set(displayScale, forKey: "displayScale")
        rememberPosition()
        tick()
    }
    private func rememberPosition() {
        defaults.set(panel.frame.origin.x, forKey: "petX")
        defaults.set(panel.frame.origin.y, forKey: "petY")
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !officialCodex.activeTurns.isEmpty else { return .terminateNow }
        let alert=NSAlert();alert.messageText="Codex 任务仍在桌宠的官方通道执行"
        alert.informativeText="退出桌宠会断开这些任务的控制通道。继续等待，或确认退出。";alert.addButton(withTitle:"继续等待");alert.addButton(withTitle:"退出桌宠")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        player?.stop()
        codexConnection.stop()
        ideBridge.stop(); officialCodex.stop()
        raceTask?.cancel(); horseTask?.cancel(); bubbles?.close()
        if let observer = stateObserver { DistributedNotificationCenter.default().removeObserver(observer) }
        codexCard?.panel.close()
        raceCard?.panel.close()
        if panel != nil { rememberPosition() }
    }

    // Opt-in local test evidence; normal launches do not create diagnostics files.
    private func writeDiagnostics() {
        guard let url = diagnosticURL else { return }
        let rect = panel.frame
        let report: [String: Any] = [
            "visible": panel.isVisible, "row": latestFrame?.row ?? -1, "column": latestFrame?.column ?? -1,
            "mode": latestFrame?.mode ?? "none", "lookIndex": runtime.lookIndex ?? -1,
            "jumpCount": runtime.jumpCount, "greetingCount": runtime.greetingCount,
            "voiceStarts": voiceStarts, "audioPlaying": player.isPlaying,
            "voiceID":voiceID, "voicePriority":voicePriority,
            "displayScale": displayScale,
            "codexConnected": codexSnapshot?.connected ?? false,
            "codexState": codexSnapshot?.activity.rawValue ?? "disconnected",
            "codexThreadID": codexSnapshot?.selected?.id ?? "",
            "codexTitle": codexSnapshot?.selected?.title ?? "",
            "codexAdapter": codexSnapshot?.message ?? "",
            "audioTime": player.currentTime, "audioDuration": player.duration, "voiceError": voiceError ?? "",
            "opaque": panel.isOpaque, "shadow": panel.hasShadow, "level": panel.level.rawValue,
            "frame": ["x": rect.origin.x, "y": rect.origin.y, "width": rect.width, "height": rect.height]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

extension AppDelegate {
    func checkIntegrationUI(resources: URL, directory: URL) throws -> [String] {
        _ = NSApplication.shared
        assets = try PetAssets(resources: resources)
        player = try AVAudioPlayer(contentsOf: assets.voiceURL)
        createPanel()
        createMenus()
        panel.orderFrontRegardless()
        defer { panel.close(); codexCard?.panel.close(); raceCard?.panel.close(); raceTask?.cancel() }
        let id = "00000000-0000-4000-8000-000000000001"
        let thread = CodexThreadSummary(id: id, title: "制作フォーエバーヤング桌宠（测试卡片）", cwd: "/本地项目/青春永驻",
            rollout: directory.appendingPathComponent("fixture.jsonl"), turnID: "test", turnStatus: "inProgress", startedAt: 0)
        receiveCodex(CodexSnapshot(connected: true, threads: [thread], selected: thread, activity: .working,
                                  message: "本地任务记录与事件 · 只读连接"))
        tick()
        try require(latestFrame?.mode == "codex-working", "real delegate renders Codex work")
        dispatch(.showCodexTasks)
        try require(codexCard?.panel.isVisible == true && codexCard?.displayedThreadCount == 1, "task card shows selected task")
        try codexCard!.awaitUI("document.querySelector('.fy-current h2')?.textContent.includes('测试卡片')")
        try codexCard?.capture(to: directory.appendingPathComponent("codex-card.png"))
        let otherThreads = (0..<8).map { index in
            CodexThreadSummary(id: UUID().uuidString, title: "滚动检查任务 \(index)", cwd: "/本地项目",
                rollout: directory.appendingPathComponent("fixture.jsonl"), turnID: "done", turnStatus: "completed", startedAt: 0)
        }
        let longSnapshot = CodexSnapshot(connected: true, threads: [thread] + otherThreads, selected: thread,
            activity: .waiting, message: "本地任务记录与事件 · 只读连接")
        codexCard!.renderCodex(longSnapshot, following: nil, enabled: true, follow: { _ in }, open: { _ in })
        try codexCard!.awaitUI("document.querySelectorAll('[data-uma-panel=tasks] .fy-thread-row').length===8")
        _ = try codexCard!.evaluateForCheck("window.scrollTo(0,200);true")
        let before = try codexCard!.evaluateForCheck("window.scrollY") as? Double ?? 0
        codexCard!.renderCodex(longSnapshot, following: nil, enabled: true, follow: { _ in }, open: { _ in })
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        let after = try codexCard!.evaluateForCheck("window.scrollY") as? Double ?? 0
        try require(before == 200 && after == before, "task status refresh preserves scroll position")
        _ = try codexCard!.evaluateForCheck("window.scrollTo(0,0);true")
        let workspaceChecks = try codexCard!.checkWorkspaceUI(defaults: defaults, directory: directory)
        renderTaskCard()
        dispatch(.queryRaces(.pastWeek, refresh: true))
        let deadline = Date(timeIntervalSinceNow: 3)
        while raceCard?.displayedRaceCount != 1 && Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)) }
        try require(raceCard?.panel.isVisible == true && raceCard?.displayedRaceCount == 1, "right-click command renders past-week race card")
        try raceCard!.awaitUI("document.querySelector('[data-uma-panel=races] .fy-race h2')?.textContent.includes('スプリンターズ')")
        try raceCard?.capture(to: directory.appendingPathComponent("jra-past-card.png"))
        try raceCard!.clickForCheck("[data-command=query][data-period=nextWeek]")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        try require(raceCard?.displayedRaceCount == 0, "next-week button queries and displays zero in-range races")
        try raceCard!.awaitUI("document.querySelector('[data-uma-panel=races]').textContent.includes('这七天没有')")
        try raceCard?.capture(to: directory.appendingPathComponent("jra-next-card.png"))
        try raceCard!.clickForCheck("[data-command=clearCache]")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        try require(raceCard?.cacheNotice?.contains("本地缓存已清理") == true, "cache button reaches provider and shows completion")
        try raceCard!.awaitUI("document.querySelector('[data-uma-panel=races]').textContent.includes('本地缓存已清理')")
        try raceCard?.capture(to: directory.appendingPathComponent("jra-cache-cleared.png"))
        try require(petView.menu?.items.contains { $0.action == #selector(queryPastRaces) } == true &&
            petView.menu?.items.contains { $0.action == #selector(showCodexTasks) } == true, "native pet right-click exposes both services")
        toggleCodex()
        try require(runtime.codexActivity == .idle && codexToggleItem?.state == .off, "menu pauses Codex animation")
        toggleCodex()
        try require(runtime.codexActivity == .working && codexToggleItem?.state == .on, "menu resumes Codex animation")
        return workspaceChecks + ["real AppDelegate renders Codex work", "task card renders current task", "unified race command opens populated card",
                "task refresh preserves scroll position", "actual next-week button queries empty week", "cache button calls provider and displays completion",
                "pet right-click includes Codex and JRA", "pause/resume Codex menu"]
    }

    // This reaches the same view callbacks used by a normal desktop launch.
    func checkVoicePlayback(resources: URL) throws -> [String] {
        func check(_ value: Bool) throws { if !value { throw CocoaError(.validationMissingMandatoryProperty) } }
        _ = NSApplication.shared
        assets = try PetAssets(resources:resources); voices = try VoiceLibrary(resources:resources)
        player = try AVAudioPlayer(contentsOf:assets.voiceURL)
        createPanel(); createMenus(); panel.orderFrontRegardless()
        defer { player.stop(); panel.orderOut(nil); bubbles?.close(); NSStatusBar.system.removeStatusItem(statusItem) }
        greet()
        try check(player.isPlaying && voicePriority == 10 && runtime.frame(at:nowMilliseconds()).mode == "waving")
        let starts = voiceStarts; greet(); try check(voiceStarts == starts)
        RunLoop.current.run(until:Date(timeIntervalSinceNow:0.12))
        try check(player.currentTime > 0.05)
        let failure = LinkedEvent(version:1,source:.vscode,instance:UUID().uuidString,sequence:1,sentAt:Date().timeIntervalSince1970*1000,state:.failed,runID:"voice-test",title:"Voice test",project:"",activeCount:0)
        applyCodexState(.failed); playStatusVoice(failure,at:nowMilliseconds())
        try check(player.isPlaying && voiceID == "surprise" && voicePriority == 40 && runtime.frame(at:nowMilliseconds()).mode != "waving")
        let criticalStarts = voiceStarts; playStatusVoice(failure,at:nowMilliseconds()+60_000)
        try check(voiceStarts == criticalStarts)
        toggleVoice(); greet()
        try check(!player.isPlaying && runtime.frame(at:nowMilliseconds()).mode == "waving")
        toggleVoice(); defaults.set(false,forKey:"automaticVoiceEnabled")
        playStatusVoice(failure,at:nowMilliseconds()+120_000)
        try check(!player.isPlaying)
        return ["Actual randomized click voice plays and waves", "Rapid clicks do not overlap or restart audio", "Audio output clock advances", "Failure preempts greeting without overriding failure animation", "Same failure event is not replayed", "Muted clicks still wave", "Automatic voice toggle suppresses status audio"]
    }

    func checkDragAnimation(resources: URL) throws -> [String] {
        enum DragCheckError: Error { case failed(String) }
        func check(_ condition: Bool, _ label: String) throws {
            if !condition { throw DragCheckError.failed(label) }
        }
        _ = NSApplication.shared
        assets = try PetAssets(resources: resources)
        player = try AVAudioPlayer(contentsOf: assets.voiceURL)
        createPanel()
        panel.orderFrontRegardless()
        defer { panel.close() }
        func capture(_ name: String) throws {
            guard let option = CommandLine.arguments.firstIndex(of: "--render-checks"),
                  option + 1 < CommandLine.arguments.count else { return }
            let directory = URL(fileURLWithPath: CommandLine.arguments[option + 1])
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            petView.displayIfNeeded()
            guard let bitmap = petView.bitmapImageRepForCachingDisplay(in: petView.bounds) else {
                throw DragCheckError.failed("view bitmap capture")
            }
            petView.cacheDisplay(in: petView.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
        }
        func event(_ type: NSEvent.EventType, _ x: Double, _ y: Double) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: y), modifierFlags: [],
                               timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                               eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        petView.mouseDown(with: event(.leftMouseDown, 100, 100))
        petView.mouseDragged(with: event(.leftMouseDragged, 130, 100))
        let right = runtime.frame(at: nowMilliseconds())
        try check(right.row == 1 && right.mode == "dragging-right", "drag right selects running-right animation")
        try capture("drag-right")
        petView.mouseDragged(with: event(.leftMouseDragged, 90, 100))
        let left = runtime.frame(at: nowMilliseconds())
        try check(left.row == 2 && left.mode == "dragging-left", "reversing drag selects running-left animation")
        try capture("drag-left")
        petView.mouseUp(with: event(.leftMouseUp, 100, 100))
        try check(!runtime.frame(at: nowMilliseconds()).mode.hasPrefix("dragging") && runtime.greetingCount == 0,
                  "release stops running without greeting")
        petView.mouseDown(with: event(.leftMouseDown, 100, 100))
        petView.mouseUp(with: event(.leftMouseUp, 100, 100))
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.9))
        tick()
        try check(player.isPlaying && latestFrame?.mode == "waving", "actual click waves beyond original 0.7-second animation")
        try capture("greeting-during-voice")
        player.stop()
        tick()
        try check(latestFrame?.mode != "waving", "stopped audio releases waving")
        let sizeItem = NSMenuItem(title: "test", action: nil, keyEquivalent: "")
        sizeItem.tag = 150
        resizePet(sizeItem)
        try check(panel.frame.size == NSSize(width: 288, height: 312) && petView.bounds.size == panel.frame.size,
                  "size menu resizes both window and artwork")
        try capture("size-150")
        sizeItem.tag = 100
        resizePet(sizeItem)
        try check(panel.frame.size == petSize, "native pixel size can be restored")
        try capture("size-100")
        return ["actual app drag right runs right", "drag reversal runs left", "release returns to interaction",
                "actual click waves through official audio", "audio stop releases greeting",
                "size menu resizes window and artwork; native size restored"]
    }
}

// Test the real NSView mouse handlers with local events; never posts OS input events.
func runWindowEventChecks(resources: URL) throws -> [String] {
    enum WindowCheckError: Error { case failed(String) }
    func check(_ condition: Bool, _ label: String) throws {
        if !condition { throw WindowCheckError.failed(label) }
    }
    _ = NSApplication.shared
    let panel = PetPanel(contentRect: NSRect(x: 100, y: 100, width: 231, height: 250),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    let view = PetView(frame: NSRect(x: 0, y: 0, width: 231, height: 250))
    panel.contentView = view
    let assets = try PetAssets(resources: resources)
    let player = try AVAudioPlayer(contentsOf: assets.voiceURL)
    var greetings = 0
    var moves = 0
    var played = false
    view.greet = { greetings += 1; played = restartOfficialVoice(player) }
    view.moved = { moves += 1 }
    func event(_ type: NSEvent.EventType, _ x: Double, _ y: Double) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: y), modifierFlags: [],
                           timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                           eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    let initial = panel.frame.origin
    view.mouseDown(with: event(.leftMouseDown, 100, 100))
    view.mouseDragged(with: event(.leftMouseDragged, 130, 120))
    try check(abs(panel.frame.origin.x - initial.x - 30) < 0.1 &&
              abs(panel.frame.origin.y - initial.y - 20) < 0.1, "drag follows event screen coordinates")
    view.mouseUp(with: event(.leftMouseUp, 100, 100))
    try check(moves == 1 && greetings == 0, "drag release does not greet")
    view.mouseDown(with: event(.leftMouseDown, 100, 100))
    view.mouseUp(with: event(.leftMouseUp, 100, 100))
    try check(greetings == 1 && played, "click invokes greeting and actual audio playback")
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.16))
    try check(player.isPlaying && player.currentTime > 0.08, "audio clock advances on output device")
    view.mouseDown(with: event(.leftMouseDown, 100, 100))
    view.mouseUp(with: event(.leftMouseUp, 100, 100))
    try check(greetings == 2 && played && player.currentTime < 0.05, "repeat click restarts the same player")
    player.stop()
    panel.close()
    return ["NSView drag changes window origin", "drag release does not greet",
            "NSView click reaches official audio playback", "audio output clock advances",
            "repeat click rewinds the same player"]
}

func printJSON(_ value: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}

if let index = CommandLine.arguments.firstIndex(of: "--send-codex-state") {
    guard index + 1 < CommandLine.arguments.count,
          let state = LocalPetCommand.parse(Data(CommandLine.arguments[index + 1].utf8)) else {
        fputs("Expected JSON: {\"version\":1,\"state\":\"working\"}\n", stderr); exit(1)
    }
    let json = "{\"version\":1,\"state\":\"\(state.rawValue)\"}"
    DistributedNotificationCenter.default().postNotificationName(LocalPetCommand.notification, object: nil,
        userInfo: ["command": json], options: [.deliverImmediately])
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    print("Local state sent: \(state.rawValue)"); exit(0)
}

if let index = CommandLine.arguments.firstIndex(of:"--companion-test") {
    do {
        _ = NSApplication.shared
        let directory=URL(fileURLWithPath:CommandLine.arguments[index+1]);let suite="org.foreveryoungpet.tests.\(UUID().uuidString)";let defaults=UserDefaults(suiteName:suite)!
        defer {defaults.removePersistentDomain(forName:suite)}
        var checks=try runCompanionChecks(defaults:defaults,directory:directory)
        let card=InformationCard(title:"Companion v3.7 checks",defaults:defaults)
        checks += try card.checkCompanionUI(defaults:defaults,directory:directory)
        card.panel.close();try printJSON(["ok":true,"checks":checks]);exit(0)
    } catch {fputs("Companion checks failed: \(error)\n",stderr);exit(1)}
}

if CommandLine.arguments.contains("--codex-check") {
    let running = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.openai.codex" }
    let snapshot = CodexHistoryReader().snapshot(clientRunning: running)
    try printJSON(["connected": snapshot.connected, "activity": snapshot.activity.rawValue, "message": snapshot.message,
                   "threadCount": snapshot.threads.count, "selectedID": snapshot.selected?.id ?? "", "title": snapshot.selected?.title ?? ""])
    exit(snapshot.connected ? 0 : 1)
}

if let index = CommandLine.arguments.firstIndex(of: "--integration-test") {
    guard index + 1 < CommandLine.arguments.count else { exit(1) }
    let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1])
    Task {
        do { try printJSON(["ok": true, "checks": try await runProviderChecks(directory: directory)]); exit(0) }
        catch { fputs("Integration test failed: \(error)\n", stderr); exit(1) }
    }
    dispatchMain()
}

if let index = CommandLine.arguments.firstIndex(of: "--racing-test") {
    guard index + 1 < CommandLine.arguments.count else { exit(1) }
    let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1])
    Task {
        do { try printJSON(["ok": true, "checks": try await runRacingChecks(directory: directory)]); exit(0) }
        catch { fputs("Racing test failed: \(error)\n", stderr); exit(1) }
    }
    dispatchMain()
}
if CommandLine.arguments.contains("--racing-check") {
    Task {
        do {
            let result = try await RacingProvider().overview(refresh: true)
            try printJSON(["ok": result.historyAvailable && !result.races.isEmpty, "raceCount": result.races.count,
                           "upcoming": result.upcoming.map { $0.object }, "historyCount": result.history.count,
                           "checks": result.checks.map { $0.object }, "warnings": result.warnings])
            exit(result.historyAvailable && !result.races.isEmpty ? 0 : 1)
        } catch { fputs("Racing check failed: \(error)\n", stderr); exit(1) }
    }
    dispatchMain()
}
if let index = CommandLine.arguments.firstIndex(of:"--linked-test") {
    do {
        _ = NSApplication.shared
        let directory=URL(fileURLWithPath:CommandLine.arguments[index+1]); let suite="org.foreveryoungpet.tests.\(UUID().uuidString)";let defaults=UserDefaults(suiteName:suite)!
        defer {defaults.removePersistentDomain(forName:suite)}
        var checks=try runLinkedChecks(directory:directory)
        let card=InformationCard(title:"Linked UI checks",defaults:defaults)
        checks += try card.checkLinkedUI(defaults:defaults,directory:directory)
        card.panel.close();try printJSON(["ok":true,"checks":checks]);exit(0)
    } catch {fputs("Linked checks failed: \(error)\n",stderr);exit(1)}
}
if CommandLine.arguments.contains("--official-check") {
    _ = NSApplication.shared
    let rpc=OfficialCodex()
    let selected=CodexHistoryReader().snapshot(clientRunning:true).selected
    rpc.connect { result in
        if case let .failure(error)=result {fputs("Official check failed: \(error.localizedDescription)\n",stderr);exit(1)}
        guard let thread=selected else {try? printJSON(["ok":true,"transport":rpc.proxy ? "proxy":"stdio","read":false]);rpc.stop();exit(0)}
        rpc.request("thread/read",["threadId":thread.id,"includeTurns":false]) { response in
            switch response {
            case let .failure(error):fputs("Official metadata read failed: \(error.localizedDescription)\n",stderr);rpc.stop();exit(1)
            case let .success(value):try? printJSON(["ok":true,"transport":rpc.proxy ? "proxy":"stdio","read":true,"threadID":(value["thread"] as? [String:Any])?["id"] ?? "","inferenceStarted":false]);rpc.stop();exit(0)
            }
        }
    }
    RunLoop.main.run();exit(1)
}
if let index = CommandLine.arguments.firstIndex(of: "--bubble-test") {
    do {
        guard index + 1 < CommandLine.arguments.count else { exit(1) }
        _ = NSApplication.shared
        let suite = "org.foreveryoungpet.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let pasteboard = NSPasteboard.withUniqueName(); defer { pasteboard.releaseGlobally() }
        let bubbles = PetBubbles(defaults: defaults, pasteboard: pasteboard)
        try printJSON(["ok":true,"checks":try bubbles.checkNativeBubbles(directory:URL(fileURLWithPath:CommandLine.arguments[index+1]))])
        exit(0)
    } catch { fputs("Bubble check failed: \(error)\n", stderr); exit(1) }
}
if let index = CommandLine.arguments.firstIndex(of: "--racing-ui-test") {
    do {
        guard index + 1 < CommandLine.arguments.count else { exit(1) }
        _ = NSApplication.shared
        let suite = "org.foreveryoungpet.tests.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suite)!
        defer { testDefaults.removePersistentDomain(forName: suite) }
        let card = InformationCard(title: "Racing UI check", defaults: testDefaults)
        try printJSON(["ok":true,"checks":try card.checkRacingUI(directory:URL(fileURLWithPath:CommandLine.arguments[index+1]))])
        card.panel.close(); exit(0)
    } catch { fputs("Racing UI check failed: \(error)\n", stderr); exit(1) }
}

if CommandLine.arguments.contains("--jra-check") {
    Task {
        do {
            let provider = JRAProvider()
            let past = try await provider.query(.pastWeek, at: Date(), refresh: true)
            let next = try await provider.query(.nextWeek, at: Date(), refresh: false)
            try printJSON(["ok": true, "pastWeek": past.races.map { ["name": $0.name, "venue": $0.venue, "course": $0.course, "winner": $0.winner, "url": $0.pageURL.absoluteString] },
                           "nextWeek": next.races.map { $0.name }, "nextOutsideWeek": next.nextRace?.name ?? "", "cached": past.cached,
                           "warning": past.warning ?? "", "fetchedAt": ISO8601DateFormatter().string(from: past.fetchedAt)])
            exit(0)
        } catch { fputs("JRA query failed: \(error.localizedDescription)\n", stderr); exit(1) }
    }
    dispatchMain()
}

if let index = CommandLine.arguments.firstIndex(of: "--integration-ui-test") {
    do {
        guard index + 1 < CommandLine.arguments.count, let resources = Bundle.main.resourceURL else { exit(1) }
        let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        let date = JRAProvider.calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 12))!
        let year = try JRAProvider.parse(Data(contentsOf: directory.appendingPathComponent("jra-g1-official.html")), expectedYear: 2026,
            sourceURL: URL(string: "https://jra.jp/datafile/seiseki/replay/g1.html")!, fetchedAt: date)
        let suite = "org.foreveryoungpet.tests.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suite)!
        defer { testDefaults.removePersistentDomain(forName: suite) }
        let testDelegate = AppDelegate(defaults: testDefaults, raceProvider: FixtureRaceProvider(year: year, now: date))
        try printJSON(["ok": true, "checks": try testDelegate.checkIntegrationUI(resources: resources, directory: directory)])
        exit(0)
    } catch { fputs("Integration UI test failed: \(error)\n", stderr); exit(1) }
}

if CommandLine.arguments.contains("--voice-ui-test") {
    do {
        guard let resources = Bundle.main.resourceURL else { throw CocoaError(.fileNoSuchFile) }
        let suite = "org.foreveryoungpet.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let delegate = AppDelegate(defaults:defaults)
        try printJSON(["ok":true,"checks":try delegate.checkVoicePlayback(resources:resources)])
        exit(0)
    } catch { fputs("Voice playback test failed: \(error)\n",stderr); exit(1) }
}

if CommandLine.arguments.contains("--ui-self-test") {
    do {
        guard let resources = Bundle.main.resourceURL else { throw CocoaError(.fileNoSuchFile) }
        let suite = "org.foreveryoungpet.tests.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suite)!
        defer { testDefaults.removePersistentDomain(forName: suite) }
        let testDelegate = AppDelegate(defaults: testDefaults)
        let checks = try testDelegate.checkDragAnimation(resources: resources) + runWindowEventChecks(resources: resources)
        let data = try JSONSerialization.data(withJSONObject: ["ok": true, "checks": checks],
                                              options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        exit(0)
    } catch {
        fputs("Window event test failed: \(error)\n", stderr)
        exit(1)
    }
}

if CommandLine.arguments.contains("--self-test") {
    do {
        var checks = try runInteractionChecks() + runCodexAnimationChecks()
        guard let resources = Bundle.main.resourceURL else { throw CocoaError(.fileNoSuchFile) }
        let assets = try PetAssets(resources: resources)
        checks += try runVoiceChecks(resources:resources)
        let player = try AVAudioPlayer(contentsOf: assets.voiceURL)
        guard assets.frames.map({ $0.count }).reduce(0, +) == 73, player.duration > 2.8, player.duration < 3.1 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        checks.append("AppKit decodes all 73 PNG frame crops")
        checks.append("AVAudioPlayer decodes the unchanged official voice")
        let report: [String: Any] = ["ok": true, "checks": checks, "voiceDuration": player.duration]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        exit(0)
    } catch {
        fputs("Self-test failed: \(error)\n", stderr)
        exit(1)
    }
}

let application = NSApplication.shared
if let identifier = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: identifier).contains(where: {
       $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
   }) { exit(0) }
application.setActivationPolicy(.accessory)
let delegate = AppDelegate()
application.delegate = delegate
application.run()
