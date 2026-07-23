import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let errorMessage = viewModel.errorMessage {
                        ErrorBanner(message: errorMessage)
                    }

                    ConfigurationSection(viewModel: viewModel)

                    if viewModel.hasConfiguration {
                        accountSection
                    }
                }
                .padding(16)
            }
            .frame(width: 396, height: 620)

            Divider()
            footer
        }
        .onAppear {
            Task {
                await viewModel.refreshOnMenuOpen()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("CPA Quota")
                    .font(.headline)

                Text(viewModel.serverDisplayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button {
                viewModel.isConfigurationExpanded.toggle()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("连接设置")

            Button {
                viewModel.openQuotaPage()
            } label: {
                Image(systemName: "safari")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.hasConfiguration == false)
            .help("打开 CPA 页面")

            Button {
                Task {
                    await viewModel.refreshAll()
                }
            } label: {
                if viewModel.isRefreshingAll {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.hasConfiguration == false || viewModel.isRefreshingAll)
            .help("刷新全部")
        }
        .padding(16)
    }

    @ViewBuilder
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            accountControls

            if viewModel.filteredAccounts.isEmpty, viewModel.isRefreshingAll == false {
                EmptyStateView()
            } else {
                ForEach(viewModel.filteredAccounts) { state in
                    AccountCardView(
                        state: state,
                        displayMode: viewModel.displayMode,
                        isManagementModeEnabled: viewModel.isManagementModeEnabled,
                        priorityText: Binding(
                            get: { viewModel.priorityDraft(for: state.id) },
                            set: { viewModel.setPriorityDraft($0, for: state.id) }
                        ),
                        isStatusUpdating: viewModel.isStatusUpdating(id: state.id),
                        isPrioritySaving: viewModel.isPrioritySaving(id: state.id),
                        isDeleting: viewModel.isDeleting(id: state.id) || viewModel.isSavingManagementChanges,
                        isDeleteConfirmationVisible: viewModel.deleteConfirmationAccountID == state.id,
                        isPriorityEditing: viewModel.isPriorityEditing(id: state.id),
                        setDisabledAction: { disabled in
                            Task {
                                await viewModel.setAuthFileDisabled(id: state.id, disabled: disabled)
                            }
                        },
                        savePriorityAction: {
                            Task {
                                await viewModel.savePriority(id: state.id)
                            }
                        },
                        requestPriorityEditingAction: {
                            viewModel.requestPriorityEditing(id: state.id)
                        },
                        cancelPriorityEditingAction: {
                            viewModel.cancelPriorityEditing()
                        },
                        requestDeleteConfirmationAction: {
                            viewModel.requestDeleteConfirmation(id: state.id)
                        },
                        cancelDeleteConfirmationAction: {
                            viewModel.cancelDeleteConfirmation()
                        },
                        deleteAction: {
                            Task {
                                await viewModel.deleteAuthFile(id: state.id)
                            }
                        },
                        refreshAction: {
                            Task {
                                await viewModel.refreshAccount(id: state.id)
                            }
                        }
                    )
                }
            }
        }
    }

    private var accountControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Picker("账号筛选", selection: Binding(
                    get: { viewModel.authProviderFilter },
                    set: { viewModel.setAuthProviderFilter($0) }
                )) {
                    ForEach(AuthProviderFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)

                displayModePicker

                if viewModel.isManagementModeEnabled {
                    Label("管理中", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                        .fixedSize()
                } else {
                    Button {
                        viewModel.toggleManagementMode()
                    } label: {
                        Label("管理", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.hasConfiguration == false)
                    .help("管理认证文件")
                }
            }

            if viewModel.isManagementModeEnabled {
                HStack(spacing: 8) {
                    if viewModel.hasUnsavedManagementChanges {
                        Text(viewModel.managementChangeSummaryText)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("可编辑账号状态与优先级")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Button {
                        viewModel.exitManagementModeDiscardingChanges()
                    } label: {
                        Label("退出", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.isManagementOperationInProgress)
                    .help(viewModel.hasUnsavedManagementChanges ? "放弃未保存修改并退出" : "退出管理")

                    Button {
                        Task {
                            await viewModel.saveManagementChanges()
                        }
                    } label: {
                        if viewModel.isSavingManagementChanges {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("保存", systemImage: "tray.and.arrow.down")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(
                        viewModel.hasConfiguration == false
                            || viewModel.hasUnsavedManagementChanges == false
                            || viewModel.isManagementOperationInProgress
                    )
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.14), lineWidth: 1)
        )
    }

    private var displayModePicker: some View {
        Picker("展示模式", selection: Binding(
            get: { viewModel.displayMode },
            set: { viewModel.setDisplayMode($0) }
        )) {
            ForEach(QuotaDisplayMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .frame(width: 116)
        .help("切换展示模式")
    }

    private var footer: some View {
        HStack {
            Button("退出") {
                viewModel.quitApplication()
            }
            .buttonStyle(.borderless)

            Spacer()

            Text("直接对接 CPA 管理接口")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

}

private struct ConfigurationSection: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        if viewModel.hasConfiguration == false || viewModel.isConfigurationExpanded {
            VStack(alignment: .leading, spacing: 12) {
                Text("连接设置")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Text("CPA 地址")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("http://192.168.2.20:8317", text: Binding(
                        get: { viewModel.serverURL },
                        set: { viewModel.serverURL = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("管理密钥")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    SecureField("请输入 Management Key", text: Binding(
                        get: { viewModel.managementKey },
                        set: { viewModel.managementKey = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                Text("支持直接粘贴根地址、`management.html#/quota` 或 `/v0/management`。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button {
                        Task {
                            await viewModel.saveConfigurationAndRefresh()
                        }
                    } label: {
                        Label("保存并刷新", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)

                    if viewModel.hasConfiguration {
                        Button("收起") {
                            viewModel.isConfigurationExpanded = false
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }
}

private struct AccountCardView: View {
    let state: AccountQuotaState
    let displayMode: QuotaDisplayMode
    let isManagementModeEnabled: Bool
    @Binding var priorityText: String
    let isStatusUpdating: Bool
    let isPrioritySaving: Bool
    let isDeleting: Bool
    let isDeleteConfirmationVisible: Bool
    let isPriorityEditing: Bool
    let setDisabledAction: (Bool) -> Void
    let savePriorityAction: () -> Void
    let requestPriorityEditingAction: () -> Void
    let cancelPriorityEditingAction: () -> Void
    let requestDeleteConfirmationAction: () -> Void
    let cancelDeleteConfirmationAction: () -> Void
    let deleteAction: () -> Void
    let refreshAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch displayMode {
            case .compact:
                compactHeader
            case .full:
                fullHeader
            }

            AccountManagementPills(account: state.account)

            if isManagementModeEnabled {
                managementControls
                if isDeleteConfirmationVisible {
                    inlineDeleteConfirmation
                }
            }

            if displayMode == .full, let snapshot = state.snapshot {
                MetadataPills(snapshot: snapshot, account: state.account)
            }

            quotaContent

            if displayMode == .compact {
                compactActions
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(cardBorderColor, lineWidth: state.account.disabled ? 1 : 0)
        )
    }

    private var cardBackgroundColor: Color {
        Color(nsColor: .controlBackgroundColor)
            .opacity(state.account.disabled ? 0.62 : 1)
    }

    private var cardBorderColor: Color {
        state.account.disabled ? Color.secondary.opacity(0.34) : Color.clear
    }

    private var accountSubtitle: String {
        var components = [state.account.providerDisplayName, state.account.name]
        if let accountID = state.account.accountID {
            components.append("ChatGPT ID: \(accountID)")
        }
        return components.joined(separator: " · ")
    }

    private var fullHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(state.account.displayName)
                    .font(.headline)
                    .foregroundStyle(state.account.disabled ? Color.secondary : Color.primary)

                Text(accountSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            refreshButton
        }
    }

    private var compactHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(state.account.displayName)
                .font(.headline)
                .foregroundStyle(state.account.disabled ? Color.secondary : Color.primary)
        }
    }

    private var managementControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Label("状态", systemImage: "power")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Text("启用")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Toggle("启用", isOn: Binding(
                    get: { state.account.disabled == false },
                    set: { enabled in
                        setDisabledAction(enabled == false)
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
                .disabled(isStatusUpdating || isDeleting)

                if isStatusUpdating {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    requestDeleteConfirmationAction()
                } label: {
                    if isDeleting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "trash")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isDeleting)
                .help("删除认证文件")
            }

            HStack(alignment: .center, spacing: 8) {
                Label("priority", systemImage: "arrow.up.arrow.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                if isPriorityEditing {
                    TextField("0", text: $priorityText)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption.monospacedDigit())
                        .frame(width: 62)
                        .disabled(isPrioritySaving || isDeleting)

                    Button(action: savePriorityAction) {
                        if isPrioritySaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "checkmark")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isPrioritySaving || isDeleting)
                    .help("确认优先级")

                    Button(action: cancelPriorityEditingAction) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isPrioritySaving || isDeleting)
                    .help("取消编辑")
                } else {
                    Button(action: requestPriorityEditingAction) {
                        Label(state.account.priorityDisplayText, systemImage: "pencil")
                            .font(.caption.monospacedDigit())
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isDeleting)
                    .help("编辑优先级")
                }
            }
        }
    }

    private var inlineDeleteConfirmation: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)

            Text("确认删除这个认证文件？")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Button("取消", action: cancelDeleteConfirmationAction)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isDeleting)

            Button(role: .destructive, action: deleteAction) {
                if isDeleting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("确认删除")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isDeleting)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.red.opacity(0.08))
        )
    }

    @ViewBuilder
    private var quotaContent: some View {
        if let errorMessage = state.errorMessage {
            ErrorBanner(message: errorMessage)
        } else if state.isLoading, state.snapshot == nil {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("正在加载额度…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else if let snapshot = state.snapshot, snapshot.windows.isEmpty == false {
            VStack(spacing: 10) {
                ForEach(snapshot.windows) { window in
                    QuotaWindowRow(window: window)
                }
            }
        } else {
            Text("暂无可展示的额度窗口。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var compactActions: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("最近更新 \(Formatting.lastUpdated(state.lastUpdatedAt))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            refreshButton
        }
    }

    private var refreshButton: some View {
        Button(action: refreshAction) {
            if state.isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Label("刷新", systemImage: "arrow.clockwise")
            }
        }
        .buttonStyle(.bordered)
        .disabled(state.isLoading || isDeleting)
    }
}

private struct MetadataPills: View {
    let snapshot: CodexQuotaSnapshot
    let account: CodexAuthFile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 8) {
                if let planName = Formatting.planName(snapshot.planType) {
                    MetadataPill(title: "套餐", value: planName)
                }

                if let expiration = Formatting.expiration(snapshot.subscriptionActiveUntil) {
                    MetadataPill(title: "续期", value: expiration)
                }

                if let resetCredits = snapshot.rateLimitResetCreditsAvailableCount {
                    MetadataPill(title: "主动重置", value: "\(resetCredits)")
                }

                if let authIndex = account.authIndex {
                    MetadataPill(title: "auth_index", value: authIndex)
                }
            }
        }
    }
}

private struct AccountManagementPills: View {
    let account: CodexAuthFile

    var body: some View {
        FlowLayout(spacing: 6) {
            ManagementPill(
                title: "提供商",
                value: account.providerDisplayName,
                systemImage: account.authProvider == .xai ? "bolt.circle" : "terminal",
                tint: account.authProvider == .xai ? .primary : .accentColor
            )

            ManagementPill(
                title: "状态",
                value: account.managementStatusText,
                systemImage: account.disabled ? "pause.circle" : "checkmark.circle",
                tint: account.disabled ? .secondary : .green
            )

            ManagementPill(
                title: "priority",
                value: account.priorityDisplayText,
                systemImage: "arrow.up.arrow.down",
                tint: .accentColor
            )
        }
    }
}

private struct ManagementPill: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))

            Text(title)
                .foregroundStyle(.secondary)

            Text(value)
                .fontWeight(.semibold)
        }
        .font(.caption)
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(tint.opacity(0.10))
        )
        .overlay(
            Capsule()
                .strokeBorder(tint.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct MetadataPill: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(nsColor: .textBackgroundColor))
        )
    }
}

private struct QuotaWindowRow: View {
    let window: QuotaWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.title)
                    .font(.subheadline.weight(.medium))

                Spacer()

                Text(remainingText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(progressColor)

                Text("重置 \(window.resetLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let detail = window.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressBar(percentage: window.remainingPercent)
                .frame(height: 8)
        }
    }

    private var remainingText: String {
        guard let remainingPercent = window.remainingPercent else {
            return "--"
        }

        return "\(Int(remainingPercent.rounded()))%"
    }

    private var progressColor: Color {
        guard let remainingPercent = window.remainingPercent else {
            return .secondary
        }

        switch remainingPercent {
        case 70...:
            return .green
        case 30...:
            return .orange
        default:
            return .red
        }
    }
}

private struct ProgressBar: View {
    let percentage: Double?

    var body: some View {
        GeometryReader { geometry in
            let fraction = max(0, min(1, (percentage ?? 0) / 100))
            let barColor: Color = {
                guard let percentage else {
                    return .secondary.opacity(0.6)
                }

                switch percentage {
                case 70...:
                    return .green
                case 30...:
                    return .orange
                default:
                    return .red
                }
            }()

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.15))

                Capsule()
                    .fill(barColor)
                    .frame(width: geometry.size.width * fraction)
            }
        }
    }
}

private struct EmptyStateView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("没有找到可用的认证文件")
                .font(.headline)

            Text("请确认 CPA 内已经存在通过认证文件方式接入的 Codex 或 xAI 账号。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.red.opacity(0.08))
        )
    }
}

private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        HStack(spacing: spacing) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}
