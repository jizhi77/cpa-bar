import Foundation
import XCTest

@testable import CPAQuotaBar

final class CPAQuotaBarTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        MockURLProtocol.recordedRequests = []
        super.tearDown()
    }

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
            priority: nil,
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

    func testCodexAuthFilesParsesSafeIntegerPriorityValues() {
        let files = CPAModelParser.codexAuthFiles(from: [
            .object([
                "name": .string("codex-a.json"),
                "provider": .string("codex"),
                "priority": .number(10),
            ]),
            .object([
                "name": .string("codex-b.json"),
                "provider": .string("codex"),
                "priority": .string(" -2 "),
            ]),
            .object([
                "name": .string("codex-c.json"),
                "provider": .string("codex"),
                "priority": .number(1.5),
            ]),
            .object([
                "name": .string("codex-d.json"),
                "provider": .string("codex"),
                "priority": .string("not-an-integer"),
            ]),
            .object([
                "name": .string("codex-e.json"),
                "provider": .string("codex"),
            ]),
        ])

        XCTAssertEqual(files.map(\.name), [
            "codex-a.json",
            "codex-b.json",
            "codex-c.json",
            "codex-d.json",
            "codex-e.json",
        ])
        XCTAssertEqual(files.map(\.priority), [10, -2, nil, nil, nil])
    }

    func testCodexAuthFileManagementDisplayTextShowsStatusAndPriority() {
        let activeAccount = makeAuthFile(name: "codex-a.json", disabled: false, priority: 12)
        let disabledAccount = makeAuthFile(name: "codex-b.json", disabled: true, priority: nil)

        XCTAssertEqual(activeAccount.managementStatusText, "启用")
        XCTAssertEqual(activeAccount.priorityDisplayText, "12")
        XCTAssertEqual(disabledAccount.managementStatusText, "已停用")
        XCTAssertEqual(disabledAccount.priorityDisplayText, "未设置")
    }

    func testCPAClientPatchesAuthFileStatusAndPriority() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.recordedRequests.append(
                RecordedRequest(
                    method: request.httpMethod,
                    path: request.url?.path,
                    authorization: request.value(forHTTPHeaderField: "Authorization"),
                    body: requestBodyText(from: request)
                )
            )

            return (
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 204,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data()
            )
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = CPAClient(
            configuration: AppConfiguration(
                serverURL: "http://cpa.test",
                managementKey: "management-secret"
            ),
            session: session
        )

        try await client.setAuthFileDisabled(name: "codex-a.json", disabled: true)
        try await client.updateAuthFilePriority(name: "codex-a.json", priority: 42)

        XCTAssertEqual(MockURLProtocol.recordedRequests.count, 2)
        XCTAssertEqual(MockURLProtocol.recordedRequests[0].method, "PATCH")
        XCTAssertEqual(MockURLProtocol.recordedRequests[0].path, "/v0/management/auth-files/status")
        XCTAssertEqual(MockURLProtocol.recordedRequests[0].authorization, "Bearer management-secret")
        XCTAssertEqual(MockURLProtocol.recordedRequests[0].jsonBody?.string("name"), "codex-a.json")
        XCTAssertEqual(MockURLProtocol.recordedRequests[0].jsonBody?.boolish("disabled"), true)

        XCTAssertEqual(MockURLProtocol.recordedRequests[1].method, "PATCH")
        XCTAssertEqual(MockURLProtocol.recordedRequests[1].path, "/v0/management/auth-files/fields")
        XCTAssertEqual(MockURLProtocol.recordedRequests[1].authorization, "Bearer management-secret")
        XCTAssertEqual(MockURLProtocol.recordedRequests[1].jsonBody?.string("name"), "codex-a.json")
        XCTAssertEqual(MockURLProtocol.recordedRequests[1].jsonBody?.double("priority"), 42)
    }

    func testCPAClientDeletesAuthFileByName() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.recordedRequests.append(
                RecordedRequest(
                    method: request.httpMethod,
                    path: request.url?.path,
                    authorization: request.value(forHTTPHeaderField: "Authorization"),
                    body: requestBodyText(from: request)
                )
            )

            return (
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 204,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data()
            )
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = CPAClient(
            configuration: AppConfiguration(
                serverURL: "http://cpa.test",
                managementKey: "management-secret"
            ),
            session: session
        )

        try await client.deleteAuthFile(name: "codex-a.json")

        XCTAssertEqual(MockURLProtocol.recordedRequests.count, 1)
        XCTAssertEqual(MockURLProtocol.recordedRequests[0].method, "DELETE")
        XCTAssertEqual(MockURLProtocol.recordedRequests[0].path, "/v0/management/auth-files")
        XCTAssertEqual(MockURLProtocol.recordedRequests[0].authorization, "Bearer management-secret")
        XCTAssertEqual(MockURLProtocol.recordedRequests[0].jsonBody?.array("names")?.map(\.stringValue), [
            "codex-a.json",
        ])
    }

    @MainActor
    func testViewModelSortsByPriorityByDefaultAndStagesPriorityChangesUntilSaveAll() async throws {
        let recorder = CPAClientServiceRecorder()
        let authFiles = [
            makeAuthFile(name: "codex-middle.json", priority: nil),
            makeAuthFile(name: "codex-alpha.json", priority: nil),
            makeAuthFile(name: "codex-low.json", priority: -1),
            makeAuthFile(name: "codex-high.json", priority: 10),
        ]
        let viewModel = makeViewModel(authFiles: authFiles, recorder: recorder)

        await viewModel.refreshAll()

        XCTAssertEqual(viewModel.accounts.map { $0.account.name }, [
            "codex-high.json",
            "codex-alpha.json",
            "codex-middle.json",
            "codex-low.json",
        ])

        viewModel.toggleManagementMode()
        viewModel.requestPriorityEditing(id: "codex-low.json")
        viewModel.setPriorityDraft("12", for: "codex-low.json")
        await viewModel.savePriority(id: "codex-low.json")

        XCTAssertTrue(viewModel.hasUnsavedManagementChanges)
        XCTAssertTrue(viewModel.isManagementModeEnabled)
        let stagedPriorityRequests = await recorder.priorityRequests()
        XCTAssertEqual(stagedPriorityRequests, [])
        XCTAssertEqual(viewModel.accounts.map { $0.account.name }, [
            "codex-low.json",
            "codex-high.json",
            "codex-alpha.json",
            "codex-middle.json",
        ])

        await viewModel.saveManagementChanges()

        let priorityRequests = await recorder.priorityRequests()
        XCTAssertEqual(priorityRequests, [
            PriorityRequest(name: "codex-low.json", priority: 12),
        ])
        XCTAssertEqual(viewModel.accounts.map { $0.account.name }, [
            "codex-low.json",
            "codex-high.json",
            "codex-alpha.json",
            "codex-middle.json",
        ])
        XCTAssertNil(viewModel.priorityEditingAccountID)
        XCTAssertFalse(viewModel.isManagementModeEnabled)
        XCTAssertFalse(viewModel.hasUnsavedManagementChanges)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testViewModelKeepsManagementModeOffUntilToggled() {
        let recorder = CPAClientServiceRecorder()
        let viewModel = makeViewModel(authFiles: [], recorder: recorder)

        XCTAssertFalse(viewModel.isManagementModeEnabled)

        viewModel.toggleManagementMode()

        XCTAssertTrue(viewModel.isManagementModeEnabled)
    }

    @MainActor
    func testViewModelStagesDisabledChangesAndKeepsDraftOnSaveFailure() async {
        let recorder = CPAClientServiceRecorder()
        let viewModel = makeViewModel(
            authFiles: [makeAuthFile(name: "codex-a.json", disabled: false)],
            recorder: recorder,
            failStatusUpdates: true
        )

        await viewModel.refreshAll()
        viewModel.toggleManagementMode()
        await viewModel.setAuthFileDisabled(id: "codex-a.json", disabled: true)

        let stagedStatusRequests = await recorder.statusRequests()
        XCTAssertEqual(stagedStatusRequests, [])
        XCTAssertEqual(viewModel.accounts.first?.account.disabled, true)
        XCTAssertTrue(viewModel.hasUnsavedManagementChanges)

        await viewModel.saveManagementChanges()

        let statusRequests = await recorder.statusRequests()
        XCTAssertEqual(statusRequests, [
            StatusRequest(name: "codex-a.json", disabled: true),
        ])
        XCTAssertEqual(viewModel.accounts.first?.account.disabled, true)
        XCTAssertTrue(viewModel.isManagementModeEnabled)
        XCTAssertTrue(viewModel.hasUnsavedManagementChanges)
        XCTAssertEqual(viewModel.errorMessage, "request failed")
    }

    @MainActor
    func testViewModelDiscardsUnsavedManagementChangesWhenExiting() async {
        let recorder = CPAClientServiceRecorder()
        let viewModel = makeViewModel(
            authFiles: [makeAuthFile(name: "codex-a.json", disabled: false, priority: 1)],
            recorder: recorder
        )

        await viewModel.refreshAll()
        viewModel.toggleManagementMode()
        await viewModel.setAuthFileDisabled(id: "codex-a.json", disabled: true)
        viewModel.requestPriorityEditing(id: "codex-a.json")
        viewModel.setPriorityDraft("9", for: "codex-a.json")
        await viewModel.savePriority(id: "codex-a.json")

        XCTAssertTrue(viewModel.hasUnsavedManagementChanges)

        viewModel.exitManagementModeDiscardingChanges()

        XCTAssertFalse(viewModel.isManagementModeEnabled)
        XCTAssertFalse(viewModel.hasUnsavedManagementChanges)
        XCTAssertEqual(viewModel.accounts.first?.account.disabled, false)
        XCTAssertEqual(viewModel.accounts.first?.account.priority, 1)
        let statusRequests = await recorder.statusRequests()
        let priorityRequests = await recorder.priorityRequests()
        XCTAssertEqual(statusRequests, [])
        XCTAssertEqual(priorityRequests, [])
    }

    @MainActor
    func testViewModelSavesStatusAndPriorityDraftsTogether() async {
        let recorder = CPAClientServiceRecorder()
        let viewModel = makeViewModel(
            authFiles: [makeAuthFile(name: "codex-a.json", disabled: false, priority: 1)],
            recorder: recorder
        )

        await viewModel.refreshAll()
        viewModel.toggleManagementMode()
        await viewModel.setAuthFileDisabled(id: "codex-a.json", disabled: true)
        viewModel.requestPriorityEditing(id: "codex-a.json")
        viewModel.setPriorityDraft("9", for: "codex-a.json")

        await viewModel.saveManagementChanges()

        let statusRequests = await recorder.statusRequests()
        let priorityRequests = await recorder.priorityRequests()
        XCTAssertEqual(statusRequests, [
            StatusRequest(name: "codex-a.json", disabled: true),
        ])
        XCTAssertEqual(priorityRequests, [
            PriorityRequest(name: "codex-a.json", priority: 9),
        ])
        XCTAssertFalse(viewModel.isManagementModeEnabled)
        XCTAssertFalse(viewModel.hasUnsavedManagementChanges)
        XCTAssertEqual(viewModel.accounts.first?.account.disabled, true)
        XCTAssertEqual(viewModel.accounts.first?.account.priority, 9)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testViewModelTreatsActivePriorityEditAsUnsavedChange() async {
        let recorder = CPAClientServiceRecorder()
        let viewModel = makeViewModel(
            authFiles: [makeAuthFile(name: "codex-a.json", priority: 1)],
            recorder: recorder
        )

        await viewModel.refreshAll()
        viewModel.toggleManagementMode()
        viewModel.requestPriorityEditing(id: "codex-a.json")
        viewModel.setPriorityDraft("8", for: "codex-a.json")

        XCTAssertTrue(viewModel.hasUnsavedManagementChanges)

        await viewModel.saveManagementChanges()

        let priorityRequests = await recorder.priorityRequests()
        XCTAssertEqual(priorityRequests, [
            PriorityRequest(name: "codex-a.json", priority: 8),
        ])
        XCTAssertFalse(viewModel.isManagementModeEnabled)
        XCTAssertEqual(viewModel.accounts.first?.account.priority, 8)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testViewModelDeletesAuthFileAfterServerSuccess() async {
        let recorder = CPAClientServiceRecorder()
        let viewModel = makeViewModel(
            authFiles: [
                makeAuthFile(name: "codex-a.json", priority: 10),
                makeAuthFile(name: "codex-b.json", priority: 1),
            ],
            recorder: recorder
        )

        await viewModel.refreshAll()
        await viewModel.deleteAuthFile(id: "codex-a.json")

        let deleteRequests = await recorder.deleteRequests()
        XCTAssertEqual(deleteRequests, ["codex-a.json"])
        XCTAssertEqual(viewModel.accounts.map { $0.account.name }, ["codex-b.json"])
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testViewModelTracksInlineDeleteConfirmationState() async {
        let recorder = CPAClientServiceRecorder()
        let viewModel = makeViewModel(
            authFiles: [makeAuthFile(name: "codex-a.json")],
            recorder: recorder
        )

        await viewModel.refreshAll()

        XCTAssertNil(viewModel.deleteConfirmationAccountID)

        viewModel.requestDeleteConfirmation(id: "codex-a.json")

        XCTAssertEqual(viewModel.deleteConfirmationAccountID, "codex-a.json")

        viewModel.cancelDeleteConfirmation()

        XCTAssertNil(viewModel.deleteConfirmationAccountID)
    }

    @MainActor
    func testViewModelTracksPriorityEditingState() async {
        let recorder = CPAClientServiceRecorder()
        let viewModel = makeViewModel(
            authFiles: [makeAuthFile(name: "codex-a.json", priority: 3)],
            recorder: recorder
        )

        await viewModel.refreshAll()

        XCTAssertNil(viewModel.priorityEditingAccountID)
        XCTAssertFalse(viewModel.isPriorityEditing(id: "codex-a.json"))

        viewModel.requestPriorityEditing(id: "codex-a.json")

        XCTAssertEqual(viewModel.priorityEditingAccountID, "codex-a.json")
        XCTAssertTrue(viewModel.isPriorityEditing(id: "codex-a.json"))

        viewModel.cancelPriorityEditing()

        XCTAssertNil(viewModel.priorityEditingAccountID)
        XCTAssertEqual(viewModel.priorityDraft(for: "codex-a.json"), "3")
    }

    private func makeAuthFile(
        name: String,
        disabled: Bool = false,
        priority: Int? = nil
    ) -> CodexAuthFile {
        CodexAuthFile(
            name: name,
            provider: "codex",
            authIndex: "1",
            disabled: disabled,
            runtimeOnly: false,
            priority: priority,
            note: nil,
            path: "/tmp/\(name)",
            accountID: nil,
            planFallback: nil,
            subscriptionActiveUntil: nil,
            raw: [:]
        )
    }

    @MainActor
    private func makeViewModel(
        authFiles: [CodexAuthFile],
        recorder: CPAClientServiceRecorder,
        failStatusUpdates: Bool = false
    ) -> MenuBarViewModel {
        let suiteName = "CPAQuotaBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let configurationStore = AppConfigurationStore(
            defaults: defaults,
            keychain: KeychainStore(
                service: "com.cpa-bar.CPAQuotaBarTests",
                account: suiteName
            )
        )
        let viewModel = MenuBarViewModel(
            configurationStore: configurationStore,
            clientFactory: { _ in
                CPAClientService(
                    fetchCodexAuthFiles: {
                        authFiles
                    },
                    fetchQuota: { _ in
                        CodexQuotaSnapshot(
                            planType: nil,
                            subscriptionActiveUntil: nil,
                            rateLimitResetCreditsAvailableCount: nil,
                            windows: []
                        )
                    },
                    setAuthFileDisabled: { name, disabled in
                        await recorder.recordStatus(name: name, disabled: disabled)
                        if failStatusUpdates {
                            throw TestError.requestFailed
                        }
                    },
                    updateAuthFilePriority: { name, priority in
                        await recorder.recordPriority(name: name, priority: priority)
                    },
                    deleteAuthFile: { name in
                        await recorder.recordDelete(name: name)
                    }
                )
            }
        )
        viewModel.serverURL = "http://cpa.test"
        viewModel.managementKey = "management-secret"
        return viewModel
    }
}

private struct RecordedRequest {
    let method: String?
    let path: String?
    let authorization: String?
    let body: String?

    var jsonBody: JSONObject? {
        body.flatMap(JSONValue.parse(from:))?.objectValue
    }
}

private struct StatusRequest: Equatable, Sendable {
    let name: String
    let disabled: Bool
}

private struct PriorityRequest: Equatable, Sendable {
    let name: String
    let priority: Int?
}

private enum TestError: LocalizedError {
    case requestFailed

    var errorDescription: String? {
        "request failed"
    }
}

private actor CPAClientServiceRecorder {
    private var recordedStatusRequests: [StatusRequest] = []
    private var recordedPriorityRequests: [PriorityRequest] = []
    private var recordedDeleteRequests: [String] = []

    func recordStatus(name: String, disabled: Bool) {
        recordedStatusRequests.append(StatusRequest(name: name, disabled: disabled))
    }

    func recordPriority(name: String, priority: Int?) {
        recordedPriorityRequests.append(PriorityRequest(name: name, priority: priority))
    }

    func recordDelete(name: String) {
        recordedDeleteRequests.append(name)
    }

    func statusRequests() -> [StatusRequest] {
        recordedStatusRequests
    }

    func priorityRequests() -> [PriorityRequest] {
        recordedPriorityRequests
    }

    func deleteRequests() -> [String] {
        recordedDeleteRequests
    }
}

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var recordedRequests: [RecordedRequest] = []

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: TestError.requestFailed)
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func requestBodyText(from request: URLRequest) -> String? {
    if let body = request.httpBody {
        return String(data: body, encoding: .utf8)
    }

    guard let stream = request.httpBodyStream else {
        return nil
    }

    stream.open()
    defer {
        stream.close()
    }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count > 0 {
            data.append(buffer, count: count)
        } else {
            break
        }
    }

    return String(data: data, encoding: .utf8)
}
