import Foundation

enum CPAModelParser {
    static func codexAuthFiles(from rawFiles: [JSONValue]) -> [CodexAuthFile] {
        let objects = rawFiles.compactMap(\.objectValue)
        let mergedFiles = mergeAuthFiles(from: objects)

        return mergedFiles.compactMap { object in
            guard isCodexProvider(object) else {
                return nil
            }

            let name = object.string("name") ?? object.string("path")
            guard let name else {
                return nil
            }

            return CodexAuthFile(
                name: name,
                provider: normalizedProvider(object.string("provider") ?? object.string("type") ?? "codex"),
                authIndex: normalizedAuthIndex(object["auth_index"] ?? object["authIndex"]),
                disabled: isDisabled(object),
                runtimeOnly: isRuntimeOnly(object),
                note: object.string("note"),
                path: object.string("path"),
                accountID: chatgptAccountID(from: object),
                planFallback: fallbackPlanType(from: object),
                subscriptionActiveUntil: subscriptionActiveUntil(from: object),
                raw: object
            )
        }
        .filter { $0.runtimeOnly == false }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    static func codexQuotaSnapshot(from response: JSONObject, fallbackAuthFile: CodexAuthFile) -> CodexQuotaSnapshot {
        let resetCreditsObject = response.object("rate_limit_reset_credits")
            ?? response.object("rateLimitResetCredits")

        let resetCredits = numericValue(
            resetCreditsObject?["available_count"] ?? resetCreditsObject?["availableCount"]
        ).map { Int($0.rounded(.towardZero)) }

        return CodexQuotaSnapshot(
            planType: response.string("plan_type")
                ?? response.string("planType")
                ?? fallbackAuthFile.planFallback,
            subscriptionActiveUntil: fallbackAuthFile.subscriptionActiveUntil,
            rateLimitResetCreditsAvailableCount: resetCredits,
            windows: codexWindows(from: response)
        )
    }

    static func chatgptAccountID(from object: JSONObject) -> String? {
        let metadata = object.object("metadata")
        let attributes = object.object("attributes")
        let candidates: [JSONValue?] = [
            object["id_token"],
            metadata?["id_token"],
            attributes?["id_token"],
        ]

        for candidate in candidates {
            guard let tokenObject = tokenObject(from: candidate),
                  let accountID = tokenObject.string("chatgpt_account_id")
                    ?? tokenObject.string("chatgptAccountId") else {
                continue
            }

            return accountID
        }

        return nil
    }

    static func mergeAuthFiles(from objects: [JSONObject]) -> [JSONObject] {
        var groups: [String: [JSONObject]] = [:]

        for object in objects {
            let name = object.string("name")
                ?? JSONValue.object(object).normalizedJSONText()
            groups[name, default: []].append(object)
        }

        return groups
            .map { (_, value) in mergeAuthFileGroup(value) }
            .sorted {
                ($0.string("name") ?? "")
                    .localizedCaseInsensitiveCompare($1.string("name") ?? "") == .orderedAscending
            }
    }

    private static func mergeAuthFileGroup(_ objects: [JSONObject]) -> JSONObject {
        let ordered = objects.sorted(by: authFileSort)
        guard var merged = ordered.first else {
            return [:]
        }

        for object in ordered.dropFirst() {
            for (key, value) in object {
                if shouldBackfillAuthField(key, into: merged),
                   (merged[key]?.isMeaningful ?? false) == false,
                   value.isMeaningful {
                    merged[key] = value
                }
            }
        }

        return merged
    }

    private static func shouldBackfillAuthField(_ key: String, into merged: JSONObject) -> Bool {
        switch key {
        case "disabled", "runtime_only", "runtimeOnly":
            return false
        default:
            return true
        }
    }

    private static func authFileSort(_ lhs: JSONObject, _ rhs: JSONObject) -> Bool {
        let scoreDifference = authFileScore(rhs) - authFileScore(lhs)
        if scoreDifference != 0 {
            return scoreDifference < 0
        }

        let timestampDifference = authFileTimestamp(rhs) - authFileTimestamp(lhs)
        if timestampDifference != 0 {
            return timestampDifference < 0
        }

        return populatedFieldCount(rhs) - populatedFieldCount(lhs) < 0
    }

    private static func authFileScore(_ object: JSONObject) -> Int {
        var score = 0

        if object.string("source")?.lowercased() == "file" {
            score += 32
        }

        if object.string("path") != nil {
            score += 16
        }

        if isRuntimeOnly(object) == false {
            score += 8
        }

        if isDisabled(object) == false {
            score += 4
        }

        if authFileTimestamp(object) > 0 {
            score += 2
        }

        return score
    }

    private static func populatedFieldCount(_ object: JSONObject) -> Int {
        object.values.reduce(0) { partial, value in
            partial + (value.isMeaningful ? 1 : 0)
        }
    }

    private static func authFileTimestamp(_ object: JSONObject) -> Int {
        let candidates: [JSONValue?] = [
            object["modtime"],
            object["updated_at"],
            object["last_refresh"],
        ]

        for candidate in candidates {
            if let timestamp = parseFlexibleDate(candidate) {
                return Int(timestamp.timeIntervalSince1970 * 1000)
            }
        }

        return 0
    }

    private static func isCodexProvider(_ object: JSONObject) -> Bool {
        normalizedProvider(object.string("provider") ?? object.string("type") ?? "") == "codex"
    }

    private static func normalizedProvider(_ rawValue: String) -> String {
        let value = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")

        if value == "x-ai" || value == "grok" {
            return "xai"
        }

        return value
    }

    private static func isRuntimeOnly(_ object: JSONObject) -> Bool {
        object.boolish("runtime_only")
            ?? object.boolish("runtimeOnly")
            ?? false
    }

    private static func isDisabled(_ object: JSONObject) -> Bool {
        object.boolish("disabled") ?? false
    }

    private static func normalizedAuthIndex(_ value: JSONValue?) -> String? {
        if let stringValue = value?.stringValue?.trimmedNonEmpty {
            return stringValue
        }

        return nil
    }

    private static func fallbackPlanType(from object: JSONObject) -> String? {
        let metadata = object.object("metadata")
        let attributes = object.object("attributes")

        let tokenCandidates: [JSONObject?] = [
            tokenObject(from: object["id_token"]),
            tokenObject(from: metadata?["id_token"]),
            tokenObject(from: attributes?["id_token"]),
        ]

        let directCandidates: [String?] = [
            object.string("plan_type"),
            object.string("planType"),
            metadata?.string("plan_type"),
            metadata?.string("planType"),
            attributes?.string("plan_type"),
            attributes?.string("planType"),
        ]

        for candidate in directCandidates {
            if let candidate {
                return candidate.lowercased()
            }
        }

        for token in tokenCandidates {
            if let planType = token?.string("plan_type") ?? token?.string("planType") {
                return planType.lowercased()
            }
        }

        return nil
    }

    private static func subscriptionActiveUntil(from object: JSONObject) -> Date? {
        let metadata = object.object("metadata")
        let attributes = object.object("attributes")

        let authObjects: [JSONObject?] = [
            openAIAuthObject(from: object["id_token"]),
            openAIAuthObject(from: metadata?["id_token"]),
            openAIAuthObject(from: attributes?["id_token"]),
        ]

        let subscriptionObjects: [JSONObject?] = [
            object.object("subscription"),
            metadata?.object("subscription"),
            attributes?.object("subscription"),
        ]

        let directCandidates: [JSONValue?] = [
            object["chatgpt_subscription_active_until"],
            object["chatgptSubscriptionActiveUntil"],
            object["subscription_active_until"],
            object["subscriptionActiveUntil"],
            metadata?["chatgpt_subscription_active_until"],
            metadata?["chatgptSubscriptionActiveUntil"],
            metadata?["subscription_active_until"],
            metadata?["subscriptionActiveUntil"],
            attributes?["chatgpt_subscription_active_until"],
            attributes?["chatgptSubscriptionActiveUntil"],
            attributes?["subscription_active_until"],
            attributes?["subscriptionActiveUntil"],
        ]

        for candidate in directCandidates {
            if let date = parseFlexibleDate(candidate) {
                return date
            }
        }

        for subscription in subscriptionObjects {
            if let date = parseFlexibleDate(subscription?["active_until"])
                ?? parseFlexibleDate(subscription?["activeUntil"]) {
                return date
            }
        }

        for authObject in authObjects {
            if let date = parseFlexibleDate(authObject?["chatgpt_subscription_active_until"])
                ?? parseFlexibleDate(authObject?["chatgptSubscriptionActiveUntil"]) {
                return date
            }
        }

        return nil
    }

    private static func openAIAuthObject(from value: JSONValue?) -> JSONObject? {
        guard let object = tokenObject(from: value) else {
            return nil
        }

        return object.object("https://api.openai.com/auth") ?? object
    }

    private static func tokenObject(from value: JSONValue?) -> JSONObject? {
        if let object = value?.objectValue {
            return object
        }

        guard let stringValue = value?.stringValue?.trimmedNonEmpty else {
            return nil
        }

        if let parsedValue = JSONValue.parse(from: stringValue),
           let object = parsedValue.objectValue {
            return object
        }

        let parts = stringValue.split(separator: ".")
        guard parts.count >= 2,
              let decoded = decodeBase64URL(String(parts[1])),
              let parsedValue = try? JSONDecoder().decode(JSONValue.self, from: decoded),
              let object = parsedValue.objectValue else {
            return nil
        }

        return object
    }

    private static func decodeBase64URL(_ value: String) -> Data? {
        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = normalized.count % 4
        if remainder > 0 {
            normalized.append(String(repeating: "=", count: 4 - remainder))
        }

        return Data(base64Encoded: normalized)
    }

    private static func parseFlexibleDate(_ value: JSONValue?) -> Date? {
        guard let value else {
            return nil
        }

        if let numericValue = numericValue(value) {
            let magnitude = abs(numericValue)
            let seconds: Double

            if magnitude < 1e11 {
                seconds = numericValue
            } else if magnitude < 1e15 {
                seconds = numericValue / 1000
            } else {
                seconds = numericValue / 1_000_000
            }

            return Date(timeIntervalSince1970: seconds)
        }

        guard let stringValue = value.stringValue?.trimmedNonEmpty else {
            return nil
        }

        if let parsed = ISO8601DateFormatter().date(from: stringValue) {
            return parsed
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = formatter.date(from: stringValue) {
            return parsed
        }

        let formatter2 = DateFormatter()
        formatter2.locale = Locale(identifier: "en_US_POSIX")
        formatter2.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
        if let parsed = formatter2.date(from: stringValue) {
            return parsed
        }

        return nil
    }

    private static func numericValue(_ value: JSONValue?) -> Double? {
        value?.doubleValue
    }

    private static func codexWindows(from response: JSONObject) -> [QuotaWindow] {
        let rateLimit = response.object("rate_limit") ?? response.object("rateLimit")
        let codeReviewRateLimit = response.object("code_review_rate_limit")
            ?? response.object("codeReviewRateLimit")
        let additionalRateLimits = response.array("additional_rate_limits")
            ?? response.array("additionalRateLimits")
            ?? []

        let limitReached = rateLimit?.boolish("limit_reached") ?? rateLimit?.boolish("limitReached")
        let allowed = rateLimit?.boolish("allowed")

        let codeReviewLimitReached = codeReviewRateLimit?.boolish("limit_reached")
            ?? codeReviewRateLimit?.boolish("limitReached")
        let codeReviewAllowed = codeReviewRateLimit?.boolish("allowed")

        var windows: [QuotaWindow] = []

        let standardRateWindows = pickRateWindows(from: rateLimit)
        appendQuotaWindow(
            to: &windows,
            id: "five-hour",
            title: "5 小时限额",
            window: standardRateWindows.fiveHourWindow,
            limitReached: limitReached,
            allowed: allowed
        )
        appendQuotaWindow(
            to: &windows,
            id: standardRateWindows.secondaryWindowIsMonthly ? "monthly" : "weekly",
            title: standardRateWindows.secondaryWindowIsMonthly ? "月度限额" : "周限额",
            window: standardRateWindows.secondaryWindow,
            limitReached: limitReached,
            allowed: allowed
        )

        let reviewRateWindows = pickRateWindows(from: codeReviewRateLimit)
        appendQuotaWindow(
            to: &windows,
            id: "code-review-five-hour",
            title: "代码审查 5 小时限额",
            window: reviewRateWindows.fiveHourWindow,
            limitReached: codeReviewLimitReached,
            allowed: codeReviewAllowed
        )
        appendQuotaWindow(
            to: &windows,
            id: reviewRateWindows.secondaryWindowIsMonthly ? "code-review-monthly" : "code-review-weekly",
            title: reviewRateWindows.secondaryWindowIsMonthly ? "代码审查月度限额" : "代码审查周限额",
            window: reviewRateWindows.secondaryWindow,
            limitReached: codeReviewLimitReached,
            allowed: codeReviewAllowed
        )

        for (index, value) in additionalRateLimits.enumerated() {
            guard let item = value.objectValue,
                  let rateLimit = item.object("rate_limit") ?? item.object("rateLimit") else {
                continue
            }

            let name = item.string("limit_name")
                ?? item.string("limitName")
                ?? item.string("metered_feature")
                ?? item.string("meteredFeature")
                ?? "additional-\(index + 1)"

            let itemLimitReached = rateLimit.boolish("limit_reached") ?? rateLimit.boolish("limitReached")
            let itemAllowed = rateLimit.boolish("allowed")

            appendQuotaWindow(
                to: &windows,
                id: "\(slugify(name, fallback: "additional-\(index + 1)"))-five-hour-\(index)",
                title: "\(name) 5 小时限额",
                window: rateLimit.object("primary_window") ?? rateLimit.object("primaryWindow"),
                limitReached: itemLimitReached,
                allowed: itemAllowed
            )

            let secondaryWindow = rateLimit.object("secondary_window") ?? rateLimit.object("secondaryWindow")
            appendQuotaWindow(
                to: &windows,
                id: "\(slugify(name, fallback: "additional-\(index + 1)"))-\(isMonthlyWindow(secondaryWindow) ? "monthly" : "weekly")-\(index)",
                title: isMonthlyWindow(secondaryWindow) ? "\(name) 月度限额" : "\(name) 周限额",
                window: secondaryWindow,
                limitReached: itemLimitReached,
                allowed: itemAllowed
            )
        }

        return windows
    }

    private static func appendQuotaWindow(
        to windows: inout [QuotaWindow],
        id: String,
        title: String,
        window: JSONObject?,
        limitReached: Bool?,
        allowed: Bool?
    ) {
        guard let window else {
            return
        }

        let resetLabel = quotaResetLabel(from: window)
        let usedPercent = numericValue(window["used_percent"])
            ?? numericValue(window["usedPercent"])
            ?? (((limitReached == true) || allowed == false) && resetLabel != "-" ? 100 : nil)

        windows.append(
            QuotaWindow(
                id: id,
                title: title,
                usedPercent: usedPercent.map { max(0, min(100, $0)) },
                resetLabel: resetLabel
            )
        )
    }

    private static func quotaResetLabel(from window: JSONObject) -> String {
        if let resetAt = parseFlexibleDate(window["reset_at"] ?? window["resetAt"]) {
            return Formatting.shortDateTime(resetAt)
        }

        if let resetAfterSeconds = numericValue(window["reset_after_seconds"] ?? window["resetAfterSeconds"]),
           resetAfterSeconds > 0 {
            return Formatting.shortDateTime(Date().addingTimeInterval(resetAfterSeconds))
        }

        return "-"
    }

    private static func limitWindowSeconds(_ window: JSONObject?) -> Int? {
        guard let value = numericValue(window?["limit_window_seconds"] ?? window?["limitWindowSeconds"]) else {
            return nil
        }

        return Int(value.rounded(.towardZero))
    }

    private static func isMonthlyWindow(_ window: JSONObject?) -> Bool {
        guard let seconds = limitWindowSeconds(window) else {
            return false
        }

        return (2_419_200...2_678_400).contains(seconds)
    }

    private static func pickRateWindows(from rateLimit: JSONObject?) -> (
        fiveHourWindow: JSONObject?,
        secondaryWindow: JSONObject?,
        secondaryWindowIsMonthly: Bool
    ) {
        let primaryWindow = rateLimit?.object("primary_window") ?? rateLimit?.object("primaryWindow")
        let secondaryWindow = rateLimit?.object("secondary_window") ?? rateLimit?.object("secondaryWindow")
        let candidates = [primaryWindow, secondaryWindow]

        var fiveHourWindow: JSONObject?
        var weeklyOrMonthlyWindow: JSONObject?

        for candidate in candidates {
            guard let candidate else {
                continue
            }

            let windowSeconds = limitWindowSeconds(candidate)
            if windowSeconds == 18_000, fiveHourWindow == nil {
                fiveHourWindow = candidate
                continue
            }

            if windowSeconds == 604_800 || isMonthlyWindow(candidate),
               weeklyOrMonthlyWindow == nil {
                weeklyOrMonthlyWindow = candidate
            }
        }

        if fiveHourWindow == nil,
           let primaryWindow,
           primaryWindow != weeklyOrMonthlyWindow {
            fiveHourWindow = primaryWindow
        }

        if weeklyOrMonthlyWindow == nil,
           let secondaryWindow,
           secondaryWindow != fiveHourWindow {
            weeklyOrMonthlyWindow = secondaryWindow
        }

        return (
            fiveHourWindow,
            weeklyOrMonthlyWindow,
            isMonthlyWindow(weeklyOrMonthlyWindow)
        )
    }

    private static func slugify(_ value: String, fallback: String) -> String {
        let slug = value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return slug.isEmpty ? fallback : slug
    }
}
