import SwiftUI

struct ReceiptCameraButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        glassLabel(configuration.label)
            .foregroundStyle(AppColor.cameraForeground)
            .contentShape(Circle())
            .compositingGroup()
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }

    @ViewBuilder
    private func glassLabel(_ label: Configuration.Label) -> some View {
        if #available(iOS 26.0, *) {
            label.glassEffect(
                .clear.tint(AppColor.cameraForeground.opacity(isSelected ? 0.2 : 0.05)).interactive(),
                in: Circle()
            )
        } else {
            label
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().strokeBorder(AppColor.cameraForeground.opacity(isSelected ? 0.7 : 0.2), lineWidth: 1)
                }
        }
    }
}
