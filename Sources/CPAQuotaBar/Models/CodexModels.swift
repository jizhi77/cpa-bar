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

enum AuthProvider: String, CaseIterable, Identifiable, Sendable {
    case codex
    case xai

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codex:
            return "Codex"
        case .xai:
            return "xAI"
        }
    }
}

enum AuthProviderFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case codex
    case xai

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .codex:
            return "Codex"
        case .xai:
            return "xAI"
        }
    }

    func includes(_ provider: AuthProvider) -> Bool {
        switch self {
        case .all:
            return true
        case .codex:
            return provider == .codex
        case .xai:
            return provider == .xai
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
    var disabled: Bool
    let runtimeOnly: Bool
    var priority: Int?
    let note: String?
    let path: String?
    let accountID: String?
    let planFallback: String?
    let subscriptionActiveUntil: Date?
    var raw: JSONObject

    var id: String { name }

    var authProvider: AuthProvider? {
        AuthProvider(rawValue: provider)
    }

    var providerDisplayName: String {
        authProvider?.title ?? provider
    }

    var displayName: String {
        note?.trimmedNonEmpty
            ?? name.removingJSONFileExtension
    }

    var managementStatusText: String {
        disabled ? "已停用" : "启用"
    }

    var priorityDisplayText: String {
        priority.map(String.init) ?? "未设置"
    }
}

struct QuotaWindow: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let usedPercent: Double?
    let resetLabel: String
    let detail: String?

    init(
        id: String,
        title: String,
        usedPercent: Double?,
        resetLabel: String,
        detail: String? = nil
    ) {
        self.id = id
        self.title = title
        self.usedPercent = usedPercent
        self.resetLabel = resetLabel
        self.detail = detail
    }

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
    var account: CodexAuthFile
    var snapshot: CodexQuotaSnapshot?
    var isLoading: Bool = false
    var errorMessage: String?
    var lastUpdatedAt: Date?

    var id: String { account.id }
}
