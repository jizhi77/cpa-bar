import Foundation

enum CPAClientError: Error, LocalizedError, Sendable {
    case invalidConfiguration
    case invalidResponse
    case server(message: String)
    case apiCall(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "连接配置无效，请检查服务器地址和管理密钥。"
        case .invalidResponse:
            return "CPA 返回了无法识别的数据。"
        case .server(let message):
            return message
        case .apiCall(_, let message):
            return message
        }
    }
}

private struct AuthFilesEnvelope: Decodable, Sendable {
    let files: [JSONValue]?
}

private struct APICallRequest: Encodable, Sendable {
    let authIndex: String
    let method: String
    let url: String
    let header: [String: String]
    let data: String?
}

private struct APICallResponse: Decodable, Sendable {
    let statusCode: Int
    let header: JSONObject?
    let body: JSONValue?

    enum CodingKeys: String, CodingKey {
        case statusCode = "status_code"
        case header
        case body
    }
}

private struct AuthFileStatusRequest: Encodable, Sendable {
    let name: String
    let disabled: Bool
}

private struct AuthFilePriorityRequest: Encodable, Sendable {
    let name: String
    let priority: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case priority
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)

        if let priority {
            try container.encode(priority, forKey: .priority)
        } else {
            try container.encodeNil(forKey: .priority)
        }
    }
}

private struct AuthFileDeleteRequest: Encodable, Sendable {
    let names: [String]
}

struct CPAClientService: Sendable {
    let fetchCodexAuthFiles: @Sendable () async throws -> [CodexAuthFile]
    let fetchQuota: @Sendable (CodexAuthFile) async throws -> CodexQuotaSnapshot
    let setAuthFileDisabled: @Sendable (String, Bool) async throws -> Void
    let updateAuthFilePriority: @Sendable (String, Int?) async throws -> Void
    let deleteAuthFile: @Sendable (String) async throws -> Void

    init(
        fetchCodexAuthFiles: @escaping @Sendable () async throws -> [CodexAuthFile],
        fetchQuota: @escaping @Sendable (CodexAuthFile) async throws -> CodexQuotaSnapshot,
        setAuthFileDisabled: @escaping @Sendable (String, Bool) async throws -> Void,
        updateAuthFilePriority: @escaping @Sendable (String, Int?) async throws -> Void,
        deleteAuthFile: @escaping @Sendable (String) async throws -> Void
    ) {
        self.fetchCodexAuthFiles = fetchCodexAuthFiles
        self.fetchQuota = fetchQuota
        self.setAuthFileDisabled = setAuthFileDisabled
        self.updateAuthFilePriority = updateAuthFilePriority
        self.deleteAuthFile = deleteAuthFile
    }

    init(client: CPAClient) {
        self.init(
            fetchCodexAuthFiles: {
                try await client.fetchCodexAuthFiles()
            },
            fetchQuota: { authFile in
                try await client.fetchQuota(for: authFile)
            },
            setAuthFileDisabled: { name, disabled in
                try await client.setAuthFileDisabled(name: name, disabled: disabled)
            },
            updateAuthFilePriority: { name, priority in
                try await client.updateAuthFilePriority(name: name, priority: priority)
            },
            deleteAuthFile: { name in
                try await client.deleteAuthFile(name: name)
            }
        )
    }
}

struct CPAClient: Sendable {
    private static let codexUsageURL = "https://chatgpt.com/backend-api/wham/usage"
    private static let codexUserAgent = "codex_cli_rs/0.76.0 (Debian 13.0.0; x86_64) WindowsTerminal"

    let configuration: AppConfiguration
    let session: URLSession

    init(configuration: AppConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func fetchCodexAuthFiles() async throws -> [CodexAuthFile] {
        let envelope: AuthFilesEnvelope = try await requestJSON(path: "/auth-files")
        return CPAModelParser.codexAuthFiles(from: envelope.files ?? [])
    }

    func fetchQuota(for authFile: CodexAuthFile) async throws -> CodexQuotaSnapshot {
        guard let authIndex = authFile.authIndex else {
            throw CPAClientError.server(message: "认证文件 \(authFile.name) 缺少 auth_index。")
        }

        var headers = [
            "Authorization": "Bearer $TOKEN$",
            "Content-Type": "application/json",
            "User-Agent": Self.codexUserAgent,
        ]

        if let accountID = authFile.accountID {
            headers["Chatgpt-Account-Id"] = accountID
        }

        let request = APICallRequest(
            authIndex: authIndex,
            method: "GET",
            url: Self.codexUsageURL,
            header: headers,
            data: nil
        )

        let response = try await performAPICall(request)

        guard (200..<300).contains(response.statusCode) else {
            throw CPAClientError.apiCall(
                statusCode: response.statusCode,
                message: apiCallErrorMessage(from: response)
            )
        }

        let bodyObject = try normalizedJSONObject(from: response.body)
        return CPAModelParser.codexQuotaSnapshot(from: bodyObject, fallbackAuthFile: authFile)
    }

    func setAuthFileDisabled(name: String, disabled: Bool) async throws {
        let body = try JSONEncoder().encode(
            AuthFileStatusRequest(name: name, disabled: disabled)
        )
        try await requestVoid(path: "/auth-files/status", method: "PATCH", body: body)
    }

    func updateAuthFilePriority(name: String, priority: Int?) async throws {
        let body = try JSONEncoder().encode(
            AuthFilePriorityRequest(name: name, priority: priority)
        )
        try await requestVoid(path: "/auth-files/fields", method: "PATCH", body: body)
    }

    func deleteAuthFile(name: String) async throws {
        let body = try JSONEncoder().encode(
            AuthFileDeleteRequest(names: [name])
        )
        try await requestVoid(path: "/auth-files", method: "DELETE", body: body)
    }

    private func requestJSON<T: Decodable>(path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        let (data, response) = try await performRequest(path: path, method: method, body: body)
        guard (200..<300).contains(response.statusCode) else {
            throw decodeServerError(from: data, fallbackStatusCode: response.statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw CPAClientError.invalidResponse
        }
    }

    private func requestVoid(path: String, method: String, body: Data?) async throws {
        let (data, response) = try await performRequest(path: path, method: method, body: body)
        guard (200..<300).contains(response.statusCode) else {
            throw decodeServerError(from: data, fallbackStatusCode: response.statusCode)
        }
    }

    private func performAPICall(_ request: APICallRequest) async throws -> APICallResponse {
        let body = try JSONEncoder().encode(request)
        return try await requestJSON(path: "/api-call", method: "POST", body: body)
    }

    private func performRequest(path: String, method: String, body: Data?) async throws -> (Data, HTTPURLResponse) {
        guard configuration.isComplete,
              let url = URL(string: configuration.managementAPIBaseURL + path) else {
            throw CPAClientError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.managementKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CPAClientError.invalidResponse
        }

        return (data, httpResponse)
    }

    private func decodeServerError(from data: Data, fallbackStatusCode: Int) -> CPAClientError {
        let message = (try? JSONDecoder().decode(JSONValue.self, from: data))
            .flatMap(serverMessage(from:))
            ?? String(data: data, encoding: .utf8)?.trimmedNonEmpty
            ?? "请求失败（\(fallbackStatusCode)）"

        return .server(message: message)
    }

    private func serverMessage(from value: JSONValue) -> String? {
        if let object = value.objectValue {
            if let error = object.string("error") {
                return error
            }

            if let message = object.string("message") {
                return message
            }
        }

        return value.stringValue?.trimmedNonEmpty
    }

    private func normalizedJSONObject(from value: JSONValue?) throws -> JSONObject {
        if let object = value?.objectValue {
            return object
        }

        if let stringValue = value?.stringValue?.trimmedNonEmpty,
           let parsedValue = JSONValue.parse(from: stringValue),
           let object = parsedValue.objectValue {
            return object
        }

        throw CPAClientError.invalidResponse
    }

    private func apiCallErrorMessage(from response: APICallResponse) -> String {
        if let body = response.body?.objectValue {
            if let errorObject = body.object("error"),
               let message = errorObject.string("message") {
                return "\(response.statusCode) \(message)"
            }

            if let error = body.string("error") {
                return "\(response.statusCode) \(error)"
            }

            if let message = body.string("message") {
                return "\(response.statusCode) \(message)"
            }
        }

        if let rawText = response.body?.stringValue?.trimmedNonEmpty {
            return "\(response.statusCode) \(rawText)"
        }

        return "请求失败（\(response.statusCode)）"
    }
}
