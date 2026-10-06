import Foundation
import AVFoundation
import CryptoKit

struct VoiceCue: Decodable {
    let id: String
    let character: String
    let file: String
    let contexts: [String]
    let hours: [Int]?
    let sha256: String
}

/// Only local recordings in the verified manifest are eligible for playback.
final class VoiceLibrary {
    let cues: [VoiceCue]
    private let resources: URL
    private var lastID = ""
    private var playedEvents = Set<String>()
    private var lastAutomatic: [String: Double] = [:]

    init(resources: URL) throws {
        struct Catalog: Decodable { let version: Int; let character: String; let clips: [VoiceCue] }
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: resources.appendingPathComponent("voices/catalog.json")))
        guard catalog.version == 1, catalog.character == "foreveryoung", !catalog.clips.isEmpty,
              Set(catalog.clips.map { $0.id }).count == catalog.clips.count else { throw CocoaError(.fileReadCorruptFile) }
        for cue in catalog.clips {
            guard cue.character == "foreveryoung", !cue.contexts.isEmpty,
                  cue.contexts.allSatisfy({ ["click","working","completed","failed","interrupted"].contains($0) }),
                  cue.file == "official-voice.mp3" || (cue.file.hasPrefix("voices/") && cue.file.split(separator:"/").count == 2 && !cue.file.contains("..")),
                  cue.hours.map({ $0.count == 2 && $0[0] >= 0 && $0[1] < 24 && $0[0] <= $0[1] }) ?? true else { throw CocoaError(.fileReadCorruptFile) }
            let data = try Data(contentsOf: resources.appendingPathComponent(cue.file))
            let hash = SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()
            guard hash == cue.sha256 else { throw CocoaError(.fileReadCorruptFile) }
        }
        cues = catalog.clips; self.resources = resources
    }

    func candidates(_ context: String, hour: Int) -> [VoiceCue] {
        cues.filter { $0.contexts.contains(context) && ($0.hours.map { hour >= $0[0] && hour <= $0[1] } ?? true) }
    }
    func select(_ context: String, hour: Int) -> VoiceCue? {
        let pool = candidates(context,hour:hour)
        let fresh = pool.filter { $0.id != lastID }
        guard let cue = (fresh.isEmpty ? pool : fresh).randomElement() else { return nil }
        lastID = cue.id; return cue
    }
    func player(for cue: VoiceCue) throws -> AVAudioPlayer {
        let player = try AVAudioPlayer(contentsOf:resources.appendingPathComponent(cue.file))
        player.numberOfLoops = 0; player.prepareToPlay(); return player
    }
    static func priority(_ context: String) -> Int {
        context == "failed" ? 40 : ["completed","interrupted"].contains(context) ? 30 : context == "working" ? 20 : 10
    }
    func allowsAutomatic(_ context: String, key: String, now: Double, busyPriority: Int) -> Bool {
        guard context != "click", cues.contains(where:{$0.contexts.contains(context)}), !playedEvents.contains(key),
              busyPriority == 0 || Self.priority(context) > busyPriority else { return false }
        let cooldown = context == "failed" ? 5_000.0 : context == "working" ? 30_000.0 : 10_000.0
        return now - (lastAutomatic[context] ?? -.greatestFiniteMagnitude) >= cooldown
    }
    func didPlay(_ context: String, key: String? = nil, now: Double) {
        guard let key = key else { return }
        if playedEvents.count >= 256 { playedEvents.removeAll() }
        playedEvents.insert(key); lastAutomatic[context] = now
    }
}

func runVoiceChecks(resources: URL) throws -> [String] {
    func check(_ value: Bool) throws { if !value { throw CocoaError(.validationMissingMandatoryProperty) } }
    let voices = try VoiceLibrary(resources:resources)
    try check(voices.cues.count == 17)
    for cue in voices.cues {
        let player = try voices.player(for:cue)
        try check(player.duration > 0.5 && player.duration < 3.1)
    }
    try check(voices.candidates("click",hour:7).contains(where:{$0.id == "morning"}))
    try check(!voices.candidates("click",hour:20).contains(where:{$0.id == "morning"}))
    try check(voices.candidates("click",hour:20).contains(where:{$0.id == "evening"}))
    try check(voices.candidates("working",hour:14).count == 5)
    try check(voices.candidates("completed",hour:14).count == 6)
    var previous = ""
    for _ in 0..<40 { let cue = voices.select("click",hour:14)!; try check(cue.id != previous); previous = cue.id }
    try check(voices.allowsAutomatic("working",key:"run-1",now:0,busyPriority:0))
    voices.didPlay("working",key:"run-1",now:0)
    try check(!voices.allowsAutomatic("working",key:"run-1",now:60_000,busyPriority:0))
    try check(!voices.allowsAutomatic("working",key:"run-2",now:2_000,busyPriority:0))
    try check(voices.allowsAutomatic("working",key:"run-2",now:30_000,busyPriority:0))
    try check(!voices.allowsAutomatic("working",key:"run-2",now:30_000,busyPriority:40))
    try check(voices.allowsAutomatic("failed",key:"failed-1",now:100,busyPriority:10))
    try check(!voices.allowsAutomatic("waiting",key:"wait-1",now:1_000,busyPriority:0))
    return ["Seventeen identity-bound SHA256 recordings decode in AVAudioPlayer", "Time-appropriate greetings and no adjacent repeats", "Five working and six completion variants", "Automatic event deduplication, cooldown and priority", "Waiting and review do not trigger repetitive audio"]
}
