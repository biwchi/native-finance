import AVFoundation
import SwiftUI

struct ReceiptCameraPreview: UIViewRepresentable {
    let camera: ReceiptCamera
    var isActive: Bool

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.camera = camera
        view.previewLayer.session = camera.session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.lastFrameView.image = camera.lastPreviewImage
        uiView.isActive = isActive
        uiView.configureRotation(device: camera.previewDevice)
        uiView.setNeedsLayout()
    }

    final class PreviewView: UIView {
        weak var camera: ReceiptCamera?
        var isActive = false {
            didSet { updateBlur() }
        }
        private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
        let lastFrameView = UIImageView()
        private var isBlurred = true
        private var previewObservation: NSKeyValueObservation?
        private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
        private var rotationObservations: [NSKeyValueObservation] = []
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override init(frame: CGRect) {
            super.init(frame: frame)
            lastFrameView.contentMode = .scaleAspectFill
            lastFrameView.clipsToBounds = true
            lastFrameView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            lastFrameView.frame = bounds
            addSubview(lastFrameView)
            blurView.isUserInteractionEnabled = false
            blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            blurView.frame = bounds
            addSubview(blurView)
            previewObservation = previewLayer.observe(\.isPreviewing, options: [.initial, .new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.updateBlur() }
            }
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func updateBlur() {
            let shouldBlur = !isActive || !previewLayer.isPreviewing
            guard shouldBlur != isBlurred else { return }
            isBlurred = shouldBlur
            // Animate the effect itself so the live camera stays behind the blur.
            UIView.animate(
                withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.35,
                delay: 0,
                options: [.beginFromCurrentState, .curveEaseInOut, .allowUserInteraction]
            ) {
                self.blurView.effect = shouldBlur ? UIBlurEffect(style: .systemMaterialDark) : nil
                self.lastFrameView.alpha = shouldBlur ? 1 : 0
            }
        }

        func configureRotation(device: AVCaptureDevice?) {
            guard rotationCoordinator == nil, let device else { return }
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
            rotationCoordinator = coordinator
            for keyPath in [\AVCaptureDevice.RotationCoordinator.videoRotationAngleForHorizonLevelPreview,
                            \AVCaptureDevice.RotationCoordinator.videoRotationAngleForHorizonLevelCapture] {
                rotationObservations.append(coordinator.observe(keyPath, options: [.initial, .new]) { [weak self] _, _ in
                    DispatchQueue.main.async { self?.updateRotation() }
                })
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            updateRotation()
        }

        private func updateRotation() {
            guard let rotationCoordinator else { return }
            let angle = rotationCoordinator.videoRotationAngleForHorizonLevelPreview
            if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
            camera?.updateRotation(rotationCoordinator.videoRotationAngleForHorizonLevelCapture)
        }
    }
}
