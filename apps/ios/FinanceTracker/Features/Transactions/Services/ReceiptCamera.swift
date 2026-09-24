@preconcurrency import AVFoundation
import Combine
import Foundation
import UIKit

/// Capture-session state is confined to queue; observable state is published on the main queue.
final class ReceiptCamera: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    enum Status {
        case starting, ready, denied, unavailable
    }

    @Published private(set) var status: Status = .starting
    @Published private(set) var isCapturing = false
    @Published private(set) var isTorchOn = false
    @Published private(set) var hasTorch = false
    @Published private(set) var previewDevice: AVCaptureDevice?
    @Published private(set) var lastPreviewImage = previewCache.image
    @Published var capturedData: Data?
    @Published var errorMessage: String?

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.financetracker.receipt-camera")
    private let output = AVCapturePhotoOutput()
    private let previewOutput = AVCaptureVideoDataOutput()
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private var lastPreviewTime: CFAbsoluteTime = 0
    private static let previewCache = PreviewCache()
    private var device: AVCaptureDevice?
    private var wantsRunning = false
    private var captureInFlight = false
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
                self?.queue.async { [weak self] in
                    guard let self, self.wantsRunning else { return }
                    self.setTorch(false)
                    self.publish {
                        $0.lastPreviewImage = Self.previewCache.image
                        $0.status = .unavailable
                    }
                }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { [weak self] _ in
            self?.queue.async { [weak self] in
                guard let self, self.wantsRunning else { return }
                self.configureAndStart()
            }
        })
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        let session = session
        queue.async { if session.isRunning { session.stopRunning() } }
    }

    func start() {
        queue.async {
            self.wantsRunning = true
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: self.configureAndStart()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    self.queue.async {
                        guard self.wantsRunning else { return }
                        if granted { self.configureAndStart() }
                        else { self.publish { $0.status = .denied } }
                    }
                }
            default: self.publish { $0.status = .denied }
            }
        }
    }

    func stop() {
        queue.async {
            self.wantsRunning = false
            self.publish {
                $0.lastPreviewImage = Self.previewCache.image
                $0.status = .starting
            }
            self.setTorch(false)
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func toggleTorch() {
        queue.async {
            guard self.wantsRunning, self.session.isRunning, let device = self.device else { return }
            self.setTorch(device.torchMode != .on)
        }
    }

    func updateRotation(_ angle: CGFloat) {
        queue.async {
            if let connection = self.output.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
            if let connection = self.previewOutput.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Keep a small, recent frame without publishing every live video frame to SwiftUI.
        let now = CFAbsoluteTimeGetCurrent()
        guard wantsRunning, now - lastPreviewTime >= 0.2,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastPreviewTime = now
        let frame = CIImage(cvPixelBuffer: buffer)
        let scale = min(1, 640 / max(frame.extent.width, frame.extent.height))
        let thumbnail = frame.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let image = imageContext.createCGImage(thumbnail, from: thumbnail.extent) else { return }
        Self.previewCache.image = UIImage(cgImage: image)
    }

    func capture() {
        queue.async {
            guard self.wantsRunning, self.session.isRunning, !self.captureInFlight,
                  self.output.connection(with: .video)?.isActive == true else { return }
            self.captureInFlight = true
            self.publish {
                $0.lastPreviewImage = Self.previewCache.image
                $0.isCapturing = true
            }
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            settings.flashMode = .off
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        queue.async {
            self.captureInFlight = false
            guard self.wantsRunning else {
                self.publish { $0.isCapturing = false }
                return
            }
            self.setTorch(false)
            self.publish {
                $0.isCapturing = false
                if let data { $0.capturedData = data }
                else { $0.errorMessage = "The photo couldn't be captured. Try again." }
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        guard error != nil else { return }
        queue.async {
            self.captureInFlight = false
            self.setTorch(false)
            self.publish {
                $0.isCapturing = false
                $0.errorMessage = "The photo couldn't be captured. Try again."
            }
        }
    }

    private func configureAndStart() {
        guard wantsRunning else { return }
        if device == nil {
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: camera) else {
                publish { $0.status = .unavailable }
                return
            }
            session.beginConfiguration()
            session.sessionPreset = .photo
            guard session.canAddInput(input), session.canAddOutput(output), session.canAddOutput(previewOutput) else {
                session.commitConfiguration()
                publish { $0.status = .unavailable }
                return
            }
            session.addInput(input)
            session.addOutput(output)
            previewOutput.alwaysDiscardsLateVideoFrames = true
            previewOutput.setSampleBufferDelegate(self, queue: queue)
            session.addOutput(previewOutput)
            device = camera
            session.commitConfiguration()
            if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            if let connection = previewOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
        if !session.isRunning { session.startRunning() }
        let ready = session.isRunning && !session.isInterrupted
        let torch = device?.hasTorch == true && device?.isTorchAvailable == true
        let previewDevice = device
        publish { $0.status = ready ? .ready : .unavailable; $0.hasTorch = torch; $0.previewDevice = previewDevice }
    }

    private func setTorch(_ enabled: Bool) {
        guard let device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if enabled { try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel) }
            else { device.torchMode = .off }
            publish { $0.isTorchOn = enabled }
        } catch {
            if enabled { publish { $0.errorMessage = "The flashlight is unavailable right now." } }
        }
    }

    private func publish(_ update: @escaping @Sendable (ReceiptCamera) -> Void) {
        DispatchQueue.main.async { update(self) }
    }

    /// Retain only the latest thumbnail across scanner presentations, never on disk.
    private final class PreviewCache: @unchecked Sendable {
        private let lock = NSLock()
        private var storedImage: UIImage?

        var image: UIImage? {
            get {
                lock.lock()
                defer { lock.unlock() }
                return storedImage
            }
            set {
                lock.lock()
                defer { lock.unlock() }
                storedImage = newValue
            }
        }
    }
}
