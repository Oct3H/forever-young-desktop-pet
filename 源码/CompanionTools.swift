import Foundation

struct ActivityRecord: Codable {
    let id: String
    let source: String
    let instance: String
    let threadID: String
    let state: String
    let title: String
    let project: String
    let date: Date
    let duration: Double?
    var object: [String: Any] {
        ["id":id,"source":source,"instance":instance,"threadID":threadID,"state":state,"title":title,
         "project":project,"date":date.timeIntervalSince1970 * 1000,"duration":duration ?? NSNull()]
    }
}

/// Local summaries and opt-in tools. Never persists prompts, console output, or credentials.
final class CompanionTools {
    let defaults: UserDefaults
    let historyURL: URL
    private(set) var history: [ActivityRecord] = []
    private var started: [String:Date] = [:]
    private(set) var phase = "idle"
    private var deadline: Date?
    private var remaining: TimeInterval = 0
    private var lastPublishedSecond = -1
    private var lastTaskSecond = -1
    var onChange: (() -> Void)?
    var onAlert: ((String,String) -> Void)?

    init(defaults: UserDefaults, root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/ForeverYoungPet")) {
        self.defaults = defaults; historyURL = root.appendingPathComponent("activity-history.json")
        if let data = try? Data(contentsOf: historyURL), data.count < 2_000_000,
           let records = try? JSONDecoder().decode([ActivityRecord].self, from:data) { history = Array(records.suffix(200)) }
    }
    var mode: String { defaults.string(forKey:"companionMode") ?? "normal" }
    var volume: Float { Float(defaults.object(forKey:"voiceVolume") as? Double ?? 1) }
    func quiet(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard defaults.bool(forKey:"quietEnabled") else { return false }
        let hour = calendar.component(.hour,from:date)
        let start = defaults.object(forKey:"quietStart") as? Int ?? 22
        let end = defaults.object(forKey:"quietEnd") as? Int ?? 8
        return start == end ? true : start < end ? (hour >= start && hour < end) : (hour >= start || hour < end)
    }
    func allowsVoice(_ context: String, automatic: Bool, at date: Date = Date()) -> Bool {
        defaults.object(forKey:"voiceEnabled") as? Bool != false &&
        defaults.object(forKey:"voiceScene."+context) as? Bool != false && !quiet(at:date) && mode != "meeting" &&
        (!automatic || (mode == "normal" && defaults.object(forKey:"automaticVoiceEnabled") as? Bool != false))
    }
    func set(_ key: String, value: Any) {
        let bools = ["voiceEnabled","automaticVoiceEnabled","quietEnabled","edgePark","raceReminders","entryReminders"] + ["click","working","completed","failed","interrupted"].map { "voiceScene."+$0 }
        if bools.contains(key), let value = value as? Bool { defaults.set(value,forKey:key) }
        else if key == "voiceVolume", let value = value as? Double, value.isFinite { defaults.set(min(1,max(0,value)),forKey:key) }
        else if ["quietStart","quietEnd"].contains(key), let value = value as? Int, (0...23).contains(value) { defaults.set(value,forKey:key) }
        else if key == "reminderLead", let value = value as? Int, [15,30,60].contains(value) { defaults.set(value,forKey:key) }
        else if key == "companionMode", let value = value as? String, ["normal","focus","meeting"].contains(value) { defaults.set(value,forKey:key) }
        else { return }
        onChange?()
    }
    var preferences: [String:Any] {
        var value: [String:Any] = ["companionMode":mode,"voiceVolume":volume,"quietStart":defaults.object(forKey:"quietStart") ?? 22,
                                  "quietEnd":defaults.object(forKey:"quietEnd") ?? 8,"reminderLead":defaults.object(forKey:"reminderLead") ?? 30]
        for key in ["voiceEnabled","automaticVoiceEnabled","quietEnabled","edgePark","raceReminders","entryReminders"] + ["click","working","completed","failed","interrupted"].map({"voiceScene."+$0}) {
            value[key] = defaults.object(forKey:key) as? Bool ?? (key.hasPrefix("voice") || key == "automaticVoiceEnabled")
        }
        return value
    }
    func receive(_ event: LinkedEvent, at now: Date = Date()) {
        let key = event.key+":"+event.runID
        if event.state == .working && started[key] == nil { started[key] = now }
        let duration = event.state.isTransient ? started.removeValue(forKey:key).map { max(0,now.timeIntervalSince($0)) } : nil
        if event.activeCount == 0 { started = started.filter { !$0.key.hasPrefix(event.key+":") } }
        if started.count > 200 { started = started.filter { now.timeIntervalSince($0.value) < 86_400 } }
        add(ActivityRecord(id:UUID().uuidString,source:event.source.rawValue,instance:event.instance,
                           threadID:event.metadata?["threadID"] ?? "",state:event.state.rawValue,title:event.title,
                           project:event.project,date:now,duration:duration))
    }
    func add(_ record: ActivityRecord) {
        history.append(record); if history.count > 200 { history.removeFirst(history.count-200) }; save(); onChange?()
    }
    func addReminder(_ state: String, title: String, at now: Date = Date()) {
        add(ActivityRecord(id:UUID().uuidString,source:state.hasPrefix("race") ? "racing":"timer",instance:"",threadID:"",state:state,title:title,project:"",date:now,duration:nil))
        onAlert?(state,title)
    }
    func reconcile(instances: Set<String>) {
        let old = started.count; started = started.filter { item in instances.contains(item.key.split(separator:":").prefix(2).joined(separator:":")) }
        if old != started.count { onChange?() }
    }
    func clearHistory() { history.removeAll(); save(); onChange?() }
    private func save() {
        do {
            try FileManager.default.createDirectory(at:historyURL.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            try JSONEncoder().encode(history).write(to:historyURL,options:.atomic)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:historyURL.path)
        } catch { /* History persistence does not block IDE execution. */ }
    }
    func timerCommand(_ action: String, minutes: Int = 25, now: Date = Date()) {
        switch action {
        case "start": phase = "work"; remaining = Double(min(180,max(1,minutes)))*60; deadline = now.addingTimeInterval(remaining)
        case "pause": if let deadline = deadline { remaining = max(0,deadline.timeIntervalSince(now)); self.deadline = nil }
        case "resume": if phase != "idle" && deadline == nil { deadline = now.addingTimeInterval(remaining) }
        case "reset": phase = "idle"; remaining = 0; deadline = nil
        default: return
        }
        lastPublishedSecond = -1; onChange?()
    }
    func tick(at now: Date = Date()) {
        if let end = deadline, now >= end {
            if phase == "work" {
                phase = "rest"; remaining = 300; deadline = now.addingTimeInterval(300); addReminder("restStart",title:"",at:now)
            } else { phase = "idle"; remaining = 0; deadline = nil; addReminder("restEnd",title:"",at:now) }
        }
        let second = Int(ceil(deadline.map { max(0,$0.timeIntervalSince(now)) } ?? remaining))
        let taskSecond = started.isEmpty ? -1 : Int(now.timeIntervalSince1970)
        if second != lastPublishedSecond || taskSecond != lastTaskSecond { lastPublishedSecond = second; lastTaskSecond = taskSecond; onChange?() }
    }
    var object: [String:Any] {
        let recent = history.reversed().filter { ["vscode","pycharm"].contains($0.source) && ["completed","failed","interrupted"].contains($0.state) }.prefix(10)
        return ["preferences":preferences,"history":history.reversed().map { $0.object },"recent":recent.map { $0.object },
                "running":started.map { ["key":$0.key,"startedAt":$0.value.timeIntervalSince1970*1000] },
                "timer":["phase":phase,"seconds":max(0,lastPublishedSecond),"paused":deadline == nil && phase != "idle"]]
    }
}
