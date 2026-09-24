import SwiftUI

struct ReceiptCaptureControls: View {
    var isTorchOn: Bool
    var canUseTorch: Bool
    var canCapture: Bool
    var isCapturing: Bool
    var canChoosePhoto: Bool
    var canAttachDocument: Bool
    var onToggleTorch: () -> Void
    var onCapture: () -> Void
    var onChoosePhoto: () -> Void
    var onAttachDocument: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.small) {
            Button(action: onToggleTorch) {
                AppIcon("flash", size: 24)
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(ReceiptCameraButtonStyle(isSelected: isTorchOn))
            .disabled(!canUseTorch)
            .accessibilityLabel(isTorchOn ? "Turn flashlight off" : "Turn flashlight on")
            .accessibilityValue(isTorchOn ? "On" : "Off")
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            Button(action: onCapture) {
                Circle().strokeBorder(AppColor.cameraForeground, lineWidth: 3).padding(5)
                .frame(width: 76, height: 76)
                .contentShape(Circle())
            }
            .disabled(!canCapture || isCapturing)
            .accessibilityLabel("Take picture")

            attachmentControls
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .trailing)
        }
        .buttonStyle(ReceiptCameraButtonStyle())
        .tint(AppColor.cameraForeground)
        .dynamicTypeSize(.large)
        .padding(.horizontal, AppSpacing.doubleExtraLarge)
        .frame(maxWidth: .infinity)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var attachmentControls: some View {
        if #available(iOS 26.0, *) {
            attachmentButtons
                .glassEffect(.clear.tint(AppColor.cameraForeground.opacity(0.05)), in: Capsule())
        } else {
            attachmentButtons
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(AppColor.cameraForeground.opacity(0.2), lineWidth: 1)
                }
        }
    }

    private var attachmentButtons: some View {
        HStack(spacing: 0) {
            Button(action: onChoosePhoto) {
                AppIcon("media-image", size: 24)
                    .frame(width: 48, height: 48)
            }
            .disabled(!canChoosePhoto)
            .accessibilityLabel("Choose photo")

            Button(action: onAttachDocument) {
                AppIcon("file", size: 24)
                    .frame(width: 48, height: 48)
            }
            .disabled(!canAttachDocument)
            .accessibilityLabel("Attach document")
            .accessibilityHint("Extract transactions from a PDF, CSV, TSV, or Excel file")
            .accessibilityIdentifier("attachScanDocument")
        }
        .buttonStyle(ReceiptAttachmentButtonStyle())
        .fixedSize()
    }
}

private struct ReceiptAttachmentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(AppColor.cameraForeground)
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}
