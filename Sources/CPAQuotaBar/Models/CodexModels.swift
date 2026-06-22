import Foundation

enum QuotaDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case compact
    case full

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact:
            return "精简"
        case .full:
            return "完整"
        }
    }
}

struct AppConfiguration: Equatable, Sendable {
    var serverURL: String = "http://192.168.2.20:8317"
    var managementKey: String = ""

    var normalizedServerURL: String {
        Self.normalizeServerURL(serverURL)
    }

    var managementAPIBaseURL: String {
        guard normalizedServerURL.isEmpty == false else {
            return ""
        }

        return normalizedServerURL + "/v0/management"
    }

    var isComplete: Bool {
        normalizedServerURL.isEmpty == false
            && managementKey.trimmedNonEmpty != nil
    }

    var quotaPageURL: URL? {
        guard normalizedServerURL.isEmpty == false else {
            return nil
        }

        return URL(string: normalizedServerURL + "/management.html#/quota")
    }

    static func normalizeServerURL(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.isEmpty == false else {
            return ""
        }

        result = result.replacingOccurrences(
            of: #"(?i)/management\.html.*$"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?i)/?v0/management/?$"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"/+$"#,
            with: "",
            options: .regularExpression
        )

        if result.lowercased().hasPrefix("http://") == false,
           result.lowercased().hasPrefix("https://") == false {
            result = "http://" + result
        }

        return result
    }
}

struct CodexAuthFile: Identifiable, Equatable, Sendable {
    let name: String
    let provider: String
    let authIndex: String?
    let disabled: Bool
    let runtimeOnly: Bool
    let note: String?
    let path: String?
    let accountID: String?
    let planFallback: String?
    let subscriptionActiveUntil: Date?
    let raw: JSONObject

    var id: String { name }

    var displayName: String {
        note?.trimmedNonEmpty
            ?? name.removingJSONFileExtension
    }
}

struct QuotaWindow: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let usedPercent: Double?
    let resetLabel: String

    var remainingPercent: Double? {
        guard let usedPercent else {
            return nil
        }

        return max(0, min(100, 100 - usedPercent))
    }
}

struct CodexQuotaSnapshot: Equatable, Sendable {
    let planType: String?
    let subscriptionActiveUntil: Date?
    let rateLimitResetCreditsAvailableCount: Int?
    let windows: [QuotaWindow]
}

struct AccountQuotaState: Identifiable, Equatable, Sendable {
    let account: CodexAuthFile
    var snapshot: CodexQuotaSnapshot?
    var isLoading: Bool = false
    var errorMessage: String?
    var lastUpdatedAt: Date?

    var id: String { account.id }
}
