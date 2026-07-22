import Foundation

enum Formatting {
    static func shortDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }

    static func lastUpdated(_ date: Date?) -> String {
        guard let date else {
            return "未刷新"
        }

        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    static func expiration(_ date: Date?) -> String? {
        guard let date else {
            return nil
        }

        return shortDateTime(date)
    }

    static func planName(_ value: String?) -> String? {
        guard let rawValue = value?.trimmedNonEmpty else {
            return nil
        }

        switch rawValue.lowercased() {
        case "pro":
            return "Pro 20x"
        case "prolite", "pro-lite", "pro_lite":
            return "Pro 5x"
        case "plus":
            return "Plus"
        case "team":
            return "Team"
        case "free":
            return "Free"
        case "supergrok":
            return "SuperGrok"
        case "supergrok-heavy":
            return "SuperGrok Heavy"
        default:
            return rawValue
        }
    }
}
