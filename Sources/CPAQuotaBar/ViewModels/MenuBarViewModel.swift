import AppKit
import Foundation

final class AppConfigurationStore {
    private let defaults: UserDefaults
    private let keychain: KeychainStore
    private let serverURLKey = "CPAQuotaBar.serverURL"
    private let displayModeKey = "CPAQuotaBar.displayMode"

    init(
        defaults: UserDefaults = .standard,
        keychain: KeychainStore = KeychainStore(
            service: "com.cpa-bar.CPAQuotaBar",
            account: "managementKey"
        )
    ) {
        self.defaults = defaults
        self.keychain = keychain
    }

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
    @Published private(set) var isManagementModeEnabled = false
    @Published private(set) var accounts: [AccountQuotaState] = []
    @Published private(set) var statusUpdatingAccountIDs: Set<String> = []
    @Published private(set) var prioritySavingAccountIDs: Set<String> = []
    @Published private(set) var deletingAccountIDs: Set<String> = []
    @Published private(set) var isSavingManagementChanges = false
    @Published private(set) var deleteConfirmationAccountID: String?
    @Published private(set) var priorityEditingAccountID: String?
    @Published private(set) var priorityDrafts: [String: String] = [:]
    @Published private(set) var isRefreshingAll = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdatedAt: Date?

    private let configurationStore: AppConfigurationStore
    private let clientFactory: @Sendable (AppConfiguration) -> CPAClientService
    private var managementOriginalDisabled: [String: Bool] = [:]
    private var managementOriginalPriority: [String: Int?] = [:]

    init(
        configurationStore: AppConfigurationStore = AppConfigurationStore(),
        clientFactory: @escaping @Sendable (AppConfiguration) -> CPAClientService = {
            CPAClientService(client: CPAClient(configuration: $0))
        }
    ) {
        self.configurationStore = configurationStore
        self.clientFactory = clientFactory
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

    var hasUnsavedManagementChanges: Bool {
        isManagementModeEnabled
            && (statusChangeIDs.isEmpty == false || priorityChangeIDs.isEmpty == false)
    }

    var managementChangeSummaryText: String {
        let changeCount = statusChangeIDs.count + priorityChangeIDs.count
        guard changeCount > 0 else {
            return "无未保存修改"
        }

        return "\(changeCount) 项未保存"
    }

    var isManagementOperationInProgress: Bool {
        isSavingManagementChanges || deletingAccountIDs.isEmpty == false
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

    func toggleManagementMode() {
        if isManagementModeEnabled {
            exitManagementModeDiscardingChanges()
        } else {
            enterManagementMode()
        }
    }

    func enterManagementMode() {
        guard hasConfiguration else {
            return
        }

        captureManagementOriginals()
        syncPriorityDraftsWithAccounts()
        deleteConfirmationAccountID = nil
        priorityEditingAccountID = nil
        errorMessage = nil
        isManagementModeEnabled = true
    }

    func exitManagementModeDiscardingChanges() {
        guard isManagementModeEnabled else {
            return
        }

        restoreManagementOriginals()
        finishManagementMode()
    }

    func priorityDraft(for id: String) -> String {
        priorityDrafts[id]
            ?? accounts.first(where: { $0.id == id })
                .map { priorityText(from: $0.account.priority) }
            ?? ""
    }

    func setPriorityDraft(_ value: String, for id: String) {
        priorityDrafts[id] = value
    }

    func isStatusUpdating(id: String) -> Bool {
        statusUpdatingAccountIDs.contains(id)
    }

    func isPrioritySaving(id: String) -> Bool {
        prioritySavingAccountIDs.contains(id)
    }

    func isPriorityEditing(id: String) -> Bool {
        priorityEditingAccountID == id
    }

    func isDeleting(id: String) -> Bool {
        deletingAccountIDs.contains(id)
    }

    func requestPriorityEditing(id: String) {
        guard let account = accounts.first(where: { $0.id == id })?.account else {
            return
        }

        priorityDrafts[id] = priorityText(from: account.priority)
        priorityEditingAccountID = id
    }

    func cancelPriorityEditing() {
        if let id = priorityEditingAccountID,
           let account = accounts.first(where: { $0.id == id })?.account {
            priorityDrafts[id] = priorityText(from: account.priority)
        }
        priorityEditingAccountID = nil
    }

    func requestDeleteConfirmation(id: String) {
        guard accounts.contains(where: { $0.id == id }) else {
            return
        }

        deleteConfirmationAccountID = id
    }

    func cancelDeleteConfirmation() {
        deleteConfirmationAccountID = nil
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

        let client = clientFactory(currentConfiguration)
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
            sortAccounts()
            syncPriorityDraftsWithAccounts()

            let results = await withTaskGroup(of: (String, Result<CodexQuotaSnapshot, Error>).self) { group in
                for authFile in authFiles {
                    group.addTask {
                        do {
                            return (authFile.id, .success(try await client.fetchQuota(authFile)))
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
        let client = clientFactory(currentConfiguration)

        do {
            let snapshot = try await client.fetchQuota(authFile)
            accounts[index].snapshot = snapshot
            accounts[index].errorMessage = nil
            accounts[index].lastUpdatedAt = Date()
            lastUpdatedAt = Date()
        } catch {
            accounts[index].errorMessage = error.localizedDescription
        }

        accounts[index].isLoading = false
    }

    func setAuthFileDisabled(id: String, disabled: Bool) async {
        guard hasConfiguration,
              isManagementModeEnabled,
              let index = accounts.firstIndex(where: { $0.id == id }) else {
            return
        }

        let oldDisabled = accounts[index].account.disabled
        guard oldDisabled != disabled else {
            return
        }

        errorMessage = nil
        accounts[index].account.disabled = disabled
        accounts[index].account.raw["disabled"] = .bool(disabled)
    }

    func savePriority(id: String) async {
        guard hasConfiguration,
              isManagementModeEnabled else {
            return
        }

        guard applyPriorityDraftToAccount(id: id) else {
            return
        }

        errorMessage = nil
        if priorityEditingAccountID == id {
            priorityEditingAccountID = nil
        }
        sortAccounts()
    }

    func saveManagementChanges() async {
        guard hasConfiguration,
              isManagementModeEnabled,
              isSavingManagementChanges == false else {
            return
        }

        guard applyAllPriorityDraftsToAccounts() else {
            return
        }

        let statusChanges = statusChanges()
        let priorityChanges = priorityChanges()
        guard statusChanges.isEmpty == false || priorityChanges.isEmpty == false else {
            finishManagementMode()
            return
        }

        let client = clientFactory(currentConfiguration)
        isSavingManagementChanges = true
        statusUpdatingAccountIDs = Set(statusChanges.map(\.id))
        prioritySavingAccountIDs = Set(priorityChanges.map(\.id))
        errorMessage = nil

        do {
            for change in statusChanges {
                try await client.setAuthFileDisabled(change.name, change.disabled)
                managementOriginalDisabled[change.id] = change.disabled
            }

            for change in priorityChanges {
                try await client.updateAuthFilePriority(change.name, change.priority)
                managementOriginalPriority[change.id] = change.priority
            }

            isSavingManagementChanges = false
            statusUpdatingAccountIDs = []
            prioritySavingAccountIDs = []
            finishManagementMode()
        } catch {
            isSavingManagementChanges = false
            statusUpdatingAccountIDs = []
            prioritySavingAccountIDs = []
            errorMessage = error.localizedDescription
        }
    }

    func deleteAuthFile(id: String) async {
        guard hasConfiguration,
              let account = accounts.first(where: { $0.id == id })?.account else {
            return
        }

        let client = clientFactory(currentConfiguration)
        deletingAccountIDs.insert(id)
        errorMessage = nil

        do {
            try await client.deleteAuthFile(account.name)
            accounts.removeAll { $0.id == id }
            priorityDrafts.removeValue(forKey: id)
            managementOriginalDisabled.removeValue(forKey: id)
            managementOriginalPriority.removeValue(forKey: id)
            statusUpdatingAccountIDs.remove(id)
            prioritySavingAccountIDs.remove(id)
            if priorityEditingAccountID == id {
                priorityEditingAccountID = nil
            }
            if deleteConfirmationAccountID == id {
                deleteConfirmationAccountID = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        deletingAccountIDs.remove(id)
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

    private func syncPriorityDraftsWithAccounts() {
        let validIDs = Set(accounts.map(\.id))
        priorityDrafts = priorityDrafts.filter { validIDs.contains($0.key) }
        if let priorityEditingAccountID,
           validIDs.contains(priorityEditingAccountID) == false {
            self.priorityEditingAccountID = nil
        }
        for account in accounts {
            priorityDrafts[account.id] = priorityText(from: account.account.priority)
        }
    }

    private var statusChangeIDs: [String] {
        guard isManagementModeEnabled else {
            return []
        }

        return accounts.compactMap { state in
            guard let originalDisabled = managementOriginalDisabled[state.id],
                  originalDisabled != state.account.disabled else {
                return nil
            }

            return state.id
        }
    }

    private var priorityChangeIDs: [String] {
        guard isManagementModeEnabled else {
            return []
        }

        return accounts.compactMap { state in
            guard priorityDraftDiffersFromOriginal(for: state) else {
                return nil
            }

            return state.id
        }
    }

    private func statusChanges() -> [(id: String, name: String, disabled: Bool)] {
        accounts.compactMap { state in
            guard statusChangeIDs.contains(state.id) else {
                return nil
            }

            return (state.id, state.account.name, state.account.disabled)
        }
    }

    private func priorityChanges() -> [(id: String, name: String, priority: Int?)] {
        accounts.compactMap { state in
            guard priorityChangeIDs.contains(state.id) else {
                return nil
            }

            return (state.id, state.account.name, state.account.priority)
        }
    }

    private func captureManagementOriginals() {
        managementOriginalDisabled = Dictionary(
            uniqueKeysWithValues: accounts.map { ($0.id, $0.account.disabled) }
        )
        managementOriginalPriority = Dictionary(
            uniqueKeysWithValues: accounts.map { ($0.id, $0.account.priority) }
        )
    }

    private func restoreManagementOriginals() {
        for index in accounts.indices {
            let id = accounts[index].id
            if let originalDisabled = managementOriginalDisabled[id] {
                accounts[index].account.disabled = originalDisabled
                accounts[index].account.raw["disabled"] = .bool(originalDisabled)
            }

            if managementOriginalPriority.keys.contains(id) {
                let originalPriority = managementOriginalPriority[id] ?? nil
                accounts[index].account.priority = originalPriority
                accounts[index].account.raw["priority"] = originalPriority.map { .number(Double($0)) } ?? .null
            }
        }

        sortAccounts()
    }

    private func finishManagementMode() {
        isManagementModeEnabled = false
        isSavingManagementChanges = false
        statusUpdatingAccountIDs = []
        prioritySavingAccountIDs = []
        deleteConfirmationAccountID = nil
        priorityEditingAccountID = nil
        managementOriginalDisabled = [:]
        managementOriginalPriority = [:]
        syncPriorityDraftsWithAccounts()
    }

    private func applyAllPriorityDraftsToAccounts() -> Bool {
        let ids = accounts.map(\.id)
        for id in ids {
            guard applyPriorityDraftToAccount(id: id) else {
                return false
            }
        }
        priorityEditingAccountID = nil
        sortAccounts()
        return true
    }

    private func applyPriorityDraftToAccount(id: String) -> Bool {
        guard accounts.contains(where: { $0.id == id }) else {
            return false
        }

        let draft = priorityDraft(for: id).trimmingCharacters(in: .whitespacesAndNewlines)
        let newPriority: Int?
        if draft.isEmpty {
            newPriority = nil
        } else if let parsedPriority = Int(draft) {
            newPriority = parsedPriority
        } else {
            errorMessage = "优先级只能是整数。"
            return false
        }

        updateAccount(id: id) { account in
            account.priority = newPriority
            account.raw["priority"] = newPriority.map { .number(Double($0)) } ?? .null
        }
        priorityDrafts[id] = priorityText(from: newPriority)
        return true
    }

    private func priorityDraftDiffersFromOriginal(for state: AccountQuotaState) -> Bool {
        guard managementOriginalPriority.keys.contains(state.id) else {
            return false
        }

        let originalPriority = managementOriginalPriority[state.id] ?? nil
        let draft = priorityDraft(for: state.id).trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.isEmpty {
            return originalPriority != nil
        }

        guard let parsedPriority = Int(draft) else {
            return true
        }

        return originalPriority != parsedPriority
    }

    private func sortAccounts() {
        accounts.sort { lhs, rhs in
            accountSort(lhs, rhs)
        }
    }

    private func accountSort(_ lhs: AccountQuotaState, _ rhs: AccountQuotaState) -> Bool {
        let lhsPriority = lhs.account.priority ?? 0
        let rhsPriority = rhs.account.priority ?? 0
        if lhsPriority != rhsPriority {
            return lhsPriority > rhsPriority
        }

        return displayNameSort(lhs.account, rhs.account)
    }

    private func displayNameSort(_ lhs: CodexAuthFile, _ rhs: CodexAuthFile) -> Bool {
        let result = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
        if result != .orderedSame {
            return result == .orderedAscending
        }

        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private func updateAccount(id: String, update: (inout CodexAuthFile) -> Void) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else {
            return
        }

        update(&accounts[index].account)
    }

    private func priorityText(from priority: Int?) -> String {
        priority.map(String.init) ?? ""
    }
}
