import Foundation
import PDFKit

// Published civil dates stay as dates; only an actual post time is converted between zones.
struct WorldRace: Codable {
    var date: String
    var name: String
    var englishName: String = ""
    var venue: String
    var course: String = ""
    var zone: String
    var start: Date? = nil
    var provisionalTime: Bool = false
    var source: URL
    var runnersSource: URL? = nil
    var japaneseRunners: [String] = []
    var entryStatus: String = "unknown"
    var foreverYoung: Bool = false
    var object: [String: Any] {
        ["localDate": date, "name": name, "englishName": englishName, "venue": venue, "course": course,
         "zone": zone, "start": start.map { $0.timeIntervalSince1970 * 1000 } ?? NSNull(),
         "provisionalTime": provisionalTime, "pageURL": source.absoluteString,
         "runnersURL": runnersSource?.absoluteString ?? "", "japaneseRunners": japaneseRunners,
         "entryStatus": entryStatus, "foreverYoung": foreverYoung, "international": true]
    }
}

struct HorseResult: Codable {
    let date: String
    let name: String
    var englishName: String = ""
    let venue: String
    let place: String
    let grade: String
    let distance: String
    let jockey: String
    var object: [String: String] {
        ["localDate": date, "name": name, "englishName": englishName, "venue": venue,
         "place": place, "grade": grade, "distance": distance, "jockey": jockey]
    }
}

struct SourceCheck {
    let url: URL
    let fetchedAt: Date
    let mode: String
    var object: [String: Any] { ["url": url.absoluteString, "fetchedAt": fetchedAt.timeIntervalSince1970 * 1000, "mode": mode] }
}

struct RacingOverview {
    var races: [WorldRace] = []
    var upcoming: [WorldRace] = []
    var history: [HorseResult] = []
    var checks: [SourceCheck] = []
    var warnings: [String] = []
    var historyAvailable = false
}

enum RacingParse {
    static let historyURL = URL(string: "https://www.jbis.or.jp/horse/0001339834/record/")!
    static let bcURL = URL(string: "https://www.breederscup.com/watch")!
    static let contendersURL = URL(string: "https://www.breederscup.com/horses/entries")!
    static let overseasURL = URL(string: "https://jra.jp/keiba/overseas/racelist/")!
    static let newsURL = URL(string: "https://jra.jp/keiba/overseas/")!
    static func allowed(_ url: URL) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil &&
        ["jra.jp", "www.jra.jp", "jra.go.jp", "www.jra.go.jp", "www.jairs.jp", "www.jbis.or.jp", "www.breederscup.com"].contains(url.host ?? "")
    }
    static func html(_ data: Data) throws -> String {
        let cp932 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)))
        guard let result = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS) ?? String(data: data, encoding: cp932) else { throw JRAError.invalidPage }
        return result.replacingOccurrences(of: "<!--.*?-->", with: "", options: .regularExpression)
    }
    static func compact(_ value: String) -> String { value.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression) }
    static func civil(_ year: Int, _ month: Int, _ day: Int) -> String? {
        guard let date = JRAProvider.calendar.date(from: DateComponents(year: year, month: month, day: day)),
              JRAProvider.calendar.component(.month, from: date) == month,
              JRAProvider.calendar.component(.day, from: date) == day else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
    static func day(_ date: Date, zone: String = "Asia/Tokyo") -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: zone); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    static func time(_ day: String, hour: Int, minute: Int, zone: String) -> Date? {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: zone); formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.isLenient = false
        return formatter.date(from: day + String(format: " %02d:%02d", hour, minute))
    }
    static func history(_ data: Data) throws -> [HorseResult] {
        let html = try html(data)
        guard html.contains("フォーエバーヤング"), let count = JRAProvider.matches("([0-9]+)戦中", in: html).first?[1], let total = Int(count) else { throw JRAError.invalidPage }
        let rows = JRAProvider.matches(#"<div>\s*<div>(20[0-9]{2})\.([0-9]{2})\.([0-9]{2})</div>(.*?)(?=<div>\s*<div>20[0-9]{2}\.|<div class="pager|</main>)"#, in: html)
        var results: [HorseResult] = []
        for row in rows {
            guard let date = civil(Int(row[1])!, Int(row[2])!, Int(row[3])!),
                  let venue = JRAProvider.matches(#"^\s*<div>(.*?)</div>"#, in: row[4]).first?[1],
                  let tag = JRAProvider.matches(#"<div class="data-6__tag">(.*?)</div>\s*<div>(.*?)</div>\s*<div>(.*?)</div>\s*<div[^>]*>(.*?)</div>"#, in: row[4]).first,
                  let name = JRAProvider.matches("<a\\b[^>]*>(.*?)</a>", in: tag[1]).first?[1] else { continue }
            let grade = JRAProvider.matches("<span\\b[^>]*>(.*?)</span>", in: tag[1]).first?[1] ?? ""
            let jockey = JRAProvider.matches(#"<a[^>]*href="/horse/jockey/[^>]*>(.*?)</a>"#, in: row[4]).first?[1] ?? ""
            results.append(HorseResult(date: date, name: JRAProvider.plainText(name), venue: JRAProvider.plainText(venue),
                place: JRAProvider.plainText(tag[2]), grade: JRAProvider.plainText(grade),
                distance: JRAProvider.plainText(tag[3] + " " + tag[4]), jockey: JRAProvider.plainText(jockey)))
        }
        guard results.count == total, total > 0, Set(results.map { $0.date }).count == total else { throw JRAError.invalidPage }
        return results.sorted { $0.date > $1.date }
    }
    static func principal(_ data: Data, year: Int, source: URL) throws -> [WorldRace] {
        guard let document = PDFDocument(data: data), let page = document.page(at: 0),
              document.string?.contains("\(year)年") == true,
              let selection = page.selection(for: page.bounds(for: .mediaBox)) else { throw JRAError.wrongYear }
        // PDFKit supplies positioned text fragments, avoiding a bundled PDF parser or guessed column order.
        let fragments = selection.selectionsByLine().map { (rect: $0.bounds(for: page), text: compact($0.string ?? "")) }
        let dates = fragments.filter { $0.text.range(of: #"^\d{1,2}/\d{1,2}$"#, options: .regularExpression) != nil }
        let countries = fragments.filter { $0.text.hasPrefix("〔") }
        let zones = ["イギリス":"Europe/London", "アイルランド":"Europe/Dublin", "フランス":"Europe/Paris", "ドイツ":"Europe/Berlin",
                     "アメリカ合衆国":"America/New_York", "オーストラリア":"Australia/Sydney", "香港":"Asia/Hong_Kong",
                     "アラブ首長国連邦":"Asia/Dubai", "サウジアラビア王国":"Asia/Riyadh"]
        var result: [WorldRace] = []
        for item in dates.sorted(by: { $0.rect.minY > $1.rect.minY }) {
            let cells = fragments.filter { abs($0.rect.minY - item.rect.minY) < 1 && $0.rect.minX > item.rect.maxX }.sorted { $0.rect.minX < $1.rect.minX }
            guard cells.count >= 3 else { continue }
            let name = cells[0].text
            if name.contains("G2") || name.contains("デイ") { continue }
            guard let country = countries.filter({ $0.rect.minY > item.rect.minY }).min(by: { $0.rect.minY < $1.rect.minY }),
                  var zone = zones[country.text.replacingOccurrences(of: "〔", with: "").replacingOccurrences(of: "〕", with: "")] else { continue }
            let parts = item.text.split(separator: "/").compactMap { Int($0) }
            guard parts.count == 2, let date = civil(year, parts[0], parts[1]) else { continue }
            let venue = cells.last!.text
            if venue.contains("デルマー") || venue.contains("サンタアニタ") { zone = "America/Los_Angeles" }
            if venue.contains("フレミントン") || venue.contains("コーフィールド") { zone = "Australia/Melbourne" }
            result.append(WorldRace(date: date, name: name, venue: venue,
                course: cells.dropFirst().dropLast().map { $0.text }.joined(separator: " · "), zone: zone, source: source))
        }
        guard result.count >= 40 else { throw JRAError.invalidPage }
        return result
    }
    static func nextData(_ data: Data) throws -> [[String: Any]] {
        let html = try html(data)
        guard let raw = JRAProvider.matches(#"<script id="__NEXT_DATA__" type="application/json">(.*?)</script>"#, in: html).first?[1],
              let data = raw.data(using: .utf8), let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let props = root["props"] as? [String: Any], let page = props["pageProps"] as? [String: Any],
              let blocks = page["blocks"] as? [[String: Any]] else { throw JRAError.invalidPage }
        return blocks
    }
    static func breedersCup(_ data: Data, year: Int) throws -> [WorldRace] {
        let blocks = try nextData(data)
        let all = String(describing: blocks)
        guard all.contains("\(year)") else { throw JRAError.wrongYear }
        let header = blocks.compactMap { $0["header"] as? [String: Any] }.first
        let config = header?["primaryConfig"] as? [String: Any]
        let countdown = (config?["countdownClock"] as? [[String: Any]])?.first
        let strings = countdown?["strings"] as? [String: String]
        let venue = strings?["eventLocation"] ?? ""
        let zone: String
        if venue == "Keeneland" || venue == "Churchill Downs" { zone = "America/New_York" }
        else if venue == "Del Mar" || venue == "Santa Anita" { zone = "America/Los_Angeles" }
        else { throw JRAError.invalidPage }
        let contents = blocks.compactMap { ($0["richTextEditor"] as? [String: Any])?["html"] as? String }
        let provisional = contents.contains { $0.contains("subject to change") }
        var races: [WorldRace] = []
        for html in contents {
            guard let header = JRAProvider.matches(#"(?:FRIDAY|SATURDAY),\s*(OCTOBER|NOVEMBER)\s+(\d{1,2}),\s*(20\d{2})"#, in: html).first,
                  Int(header[3]) == year, let date = civil(year, header[1] == "OCTOBER" ? 10 : 11, Int(header[2])!) else { continue }
            for row in JRAProvider.matches("<tr\\b[^>]*>(.*?)</tr>", in: html) {
                let cells = JRAProvider.matches("<td\\b[^>]*>(.*?)</td>", in: row[1]).map { JRAProvider.plainText($0[1]) }
                guard cells.count >= 3, cells[2].contains("Breeders' Cup"),
                      let clock = JRAProvider.matches(#"^(\d{1,2}):(\d{2})\s*(AM|PM)$"#, in: cells[1]).first else { continue }
                let hour = Int(clock[1])! % 12 + (clock[3] == "PM" ? 12 : 0)
                let name = String(cells[2][cells[2].range(of: "Breeders' Cup")!.lowerBound...])
                races.append(WorldRace(date: date, name: name, englishName: name, venue: venue, zone: zone,
                    start: time(date, hour: hour, minute: Int(clock[2])!, zone: zone), provisionalTime: provisional, source: bcURL))
            }
        }
        guard races.count >= 10 else { throw JRAError.invalidPage }
        return races
    }
    static func contenders(_ data: Data, year: Int, races: inout [WorldRace], history: inout [HorseResult]) throws {
        let blocks = try nextData(data)
        guard let cards = blocks.compactMap({ $0["horseCards"] as? [String: Any] }).first,
              let groups = cards["races"] as? [[String: Any]] else { throw JRAError.invalidPage }
        for group in groups {
            guard let name = group["raceName"] as? String, let horses = group["horses"] as? [[String: Any]] else { continue }
            for horse in horses where horse["horseName"] as? String == "Forever Young" {
                for performance in horse["pastPerformances"] as? [[String: Any]] ?? [] {
                    guard let raw = performance["raceDate"] as? String, let english = performance["raceName"] as? String else { continue }
                    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
                    formatter.timeZone = TimeZone(identifier: "UTC"); formatter.dateFormat = "MMMM, dd yyyy HH:mm:ss"
                    if let date = formatter.date(from: raw), let i = history.firstIndex(where: { $0.date == day(date, zone: "UTC") }) { history[i].englishName = english }
                }
            }
            guard let index = races.firstIndex(where: { $0.englishName == name }) else { continue }
            let current = horses.filter { $0["year"] as? Int == year }
            // Trainer affiliation, not the (JPN) birthplace suffix, identifies Japanese-trained runners.
            // Only the official trainer names already verified in this adapter are classified here.
            let japaneseTrainers = ["Yoshito Yahagi", "Tomokazu Takano", "Yasuo Tomomichi", "Mitsumasa Nakauchida", "Noriyuki Hori", "Yasuo Ikee", "Hideaki Fujiwara", "Naosuke Sugai", "Manabu Ikezoe", "Takayuki Yasuda"]
            races[index].japaneseRunners = current.filter { japaneseTrainers.contains($0["trainer"] as? String ?? "") }.compactMap { $0["horseName"] as? String }
            races[index].entryStatus = group["horseType"] as? String == "entries" ? "declared" : "candidate"
            races[index].runnersSource = contendersURL
            races[index].foreverYoung = current.contains { $0["horseName"] as? String == "Forever Young" && $0["trainer"] as? String == "Yoshito Yahagi" }
        }
    }
    static func overseas(_ data: Data, year: Int) throws -> [WorldRace] {
        let html = try html(data)
        guard html.contains("\(year)年 発売レース") else { throw JRAError.wrongYear }
        let zones = ["fra":"Europe/Paris", "gbr":"Europe/London", "usa":"America/New_York", "ksa":"Asia/Riyadh", "hkg":"Asia/Hong_Kong", "aus":"Australia/Sydney", "uae":"Asia/Dubai"]
        var races: [WorldRace] = []
        for row in JRAProvider.matches("<tr\\b[^>]*>(.*?)</tr>", in: html) {
            let cells = JRAProvider.matches("<td\\b[^>]*>(.*?)</td>", in: row[1]).map { $0[1] }
            guard cells.count >= 4, let parts = JRAProvider.matches(#"(20\d{2})年(\d{1,2})月(\d{1,2})日"#, in: cells[0]).first,
                  Int(parts[1]) == year, let date = civil(year, Int(parts[2])!, Int(parts[3])!),
                  let country = JRAProvider.matches(#"flag_([a-z]+)_"#, in: cells[1]).first?[1], let zone = zones[country],
                  let link = JRAProvider.matches(#"href="([^"]+)""#, in: cells[2]).first?[1],
                  let url = URL(string: link, relativeTo: overseasURL)?.absoluteURL, allowed(url) else { continue }
            let name = JRAProvider.plainText(cells[2]).replacingOccurrences(of: "（G1）", with: "")
            races.append(WorldRace(date: date, name: name, venue: JRAProvider.plainText(cells[1]), course: JRAProvider.plainText(cells[3]), zone: zone, source: url))
        }
        guard !races.isEmpty else { throw JRAError.invalidPage }
        return races
    }
    static func declarationLinks(_ data: Data, year: Int) throws -> [(String, URL)] {
        let html = try html(data)
        return JRAProvider.matches(#"<a[^>]*href="(/news/[^\"]+\.html)"[^>]*>(.*?)</a>"#, in: html).compactMap {
            let title = JRAProvider.plainText($0[2])
            guard title.hasPrefix("\(year)"), title.contains("の出馬表"), let url = URL(string: $0[1], relativeTo: newsURL)?.absoluteURL else { return nil }
            return (title, url)
        }
    }
    static func enrich(_ data: Data, source: URL, race: inout WorldRace) throws {
        let html = try html(data), plain = compact(JRAProvider.plainText(html))
        guard plain.contains(race.name + "（G1）の出馬表") || plain.contains(race.name + "(G1)の出馬表") else { throw JRAError.invalidPage }
        var names: [String] = []
        for match in JRAProvider.matches(#"href="/JRADB/accessU[^>]*>(.*?)</a>\s*<span class="data">[^<]*(?:栗東|美浦)"#, in: html) {
            let name = JRAProvider.plainText(match[1])
            if !names.contains(name) { names.append(name) }
        }
        race.japaneseRunners = names; race.entryStatus = "declared"; race.runnersSource = source
        race.foreverYoung = names.contains("フォーエバーヤング")
        if let clock = JRAProvider.matches(#"日本時間.*?(\d{1,2})月(\d{1,2})日.*?(\d{1,2})時(\d{2})分"#, in: plain).first,
           let year = Int(race.date.prefix(4)), let day = civil(year, Int(clock[1])!, Int(clock[2])!) {
            race.start = time(day, hour: Int(clock[3])!, minute: Int(clock[4])!, zone: "Asia/Tokyo")
        }
    }
}

actor RacingProvider {
    private struct Cache: Codable { let source: URL; let fetchedAt: Date; let data: Data }
    private let directory: URL
    private let session: URLSession
    private var generation = 0
    init(directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("org.foreveryoungpet.desktop/Racing"), session: URLSession = JRAProvider.makeSession()) {
        self.directory = directory; self.session = session
    }
    private func load(_ url: URL, key: String, now: Date, refresh: Bool) async throws -> (Data, SourceCheck) {
        guard RacingParse.allowed(url), key.range(of: #"^[a-z0-9-]+$"#, options: .regularExpression) != nil else { throw JRAError.invalidPage }
        let path = directory.appendingPathComponent(key + ".json"), currentGeneration = generation
        let cache = (try? Data(contentsOf: path)).flatMap { try? JSONDecoder().decode(Cache.self, from: $0) }
        let valid = cache.flatMap { $0.source == url && $0.data.count <= 4_000_000 ? $0 : nil }
        if !refresh, let cache = valid, (0..<300).contains(now.timeIntervalSince(cache.fetchedAt)) { return (cache.data, SourceCheck(url: url, fetchedAt: cache.fetchedAt, mode: "localCache")) }
        do {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 18)
            request.setValue("ForeverYoungDesktop/3.3 (personal race information)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  response.url.map(RacingParse.allowed) == true, data.count <= 4_000_000 else { throw JRAError.badResponse }
            // Validate before replacing a usable cache with a maintenance page or changed format.
            let year = JRAProvider.calendar.component(.year, from: now)
            if key == "horse-history" { _ = try RacingParse.history(data) }
            else if key.hasPrefix("principal-") { _ = try RacingParse.principal(data, year: Int(key.suffix(4))!, source: url) }
            else if key.hasPrefix("overseas-") && key != "overseas-news" { _ = try RacingParse.overseas(data, year: year) }
            else if key == "bc-watch" { _ = try RacingParse.breedersCup(data, year: year) }
            else if key == "bc-entries" { _ = try RacingParse.nextData(data) }
            else if key == "overseas-news" { guard try RacingParse.html(data).contains("海外競馬") else { throw JRAError.invalidPage } }
            if currentGeneration == generation {
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                if let encoded = try? JSONEncoder().encode(Cache(source: url, fetchedAt: now, data: data)) { try? encoded.write(to: path, options: .atomic) }
            }
            return (data, SourceCheck(url: url, fetchedAt: now, mode: "online"))
        } catch {
            try Task.checkCancellation()
            if generation == currentGeneration, let cache = valid { return (cache.data, SourceCheck(url: url, fetchedAt: cache.fetchedAt, mode: "fallbackCache")) }
            throw error
        }
    }
    func clearCache() throws -> Int {
        generation += 1
        guard FileManager.default.fileExists(atPath: directory.path) else { return 0 }
        var count = 0
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) {
            guard file.lastPathComponent.range(of: #"^(principal-\d{4}|overseas-\d{4}|bc-watch|bc-entries|horse-history|overseas-news|declared-\d+)\.json$"#, options: .regularExpression) != nil else { continue }
            let value = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if value.isRegularFile == true && value.isSymbolicLink != true { try FileManager.default.removeItem(at: file); count += 1 }
        }
        return count
    }
    func overview(at now: Date = Date(), refresh: Bool = false) async throws -> RacingOverview {
        let year = JRAProvider.calendar.component(.year, from: now)
        let principalURL = URL(string: "https://www.jairs.jp/\(year)_world_principal_race_schedule.pdf")!
        var overview = RacingOverview()
        // Independent sources fail independently; a missing source never masquerades as an empty result.
        let inputs: [(URL, String)] = [(principalURL,"principal-\(year)"),(RacingParse.overseasURL,"overseas-\(year)"),
            (RacingParse.bcURL,"bc-watch"),(RacingParse.contendersURL,"bc-entries"),(RacingParse.historyURL,"horse-history"),(RacingParse.newsURL,"overseas-news")]
        var pages: [String: Data] = [:]
        await withTaskGroup(of: (String, Result<(Data, SourceCheck), Error>).self) { group in
            for (url, key) in inputs { group.addTask { do { return (key, .success(try await self.load(url, key: key, now: now, refresh: refresh))) } catch { return (key, .failure(error)) } } }
            for await (key, result) in group {
                switch result {
                case let .success((data, check)): pages[key] = data; overview.checks.append(check)
                case let .failure(error): overview.warnings.append("\(key): \(error.localizedDescription)")
                }
            }
        }
        try Task.checkCancellation()
        if let data = pages["principal-\(year)"] { do { overview.races = try RacingParse.principal(data, year: year, source: principalURL) } catch { overview.warnings.append("JAIRS: \(error.localizedDescription)") } }
        if let data = pages["overseas-\(year)"] { do {
            for race in try RacingParse.overseas(data, year: year) {
                if let i = overview.races.firstIndex(where: { $0.date == race.date && $0.name == race.name }) { overview.races[i] = race } else { overview.races.append(race) }
            }
        } catch { overview.warnings.append("JRA overseas: \(error.localizedDescription)") } }
        if let data = pages["bc-watch"] { do {
            let races = try RacingParse.breedersCup(data, year: year)
            overview.races.removeAll { $0.name.hasPrefix("ブリーダーズカップ") }
            overview.races += races
        } catch { overview.warnings.append("Breeders’ Cup schedule: \(error.localizedDescription)") } }
        if let data = pages["horse-history"] { do { overview.history = try RacingParse.history(data); overview.historyAvailable = true } catch { overview.warnings.append("JBIS: \(error.localizedDescription)") } }
        if let data = pages["bc-entries"] { do { try RacingParse.contenders(data, year: year, races: &overview.races, history: &overview.history) } catch { overview.warnings.append("Breeders’ Cup contenders: \(error.localizedDescription)") } }
        if let data = pages["overseas-news"], let links = try? RacingParse.declarationLinks(data, year: year) {
            for (title, url) in links.prefix(8) {
                guard let index = overview.races.firstIndex(where: { title.contains($0.name + "（G1）の出馬表") || title.contains($0.name + "(G1)の出馬表") }) else { continue }
                do {
                    let key = "declared-" + url.deletingPathExtension().lastPathComponent
                    let (data, check) = try await load(url, key: key, now: now, refresh: refresh)
                    try RacingParse.enrich(data, source: url, race: &overview.races[index]); overview.checks.append(check)
                } catch { overview.warnings.append("JRA runners: \(error.localizedDescription)") }
            }
        }
        try Task.checkCancellation()
        let start = RacingParse.day(now), end = RacingParse.day(JRAProvider.calendar.date(byAdding: .day, value: 30, to: now)!)
        if end.prefix(4) != start.prefix(4) { overview.warnings.append("未来三十天跨年；下一年度尚未纳入的计划可能缺失，请核对主办方。") }
        overview.upcoming = overview.races.filter { $0.foreverYoung && $0.date >= start && $0.date < end }.sorted { $0.date < $1.date }
        if !overview.checks.contains(where: { $0.url == RacingParse.contendersURL }) { overview.warnings.append("参赛计划来源不可用；不能确认未来三十天是否参赛。") }
        overview.races.sort { $0.start ?? RacingParse.time($0.date, hour: 12, minute: 0, zone: $0.zone)! < $1.start ?? RacingParse.time($1.date, hour: 12, minute: 0, zone: $1.zone)! }
        return overview
    }
}

actor CombinedRaceProvider: RaceInformationProviding {
    let jra: JRAProvider
    let racing: RacingProvider
    init(jra: JRAProvider = JRAProvider(), racing: RacingProvider) { self.jra = jra; self.racing = racing }
    func query(_ period: RacePeriod, at now: Date, refresh: Bool) async throws -> RaceQueryResult {
        async let domestic = jra.query(period, at: now, refresh: refresh)
        async let overseas = racing.overview(at: now, refresh: refresh)
        var result: RaceQueryResult
        var domesticError: Error?
        do { result = try await domestic }
        catch {
            try Task.checkCancellation()
            domesticError = error
            result = RaceQueryResult(period: period, range: period.range(at: now), races: [], fetchedAt: now,
                sourceURLs: [], cached: false, warning: "JRA 国内赛程不可用：\(error.localizedDescription)", nextRace: nil)
            result.domesticAvailable = false
        }
        let overview = try await overseas
        if !result.domesticAvailable && overview.races.isEmpty { throw domesticError ?? JRAError.badResponse }
        let lower = RacingParse.day(result.range.lowerBound), upper = RacingParse.day(result.range.upperBound)
        result.international = overview.races.filter { $0.date >= lower && $0.date <= upper }
        result.internationalChecks = overview.checks.filter { $0.url != RacingParse.historyURL }
        result.internationalWarnings = overview.warnings
        result.internationalAvailable = !overview.races.isEmpty
        return result
    }
    func clearCache() async throws -> Int { let first = try await jra.clearCache(); return first + (try await racing.clearCache()) }
}
