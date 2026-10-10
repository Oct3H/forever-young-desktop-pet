import AppKit

func runVersionChecks(directory: URL) throws -> [String] {
    let fm = FileManager.default,fixture = directory.appendingPathComponent("versions-"+UUID().uuidString)
    try fm.createDirectory(at:fixture,withIntermediateDirectories:true)
    let manager = VersionManager(root:fixture.appendingPathComponent("store"))
    let current = Bundle.main.bundleURL.deletingLastPathComponent(),release = try VersionManager.read(current)
    try VersionManager.verify(current,release:release)
    let installed = try manager.importRelease(current)
    try require(try VersionManager.read(installed).version == "3.8.0","complete signed version and paired plugins imported")
    try require(try manager.importRelease(current).path == installed.path,"identical release imports are idempotent")
    let previous = current.appendingPathComponent("回退版本/v3.7.2")
    _ = try manager.importRelease(previous)
    try require(Set(manager.stored().map {$0.1.version}) == Set(["3.8.0","3.7.2"]),"previous signed app and plugin pair remain available for rollback")
    let tampered = fixture.appendingPathComponent("tampered"); try fm.copyItem(at:previous,to:tampered)
    let plist = tampered.appendingPathComponent("Forever Young.app/Contents/Info.plist")
    try Data("tampered".utf8).write(to:plist)
    do { _ = try manager.importRelease(tampered); throw IntegrationCheckError.failed("tampered release accepted") } catch is VersionError {}
    try VersionManager.verify(installed,release:release)
    try require(manager.stored().count == 2,"failed import keeps installed versions intact")
    try require(!PetRelease.safePath("../outside") && !PetRelease.safePath("/outside") && !PetRelease.safePath("a//b") && !PetRelease.safePath("a\\b"),"unsafe manifest paths rejected")
    let symlink = fixture.appendingPathComponent("symlink"); try fm.copyItem(at:previous,to:symlink)
    let appInfo = symlink.appendingPathComponent("Forever Young.app/Contents/Info.plist")
    try fm.removeItem(at:appInfo);try fm.createSymbolicLink(at:appInfo,withDestinationURL:previous.appendingPathComponent("Forever Young.app/Contents/Info.plist"))
    do { _ = try manager.importRelease(symlink); throw IntegrationCheckError.failed("symlink release accepted") } catch is VersionError {}
    var blocked = false; manager.activate(version:"3.7.2",hasActiveTasks:true) { if case .failure = $0 { blocked = true } }
    try require(blocked,"active tasks block version switching before any launch")
    return ["complete signed app and plugin pair","idempotent release import","previous version retained for rollback","tampered package refused","failed import preserves installed versions","manifest traversal rejected","symlink refused","active task switch protection"]
}
