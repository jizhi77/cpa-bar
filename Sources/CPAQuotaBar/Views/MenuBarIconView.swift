import SwiftUI

struct GaugeTemplateIconView: View {
    var body: some View {
        Image(systemName: "gauge.medium")
            .symbolRenderingMode(.monochrome)
            .font(.system(size: 12.5, weight: .medium))
            .frame(width: 15, height: 13, alignment: .center)
            .accessibilityHidden(true)
    }
}
