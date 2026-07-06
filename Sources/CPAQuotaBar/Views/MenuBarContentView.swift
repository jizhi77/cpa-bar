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
                        summarySection
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
                Text("CPA Codex Quota")
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

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                SummaryMetric(
                    systemImage: "person.crop.circle",
                    title: "账号",
                    value: "\(viewModel.accountCount)"
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                    .frame(height: 36)

                SummaryMetric(
                    systemImage: "clock.arrow.circlepath",
                    title: "最近刷新",
                    value: Formatting.lastUpdated(viewModel.lastUpdatedAt)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
            }

            Divider()
                .opacity(0.45)

            HStack(alignment: .center, spacing: 10) {
                Label("展示模式", systemImage: "rectangle.split.2x1")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

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
                .frame(width: 132)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var accountSection: some View {
        if viewModel.accounts.isEmpty, viewModel.isRefreshingAll == false {
            EmptyStateView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(viewModel.accounts) { state in
                    AccountCardView(
                        state: state,
                        displayMode: viewModel.displayMode,
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

private struct SummaryMetric: View {
    let systemImage: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))

                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
    }
}

private struct AccountCardView: View {
    let state: AccountQuotaState
    let displayMode: QuotaDisplayMode
    let refreshAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch displayMode {
            case .compact:
                compactHeader
            case .full:
                fullHeader
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
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var accountSubtitle: String {
        var components = [state.account.name]
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
        Text(state.account.displayName)
            .font(.headline)
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
        .disabled(state.isLoading)
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
            Text("没有找到可用的 Codex 认证文件")
                .font(.headline)

            Text("请确认 CPA 内已经存在通过认证文件方式接入的 Codex 账号，并且该文件没有被停用。")
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
