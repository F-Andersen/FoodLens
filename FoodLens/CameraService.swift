import AVFoundation
import SwiftUI
import UIKit
import HealthKit
import Speech
import Vision

final class CameraService: NSObject, ObservableObject {
    let session = AVCaptureSession()
    @Published var permissionDenied = false
    @Published var cameraUnavailable = false
    @Published var photo: UIImage?

    private let output = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "foodlens.camera.session")
    private var isConfigured = false

    override init() { super.init() }

    func start() {
        guard isConfigured else { requestAccessAndConfigure(); return }
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func capture() {
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    private func requestAccessAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { self?.configure() }
                else { DispatchQueue.main.async { self?.permissionDenied = true } }
            }
        default:
            permissionDenied = true
        }
    }

    private func configure() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            defer { self.session.commitConfiguration(); self.start() }

            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: camera),
                  self.session.canAddInput(input), self.session.canAddOutput(self.output) else {
                DispatchQueue.main.async { self.cameraUnavailable = true }
                return
            }
            self.session.addInput(input)
            self.session.addOutput(self.output)
            self.isConfigured = true
        }
    }
}

extension CameraService: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        DispatchQueue.main.async { self.photo = image }
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

@MainActor
final class HealthService: ObservableObject {
    @Published var steps = 0
    @Published var activeCalories = 0
    private let store = HKHealthStore()

    func requestAndLoad() async {
        #if targetEnvironment(simulator)
        return
        #else
        guard HKHealthStore.isHealthDataAvailable(),
              let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount),
              let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: [stepsType, energyType])
            steps = Int(try await sum(for: stepsType, unit: .count()))
            activeCalories = Int(try await sum(for: energyType, unit: .kilocalorie()))
        } catch { }
        #endif
    }

    private func sum(for type: HKQuantityType, unit: HKUnit) async throws -> Double {
        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: result?.sumQuantity()?.doubleValue(for: unit) ?? 0) }
            }
            store.execute(query)
        }
    }
}

@MainActor
final class VoiceEntryService: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "uk-UA"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggle() async {
        if isRecording { stop(); return }
        let speechAllowed = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speechAllowed, await AVAudioApplication.requestRecordPermission() else { return }
        start()
    }

    private func start() {
        transcript = ""
        let request = SFSpeechAudioBufferRecognitionRequest()
        self.request = request
        let node = audioEngine.inputNode
        let format = node.outputFormat(forBus: 0)
        node.removeTap(onBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        audioEngine.prepare()
        try? audioEngine.start()
        isRecording = true
        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                if let result { self?.transcript = result.bestTranscription.formattedString }
                if error != nil || result?.isFinal == true { self?.stop() }
            }
        }
    }

    func stop() {
        audioEngine.stop(); audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio(); task?.cancel(); isRecording = false
    }
}

struct FoodAnalysis: Codable {
    var dish: String
    var estimatedGrams: Double
    var caloriesPer100g: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double
    var confidence: Double
    var ingredients: [FoodComponent]
}

enum FoodAIService {
    static func analyze(_ image: UIImage, backendURL: String) async throws -> FoodAnalysis {
        guard let jpeg = image.jpegData(compressionQuality: 0.72),
              let url = URL(string: backendURL.trimmingCharacters(in: .whitespacesAndNewlines))?.appendingPathComponent("analyze") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["image_base64": jpeg.base64EncodedString()])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(FoodAnalysis.self, from: data)
    }
}

enum FoodRecognitionError: LocalizedError {
    case invalidImage
    case noFoodDetected

    var errorDescription: String? {
        switch self {
        case .invalidImage: "Не вдалося прочитати фото."
        case .noFoodDetected: "Не вдалося впевнено визначити страву. Спробуйте зняти тарілку зверху при хорошому освітленні."
        }
    }
}

private struct FoodNutritionProfile {
    let keywords: [String]
    let name: String
    let defaultGrams: Double
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let fiber: Double
}

enum OnDeviceFoodRecognitionService {
    private static let catalog: [FoodNutritionProfile] = [
        .init(keywords: ["pizza"], name: "Піца", defaultGrams: 300, calories: 266, protein: 11, carbs: 33, fat: 10, fiber: 2.3),
        .init(keywords: ["hamburger", "burger", "cheeseburger"], name: "Бургер", defaultGrams: 250, calories: 260, protein: 13, carbs: 25, fat: 12, fiber: 1.5),
        .init(keywords: ["sandwich", "submarine sandwich"], name: "Сендвіч", defaultGrams: 220, calories: 240, protein: 12, carbs: 30, fat: 8, fiber: 2),
        .init(keywords: ["salad", "caesar salad"], name: "Овочевий салат", defaultGrams: 280, calories: 95, protein: 3, carbs: 9, fat: 6, fiber: 3),
        .init(keywords: ["soup", "stew", "chowder"], name: "Суп", defaultGrams: 350, calories: 75, protein: 4, carbs: 9, fat: 3, fiber: 1.5),
        .init(keywords: ["pasta", "spaghetti", "noodle", "carbonara", "lasagna"], name: "Паста", defaultGrams: 320, calories: 158, protein: 6, carbs: 31, fat: 1.5, fiber: 1.8),
        .init(keywords: ["rice", "risotto", "pilaf"], name: "Рисова страва", defaultGrams: 300, calories: 150, protein: 4, carbs: 29, fat: 2, fiber: 1),
        .init(keywords: ["sushi", "maki", "sashimi"], name: "Суші", defaultGrams: 250, calories: 150, protein: 6, carbs: 28, fat: 2, fiber: 1),
        .init(keywords: ["steak", "beef", "roast beef", "meat"], name: "Яловичина", defaultGrams: 220, calories: 250, protein: 26, carbs: 0, fat: 16, fiber: 0),
        .init(keywords: ["chicken", "poultry", "fried chicken"], name: "Курка", defaultGrams: 220, calories: 190, protein: 27, carbs: 2, fat: 8, fiber: 0),
        .init(keywords: ["fish", "salmon", "trout", "tuna", "seafood"], name: "Риба", defaultGrams: 200, calories: 180, protein: 23, carbs: 0, fat: 10, fiber: 0),
        .init(keywords: ["omelet", "omelette", "egg"], name: "Омлет", defaultGrams: 200, calories: 154, protein: 11, carbs: 2, fat: 12, fiber: 0),
        .init(keywords: ["oatmeal", "porridge", "cereal"], name: "Каша", defaultGrams: 280, calories: 110, protein: 4, carbs: 19, fat: 2, fiber: 2.5),
        .init(keywords: ["bread", "toast", "bagel", "croissant"], name: "Випічка", defaultGrams: 100, calories: 270, protein: 9, carbs: 50, fat: 4, fiber: 2.5),
        .init(keywords: ["cake", "dessert", "pie", "pancake", "waffle", "donut"], name: "Десерт", defaultGrams: 150, calories: 330, protein: 5, carbs: 48, fat: 14, fiber: 1.5),
        .init(keywords: ["french fries", "fries", "potato"], name: "Картопля", defaultGrams: 220, calories: 210, protein: 4, carbs: 32, fat: 8, fiber: 3),
        .init(keywords: ["apple"], name: "Яблуко", defaultGrams: 180, calories: 52, protein: 0.3, carbs: 14, fat: 0.2, fiber: 2.4),
        .init(keywords: ["banana"], name: "Банан", defaultGrams: 120, calories: 89, protein: 1.1, carbs: 23, fat: 0.3, fiber: 2.6),
        .init(keywords: ["fruit", "berry", "orange"], name: "Фрукти", defaultGrams: 200, calories: 55, protein: 0.8, carbs: 13, fat: 0.3, fiber: 2.5),
        .init(keywords: ["vegetable", "broccoli", "carrot", "cabbage"], name: "Овочі", defaultGrams: 250, calories: 45, protein: 2, carbs: 8, fat: 0.5, fiber: 3)
    ]

    static func analyze(_ image: UIImage) async throws -> FoodAnalysis {
        guard let cgImage = image.cgImage else { throw FoodRecognitionError.invalidImage }
        let observations: [VNClassificationObservation] = try await Task.detached(priority: .userInitiated) {
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: image.cgOrientation)
            try handler.perform([request])
            return request.results ?? []
        }.value

        let candidates = observations.prefix(30)
        let matches: [(FoodNutritionProfile, Float, String)] = candidates.compactMap { observation in
            let identifier = observation.identifier.lowercased()
            guard let profile = catalog.first(where: { profile in profile.keywords.contains(where: identifier.contains) }) else { return nil }
            return (profile, observation.confidence, observation.identifier)
        }
        guard let best = matches.max(by: { $0.1 < $1.1 }), best.1 >= 0.08 else {
            throw FoodRecognitionError.noFoodDetected
        }
        let p = best.0
        let factor = p.defaultGrams / 100
        let component = FoodComponent(
            name: p.name, grams: p.defaultGrams, calories: p.calories * factor,
            protein: p.protein * factor, carbs: p.carbs * factor,
            fat: p.fat * factor, fiber: p.fiber * factor
        )
        return FoodAnalysis(
            dish: p.name, estimatedGrams: p.defaultGrams, caloriesPer100g: p.calories,
            protein: p.protein * factor, carbs: p.carbs * factor, fat: p.fat * factor,
            fiber: p.fiber * factor, confidence: Double(best.1), ingredients: [component]
        )
    }
}

private extension UIImage {
    var cgOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: .up
        case .upMirrored: .upMirrored
        case .down: .down
        case .downMirrored: .downMirrored
        case .left: .left
        case .leftMirrored: .leftMirrored
        case .right: .right
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
