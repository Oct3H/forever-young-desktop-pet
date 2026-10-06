import AppKit

func runCompanionChecks(defaults: UserDefaults, directory: URL) throws -> [String] {
    let root = directory.appendingPathComponent("isolated-history")
    let tools = CompanionTools(defaults:defaults,root:root); tools.clearHistory()
    let now = RacingParse.time("2026-10-06",hour:12,minute:0,zone:"UTC")!
    var calendar = Calendar(identifier:.gregorian); calendar.timeZone = TimeZone(secondsFromGMT:0)!
    tools.set("quietEnabled",value:true); tools.set("quietStart",value:22); tools.set("quietEnd",value:8)
    try require(tools.quiet(at:now.addingTimeInterval(11*3600),calendar:calendar) && !tools.quiet(at:now,calendar:calendar),"overnight quiet hours cross midnight correctly")
    tools.set("quietEnd",value:22); try require(tools.quiet(at:now,calendar:calendar),"equal quiet start/end is all day")
    tools.set("quietEnabled",value:false); tools.set("voiceVolume",value:4.0); try require(tools.volume == 1,"volume is clamped")
    tools.set("voiceScene.failed",value:false); try require(!tools.allowsVoice("failed",automatic:true,at:now),"individual failure voice can be disabled")
    tools.set("companionMode",value:"focus"); try require(!tools.allowsVoice("working",automatic:true,at:now) && tools.allowsVoice("click",automatic:false,at:now),"focus suppresses automatic voice but allows explicit greeting")
    tools.set("companionMode",value:"meeting"); try require(!tools.allowsVoice("click",automatic:false,at:now),"meeting mode silences clicks")
    tools.set("companionMode",value:"normal"); tools.set("unrecognized",value:true); try require(defaults.object(forKey:"unrecognized") == nil,"unknown settings cannot write arbitrary defaults")
    let hub=IntegrationHub(); hub.onTransition={tools.receive($0,at:now)}
    func event(_ sequence:Int,_ state:CodexActivity,_ active:Int) -> LinkedEvent {
        LinkedEvent(version:1,source:.vscode,instance:"22222222-2222-4222-8222-222222222222",sequence:sequence,sentAt:now.timeIntervalSince1970*1000,state:state,runID:"fixture",title:"<literal> run",project:"/tmp/fixture",activeCount:active,metadata:["pluginVersion":"3.7.0","runTarget":"Main"])
    }
    hub.receive(event(1,.working,1),now:now);hub.receive(event(2,.working,1),now:now)
    try require(tools.history.count == 1,"heartbeats do not enter history")
    tools.receive(event(3,.completed,0),at:now.addingTimeInterval(15))
    try require(tools.history.last?.duration == 15 && (tools.object["running"] as? [[String:Any]])?.isEmpty == true,"completed task timing stops and records approximate elapsed time")
    try require(CompanionTools(defaults:defaults,root:root).history.count == 2,"summaries survive restart")
    let json = String(decoding:try Data(contentsOf:tools.historyURL),as:UTF8.self)
    try require(!json.contains("prompt") && !json.contains("consoleOutput"),"history has no prompt or console body fields")
    for _ in 0..<205 {tools.add(ActivityRecord(id:UUID().uuidString,source:"timer",instance:"",threadID:"",state:"restEnd",title:"",project:"",date:now,duration:nil))}
    try require(tools.history.count == 200 && CompanionTools(defaults:defaults,root:root).history.count == 200,"bounded history persists at most 200 summaries")
    var alerts:[String]=[];tools.onAlert={state,_ in alerts.append(state)}
    tools.timerCommand("start",minutes:1,now:now);tools.timerCommand("pause",now:now.addingTimeInterval(30));tools.tick(at:now.addingTimeInterval(3600))
    try require(tools.phase == "work" && alerts.isEmpty,"paused timer does not expire")
    tools.timerCommand("resume",now:now.addingTimeInterval(3600));tools.tick(at:now.addingTimeInterval(3631));try require(tools.phase == "rest" && alerts == ["restStart"],"resume preserves remaining time and begins five-minute break")
    tools.tick(at:now.addingTimeInterval(3932));tools.tick(at:now.addingTimeInterval(3933));try require(tools.phase == "idle" && alerts == ["restStart","restEnd"],"break completion alerts once and waits for manual restart")
    let source=RacingParse.contendersURL
    var race=WorldRace(date:"2026-10-06",name:"試験,レース;\nBEGIN:VEVENT",englishName:"Fixture",venue:"Tokyo",zone:"Asia/Tokyo",start:now.addingTimeInterval(600),source:source,runnersSource:source,entryStatus:"candidate",foreverYoung:true)
    let reminders=RaceReminders(defaults:defaults);var raceAlerts:[String]=[];reminders.onAlert={state,_ in raceAlerts.append(state)}
    defaults.set(true,forKey:"entryReminders");defaults.set(true,forKey:"raceReminders")
    let live=[SourceCheck(url:source,fetchedAt:now,mode:"online")]
    reminders.update([race],checks:live,now:now);reminders.tick(now:now);try require(raceAlerts.isEmpty,"candidate entry never triggers confirmed start reminder")
    race.entryStatus="declared";reminders.update([race],checks:[SourceCheck(url:source,fetchedAt:now,mode:"fallbackCache")],now:now)
    try require(raceAlerts.isEmpty,"offline fallback does not create declaration alert")
    reminders.update([race],checks:live,now:now);reminders.update([race],checks:live,now:now);try require(raceAlerts == ["raceDeclared"],"fresh candidate to declared transition alerts once")
    reminders.tick(now:now);reminders.tick(now:now);try require(raceAlerts == ["raceDeclared","raceStart"],"known start reminder is deduplicated")
    let restarted=RaceReminders(defaults:defaults);restarted.onAlert={state,_ in raceAlerts.append(state)};restarted.update([race],checks:live,now:now);restarted.tick(now:now);try require(raceAlerts.count == 2,"reminder deduplication survives restart")
    let timed=RaceReminders.calendar([race],language:"zh",now:now)
    try require(timed.contains("DTSTART:20261006T121000Z") && timed.contains("\\,レース\\;\\nBEGIN:VEVENT") && timed.components(separatedBy:"\r\n").filter({$0 == "BEGIN:VEVENT"}).count == 1,"calendar UTC instant and text escaping prevent injected events")
    race.provisionalTime=true;race.entryStatus="candidate";race.name=String(repeating:"フォーエバーヤング",count:20)
    let allDay=RaceReminders.calendar([race],language:"ja",now:now)
    try require(allDay.contains("DTSTART;VALUE=DATE:20261006") && allDay.contains("STATUS:TENTATIVE") && allDay.components(separatedBy:"\r\n").allSatisfy({$0.utf8.count <= 75}),"unconfirmed time is tentative all-day; UTF-8 folding respects 75 octets")
    try allDay.write(to:directory.appendingPathComponent("calendar-fixture.ics"),atomically:true,encoding:.utf8)
    tools.clearHistory();try require(CompanionTools(defaults:defaults,root:root).history.isEmpty,"manual history clearing is persisted")
    return ["overnight quiet hours","all-day quiet interval","volume clamp","scene switches","focus voice policy","meeting mute","validated settings keys","heartbeat-free history","task duration and completion","history restart persistence","summary-only privacy","history bound","timer pause","timer resume and break","single break completion","candidate reminder exclusion","offline entry alert exclusion","fresh entry transition","start reminder deduplication","reminder restart persistence","calendar UTC and escaping","tentative all-day and UTF-8 folding","manual history clearing"]
}

extension InformationCard {
    func checkCompanionUI(defaults: UserDefaults,directory: URL) throws -> [String] {
        let tools=CompanionTools(defaults:defaults,root:directory.appendingPathComponent("ui-history"));tools.clearHistory()
        tools.add(ActivityRecord(id:"fixture",source:"vscode",instance:"fixture",threadID:"",state:"failed",title:"Literal <task>",project:"/tmp/fixture",date:Date(),duration:2))
        var object=tools.object;object["diagnostics"]=["sources":[["source":"vscode","label":"VS Code","connected":true,"sentAt":Date().timeIntervalSince1970*1000,"metadata":["pluginVersion":"3.7.0","runTarget":"Main","runtime":"/usr/bin/python3","file":"/tmp/main.py","trusted":"true"]]]]
        renderCompanion(object);selectPage(.tools)
        var commands:[String]=[]
        onTools={ value in commands.append(value["command"] as? String ?? ""); if value["command"] as? String == "toolSetting",let key=value["key"] as? String,let setting=value["value"] {tools.set(key,value:setting);self.renderCompanion(tools.object)} }
        try awaitUI("Boolean(window.petTools) && document.querySelector('[data-panel=tools] [data-timer-clock]')!==null")
        try require(try evaluateForCheck("document.querySelector('[data-panel=tools]').textContent.includes('Literal <task>') && !document.querySelector('[data-panel=tools] task')") as? Bool == true,"history escapes external task titles")
        try clickForCheck("[data-command=historyJump]");try require(commands.last == "historyJump","history jump reaches native dispatch")
        try clickForCheck("[data-command=timer][data-action=start]");try require(commands.last == "timer","timer button reaches native dispatch")
        for style in ["anime","minimal"] {
            try setPreferenceForCheck("data-ui-style",value:style)
            for language in ["zh","ja","en"] {
                try setPreferenceForCheck("data-ui-language",value:language)
                panel.setContentSize(NSSize(width:320,height:700));try awaitUI("document.documentElement.scrollWidth<=innerWidth")
                try clickForCheck("[data-open-settings]")
                _ = try evaluateForCheck("[...document.querySelector('[data-ui-surface]:not([hidden]) [data-tool-settings]').querySelectorAll('details')].forEach(e=>e.open=true);true")
                try require(try evaluateForCheck("document.documentElement.scrollWidth<=innerWidth && document.querySelector('[data-ui-surface]:not([hidden]) [data-tool-key=voiceVolume]')!==null") as? Bool == true,"new settings fit 320px for \(style)/\(language)")
                try clickForCheck("[data-command=audition]");try require(commands.last == "audition","scene audition reaches native bridge")
                try clickForCheck("[data-close-settings]")
            }
        }
        try clickForCheck("[data-open-settings]")
        _ = try evaluateForCheck("(() => {const e=document.querySelector('[data-ui-surface]:not([hidden]) [data-tool-key=companionMode]');e.value='meeting';e.dispatchEvent(new Event('change',{bubbles:true}));return true})()")
        try require(tools.mode == "meeting","UI meeting selector persists through native settings")
        try capture(to:directory.appendingPathComponent("companion-settings-en-320.png"))
        try clickForCheck("[data-close-settings]");try setPreferenceForCheck("data-ui-language",value:"zh");panel.setContentSize(NSSize(width:590,height:760))
        try capture(to:directory.appendingPathComponent("companion-anime-history.png"))
        return ["escaped history titles","native history jump","native timer dispatch","six 320px tool/settings layouts","five scene audition controls","native mode persistence"]
    }
}
