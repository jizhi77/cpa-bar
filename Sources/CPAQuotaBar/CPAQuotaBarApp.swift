import AppKit
import SwiftUI

@main
struct CPAQuotaBarApp: App {
    @StateObject private var viewModel = MenuBarViewModel()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(viewModel: viewModel)
        } label: {
            MenuBarLabelView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabelView: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        HStack(spacing: 4) {
            GaugeTemplateIconView()

            if viewModel.accountCount > 0 {
                Text("\(viewModel.accountCount)")
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .fixedSize()
        .padding(.horizontal, 1)
    }
}
