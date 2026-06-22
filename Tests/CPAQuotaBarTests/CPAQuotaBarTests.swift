import Foundation
import XCTest

@testable import CPAQuotaBar

final class CPAQuotaBarTests: XCTestCase {
    func testExtractsChatGPTAccountIDFromJWTLikeToken() throws {
        let payload: JSONObject = [
            "chatgpt_account_id": .string("acct_123"),
        ]
        let payloadData = try JSONSerialization.data(
            withJSONObject: JSONValue.object(payload).serializableObject,
            options: [.sortedKeys]
        )
        let base64Payload = payloadData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let authFile = JSONValue.object([
            "name": .string("codex-a.json"),
            "provider": .string("codex"),
            "auth_index": .string("12"),
            "id_token": .string("header.\(base64Payload).signature"),
        ])

        let files = CPAModelParser.codexAuthFiles(from: [authFile])
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.accountID, "acct_123")
    }

    func testCodexQuotaSnapshotBuildsFiveHourAndWeeklyWindows() {
        let response: JSONObject = [
            "plan_type": .string("pro"),
            "rate_limit_reset_credits": .object([
                "available_count": .number(2),
            ]),
            "rate_limit": .object([
                "primary_window": .object([
                    "limit_window_seconds": .number(18_000),
                    "used_percent": .number(42),
                    "reset_after_seconds": .number(1_800),
                ]),
                "secondary_window": .object([
                    "limit_window_seconds": .number(604_800),
                    "used_percent": .number(12),
                    "reset_after_seconds": .number(3_600),
                ]),
            ]),
        ]

        let authFile = CodexAuthFile(
            name: "codex-a.json",
            provider: "codex",
            authIndex: "1",
            disabled: false,
            runtimeOnly: false,
            note: "A",
            path: "/tmp/codex-a.json",
            accountID: "acct_a",
            planFallback: "plus",
            subscriptionActiveUntil: nil,
            raw: [:]
        )

        let snapshot = CPAModelParser.codexQuotaSnapshot(from: response, fallbackAuthFile: authFile)
        XCTAssertEqual(snapshot.planType, "pro")
        XCTAssertEqual(snapshot.rateLimitResetCreditsAvailableCount, 2)
        XCTAssertEqual(snapshot.windows.map(\.id), ["five-hour", "weekly"])
        XCTAssertEqual(snapshot.windows.first?.usedPercent, 42)
        XCTAssertNotEqual(snapshot.windows.first?.resetLabel, "-")
    }

    func testMergePrefersPhysicalFileRecordAndFillsMissingFields() {
        let runtimeRecord = JSONValue.object([
            "name": .string("codex-a.json"),
            "provider": .string("codex"),
            "auth_index": .string("7"),
            "id_token": .object([
                "chatgpt_account_id": .string("acct_merge"),
            ]),
            "runtime_only": .bool(true),
        ])

        let fileRecord = JSONValue.object([
            "name": .string("codex-a.json"),
            "provider": .string("codex"),
            "source": .string("file"),
            "path": .string("/tmp/codex-a.json"),
            "note": .string("主账号"),
        ])

        let files = CPAModelParser.codexAuthFiles(from: [runtimeRecord, fileRecord])
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].note, "主账号")
        XCTAssertEqual(files[0].authIndex, "7")
        XCTAssertEqual(files[0].accountID, "acct_merge")
        XCTAssertFalse(files[0].runtimeOnly)
    }
}
