import Foundation
import CryptoKit

final class RaceReminders {
    private let defaults: UserDefaults
    private(set) var races: [WorldRace] = []
    private var statuses: [String:String]
    private var reminded: Set<String>
    var onAlert: ((String,String) -> Void)?
    init(defaults: UserDefaults) {
        self.defaults = defaults
        statuses = defaults.dictionary(forKey:"raceEntryStates") as? [String:String] ?? [:]
        reminded = Set(defaults.stringArray(forKey:"raceReminderIDs") ?? [])
    }
    static func identity(_ race: WorldRace) -> String { race.date+":"+race.venue+":"+(race.englishName.isEmpty ? race.name : race.englishName) }
    func update(_ values: [WorldRace], checks: [SourceCheck], now: Date = Date()) {
        var merged = Dictionary(races.map { (Self.identity($0),$0) },uniquingKeysWith:{_,new in new})
        for race in values {
            let key = Self.identity(race)
            // Entry alerts require a fresh fetch of the authority that supplied the runner status.
            let authority = race.runnersSource ?? race.source
            let live = checks.contains { $0.url == authority && $0.mode == "online" && abs(now.timeIntervalSince($0.fetchedAt)) < 3600 }
            if live {
                if statuses[key] == "candidate" && race.entryStatus == "declared" && defaults.bool(forKey:"entryReminders") { onAlert?("raceDeclared",race.name) }
                if ["candidate","declared"].contains(race.entryStatus) { statuses[key] = race.entryStatus }
            }
            merged[key] = race
        }
        races = merged.values.filter { $0.date >= RacingParse.day(now.addingTimeInterval(-86_400),zone:$0.zone) }.sorted { $0.date < $1.date }
        let keys = Set(races.map(Self.identity)); statuses = statuses.filter { keys.contains($0.key) }
        defaults.set(statuses,forKey:"raceEntryStates")
    }
    func tick(now: Date = Date()) {
        guard defaults.bool(forKey:"raceReminders") else { return }
        let lead = Double(defaults.object(forKey:"reminderLead") as? Int ?? 30)*60
        for race in races {
            guard let start = race.start, !race.provisionalTime, race.entryStatus != "candidate",
                  start > now, start.timeIntervalSince(now) <= lead else { continue }
            let id = Self.identity(race)+":"+String(start.timeIntervalSince1970)
            guard !reminded.contains(id) else { continue }
            reminded.insert(id); onAlert?("raceStart",race.name)
        }
        if reminded.count > 200 { reminded = Set(reminded.sorted().suffix(200)) }
        defaults.set(Array(reminded),forKey:"raceReminderIDs")
    }
    func clearData() { races.removeAll() }
    var object: [[String:Any]] { races.map { race in var value = race.object; value["id"] = Self.identity(race); return value } }
    static func calendar(_ values: [WorldRace], language: String, now: Date = Date()) -> String {
        func escaped(_ value: String) -> String { value.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\r\n",with:"\n").replacingOccurrences(of:"\r",with:"\n").replacingOccurrences(of:"\n",with:"\\n").replacingOccurrences(of:";",with:"\\;").replacingOccurrences(of:",",with:"\\,") }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier:"en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT:0); formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        var lines = ["BEGIN:VCALENDAR","VERSION:2.0","PRODID:-//Forever Young Pet//Local Races 3.7//EN","CALSCALE:GREGORIAN","METHOD:PUBLISH"]
        for race in values {
            let uid = SHA256.hash(data:Data(Self.identity(race).utf8)).map { String(format:"%02x",$0) }.joined()
            lines += ["BEGIN:VEVENT","UID:\(uid)@foreveryoungpet.local","DTSTAMP:"+formatter.string(from:now)]
            if let start = race.start, !race.provisionalTime { lines += ["DTSTART:"+formatter.string(from:start)] }
            else {
                let day = race.date.replacingOccurrences(of:"-",with:"")
                let end = RacingParse.time(race.date,hour:12,minute:0,zone:"UTC").map { $0.addingTimeInterval(86_400) }
                let civil = DateFormatter(); civil.locale = Locale(identifier:"en_US_POSIX"); civil.timeZone = TimeZone(secondsFromGMT:0); civil.dateFormat = "yyyyMMdd"
                lines += ["DTSTART;VALUE=DATE:"+day]; if let end = end { lines += ["DTEND;VALUE=DATE:"+civil.string(from:end)] }
            }
            let candidate = race.entryStatus == "candidate"
            let name = language == "en" && !race.englishName.isEmpty ? race.englishName : race.name
            let note = candidate ? ["zh":"候选计划，尚未确认出走","ja":"出走候補・未確定","en":"Candidate plan; entry unconfirmed"][language]! : ""
            let timeNote = race.start == nil || race.provisionalTime ? ["zh":"时刻未确认；按比赛当地日期记录","ja":"時刻未確定・開催地の日付","en":"Time unconfirmed; local venue date"][language]! : race.zone
            lines += ["SUMMARY:"+escaped(name+(candidate ? " · "+note:"")),"LOCATION:"+escaped(race.venue),"DESCRIPTION:"+escaped(timeNote+"\n"+note+"\n"+race.source.absoluteString),"URL:"+race.source.absoluteString,"STATUS:"+(candidate || race.provisionalTime ? "TENTATIVE":"CONFIRMED"),"END:VEVENT"]
        }
        lines.append("END:VCALENDAR")
        // RFC 5545 folds at 75 octets without splitting UTF-8 characters.
        return lines.map { line in
            var pieces:[String]=[], current=""
            for character in line { let next=String(character); if current.utf8.count+next.utf8.count > 75 { pieces.append(current); current=" " }; current += next }
            pieces.append(current); return pieces.joined(separator:"\r\n")
        }.joined(separator:"\r\n")+"\r\n"
    }
}
