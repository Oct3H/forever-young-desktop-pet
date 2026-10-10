import AppKit
import CryptoKit

struct PetRelease: Codable {
    struct Plugin: Codable { let version: String; let path: String }
    let schema: Int
    let version: String
    let bundleID: String
    let app: String
    let bridgeAPI: Int
    let plugins: [String:Plugin]
    let files: [String:String]
    static let identifier = "org.foreveryoungpet.desktop"
    static func validVersion(_ value: String) -> Bool { value.range(of:"^[0-9]{1,4}\\.[0-9]{1,4}\\.[0-9]{1,4}$",options:.regularExpression) != nil }
    func validate() throws {
        guard schema == 1, Self.validVersion(version), bundleID == Self.identifier, app == "Forever Young.app", (1...2).contains(bridgeAPI), files.count <= 5000,
              Set(plugins.keys) == Set(["vscode","pycharm"]) else { throw VersionError.invalid }
        for (path,hash) in files {
            guard Self.safePath(path), hash.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil else { throw VersionError.invalid }
        }
        for (source,plugin) in plugins {
            guard Self.validVersion(plugin.version), plugin.path == "联动插件/forever-young-\(source)-\(plugin.version).\(source == "vscode" ? "vsix" : "zip")", files[plugin.path] != nil else { throw VersionError.invalid }
        }
        guard files[app+"/Contents/Info.plist"] != nil, files[app+"/Contents/MacOS/ForeverYoungDesktop"] != nil else { throw VersionError.invalid }
    }
    static func safePath(_ path: String) -> Bool {
        !path.isEmpty && path.utf8.count < 4096 && !path.hasPrefix("/") && !path.contains("\\") && !path.contains("\0") && path.split(separator:"/",omittingEmptySubsequences:false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}
enum VersionError: LocalizedError {
    case invalid, integrity, busy
    var errorDescription: String? { switch self {
    case .invalid: return "Invalid or unsupported release package."
    case .integrity: return "Release integrity check failed. Keep the existing version and download the complete package again."
    case .busy: return "Wait until pet-started tasks finish before switching versions."
    } }
}

/// Versions are copied beside one another. A failed import never changes the running app.
final class VersionManager {
    let root: URL
    private(set) var status = "idle"
    private(set) var detail = ""
    private(set) var available: PetRelease?
    var onChange: (() -> Void)?
    private var busy = false
    static let repository = URL(string:"https://github.com/Oct3H/forever-young-desktop-pet")!
    static let manifestURL = URL(string:"https://raw.githubusercontent.com/Oct3H/forever-young-desktop-pet/main/release-manifest.json")!
    init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/ForeverYoungPet/Versions")) { self.root = root }
    var currentVersion: String { Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "3.8.0" }
    var object: [String:Any] { ["current":currentVersion,"status":status,"detail":detail,"available":available?.version ?? "","busy":busy,"requiredPlugins":["vscode":"3.8.0","pycharm":"3.8.0"],"versions":stored().map { ["version":$0.1.version,"path":$0.0.path] }] }
    private func changed(_ value: String, _ message: String = "") { status = value; detail = message; onChange?() }
    func check() {
        guard !busy else { return }; busy = true; changed("checking")
        var request = URLRequest(url:Self.manifestURL); request.timeoutInterval = 15; request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with:request) { [weak self] data,response,error in
            DispatchQueue.main.async {
                guard let self = self else { return }; self.busy = false
                if let response = response as? HTTPURLResponse, response.statusCode == 404 { self.available = nil; self.changed("unpublished"); return }
                guard error == nil, let response = response as? HTTPURLResponse, response.statusCode == 200, response.url == Self.manifestURL,
                      let data = data, data.count <= 1_000_000, let release = try? JSONDecoder().decode(PetRelease.self,from:data), (try? release.validate()) != nil else { self.changed("checkFailed",error?.localizedDescription ?? "Release manifest unavailable."); return }
                self.available = release
                self.changed(release.version.compare(self.currentVersion,options:.numeric) == .orderedDescending ? "available" : "latest")
            }
        }.resume()
    }
    static func read(_ directory: URL) throws -> PetRelease {
        let url = directory.appendingPathComponent("release-manifest.json")
        let values = try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 0) <= 1_000_000 else { throw VersionError.invalid }
        let release = try JSONDecoder().decode(PetRelease.self,from:Data(contentsOf:url)); try release.validate(); return release
    }
    static func verify(_ directory: URL, release: PetRelease) throws {
        try release.validate(); var total = 0
        for (path,hash) in release.files {
            var url = directory
            for part in path.split(separator:"/") {
                url.appendPathComponent(String(part)); let values = try url.resourceValues(forKeys:[.isSymbolicLinkKey]); guard values.isSymbolicLink != true else { throw VersionError.integrity }
            }
            let values = try url.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey])
            guard values.isRegularFile == true, let size = values.fileSize, size <= 100_000_000 else { throw VersionError.integrity }; total += size
            guard total <= 512_000_000, SHA256.hash(data:try Data(contentsOf:url)).map({String(format:"%02x",$0)}).joined() == hash else { throw VersionError.integrity }
        }
        let app = directory.appendingPathComponent(release.app)
        guard let entries = FileManager.default.enumerator(at:app,includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey]) else { throw VersionError.integrity }
        for case let url as URL in entries {
            let values = try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey]); guard values.isSymbolicLink != true else { throw VersionError.integrity }
            if values.isRegularFile == true && release.files[String(url.path.dropFirst(directory.path.count+1))] == nil { throw VersionError.integrity }
        }
        let info = try PropertyListSerialization.propertyList(from:Data(contentsOf:app.appendingPathComponent("Contents/Info.plist")),format:nil) as? [String:Any]
        guard info?["CFBundleIdentifier"] as? String == release.bundleID, info?["CFBundleShortVersionString"] as? String == release.version else { throw VersionError.integrity }
        let process = Process(); process.executableURL = URL(fileURLWithPath:"/usr/bin/codesign"); process.arguments = ["--verify","--deep","--strict",app.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice; try process.run(); process.waitUntilExit(); guard process.terminationStatus == 0 else { throw VersionError.integrity }
    }
    @discardableResult func importRelease(_ directory: URL) throws -> URL {
        let release = try Self.read(directory); try Self.verify(directory,release:release)
        let fm = FileManager.default; try fm.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let target = root.appendingPathComponent(release.version),stage = root.appendingPathComponent(".stage-"+UUID().uuidString)
        if fm.fileExists(atPath:target.path) { let existing = try Self.read(target)
            let required = Set(release.plugins.values.map { $0.path })
            let runtimeFiles = { (files: [String:String]) in files.filter { $0.key.hasPrefix(release.app+"/") || required.contains($0.key) } }
            guard existing.bridgeAPI == release.bridgeAPI, runtimeFiles(existing.files) == runtimeFiles(release.files) else { throw VersionError.integrity }; try Self.verify(target,release:existing); return target }
        try fm.createDirectory(at:stage,withIntermediateDirectories:false); defer { try? fm.removeItem(at:stage) }
        for path in release.files.keys {
            let destination = stage.appendingPathComponent(path); try fm.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
            try fm.copyItem(at:directory.appendingPathComponent(path),to:destination)
        }
        try JSONEncoder().encode(release).write(to:stage.appendingPathComponent("release-manifest.json"),options:.atomic)
        try Self.verify(stage,release:release); try fm.moveItem(at:stage,to:target); return target
    }
    func backupCurrent() throws {
        if stored().contains(where:{$0.1.version == currentVersion}) { return }
        let fm = FileManager.default,stage = root.appendingPathComponent(".backup-"+UUID().uuidString)
        try fm.createDirectory(at:stage,withIntermediateDirectories:true); defer { try? fm.removeItem(at:stage) }
        try fm.copyItem(at:Bundle.main.bundleURL,to:stage.appendingPathComponent("Forever Young.app"))
        let bridges = Bundle.main.resourceURL!.appendingPathComponent("Bridges")
        try fm.copyItem(at:bridges,to:stage.appendingPathComponent("联动插件"))
        var hashes: [String:String] = [:]
        for case let url as URL in fm.enumerator(at:stage,includingPropertiesForKeys:[.isRegularFileKey])! {
            if try url.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile == true { hashes[String(url.path.dropFirst(stage.path.count+1))] = SHA256.hash(data:try Data(contentsOf:url)).map {String(format:"%02x",$0)}.joined() }
        }
        let release = PetRelease(schema:1,version:currentVersion,bundleID:PetRelease.identifier,app:"Forever Young.app",bridgeAPI:2,plugins:["vscode":.init(version:"3.8.0",path:"联动插件/forever-young-vscode-3.8.0.vsix"),"pycharm":.init(version:"3.8.0",path:"联动插件/forever-young-pycharm-3.8.0.zip")],files:hashes)
        try JSONEncoder().encode(release).write(to:stage.appendingPathComponent("release-manifest.json")); _ = try importRelease(stage)
    }
    func chooseImport() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.message = "选择解压后的完整成品文件夹 / Choose the extracted complete release folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        busy = true; changed("verifying")
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            guard let self = self else { return }; let result = Result { try self.backupCurrent(); return try self.importRelease(url) }
            DispatchQueue.main.async { self.busy = false; switch result { case .success: self.changed("imported"); case let .failure(error): self.changed("importFailed",error.localizedDescription) } }
        }
    }
    func stored() -> [(URL,PetRelease)] {
        (try? FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil))?.compactMap { url in
            guard PetRelease.validVersion(url.lastPathComponent), let release = try? Self.read(url), release.version == url.lastPathComponent else { return nil }; return (url,release)
        }.sorted { $0.1.version.compare($1.1.version,options:.numeric) == .orderedDescending } ?? []
    }
    func plugins(version: String) {
        guard let item = stored().first(where:{$0.1.version == version}) else { return }
        NSWorkspace.shared.open(item.0.appendingPathComponent("联动插件"))
    }
    func activate(version: String, hasActiveTasks: Bool, completion: @escaping (Result<Void,Error>) -> Void) {
        guard !busy else { return }; guard !hasActiveTasks else { completion(.failure(VersionError.busy)); return }
        guard let item = stored().first(where:{$0.1.version == version}) else { completion(.failure(VersionError.invalid)); return }
        do { try Self.verify(item.0,release:item.1) } catch { completion(.failure(error)); return }
        let alert = NSAlert(); alert.messageText = "Forever Young · \(version)"
        alert.informativeText = "切换前请安装该版本目录内配套的两个 IDE 插件，并按 IDE 提示重载／重启。旧版与设置保留。包内校验不代表 Apple 公证。\nInstall this version's paired IDE bridges and reload/restart the IDEs. Previous versions and preferences are preserved. Integrity checks are not Apple notarization."
        alert.addButton(withTitle:"切换 / Switch"); alert.addButton(withTitle:"取消 / Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let process = Process(); process.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/VersionSwitch")
            process.arguments = [item.0.appendingPathComponent(item.1.app).path,String(ProcessInfo.processInfo.processIdentifier),Bundle.main.bundleURL.path]
            let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
            var finished = false
            let finish: (Result<Void,Error>) -> Void = { result in
                guard !finished else { return }; finished = true
                pipe.fileHandleForReading.readabilityHandler = nil; self.busy = false
                completion(result)
            }
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                DispatchQueue.main.async {
                    if String(data:data,encoding:.utf8) == "READY\n" { finish(.success(())) }
                    else if data.isEmpty { finish(.failure(VersionError.integrity)) }
                }
            }
            busy = true
            do { try process.run() } catch { finish(.failure(error)); return }
            DispatchQueue.main.asyncAfter(deadline:.now()+5) {
                guard !finished else { return }; if process.isRunning { process.terminate() }
                finish(.failure(VersionError.integrity))
            }
        }
    }
}
