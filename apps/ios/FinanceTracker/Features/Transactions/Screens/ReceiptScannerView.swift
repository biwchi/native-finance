import PhotosUI
import SwiftUI

struct ReceiptScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var scanDraftStore: ScanDraftStore
    @StateObject private var camera = ReceiptCamera()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isChoosingPhoto = false
    @State private var isChoosingDocument = false

    let defaultAccountID: UUID
    var replacingDraftID: UUID?
    var onBottomActionBarHeightChange: (CGFloat) -> Void = { _ in }

    var body: some View {
        ZStack {
            AppColor.cameraBackground.ignoresSafeArea()
            ReceiptCameraPreview(
                camera: camera,
                isActive: camera.status == .ready && scenePhase == .active && !isBusy
            )
                .ignoresSafeArea()
                .accessibilityHidden(true)

            if camera.status == .denied || camera.status == .unavailable {
                cameraStatus
            }
        }
        .foregroundStyle(AppColor.cameraForeground)
        .overlay(alignment: .topLeading) {
            Button(action: close) {
                AppIcon("xmark", size: 24)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(ReceiptCameraButtonStyle())
            .accessibilityLabel("Close scanner")
            .padding(AppSpacing.doubleExtraLarge)
        }
        .overlay(alignment: .bottom) {
            ReceiptCaptureControls(
                isTorchOn: camera.isTorchOn,
                canUseTorch: camera.hasTorch && camera.status == .ready && !isBusy,
                canCapture: camera.status == .ready && !isBusy,
                isCapturing: camera.isCapturing,
                canChoosePhoto: !isBusy,
                canAttachDocument: !isBusy,
                onToggleTorch: camera.toggleTorch,
                onCapture: camera.capture,
                onChoosePhoto: { camera.stop(); isChoosingPhoto = true },
                onAttachDocument: chooseDocument
            )
            .foregroundStyle(AppColor.cameraForeground)
            .padding(.bottom, AppSpacing.doubleExtraLarge)
            .reportScanDraftBottomBarHeight(onBottomActionBarHeightChange)
        }
        .photosPicker(isPresented: $isChoosingPhoto, selection: $selectedPhoto, matching: .images)
        .fileImporter(isPresented: $isChoosingDocument, allowedContentTypes: ReceiptDocument.supportedTypes) { result in
            switch result {
            case .success(let url):
                scanDraftStore.enqueueDocument(
                    url,
                    defaultAccountID: defaultAccountID,
                    replacing: replacingDraftID
                )
                close()
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError {
                    // The native picker owns its own error presentation. Keep the
                    // scanner open so the user can choose another source.
                }
                resumeCameraIfNeeded()
            }
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            scanDraftStore.enqueuePhoto(
                item,
                defaultAccountID: defaultAccountID,
                replacing: replacingDraftID
            )
            close()
        }
        .onChange(of: isChoosingPhoto) { _, choosing in
            if !choosing { resumeCameraIfNeeded() }
        }
        .onChange(of: isChoosingDocument) { _, choosing in
            if !choosing { resumeCameraIfNeeded() }
        }
        .onChange(of: camera.capturedData) { _, data in
            guard let data else { return }
            camera.capturedData = nil
            scanDraftStore.enqueueCameraPhoto(
                data,
                defaultAccountID: defaultAccountID,
                replacing: replacingDraftID
            )
            close()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { resumeCameraIfNeeded() } else { camera.stop() }
        }
        .onAppear { resumeCameraIfNeeded() }
        .onDisappear { camera.stop() }
        .accessibilityAction(.escape, close)
        .preferredColorScheme(.dark)
        .tint(AppColor.cameraForeground)
    }

    private var isBusy: Bool {
        camera.isCapturing || isChoosingPhoto || isChoosingDocument
    }

    @ViewBuilder
    private var cameraStatus: some View {
        VStack(spacing: AppSpacing.medium) {
            AppIcon("camera", size: 40)
            Text(camera.status == .denied ? "Allow camera access to take a photo" : "Camera unavailable")
                .font(.headline)
            Text("You can still choose a photo or attach a document.")
                .font(.subheadline)
            if camera.status == .denied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.bordered)
            } else {
                Button("Try camera again", action: camera.start)
                    .buttonStyle(.bordered)
            }
        }
        .multilineTextAlignment(.center)
        .padding(AppSpacing.doubleExtraLarge)
        .background(AppColor.cameraBackground.opacity(0.85), in: RoundedRectangle(cornerRadius: AppRadius.large))
    }

    private func chooseDocument() {
        camera.stop()
        isChoosingDocument = true
    }

    private func resumeCameraIfNeeded() {
        if scenePhase == .active && !isBusy { camera.start() }
    }

    private func close() {
        camera.stop()
        dismiss()
    }
}
