import Foundation

struct SpriteFrame: Equatable {
    let row: Int
    let column: Int
    let mode: String
}

struct PetRuntime {
    static let durations: [[Double]] = [
        [280, 110, 110, 140, 140, 320],
        [120, 120, 120, 120, 120, 120, 120, 220],
        [120, 120, 120, 120, 120, 120, 120, 220],
        [140, 140, 140, 280],
        [140, 140, 140, 140, 280],
        [140, 140, 140, 140, 140, 140, 140, 240],
        [150, 150, 150, 150, 150, 260],
        [120, 120, 120, 120, 120, 220],
        [150, 150, 150, 150, 150, 280]
    ]
    private(set) var inside = false
    private(set) var lookIndex: Int?
    private(set) var jumpCount = 0
    private(set) var greetingCount = 0
    private(set) var previewRow: Int?
    private var action: (row: Int, started: Double, duration: Double)?
    private var drag: (row: Int, started: Double)?
    private var gazeAngle: Double?
    private var pointTime: Double?
    private var lastPoint: (x: Double, y: Double)?
    private var nextIdleTime: Double?
    private var idleStarted: Double?
    private var started: Double = 0
    private(set) var codexActivity: CodexActivity = .idle
    private var codexStarted: Double = 0

    mutating func handle(_ command: PetCommand, at now: Double) {
        switch command {
        case let .pointer(dx, dy): point(dx: dx, dy: dy, at: now)
        case let .hover(inside, allowJump): hover(inside, at: now, allowJump: allowJump)
        case let .drag(delta): dragging(horizontalDelta: delta, at: now)
        case let .greet(duration): greet(at: now, duration: duration)
        case let .preview(row): preview(row, at: now)
        case let .codexState(state):
            guard codexActivity != state else { return }
            codexActivity = state
            codexStarted = now
            idleStarted = nil
        default: break // Information cards and navigation belong to the application layer.
        }
    }

    // dx and dy use image coordinates: right is positive x, down is positive y.
    mutating func point(dx: Double, dy: Double, at now: Double? = nil) {
        if let now = now {
            if lastPoint == nil || hypot(dx - lastPoint!.x, dy - lastPoint!.y) > 4 {
                idleStarted = nil
                nextIdleTime = now + 6_000
                lastPoint = (dx, dy)
            }
        }
        guard hypot(dx, dy) > 8 else {
            lookIndex = nil
            gazeAngle = nil
            pointTime = now
            return
        }
        let degrees = (atan2(dx, -dy) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        func difference(_ a: Double, _ b: Double) -> Double {
            (a - b + 540).truncatingRemainder(dividingBy: 360) - 180
        }
        if let now = now, let previousTime = pointTime, let previousAngle = gazeAngle {
            let weight = 1 - exp(-max(0, now - previousTime) / 65)
            gazeAngle = (previousAngle + difference(degrees, previousAngle) * weight + 360)
                .truncatingRemainder(dividingBy: 360)
        } else { gazeAngle = degrees }
        pointTime = now
        let angle = gazeAngle!
        // Four extra degrees past a sector boundary prevent adjacent poses from chattering.
        if let index = lookIndex, abs(difference(angle, Double(index) * 22.5)) <= 15.25 { return }
        lookIndex = Int((angle / 22.5).rounded()) % 16
    }

    mutating func hover(_ isInside: Bool, at now: Double, allowJump: Bool = true) {
        guard isInside != inside else { return }
        inside = isInside
        guard isInside, allowJump, previewRow == nil, action == nil, drag == nil else { return }
        idleStarted = nil
        action = (4, now, Self.durations[4].reduce(0, +))
        jumpCount += 1
    }

    mutating func greet(at now: Double, duration: Double = 700) {
        previewRow = nil
        idleStarted = nil
        action = (3, now, max(700, duration))
        greetingCount += 1
    }

    mutating func synchronizeGreeting(audioTime: Double, playing: Bool, at now: Double) {
        guard let current = action, current.row == 3 else { return }
        if playing {
            action = (3, now - audioTime, current.duration)
        } else {
            action = nil
            nextIdleTime = now + 6_000
        }
    }

    mutating func dragging(horizontalDelta: Double?, at now: Double) {
        guard let delta = horizontalDelta else {
            drag = nil
            nextIdleTime = now + 6_000
            return
        }
        let row = abs(delta) > 0.5 ? (delta > 0 ? 1 : 2) : (drag?.row ?? 1)
        if drag?.row != row { drag = (row, now) }
        action = nil
        previewRow = nil
        idleStarted = nil
    }

    mutating func preview(_ row: Int?, at now: Double) {
        action = nil
        idleStarted = nil
        previewRow = row
        started = now
        nextIdleTime = now + 6_000
    }

    private func column(row: Int, elapsed: Double) -> Int {
        let timing = Self.durations[row]
        var offset = max(0, elapsed).truncatingRemainder(dividingBy: timing.reduce(0, +))
        for (index, duration) in timing.enumerated() {
            if offset < duration { return index }
            offset -= duration
        }
        return 0
    }

    mutating func frame(at now: Double) -> SpriteFrame {
        if let drag = drag {
            return SpriteFrame(row: drag.row, column: column(row: drag.row, elapsed: now - drag.started),
                               mode: drag.row == 1 ? "dragging-right" : "dragging-left")
        }
        if let action = action {
            let elapsed = now - action.started
            if elapsed < action.duration {
                let frameColumn: Int
                if action.row == 3 {
                    // Raise the hand, alternate the two waving poses through the sentence, then lower it.
                    frameColumn = elapsed < 140 ? 0 : elapsed >= action.duration - 280 ? 3 :
                        1 + Int(max(0, elapsed - 140) / 180) % 2
                } else { frameColumn = column(row: action.row, elapsed: elapsed) }
                return SpriteFrame(row: action.row, column: frameColumn,
                                   mode: action.row == 4 ? "jumping" : "waving")
            }
            self.action = nil
            started = now
            nextIdleTime = now + 6_000
        }
        if let row = previewRow {
            return SpriteFrame(row: row, column: column(row: row, elapsed: now - started), mode: "preview")
        }
        if let row = codexActivity.animationRow {
            let elapsed = now - codexStarted
            if !codexActivity.isTransient || elapsed < Self.durations[row].reduce(0, +) {
                return SpriteFrame(row: row, column: column(row: row, elapsed: elapsed),
                                   mode: "codex-" + codexActivity.rawValue)
            }
            codexActivity = .idle
        }
        if let look = lookIndex {
            if let next = nextIdleTime, now >= next, idleStarted == nil { idleStarted = now }
            if let start = idleStarted {
                if now - start < Self.durations[0].reduce(0, +) {
                    return SpriteFrame(row: 0, column: column(row: 0, elapsed: now - start), mode: "idle-blink")
                }
                idleStarted = nil
                nextIdleTime = now + 6_000
            }
            return SpriteFrame(row: 9 + look / 8, column: look % 8, mode: "looking")
        }
        let elapsed = max(0, now - started).truncatingRemainder(dividingBy: 6_000)
        return SpriteFrame(row: 0, column: elapsed < 1_100 ? column(row: 0, elapsed: elapsed) : 0, mode: "idle")
    }
}

func runInteractionChecks() throws -> [String] {
    enum CheckFailure: Error { case failed(String) }
    func check(_ condition: Bool, _ label: String) throws {
        if !condition { throw CheckFailure.failed(label) }
    }
    var pet = PetRuntime()
    for index in 0..<16 {
        let radians = Double(index) * .pi / 8
        pet.point(dx: sin(radians) * 300, dy: -cos(radians) * 300)
        try check(pet.lookIndex == index, "direction \(index)")
        let frame = pet.frame(at: 0)
        try check(frame.row == 9 + index / 8 && frame.column == index % 8, "atlas selection \(index)")
    }
    pet.point(dx: 0, dy: 0)
    try check(pet.frame(at: 0).mode == "idle", "center dead zone")
    pet.point(dx: 300, dy: 0)
    pet.hover(true, at: 0)
    try check(pet.frame(at: 300).row == 4 && pet.frame(at: 300).column == 2, "airborne jump frame")
    for time in stride(from: 0.0, through: 10_000, by: 10) {
        pet.hover(true, at: time)
        _ = pet.frame(at: time)
    }
    try check(pet.jumpCount == 1 && pet.frame(at: 10_000).mode == "looking", "one jump during stationary hover")
    pet.hover(false, at: 10_001)
    pet.hover(true, at: 10_002)
    try check(pet.jumpCount == 2 && pet.frame(at: 10_003).mode == "jumping", "leave and re-enter")
    pet.greet(at: 10_004)
    try check(pet.frame(at: 10_005).mode == "waving", "click interrupts jump")
    pet.point(dx: -300, dy: 0)
    try check(pet.frame(at: 10_705).row == 10 && pet.frame(at: 10_705).column == 4, "latest mouse direction resumes")
    pet.greet(at: 11_000)
    pet.greet(at: 11_100)
    try check(pet.greetingCount == 3 && pet.frame(at: 11_101).column == 0, "repeat click restarts greeting")
    pet.hover(false, at: 12_000)
    pet.hover(true, at: 12_001, allowJump: false)
    try check(pet.jumpCount == 2, "drag does not trigger jump")
    for row in 0..<9 {
        pet.preview(row, at: 20_000)
        try check(pet.frame(at: 20_010).row == row, "preview row \(row)")
    }
    pet.preview(nil, at: 21_000)
    try check(pet.frame(at: 21_001).mode == "looking", "return to mouse interaction")

    var stable = PetRuntime()
    stable.point(dx: 0, dy: -300)
    for index in 0..<300 {
        let angle = (index.isMultiple(of: 2) ? 11.0 : 11.5) * .pi / 180
        stable.point(dx: sin(angle) * 300, dy: -cos(angle) * 300)
        try check(stable.lookIndex == 0, "direction boundary jitter is held")
    }
    let crossing = 17.0 * .pi / 180
    stable.point(dx: sin(crossing) * 300, dy: -cos(crossing) * 300)
    try check(stable.lookIndex == 1, "intentional sector crossing is followed")
    stable.point(dx: -5, dy: -300)
    try check(stable.lookIndex == 0, "wraparound gaze selects north")
    stable.point(dx: 0, dy: -300, at: 0)
    stable.point(dx: 300, dy: 0, at: 16)
    try check(stable.lookIndex == 1, "rapid cursor motion is eased rather than snapped")
    for time in stride(from: 32.0, through: 600, by: 16) {
        stable.point(dx: 300, dy: 0, at: time)
    }
    try check(stable.lookIndex == 4, "smoothed gaze converges to latest cursor")

    var resting = PetRuntime()
    resting.point(dx: 300, dy: 0, at: 0)
    try check(resting.frame(at: 5_999).mode == "looking", "rest interval retains gaze")
    _ = resting.frame(at: 6_000)
    try check(resting.frame(at: 6_400) == SpriteFrame(row: 0, column: 2, mode: "idle-blink"),
              "quiet pointer allows a natural idle cycle")
    try check(resting.frame(at: 6_600).column == 3, "idle cycle reaches closed-eye blink")
    resting.point(dx: -300, dy: 0, at: 6_650)
    try check(resting.frame(at: 6_650).mode == "looking", "cursor movement interrupts idle immediately")

    var dragging = PetRuntime()
    dragging.greet(at: 0, duration: 2_900)
    dragging.dragging(horizontalDelta: 30, at: 100)
    try check(dragging.frame(at: 100).row == 1, "drag preempts greeting")
    dragging.dragging(horizontalDelta: 5, at: 220)
    try check(dragging.frame(at: 230).column == 1, "same-direction events do not restart running clock")
    dragging.dragging(horizontalDelta: -5, at: 250)
    try check(dragging.frame(at: 251).row == 2, "drag reversal selects left")
    dragging.dragging(horizontalDelta: 0, at: 270)
    try check(dragging.frame(at: 380).column == 1, "vertical drag preserves last direction and animation clock")
    dragging.dragging(horizontalDelta: nil, at: 400)
    try check(!dragging.frame(at: 401).mode.hasPrefix("dragging"), "release ends running")

    var greeting = PetRuntime()
    greeting.greet(at: 0, duration: 2_900)
    try check(greeting.frame(at: 800).mode == "waving" && greeting.frame(at: 2_400).mode == "waving",
              "wave covers the full official voice")
    try check(greeting.frame(at: 2_650).column == 3, "hand lowers near end of sentence")
    greeting.synchronizeGreeting(audioTime: 400, playing: true, at: 2_800)
    try check(greeting.frame(at: 2_800).mode == "waving" && greeting.frame(at: 2_800).column != 3,
              "voice output clock controls greeting even if wall clock differs")
    greeting.synchronizeGreeting(audioTime: 2_900, playing: false, at: 3_000)
    try check(greeting.frame(at: 3_000).mode != "waving", "voice ending or stopping ends greeting")
    greeting.greet(at: 3_100, duration: 2_900)
    try check(greeting.frame(at: 3_101).column == 0, "repeat greeting restarts raise-hand phase")
    return ["16 screen directions and atlas cells", "center dead zone", "10 seconds of hover has one jump",
            "re-entry starts a new jump", "click preempts jump", "gaze resumes at latest pointer",
            "repeat click restarts greeting", "drag does not trigger jump", "all nine original actions",
            "300 boundary jitters held; deliberate crossing and wraparound followed", "gaze easing converges",
            "idle blink interrupted by mouse movement", "drag direction, reversal and continuous running clock",
            "raise, wave, lower synchronized to audio clock"]
}
