import AppKit
import Foundation

final class AppConfigurationStore {
    private let defaults = UserDefaults.standard
    private let keychain = KeychainStore(
        service: "com.cpa-bar.CPAQuotaBar",
        account: "managementKey"
    )
    private let serverURLKey = "CPAQuotaBar.serverURL"
    private let displayModeKey = "CPAQuotaBar.displayMode"

    func load() -> AppConfiguration {
        var configuration = AppConfiguration()
        if let storedServerURL = defaults.string(forKey: serverURLKey)?.trimmedNonEmpty {
            configuration.serverURL = storedServerURL
        }

        configuration.managementKey = keychain.load() ?? ""
        return configuration
    }

    func save(_ configuration: AppConfiguration) throws {
        defaults.set(configuration.normalizedServerURL, forKey: serverURLKey)

        if let managementKey = configuration.managementKey.trimmedNonEmpty {
            try keychain.save(managementKey)
        } else {
            try keychain.delete()
        }
    }

    func loadDisplayMode() -> QuotaDisplayMode {
        guard let rawValue = defaults.string(forKey: displayModeKey),
              let displayMode = QuotaDisplayMode(rawValue: rawValue) else {
            return .full
        }

        return displayMode
    }

    func saveDisplayMode(_ displayMode: QuotaDisplayMode) {
        defaults.set(displayMode.rawValue, forKey: displayModeKey)
    }
}

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published var serverURL: String
    @Published var managementKey: String
    @Published var isConfigurationExpanded: Bool
    @Published private(set) var displayMode: QuotaDisplayMode
    @Published private(set) var accounts: [AccountQuotaState] = []
    @Published private(set) var isRefreshingAll = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdatedAt: Date?

    private let configurationStore: AppConfigurationStore

    init(configurationStore: AppConfigurationStore = AppConfigurationStore()) {
        self.configurationStore = configurationStore
        let configuration = configurationStore.load()
        serverURL = configuration.serverURL
        managementKey = configuration.managementKey
        isConfigurationExpanded = configuration.isComplete == false
        displayMode = configurationStore.loadDisplayMode()
    }

    var currentConfiguration: AppConfiguration {
        AppConfiguration(
            serverURL: serverURL,
            managementKey: managementKey
        )
    }

    var accountCount: Int {
        accounts.count
    }

    var hasConfiguration: Bool {
        currentConfiguration.isComplete
    }

    var serverDisplayText: String {
        currentConfiguration.normalizedServerURL.isEmpty
            ? "未配置连接地址"
            : currentConfiguration.normalizedServerURL
    }

    func refreshOnMenuOpen() async {
        if currentConfiguration.isComplete {
            await refreshAll()
        }
    }

    func setDisplayMode(_ displayMode: QuotaDisplayMode) {
        guard self.displayMode != displayMode else {
            return
        }

        self.displayMode = displayMode
        configurationStore.saveDisplayMode(displayMode)
    }

    func saveConfigurationAndRefresh() async {
        let configuration = currentConfiguration
        guard configuration.normalizedServerURL.isEmpty == false else {
            errorMessage = "请输入有效的 CPA 地址。"
            isConfigurationExpanded = true
            return
        }

        guard configuration.managementKey.trimmedNonEmpty != nil else {
            errorMessage = "请输入管理密钥。"
            isConfigurationExpanded = true
            return
        }

        do {
            try configurationStore.save(configuration)
            errorMessage = nil
            isConfigurationExpanded = false
            await refreshAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshAll() async {
        guard hasConfiguration else {
            errorMessage = "请先配置连接地址和管理密钥。"
            isConfigurationExpanded = true
            return
        }

        guard isRefreshingAll == false else {
            return
        }

        isRefreshingAll = true
        errorMessage = nil

        let client = CPAClient(configuration: currentConfiguration)
        let existingStates = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })

        do {
            let authFiles = try await client.fetchCodexAuthFiles()
            accounts = authFiles.map { authFile in
                let existingState = existingStates[authFile.id]
                return AccountQuotaState(
                    account: authFile,
                    snapshot: existingState?.snapshot,
                    isLoading: true,
                    errorMessage: nil,
                    lastUpdatedAt: existingState?.lastUpdatedAt
                )
            }

            let results = await withTaskGroup(of: (String, Result<CodexQuotaSnapshot, Error>).self) { group in
                for authFile in authFiles {
                    group.addTask {
                        do {
                            return (authFile.id, .success(try await client.fetchQuota(for: authFile)))
                        } catch {
                            return (authFile.id, .failure(error))
                        }
                    }
                }

                var collected: [(String, Result<CodexQuotaSnapshot, Error>)] = []
                for await item in group {
                    collected.append(item)
                }

                return collected
            }

            for (id, result) in results {
                applyQuotaResult(result, to: id)
            }

            lastUpdatedAt = Date()
        } catch {
            errorMessage = error.localizedDescription
        }

        isRefreshingAll = false
    }

    func refreshAccount(id: String) async {
        guard hasConfiguration,
              let index = accounts.firstIndex(where: { $0.id == id }) else {
            return
        }

        accounts[index].isLoading = true
        accounts[index].errorMessage = nil

        let authFile = accounts[index].account
        let client = CPAClient(configuration: currentConfiguration)

        do {
            let snapshot = try await client.fetchQuota(for: authFile)
            accounts[index].snapshot = snapshot
            accounts[index].errorMessage = nil
            accounts[index].lastUpdatedAt = Date()
            lastUpdatedAt = Date()
        } catch {
            accounts[index].errorMessage = error.localizedDescription
        }

        accounts[index].isLoading = false
    }

    func openQuotaPage() {
        guard let url = currentConfiguration.quotaPageURL else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func quitApplication() {
        NSApplication.shared.terminate(nil)
    }

    private func applyQuotaResult(_ result: Result<CodexQuotaSnapshot, Error>, to accountID: String) {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else {
            return
        }

        switch result {
        case .success(let snapshot):
            accounts[index].snapshot = snapshot
            accounts[index].errorMessage = nil
            accounts[index].lastUpdatedAt = Date()
        case .failure(let error):
            accounts[index].errorMessage = error.localizedDescription
        }

        accounts[index].isLoading = false
    }
}
