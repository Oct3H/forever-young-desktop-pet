import Foundation

enum CodexActivity: String, Codable {
    case idle, working, waiting, review, completed, failed, interrupted, disconnected

    var label: String {
        switch self {
        case .idle: return "空闲"
        case .working: return "工作中"
        case .waiting: return "等待工具结果"
        case .review: return "正在检查"
        case .completed: return "本轮已完成"
        case .failed: return "本轮失败"
        case .interrupted: return "本轮已中断"
        case .disconnected: return "Codex 未连接"
        }
    }

    var animationRow: Int? {
        switch self {
        case .working: return 7
        case .waiting: return 6
        case .review: return 8
        case .completed: return 3
        case .failed: return 5
        case .interrupted: return 6
        case .idle, .disconnected: return nil
        }
    }

    var isTransient: Bool { self == .completed || self == .failed || self == .interrupted }
}

enum PetCommand {
    case pointer(dx: Double, dy: Double)
    case hover(Bool, allowJump: Bool)
    case drag(Double?)
    case greet(duration: Double)
    case preview(Int?)
    case codexState(CodexActivity)
    case queryRaces(RacePeriod, refresh: Bool)
    case clearRaceCache
    case showCodexTasks
    case openCodexThread(String)
}

// A local-only event input for future Hooks/App Server adapters; no network listener.
enum LocalPetCommand {
    static let notification = Notification.Name("org.foreveryoungpet.desktop.codex-state.v1")

    static func parse(_ data: Data) -> CodexActivity? {
        guard data.count < 1024,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["version"] as? Int == 1,
              let state = object["state"] as? String else { return nil }
        return CodexActivity(rawValue: state)
    }
}
