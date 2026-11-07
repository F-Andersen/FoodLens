import AVFoundation
import SwiftUI
import UIKit

/// UI-facing camera state. All capture-session work happens on `CaptureSessionController`'s queue.
@MainActor
final class CameraService: ObservableObject {
    @Published var permissionDenied = false
    @Published var cameraUnavailable = false
    @Published var photo: UIImage?
    @Published private(set) var isCapturing = false

    private let controller = CaptureSessionController()

    var session: AVCaptureSession { controller.session }

    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { permissionDenied = true; return }
        default:
            permissionDenied = true
            return
        }
        guard photo == nil else { return }
        if await !controller.configureAndStart() { cameraUnavailable = true }
    }

    func stop() { controller.stop() }

    func capture() async {
        guard !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }
        guard let image = await controller.capturePhoto() else { return }
        photo = image
        controller.stop()
    }

    func show(_ image: UIImage) {
        photo = image
        controller.stop()
    }

    func retake() {
        photo = nil
        controller.start()
    }
}

/// Owns the AVCaptureSession. Every mutable property is touched only on `queue`.
final class CaptureSessionController: @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "foodlens.camera.session")
    private var isConfigured = false
    private var inFlight: [Int64: PhotoCaptureProcessor] = [:]

    func configureAndStart() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                guard self.configureIfNeeded() else { continuation.resume(returning: false); return }
                if !self.session.isRunning { self.session.startRunning() }
                continuation.resume(returning: true)
            }
        }
    }

    func start() {
        queue.async {
            guard self.isConfigured, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        queue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func capturePhoto() async -> UIImage? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard self.isConfigured, self.session.isRunning else { continuation.resume(returning: nil); return }
                let settings = AVCapturePhotoSettings()
                let captureID = settings.uniqueID
                // The strong capture is released when the processor is removed from `inFlight`.
                let processor = PhotoCaptureProcessor { image in
                    self.queue.async { self.inFlight[captureID] = nil }
                    continuation.resume(returning: image)
                }
                self.inFlight[captureID] = processor
                self.output.capturePhoto(with: settings, delegate: processor)
            }
        }
    }

    private func configureIfNeeded() -> Bool {
        if isConfigured { return true }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input), session.canAddOutput(output) else { return false }
        session.addInput(input)
        session.addOutput(output)
        isConfigured = true
        return true
    }
}

/// Holds the photo between AVFoundation's two delegate callbacks and reports once capture is complete.
private final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let completion: @Sendable (UIImage?) -> Void
    private var image: UIImage?

    init(completion: @escaping @Sendable (UIImage?) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        image = UIImage(data: data)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: (any Error)?) {
        completion(image)
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
