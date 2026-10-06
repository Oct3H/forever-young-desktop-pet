import Foundation

enum RacePeriod: String, Codable {
    case pastWeek, nextWeek
    var label: String { self == .pastWeek ? "过去七天" : "未来七天" }

    func range(at now: Date) -> ClosedRange<Date> {
        let today = JRAProvider.calendar.startOfDay(for: now)
        if self == .pastWeek {
            return JRAProvider.calendar.date(byAdding: .day, value: -6, to: today)!...today
        }
        return today...JRAProvider.calendar.date(byAdding: .day, value: 6, to: today)!
    }
}

struct JRARace: Codable, Equatable {
    let date: Date
    let name: String
    let venue: String
    let course: String
    let winner: String
    let jockey: String
    let pageURL: URL
    let resultURL: URL?
    let isJump: Bool
}

struct JRAYear: Codable {
    let year: Int
    let fetchedAt: Date
    let sourceURL: URL
    let races: [JRARace]
}

enum RaceDataSource {
    case online, localCache, fallbackCache, mixed
    var label: String {
        switch self {
        case .online: return "官网在线获取"
        case .localCache: return "本地缓存（五分钟内，本次未联网）"
        case .fallbackCache: return "旧缓存（本次官网查询失败）"
        case .mixed: return "部分在线获取，部分使用本地缓存"
        }
    }
}

struct RaceQueryResult {
    let period: RacePeriod
    let range: ClosedRange<Date>
    let races: [JRARace]
    let fetchedAt: Date
    let sourceURLs: [URL]
    let cached: Bool
    let warning: String?
    let nextRace: JRARace?
    var dataSource: RaceDataSource? = nil
    var international: [WorldRace] = []
    var internationalChecks: [SourceCheck] = []
    var internationalWarnings: [String] = []
    var internationalAvailable = false
    var domesticAvailable = true
    var sourceLabel: String { (dataSource ?? (cached ? (warning == nil ? .localCache : .fallbackCache) : .online)).label }
}

enum JRAError: LocalizedError {
    case invalidPage, wrongYear, badResponse
    var errorDescription: String? {
        switch self {
        case .invalidPage: return "官网页面结构或编码发生变化，无法确认赛事。"
        case .wrongYear: return "官网尚未提供所查询年份的数据。"
        case .badResponse: return "JRA 官网暂时无法访问。"
        }
    }
}

protocol RaceInformationProviding {
    func query(_ period: RacePeriod, at now: Date, refresh: Bool) async throws -> RaceQueryResult
    func clearCache() async throws -> Int
}

actor JRAProvider: RaceInformationProviding {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }
    static func isOfficial(_ url: URL) -> Bool {
        url.scheme == "https" && ["jra.jp", "www.jra.jp", "jra.go.jp", "www.jra.go.jp"].contains(url.host ?? "")
    }

    private let cacheDirectory: URL
    private let session: URLSession
    private var cacheGeneration = 0

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration)
    }

    init(cacheDirectory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("org.foreveryoungpet.desktop/JRA"), session: URLSession = JRAProvider.makeSession()) {
        self.cacheDirectory = cacheDirectory
        self.session = session
    }

    func clearCache() async throws -> Int {
        cacheGeneration += 1
        guard FileManager.default.fileExists(atPath: cacheDirectory.path) else { return 0 }
        let files = try FileManager.default.contentsOfDirectory(at: cacheDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        var removed = 0
        for file in files where file.lastPathComponent.range(of: #"^g1-[0-9]{4}\.json$"#, options: .regularExpression) != nil {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            try FileManager.default.removeItem(at: file)
            removed += 1
        }
        return removed
    }

    static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (0..<match.numberOfRanges).map { index in
                guard let range = Range(match.range(at: index), in: text) else { return "" }
                return String(text[range])
            }
        }
    }

    static func plainText(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
        for match in matches("&#(x[0-9a-f]+|[0-9]+);", in: text) {
            let value = match[1].lowercased()
            let number = value.hasPrefix("x") ? UInt32(value.dropFirst(), radix: 16) : UInt32(value)
            if let number = number, let scalar = UnicodeScalar(number) {
                text = text.replacingOccurrences(of: match[0], with: String(scalar))
            }
        }
        for (entity, value) in [("&nbsp;", " "), ("&amp;", "&"), ("&quot;", "\""), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">") ] {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        return text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parse(_ data: Data, expectedYear: Int, sourceURL: URL, fetchedAt: Date) throws -> JRAYear {
        guard isOfficial(sourceURL), data.count <= 2_000_000,
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS),
              let yearText = matches("G(?:&#8544;|Ⅰ|I)レース一覧\\s*(20[0-9]{2})年", in: html).first?[1],
              let year = Int(yearText) else { throw JRAError.invalidPage }
        guard year == expectedYear else { throw JRAError.wrongYear }
        func link(_ cell: String) -> URL? {
            guard let href = matches("href\\s*=\\s*[\"']([^\"']+)[\"']", in: cell).first?[1],
                  let url = URL(string: plainText(href), relativeTo: sourceURL)?.absoluteURL,
                  isOfficial(url) else { return nil }
            return url
        }
        var races: [JRARace] = []
        for row in matches("<tr\\b[^>]*>(.*?)</tr>", in: html) {
            var cells: [String: String] = [:]
            for cell in matches("<td\\b[^>]*class=[\"']([^\"']+)[\"'][^>]*>(.*?)</td>", in: row[1]) {
                for key in cell[1].split(separator: " ") { cells[String(key)] = cell[2] }
            }
            guard let dateCell = cells["date"], let raceCell = cells["race"],
                  let dateParts = matches("([0-9]{1,2})月([0-9]{1,2})日", in: dateCell).first,
                  let month = Int(dateParts[1]), let day = Int(dateParts[2]),
                  let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
                  calendar.component(.month, from: date) == month, calendar.component(.day, from: date) == day,
                  let name = matches("<a\\b[^>]*>(.*?)</a>", in: raceCell).first?[1],
                  let page = link(raceCell), !plainText(name).isEmpty else { continue }
            races.append(JRARace(date: date, name: plainText(name), venue: plainText(cells["place"] ?? ""),
                                 course: plainText(cells["course"] ?? ""), winner: plainText(cells["winner"] ?? ""),
                                 jockey: plainText(cells["jockey"] ?? ""), pageURL: page,
                                 resultURL: link(cells["result"] ?? ""), isJump: plainText(raceCell).hasPrefix("J")))
        }
        guard races.count >= 20, races.allSatisfy({ !$0.venue.isEmpty && !$0.course.isEmpty }),
              Set(races.map { "\($0.date.timeIntervalSince1970)-\($0.name)" }).count == races.count else {
            throw JRAError.invalidPage
        }
        return JRAYear(year: year, fetchedAt: fetchedAt, sourceURL: sourceURL, races: races.sorted { $0.date < $1.date })
    }

    private func load(_ year: Int, now: Date, refresh: Bool) async throws -> (JRAYear, Bool, String?) {
        let generation = cacheGeneration
        let path = cacheDirectory.appendingPathComponent("g1-\(year).json")
        let cached = (try? Data(contentsOf: path)).flatMap { try? JSONDecoder().decode(JRAYear.self, from: $0) }
        let validCache = cached.flatMap { value -> JRAYear? in
            guard value.year == year, Self.isOfficial(value.sourceURL), value.races.count >= 20,
                  value.races.allSatisfy({ Self.isOfficial($0.pageURL) && ($0.resultURL.map(Self.isOfficial) ?? true) }) else { return nil }
            return value
        }
        if !refresh, let cached = validCache, now.timeIntervalSince(cached.fetchedAt) >= 0,
           now.timeIntervalSince(cached.fetchedAt) < 300 { return (cached, true, nil) }
        let currentYear = Self.calendar.component(.year, from: now)
        let suffix = year == currentYear ? "g1.html" : "\(year)/g1.html"
        let source = URL(string: "https://jra.jp/datafile/seiseki/replay/\(suffix)")!
        do {
            var request = URLRequest(url: source, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            request.setValue("ForeverYoungDesktop/3.1 (personal race calendar)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  let finalURL = response.url, Self.isOfficial(finalURL) else { throw JRAError.badResponse }
            let result = try Self.parse(data, expectedYear: year, sourceURL: source, fetchedAt: now)
            if generation == cacheGeneration {
                try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
                if let encoded = try? JSONEncoder().encode(result) { try? encoded.write(to: path, options: .atomic) }
            }
            return (result, false, nil)
        } catch {
            try Task.checkCancellation()
            if generation == cacheGeneration, let cached = validCache {
                return (cached, true, "官网查询失败，展示之前缓存的数据；请留意更新时间。")
            }
            throw error
        }
    }

    func query(_ period: RacePeriod, at now: Date = Date(), refresh: Bool = false) async throws -> RaceQueryResult {
        let range = period.range(at: now)
        let years = Set([Self.calendar.component(.year, from: range.lowerBound), Self.calendar.component(.year, from: range.upperBound)])
        var data: [JRAYear] = []
        var cached = false
        var cachedYears = 0
        var warnings: [String] = []
        for year in years.sorted() {
            let (value, usedCache, warning) = try await load(year, now: now, refresh: refresh)
            data.append(value)
            cached = cached || usedCache
            if usedCache { cachedYears += 1 }
            if let warning = warning { warnings.append(warning) }
        }
        let flatRaces = data.flatMap { $0.races }.filter { !$0.isJump }.sorted { $0.date < $1.date }
        return RaceQueryResult(period: period, range: range, races: flatRaces.filter { range.contains($0.date) },
                               fetchedAt: data.map { $0.fetchedAt }.min()!, sourceURLs: data.map { $0.sourceURL },
                               cached: cached, warning: warnings.isEmpty ? nil : warnings.joined(separator: "\n"),
                               nextRace: flatRaces.first { $0.date > range.upperBound },
                               dataSource: !warnings.isEmpty ? .fallbackCache : cachedYears == 0 ? .online :
                                    cachedYears == data.count ? .localCache : .mixed)
    }
}
