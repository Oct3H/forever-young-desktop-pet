import AppKit

enum PetBubbleText {
    static func value(_ key: String, language: String) -> String {
        let strings: [String: [String: String]] = [
            "desk":["zh":"打开工作台", "ja":"ワークスペース", "en":"Workspace"],
            "input":["zh":"文字输入", "ja":"テキスト入力", "en":"Text input"],
            "close":["zh":"关闭", "ja":"閉じる", "en":"Close"],
            "run":["zh":"运行／快捷操作", "ja":"実行／ショートカット", "en":"Run / shortcuts"],
            "links":["zh":"联动来源", "ja":"連携先", "en":"Linked apps"],
            "send":["zh":"发送到此任务", "ja":"このタスクに送信", "en":"Send to this task"],
            "sent":["zh":"已通过官方接口发送。", "ja":"公式 API で送信しました。", "en":"Sent through the official API."],
            "sending":["zh":"发送中，请勿重复操作…", "ja":"送信中…", "en":"Sending; please wait…"],
            "compose":["zh":"写给 Codex", "ja":"Codex への入力", "en":"Write to Codex"],
            "hint":["zh":"发送将启动或追加一轮 Codex 任务。执行仍遵守原有审批与沙盒规则。", "ja":"送信で Codex のターンを開始／追加します。承認とサンドボックス設定は維持します。", "en":"Send starts or steers a Codex turn. Existing approval and sandbox rules are preserved."],
            "copy":["zh":"复制并打开 Codex", "ja":"コピーして Codex を開く", "en":"Copy and open Codex"],
            "copied":["zh":"已复制，请在 Codex 粘贴并发送。", "ja":"コピーしました。Codex で貼り付けて送信してください。", "en":"Copied. Paste and send in Codex."],
            "working":["zh":"Codex 正在处理这项任务。", "ja":"Codex がこのタスクを実行中です。", "en":"Codex is working on this task."],
            "waiting":["zh":"正在等待工具返回结果。", "ja":"ツールの結果を待っています。", "en":"Waiting for a tool result."],
            "review":["zh":"正在检查本轮结果。", "ja":"今回の結果を確認中です。", "en":"Reviewing this turn’s result."],
            "completed":["zh":"这一轮已经完成。", "ja":"このターンが完了しました。", "en":"This turn is complete."],
            "failed":["zh":"这一轮失败了，请到 Codex 查看。", "ja":"このターンは失敗しました。Codex を確認してください。", "en":"This turn failed. Check Codex."],
            "interrupted":["zh":"这一轮已中断。", "ja":"このターンは中断されました。", "en":"This turn was interrupted."],
            "disconnected":["zh":"暂时无法确认 Codex 状态。", "ja":"Codex の状態を確認できません。", "en":"Codex status is currently unconfirmed."],
            "idle":["zh":"Codex 当前空闲。", "ja":"Codex は待機中です。", "en":"Codex is idle."]]
        return strings[key]?[language] ?? strings[key]?["zh"] ?? key
    }
}

final class PetBubbles: NSObject {
    let actions: NSPanel
    let status: NSPanel
    private let defaults: UserDefaults
    private let pasteboard: NSPasteboard
    private let statusLabel: NSTextField
    private let taskLabel: NSTextField
    private let sourceLabel: NSTextField
    private let greetingLabel: NSTextField
    private var actionButtons: [NSButton] = []
    private var composer: NSPanel?
    private var editor: NSTextView?
    private var hint: NSTextField?
    private var copyButton: NSButton?
    private var sendButton: NSButton?
    private var targetLabel: NSTextField?
    private var sending = false
    private(set) var statusPriority = 0
    private var greetings: [Int] = []
    private var lastGreeting = -1
    var composeTarget = ""
    var onBeginCompose: (() -> Void)?
    var onSend: ((String,@escaping(Result<Void,Error>)->Void)->Void)?
    var onRun: (() -> Void)?
    var onLinks: (() -> Void)?
    private var lastKey = ""
    private var lastShown: Date = .distantPast
    private var statusUntil = Date.distantPast
    private var actionsUntil = Date.distantPast
    private var currentActivity: CodexActivity = .idle
    private var currentTitle = ""
    private(set) var copiedCount = 0
    var onWorkspace: (() -> Void)?
    var onOpenCodex: (() -> Void)?
    private var language: String { defaults.string(forKey: "uiLanguage") ?? "zh" }

    private static func makePanel(size: NSSize) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .floating; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .aqua)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let box = NSBox(frame: NSRect(origin: .zero, size: size)); box.boxType = .custom
        box.cornerRadius = 14; box.fillColor = .white; box.borderColor = NSColor(calibratedRed: 0.77, green: 0.84, blue: 0.67, alpha: 1)
        box.borderWidth = 1; box.contentViewMargins = .zero; panel.contentView = box
        return panel
    }
    init(defaults: UserDefaults = .standard, pasteboard: NSPasteboard = .general) {
        self.defaults = defaults
        self.pasteboard = pasteboard
        actions = Self.makePanel(size: NSSize(width: 300, height: 66))
        status = Self.makePanel(size: NSSize(width: 288, height: 108))
        actions.title = "フォーエバーヤング · Actions"
        status.title = "Codex · Status"
        statusLabel = NSTextField(wrappingLabelWithString: "")
        taskLabel = NSTextField(labelWithString: "")
        sourceLabel = NSTextField(labelWithString: "")
        greetingLabel = NSTextField(labelWithString: "")
        super.init()
        sourceLabel.frame = NSRect(x:14,y:84,width:260,height:16); sourceLabel.font = .systemFont(ofSize:10,weight:.semibold)
        sourceLabel.textColor = NSColor(calibratedWhite:0.4,alpha:1)
        statusLabel.frame = NSRect(x: 14, y: 40, width: 260, height: 42)
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium); statusLabel.textColor = NSColor(calibratedWhite: 0.17, alpha: 1)
        taskLabel.frame = NSRect(x: 14, y: 23, width: 260, height: 18)
        taskLabel.font = .systemFont(ofSize: 11); taskLabel.textColor = .secondaryLabelColor
        taskLabel.lineBreakMode = .byTruncatingTail
        greetingLabel.frame = NSRect(x:14,y:7,width:260,height:14); greetingLabel.font = .systemFont(ofSize:10); greetingLabel.textColor = .secondaryLabelColor
        status.contentView!.addSubview(sourceLabel); status.contentView!.addSubview(greetingLabel)
        status.contentView!.addSubview(statusLabel); status.contentView!.addSubview(taskLabel)
        let symbols = ["square.grid.2x2","text.bubble","play.fill","point.3.connected.trianglepath.dotted","xmark"]
        let selectors = [#selector(openDesk),#selector(openInput),#selector(runShortcut),#selector(openLinks),#selector(hideActions)]
        for (i, key) in ["desk", "input", "run", "links", "close"].enumerated() {
            let button = NSButton(title: "", target: self, action:selectors[i])
            button.bezelStyle = .circular; button.imagePosition = .imageOnly
            button.image = NSImage(systemSymbolName:symbols[i],accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:25,weight:.medium))
            button.frame = NSRect(x: 12 + i * 56, y: 10, width: 52, height: 46)
            button.identifier = NSUserInterfaceItemIdentifier(key)
            actions.contentView!.addSubview(button); actionButtons.append(button)
        }
        preferencesChanged()
    }
    func preferencesChanged() {
        let anime = defaults.string(forKey:"uiStyle") != "minimal"
        for box in [actions.contentView,status.contentView].compactMap({$0 as? NSBox}) {
            box.fillColor = anime ? NSColor(calibratedRed:0.96,green:0.985,blue:0.93,alpha:1) : .white
            box.borderColor = anime ? NSColor(calibratedRed:0.55,green:0.73,blue:0.32,alpha:1) : NSColor(calibratedWhite:0.84,alpha:1)
        }
        for button in actionButtons {
            let label = PetBubbleText.value(button.identifier!.rawValue,language:language)
            button.title = ""; button.toolTip = label; button.setAccessibilityLabel(label)
            button.contentTintColor = anime ? NSColor(calibratedRed:0.27,green:0.46,blue:0.13,alpha:1) : NSColor(calibratedWhite:0.24,alpha:1)
        }
        statusLabel.stringValue = PetBubbleText.value(currentActivity.rawValue, language: language)
        composer?.title = PetBubbleText.value("compose", language: language)
        hint?.stringValue = PetBubbleText.value("hint", language: language)
        copyButton?.title = PetBubbleText.value("copy", language: language)
        sendButton?.title = PetBubbleText.value("send",language:language)
        targetLabel?.stringValue = composeTarget
    }
    func showActions(near pet: NSRect) {
        actionsUntil = Date(timeIntervalSinceNow: 15)
        position(near: pet); actions.orderFrontRegardless()
    }
    func update(_ snapshot: CodexSnapshot, enabled: Bool) {
        guard enabled else { status.orderOut(nil); return }
        let key = (snapshot.selected?.id ?? "") + (snapshot.selected?.turnID ?? "") + snapshot.activity.rawValue
        guard key != lastKey else { return }
        let first = lastKey.isEmpty
        lastKey = key; currentActivity = snapshot.activity; currentTitle = snapshot.selected?.title ?? "Codex"
        // Do not replay a historical completion at startup or repeatedly report tool-state oscillation.
        guard !(first && (snapshot.activity.isTransient || snapshot.activity == .idle)),
              snapshot.activity.isTransient || Date().timeIntervalSince(lastShown) >= 20 else { return }
        lastShown = Date(); statusUntil = Date(timeIntervalSinceNow: 7)
        statusLabel.stringValue = PetBubbleText.value(snapshot.activity.rawValue, language: language)
        taskLabel.stringValue = currentTitle; taskLabel.toolTip = currentTitle
        status.orderFrontRegardless()
    }
    var canPresentNotice: Bool { !status.isVisible || Date() >= statusUntil || statusPriority < 70 }
    func showNotice(_ event: LinkedEvent) {
        statusPriority = 70; currentActivity = event.state; currentTitle = event.title
        lastShown = Date(); statusUntil = Date(timeIntervalSinceNow:6)
        sourceLabel.stringValue = event.source.label
        statusLabel.stringValue = PetBubbleText.value(event.state.rawValue,language:language).replacingOccurrences(of:"Codex",with:event.source.label)
        taskLabel.stringValue = event.title; taskLabel.toolTip = event.title; greetingLabel.stringValue = ""
        status.orderFrontRegardless()
    }
    func showClickStatus(_ event: LinkedEvent?) {
        guard canPresentNotice else { return } // First unseen transitions always precede click/greeting text.
        if let event = event { showNotice(event) }
        else { sourceLabel.stringValue = "Forever Young"; statusLabel.stringValue = PetBubbleText.value("idle",language:language); taskLabel.stringValue = ""; statusUntil = Date(timeIntervalSinceNow:6); status.orderFrontRegardless() }
        statusPriority = 20
        if greetings.isEmpty { greetings = Array(0..<3).shuffled(); if greetings.first == lastGreeting { greetings.reverse() } }
        lastGreeting = greetings.removeFirst()
        let lines = language == "ja" ? ["こんにちは。","ここにいるよ。","ひと休みしよう。"] : language == "en" ? ["Hello there.","I’m here with you.","Time for a short break?"] : ["你好，我在这里。","今天也陪着你。","记得稍微休息一下。"]
        greetingLabel.stringValue = lines[lastGreeting]
    }
    func showMessage(_ message: String) {
        statusPriority = 70; sourceLabel.stringValue = "Forever Young"; statusLabel.stringValue = message
        taskLabel.stringValue = ""; greetingLabel.stringValue = ""; statusUntil = Date(timeIntervalSinceNow:8); status.orderFrontRegardless()
    }
    func position(near pet: NSRect) {
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(pet) }?.visibleFrame ?? NSScreen.main!.visibleFrame
        func clamp(_ origin: NSPoint, panel: NSPanel) -> NSPoint {
            NSPoint(x: max(screen.minX, min(origin.x, screen.maxX - panel.frame.width)),
                    y: max(screen.minY, min(origin.y, screen.maxY - panel.frame.height)))
        }
        var bottom = pet.minY - actions.frame.height - 6
        if bottom < screen.minY { bottom = pet.maxY + 6 }
        actions.setFrameOrigin(clamp(NSPoint(x: pet.midX - actions.frame.width / 2, y: bottom), panel: actions))
        var top = pet.maxY + 8
        if top + status.frame.height > screen.maxY { top = pet.minY - status.frame.height - 8 }
        if actions.isVisible && abs(top - bottom) < status.frame.height {
            let above = bottom + actions.frame.height + 6
            top = above + status.frame.height <= screen.maxY ? above : bottom - status.frame.height - 6
        }
        status.setFrameOrigin(clamp(NSPoint(x: pet.midX - status.frame.width / 2, y: top), panel: status))
    }
    func tick(near pet: NSRect, visible: Bool, dragging: Bool) {
        guard visible && !dragging else { actions.orderOut(nil); status.orderOut(nil); return }
        if Date() >= actionsUntil { actions.orderOut(nil) }
        if Date() >= statusUntil { status.orderOut(nil) }
        if actions.isVisible || status.isVisible { position(near: pet) }
    }
    @objc private func openDesk() { hideActions(); onWorkspace?() }
    @objc private func runShortcut() { hideActions(); onRun?() }
    @objc private func openLinks() { hideActions(); onLinks?() }
    @objc private func hideActions() { actions.orderOut(nil); actionsUntil = .distantPast }
    @objc func openInput() {
        hideActions()
        onBeginCompose?()
        if composer == nil {
            let panel = NSPanel(contentRect: NSRect(x: 200, y: 200, width: 390, height: 260), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            panel.level = .floating; panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
            panel.appearance = NSAppearance(named: .aqua)
            let target = NSTextField(labelWithString:composeTarget); target.frame = NSRect(x:14,y:232,width:362,height:18); target.font = .systemFont(ofSize:11,weight:.semibold); target.lineBreakMode = .byTruncatingMiddle
            panel.contentView!.addSubview(target); targetLabel = target
            let scroll = NSScrollView(frame: NSRect(x: 14, y: 90, width: 362, height: 132)); scroll.hasVerticalScroller = true
            scroll.borderType = .bezelBorder
            let editor = NSTextView(frame: scroll.bounds); editor.isRichText = false; editor.font = .systemFont(ofSize: 14)
            editor.isVerticallyResizable = true; editor.autoresizingMask = [.width]; editor.textContainer?.widthTracksTextView = true
            scroll.documentView = editor; panel.contentView!.addSubview(scroll); self.editor = editor
            let hint = NSTextField(wrappingLabelWithString: ""); hint.frame = NSRect(x: 14, y: 45, width: 362, height: 40)
            hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor; panel.contentView!.addSubview(hint); self.hint = hint
            let button = NSButton(title: "", target: self, action: #selector(copyAndOpen)); button.bezelStyle = .rounded
            button.frame = NSRect(x: 14, y: 8, width: 178, height: 30); panel.contentView!.addSubview(button); copyButton = button
            let send = NSButton(title:"",target:self,action:#selector(sendText)); send.bezelStyle = .rounded; send.keyEquivalent = "\r"
            send.frame = NSRect(x:198,y:8,width:178,height:30); panel.contentView!.addSubview(send); sendButton = send
            composer = panel; panel.center()
        }
        preferencesChanged(); NSApp.activate(ignoringOtherApps: true)
        composer?.makeKeyAndOrderFront(nil); composer?.makeFirstResponder(editor)
    }
    func compose(preset: String) { openInput(); editor?.string = preset }
    @objc private func sendText() {
        guard !sending, let value = editor?.string.trimmingCharacters(in:.whitespacesAndNewlines), !value.isEmpty, value.utf8.count <= 32_768 else { NSSound.beep(); return }
        guard let onSend = onSend else { hint?.stringValue = "Codex 未连接。"; return }
        sending = true; sendButton?.isEnabled = false; editor?.isEditable = false
        hint?.stringValue = PetBubbleText.value("sending",language:language)
        onSend(value) { [weak self] result in
            guard let self = self else { return }; self.sending = false; self.sendButton?.isEnabled = true; self.editor?.isEditable = true
            switch result {
            case .success: self.editor?.string = ""; self.hint?.stringValue = PetBubbleText.value("sent",language:self.language)
            case let .failure(error): self.hint?.stringValue = error.localizedDescription; self.hint?.toolTip = error.localizedDescription
                let alert = NSAlert(); alert.messageText = "Codex"; alert.informativeText = error.localizedDescription; alert.runModal()
            }
        }
    }
    @objc private func copyAndOpen() {
        guard let value = editor?.string.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty, value.utf8.count <= 32_768 else { NSSound.beep(); return }
        pasteboard.clearContents(); pasteboard.setString(value, forType: .string)
        copiedCount += 1; hint?.stringValue = PetBubbleText.value("copied", language: language)
        onOpenCodex?()
    }
    func close() { actions.close(); status.close(); composer?.close() }
}

extension PetBubbles {
    func checkNativeBubbles(directory: URL) throws -> [String] {
        let id = "00000000-0000-4000-8000-000000000001"
        let thread = CodexThreadSummary(id: id, title: "气泡验证任务", cwd: "/tmp", rollout: directory.appendingPathComponent("fixture.jsonl"), turnID: "test", turnStatus: "inProgress", startedAt: 0)
        let completed = CodexSnapshot(connected: true, threads: [thread], selected: thread, activity: .completed, message: "fixture")
        update(completed, enabled: true)
        try require(!status.isVisible, "historical completion does not show a bubble")
        let working = CodexSnapshot(connected: true, threads: [thread], selected: thread, activity: .working, message: "fixture")
        update(working, enabled: true)
        try require(status.isVisible && statusLabel.stringValue.contains("正在处理") && taskLabel.stringValue == thread.title, "actual native work bubble uses lifecycle and task title")
        let stamp = lastShown; update(working, enabled: true)
        try require(lastShown == stamp, "polling does not repeat a status bubble")
        defaults.set("en", forKey: "uiLanguage"); preferencesChanged()
        try require(statusLabel.stringValue == "Codex is working on this task.", "native status and controls follow language")
        var openedDesk = 0, openedCodex = 0
        onWorkspace = { openedDesk += 1 }; onOpenCodex = { openedCodex += 1 }
        let screen = NSScreen.main!.visibleFrame
        showActions(near: NSRect(x: screen.maxX - 100, y: screen.minY, width: 100, height: 150))
        try require(screen.contains(actions.frame), "bottom controls stay on screen")
        actionButtons[0].performClick(nil)
        try require(openedDesk == 1 && !actions.isVisible, "workspace bubble button invokes real action")
        openInput(); editor?.string = "Local input fixture"
        copyAndOpen()
        try require(pasteboard.string(forType: .string) == "Local input fixture" && openedCodex == 1 && copiedCount == 1,
                    "native text entry copies on explicit action and opens task without executing")
        editor?.string = "   "; copyAndOpen(); try require(copiedCount == 1, "empty input does not send")
        try require(actionButtons.count == 5 && actionButtons.allSatisfy { $0.title.isEmpty && $0.image != nil && $0.toolTip != nil },"compact icon-only buttons retain accessible labels")
        let event = LinkedEvent(version:1,source:.vscode,instance:UUID().uuidString,sequence:1,sentAt:Date().timeIntervalSince1970*1000,state:.working,runID:"fixture",title:"VS Code task",project:"/tmp",activeCount:1)
        showNotice(event);let first = statusLabel.stringValue;showClickStatus(nil)
        try require(statusLabel.stringValue == first && greetingLabel.stringValue.isEmpty,"new status has priority over click greeting")
        var seenGreetings=Set<String>()
        for _ in 0..<3 {statusUntil = .distantPast;showClickStatus(event);seenGreetings.insert(greetingLabel.stringValue)}
        try require(seenGreetings.count == 3 && taskLabel.stringValue == "VS Code task","each click reports latest state and rotates greetings")
        var sent = "";onSend={value,done in sent=value;done(.success(()))};editor?.string="Direct input fixture";sendText()
        try require(sent == "Direct input fixture" && editor?.string.isEmpty == true,"explicit native send callback receives text and clears only after success")
        for style in ["anime","minimal"] {
            defaults.set(style,forKey:"uiStyle");preferencesChanged();showActions(near:NSRect(x:screen.midX,y:screen.midY,width:100,height:150))
            let view=actions.contentView!;if let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) {view.cacheDisplay(in:view.bounds,to:bitmap);try bitmap.representation(using:.png,properties:[:])?.write(to:directory.appendingPathComponent("bubble-\(style).png"))}
        }
        update(completed, enabled: false); try require(!status.isVisible, "disabled Codex link hides bubble")
        close()
        return ["real native status bubble and lifecycle summary", "no historical or repeated status messages", "native language switching",
                "screen-edge placement and workspace action", "explicit clipboard fallback", "compact icon controls with accessible labels", "new status preempts click greetings", "latest state and nonrepeating greeting rotation", "native explicit direct-send callback"]
    }
}
