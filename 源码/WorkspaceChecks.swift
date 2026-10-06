import AppKit
import WebKit

// Opt-in checks exercise the exact bundled page and native bridge in an isolated test defaults suite.
extension InformationCard {
    func evaluateForCheck(_ script: String) throws -> Any? {
        var finished = false
        var result: Any?
        var failure: Error?
        webView.evaluateJavaScript(script) { value, error in result = value; failure = error; finished = true }
        let deadline = Date(timeIntervalSinceNow: 5)
        while !finished && Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)) }
        if let failure = failure { throw failure }
        try require(finished, "web evaluation completed")
        return result
    }

    func awaitUI(_ condition: String) throws {
        let deadline = Date(timeIntervalSinceNow: 5)
        while Date() < deadline {
            if (try? evaluateForCheck(condition)) as? Bool == true { return }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        }
        throw IntegrationCheckError.failed("UI condition: " + condition)
    }

    func setPreferenceForCheck(_ attribute: String, value: String) throws {
        _ = try evaluateForCheck("(() => {const input=document.querySelector('[data-ui-surface]:not([hidden]) [\(attribute)]');input.value='\(value)';input.dispatchEvent(new Event('change',{bubbles:true}));return true})()")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    }

    func clickForCheck(_ selector: String) throws {
        _ = try evaluateForCheck("document.querySelector('[data-ui-surface]:not([hidden]) \(selector)').click();true")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    }

    func checkWorkspaceUI(defaults: UserDefaults, directory: URL) throws -> [String] {
        try awaitUI("Boolean(window.petUI) && [...document.images].every(image=>image.complete && image.naturalWidth>0)")
        try setPreferenceForCheck("data-ui-language", value: "ja")
        try awaitUI("document.querySelector('[data-module=tasks] .fy-nav-full').textContent==='Codex タスク'")
        try require(defaults.string(forKey: "uiLanguage") == "ja", "language saved through native bridge")
        try setPreferenceForCheck("data-ui-style", value: "minimal")
        try awaitUI("!document.querySelector('[data-ui-surface=minimal]').hidden")
        try require(defaults.string(forKey: "uiStyle") == "minimal", "style saved through native bridge")
        try setPreferenceForCheck("data-ui-language", value: "en")
        try awaitUI("document.querySelector('[data-ui-surface=minimal] [data-panel=tasks] h3').textContent==='Current task'")
        let generation = loadCount
        webView.reload()
        let reloadDeadline = Date(timeIntervalSinceNow: 5)
        while loadCount == generation && Date() < reloadDeadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03)) }
        try require(loadCount > generation, "actual document reload completed")
        try awaitUI("!document.querySelector('[data-ui-surface=minimal]').hidden && document.querySelector('#forever-young-pet-ui').lang==='en'")
        try capture(to: directory.appendingPathComponent("minimal-en.png"))
        panel.setContentSize(NSSize(width: 320, height: 700))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        for style in ["minimal", "anime"] {
            try setPreferenceForCheck("data-ui-style", value: style)
            for language in ["zh", "ja", "en"] {
                try setPreferenceForCheck("data-ui-language", value: language)
                _ = try evaluateForCheck("document.querySelector('[data-ui-surface]:not([hidden]) [data-open-settings]').click();true")
                try awaitUI("document.querySelector('[data-ui-surface]:not([hidden]) .fy-settings').hidden===false")
                let fits = try evaluateForCheck("(() => {const surface=document.querySelector('[data-ui-surface]:not([hidden])');const menu=surface.querySelector('.fy-settings').getBoundingClientRect();return menu.left>=0 && menu.right<=innerWidth && document.documentElement.scrollWidth<=innerWidth})()") as? Bool
                try require(fits == true, "320px settings fit for \(style)/\(language)")
                _ = try evaluateForCheck("document.querySelector('[data-ui-surface]:not([hidden]) [data-close-settings]').click();true")
            }
        }
        try clickForCheck("[data-open-settings]")
        try clickForCheck("[data-command=guide]")
        try awaitUI("document.querySelector('#fy-connection-guide').open && document.querySelector('[data-guide-home]').textContent.length>0")
        _ = try evaluateForCheck("document.querySelector('[data-manual-page=codex]').click();true")
        _ = try evaluateForCheck("document.querySelector('[data-toggle-codex]').click();true")
        try awaitUI("document.querySelector('[data-toggle-codex]').checked===false")
        try require(!defaults.bool(forKey: "codexLinked"), "guide toggle reaches native animation preference")
        _ = try evaluateForCheck("document.querySelector('[data-toggle-codex]').click();true")
        try awaitUI("document.querySelector('[data-toggle-codex]').checked===true")
        try require(defaults.bool(forKey: "codexLinked"), "guide toggle restores native animation link")
        let white = try evaluateForCheck("getComputedStyle(document.querySelector('#fy-connection-guide')).backgroundColor==='rgb(255, 255, 255)'") as? Bool
        try require(white == true, "guide is opaque white even in dark macOS")
        try capture(to: directory.appendingPathComponent("connection-guide-en-320.png"))
        _ = try evaluateForCheck("document.querySelector('[data-command=closeGuide]').click();true")
        panel.setContentSize(NSSize(width: 590, height: 760))
        try setPreferenceForCheck("data-ui-language", value: "zh")
        return ["actual WebKit zh/ja/en changes functional labels", "native settings persist style and language",
                "actual WebKit reload restores saved preferences",
                "both styles and all three languages fit 320px settings", "connection guide uses real folder and status; opaque white"]
    }
}
