import AppKit

func runLinkedChecks(directory: URL) throws -> [String] {
    let now = Date()
    func event(_ source: LinkedSource, _ state: CodexActivity, _ sequence: Int, _ active: Int = 0) -> LinkedEvent {
        LinkedEvent(version:1,source:source,instance:source == .codex ? "11111111-1111-4111-8111-111111111111" : source == .vscode ? "22222222-2222-4222-8222-222222222222" : "33333333-3333-4333-8333-333333333333",sequence:sequence,sentAt:now.timeIntervalSince1970*1000,state:state,runID:"run-1",title:source.label+" fixture",project:"/tmp/fixture",activeCount:active)
    }
    let hub = IntegrationHub()
    hub.receive(event(.codex,.completed,1)); try require(hub.queue.isEmpty,"startup does not replay historical completion")
    hub.receive(event(.codex,.working,2,1)); hub.receive(event(.vscode,.working,1,1)); hub.receive(event(.pycharm,.working,1,1))
    try require(hub.events.count == 3,"all three sources remain received concurrently")
    hub.primary = "pycharm"; try require(hub.selectedSource == .pycharm,"manual primary selection")
    hub.primary = "auto"; hub.frontmost = .vscode; try require(hub.selectedSource == .vscode,"frontmost source automatic primary")
    let windows = IntegrationHub()
    var older = event(.vscode,.working,1,1); older.metadata = ["focusedAt":"100"]
    var focused = older; focused = LinkedEvent(version:1,source:.vscode,instance:UUID().uuidString,sequence:1,sentAt:older.sentAt-100,state:.idle,runID:"",title:"Focused window",project:"/tmp/second",activeCount:0,metadata:["focusedAt":"200"])
    windows.receive(older); windows.receive(focused)
    try require(windows.latest(.vscode)?.instance == focused.instance,"focused window wins over an active background task and newer heartbeat")
    windows.pinnedProjects["vscode"] = older.project
    try require(windows.latest(.vscode)?.instance == older.instance,"pinned workspace overrides focus")
    windows.pinnedProjects["vscode"] = "/tmp/closed-project"
    try require(windows.latest(.vscode) == nil,"closed pinned workspace never falls through to a different project")
    hub.receive(event(.vscode,.failed,2)); hub.receive(event(.pycharm,.completed,2)); hub.receive(event(.codex,.waiting,3,1))
    try require(hub.takeNotice()?.event.state == .failed && hub.takeNotice()?.event.state == .completed,"failure and completion precede ordinary events")
    let count=hub.queue.count; hub.receive(event(.codex,.waiting,3,1)); hub.receive(event(.codex,.waiting,4,1))
    try require(hub.queue.count == count,"duplicates and heartbeat do not create repeat reminders")
    let bridge = IDEBridge(root:directory.appendingPathComponent("mailbox-check")); try bridge.start(); defer { bridge.stop() }
    let input=event(.pycharm,.working,5,1); let file=bridge.root.appendingPathComponent("events/fixture.json")
    try JSONEncoder().encode(input).write(to:file,options:.atomic)
    var received=0; bridge.onEvent={ _ in received += 1 }; bridge.poll(now:now); bridge.poll(now:now)
    try require(received == 1,"real mailbox parsing is sequence deduplicated")
    try bridge.command("run",target:input)
    let commands=try FileManager.default.contentsOfDirectory(at:bridge.root.appendingPathComponent("commands"),includingPropertiesForKeys:nil)
    let command=try JSONSerialization.jsonObject(with:Data(contentsOf:commands[0])) as! [String:Any]
    try require(command["action"] as? String == "run" && command["instance"] as? String == input.instance && command["command"] == nil,"fixed-action targeted mailbox contains no arbitrary shell")
    var ackOK = false; bridge.onAck = { _,ok,_ in ackOK = ok }
    let id = command["id"] as! String
    try JSONSerialization.data(withJSONObject:["version":1,"id":id,"ok":true]).write(to:bridge.root.appendingPathComponent("acks/\(id).json"))
    bridge.poll(now:now); try require(ackOK,"IDE acknowledgement is matched to the pending command")
    let malformed=Data("{\"source\":\"unknown\"}".utf8); try require(LinkedEvent.parse(malformed) == nil,"invalid source rejected")
    hub.expire(now:now.addingTimeInterval(41)); try require(hub.events.count == 1,"stale IDE heartbeats expire while Codex remains received")
    let rpc=OfficialCodex(); var methods:[String]=[],params:[[String:Any]]=[]
    rpc.requestHook={ method,value,done in methods.append(method);params.append(value);done(.success(method == "turn/start" ? ["turn":["id":"turn-1"]] : [:])) }
    let thread=CodexThreadSummary(id:"01a0fae6-ac9f-7820-ad67-8d7a422d5752",title:"fixture",cwd:directory.path,rollout:directory.appendingPathComponent("fixture.jsonl"),turnID:"turn-elsewhere",turnStatus:"idle",startedAt:0)
    var result: Result<Void,Error>?
    rpc.send("literal `text` $(data)",to:thread,activeElsewhere:false){result=$0}
    if case .success? = result {} else { throw IntegrationCheckError.failed("direct send") }
    try require(methods == ["thread/resume","turn/start"] && params[0]["threadId"] as? String == thread.id && params[0]["approvalPolicy"] == nil,"direct input routes to the tracked thread and preserves policies")
    rpc.send("continue",to:thread,activeElsewhere:true){result=$0}
    try require(methods.last == "turn/steer" && params.last?["expectedTurnId"] as? String == "turn-1","own active turn uses official steer precondition")
    let other=OfficialCodex(); var invoked=0; other.requestHook={ _,_,done in invoked += 1;done(.success([:])) }
    other.send("do not take over",to:thread,activeElsewhere:true){result=$0}
    if case .failure? = result {} else { throw IntegrationCheckError.failed("active other-client exclusion") }
    try require(invoked == 0,"other-client active turn never creates a second executor")
    var states:[CodexActivity]=[];rpc.onEvent={ _,event in states.append(event.state) }
    rpc.notification("item/started",params:["threadId":thread.id,"item":["type":"commandExecution"]])
    rpc.notification("turn/completed",params:["threadId":thread.id,"turn":["status":"failed"]])
    try require(states == [.waiting,.failed],"official streamed events map to wait and failure")
    states.removeAll()
    rpc.notification("turn/started",params:["threadId":thread.id,"turn":["id":"turn-2"]])
    rpc.stop()
    try require(states == [.working,.disconnected] && rpc.activeTurns.isEmpty,"official disconnect clears active state and reports unconfirmed connection")
    return ["concurrent three-source reception","manual and frontmost primary selection","window focus overrides background activity","pinned workspace target","closed pinned workspace refuses other projects","matched IDE acknowledgement","severity and primary reminder queue","heartbeat deduplication and expiry","atomic targeted IDE command mailbox","official direct send preserves thread and policies","official steering on own active turn","no takeover of another active client","official event mapping","official disconnection clears active state"]
}

extension InformationCard {
    func checkLinkedUI(defaults: UserDefaults,directory: URL) throws -> [String] {
        let sources=LinkedSource.allCases.map { ["source":$0.rawValue,"label":$0.label,"state":"working","title":"Fixture <task>","project":"/tmp/fixture","instance":"22222222-2222-4222-8222-222222222222","activeCount":1,"connected":true,"metadata":["pluginVersion":"3.8.0","bridgeAPI":"2","runToken":"select","fileToken":"fixture","file":$0 == .pycharm ? "/tmp/exercise.py":"/tmp/exercise.cpp","runtime":"/usr/bin/clang++","runTarget":"Build Workspace"],"actions":$0 == .vscode ? ["run","chooseRun","runFile","build","test","stop"] : ["run","chooseRun","runFile","test","stop"]] as [String:Any] }
        var primary="auto",action="",actionSource:LinkedSource?,actionInstance:String?,preset="",officialChecks=0
        onPrimary={ value in
            primary=value
            self.renderIntegrations(["primary":value,"selected":"vscode","sources":sources],official:["ready":true,"transport":"stdio"])
        };onLinkedAction={value,source,instance,_ in action=value;actionSource=source;actionInstance=instance};onCodexCompose={preset=$0};onOfficialConnect={officialChecks += 1}
        renderIntegrations(["primary":"auto","selected":"vscode","sources":sources],official:["ready":true,"transport":"stdio"])
        selectPage(.integrations)
        try awaitUI("document.querySelector('[data-uma-panel=integrations] .fy-source-card') !== null")
        try require(try evaluateForCheck("document.querySelector('[data-linked-source=vscode]')!==null") as? Bool == true,"software cards select the operation source")
        try clickForCheck("[data-linked-source=vscode]")
        try clickForCheck("[data-command=linkedAction][data-action=runFile]")
        try require(actionSource == .vscode && action == "runFile" && primary == "auto" && actionInstance == "22222222-2222-4222-8222-222222222222","current-file command explicitly targets the displayed VS Code instance without changing primary")
        renderIntegrations(["primary":"auto","selected":"codex","sources":sources],official:["ready":true,"transport":"stdio"])
        try awaitUI("document.querySelector('[data-ui-surface]:not([hidden]) [data-linked-controls]').dataset.linkedControls==='vscode'")
        try clickForCheck("[data-linked-source=pycharm]")
        try clickForCheck("[data-command=linkedAction][data-action=runFile]")
        try require(action == "runFile" && actionSource == .pycharm,"PyCharm primary action runs the current file")
        try clickForCheck("[data-command=linkedAction][data-action=chooseRun]")
        try require(actionSource == .pycharm && action == "chooseRun","PyCharm control targets PyCharm while primary is Codex")
        try clickForCheck("[data-linked-source=codex]")
        try clickForCheck("[data-command=codexCompose][data-preset=test]")
        try require(preset.contains("测试"),"Codex card shows its own draft controls")
        try clickForCheck("[data-linked-source=vscode]")
        try require(try evaluateForCheck("document.querySelectorAll('[data-panel] [data-primary-integration],[data-uma-panel] [data-primary-integration]').length===0 && document.querySelector('[data-primary-display]')!==null") as? Bool == true,"main integration summary is read-only; settings owns selection")
        try require(try evaluateForCheck("[...document.querySelectorAll('[data-ui-surface]')].every(s=>s.querySelectorAll('nav > [data-module]').length===3 && s.querySelector('nav > [data-module=integrations]'))") as? Bool == true,"third navigation entry opens software integrations")
        try require(try evaluateForCheck("document.querySelectorAll('[data-panel] [data-command=guide],[data-uma-panel] [data-command=guide],[data-panel] [data-command=officialConnect],[data-uma-panel] [data-command=officialConnect]').length===0") as? Bool == true,"connection instructions and diagnostics live in settings")
        try require(try evaluateForCheck("document.querySelector('[data-uma-panel=integrations]').textContent.includes('Fixture <task>')") as? Bool == true,"external task title is escaped as plain text")
        for style in ["anime","minimal"] {
            try setPreferenceForCheck("data-ui-style",value:style)
            for language in ["zh","ja","en"] {
                try setPreferenceForCheck("data-ui-language",value:language)
                panel.setContentSize(NSSize(width:320,height:700))
                try awaitUI("document.documentElement.scrollWidth<=innerWidth")
                try require(try evaluateForCheck("(() => {const p=document.querySelector('[data-ui-surface]:not([hidden]) [data-linked-controls=vscode]');return p.querySelector('.fy-actions [data-action=runFile]')!==null && !p.querySelector('[data-advanced-vscode]').open})()") as? Bool == true,"current file is visible primary and advanced project operations start collapsed")
                try clickForCheck(".fy-actions [data-command=linkedAction][data-action=runFile]")
                try require(action == "runFile","visible primary runs the current file through native handler")
                try clickForCheck("[data-vscode-advanced-toggle]")
                try awaitUI("document.querySelector('[data-ui-surface]:not([hidden]) [data-advanced-vscode]').open")
                renderIntegrations(["primary":"auto","selected":"codex","sources":sources],official:["ready":true,"transport":"stdio"])
                try awaitUI("document.querySelector('[data-ui-surface]:not([hidden]) [data-advanced-vscode]').open")
                try clickForCheck("[data-advanced-vscode] [data-command=linkedAction][data-action=run]")
                try require(action == "run","optional project run reaches native handler after expanding")
                try clickForCheck("[data-vscode-advanced-toggle]")
                try clickForCheck("[data-open-settings]")
                try clickForCheck("[data-command=guide]")
                for page in ["basics","codex","vscode","pycharm"] {
                    _ = try evaluateForCheck("document.querySelector('[data-manual-page=\(page)]').click();true")
                    try awaitUI("!document.querySelector('[data-manual-panel=\(page)]').hidden")
                    try require(try evaluateForCheck("(() => {const d=document.querySelector('#fy-connection-guide');return d.scrollWidth<=d.clientWidth+1 && d.getBoundingClientRect().left>=0 && d.getBoundingClientRect().right<=innerWidth})()") as? Bool == true,"manual fits 320px for \(style)/\(language)/\(page)")
                }
                _ = try evaluateForCheck("document.querySelector('[data-manual-page=codex]').click();document.querySelector('[data-command=officialConnect]').click();document.querySelector('[data-command=closeGuide]').click();true")
            }
        }
        _ = try evaluateForCheck("(() => {const s=document.querySelector('[data-ui-surface]:not([hidden]) [data-primary-integration]');s.value='pycharm';s.dispatchEvent(new Event('change',{bubbles:true}));return true})()")
        RunLoop.main.run(until:Date(timeIntervalSinceNow:0.1));try require(primary == "pycharm","primary selector reaches native callback")
        try awaitUI("document.querySelector('[data-ui-surface]:not([hidden]) [data-primary-integration]').value==='pycharm' && document.querySelector('[data-primary-display]').textContent.includes('PyCharm')")
        try require(officialChecks == 6,"manual official connection check reaches native handler")
        try clickForCheck("[data-linked-source=codex]")
        try clickForCheck("[data-command=codexCompose][data-preset=test]")
        try require(preset.contains("测试"),"Codex shortcut fills a reviewable prompt")
        try capture(to:directory.appendingPathComponent("integrations-minimal-en.png"))
        return ["all three source cards and safe external text","software selection switches matching functional controls","IDE actions target the displayed source and instance","operation source survives automatic primary changes","main source summary is read-only; settings selection persists through refresh","third navigation module; connection help moved to settings","four manual sections across six style-language combinations at 320px","manual official connection checks reach native handler","default current-file and optional project controls in six style-language combinations; expansion survives refresh","native run and primary selection commands","Codex shortcut drafts"]
    }
}
