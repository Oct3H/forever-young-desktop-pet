import AppKit
import Darwin

// Fixed-purpose handoff: wait for the parent to exit, then open an already-verified bundle.
guard CommandLine.arguments.count == 4, let parent = Int32(CommandLine.arguments[2]), parent > 1, getppid() == parent else { exit(1) }
let target = URL(fileURLWithPath:CommandLine.arguments[1]),fallback = URL(fileURLWithPath:CommandLine.arguments[3])
func valid(_ app: URL) -> Bool {
    guard app.lastPathComponent == "Forever Young.app", let info = NSDictionary(contentsOf:app.appendingPathComponent("Contents/Info.plist")), info["CFBundleIdentifier"] as? String == "org.foreveryoungpet.desktop" else { return false }
    let p = Process(); p.executableURL = URL(fileURLWithPath:"/usr/bin/codesign"); p.arguments = ["--verify","--deep","--strict",app.path]; p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
    do { try p.run();p.waitUntilExit();return p.terminationStatus == 0 } catch { return false }
}
guard valid(target),valid(fallback) else { exit(1) }
print("READY"); fflush(stdout)
let deadline = Date(timeIntervalSinceNow:15)
while kill(parent,0) == 0 && Date() < deadline { Thread.sleep(forTimeInterval:0.05) }
guard kill(parent,0) != 0 else { exit(1) }
let p = Process();p.executableURL = URL(fileURLWithPath:"/usr/bin/open");p.arguments = ["-n",target.path]
do {try p.run();p.waitUntilExit();if p.terminationStatus == 0 {exit(0)}}catch{}
let recovery = Process();recovery.executableURL = URL(fileURLWithPath:"/usr/bin/open");recovery.arguments = ["-n",fallback.path]
try? recovery.run()
