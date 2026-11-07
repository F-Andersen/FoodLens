import Foundation
import UIKit

struct FoodAnalysis: Codable, Sendable {
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

enum FoodAIError: LocalizedError, Equatable {
    case invalidServerURL
    case imageEncodingFailed
    case server(status: Int)
    case invalidResponse
    case timedOut
    case offline

    var errorDescription: String? {
        switch self {
        case .invalidServerURL: "Некоректна адреса AI-сервера."
        case .imageEncodingFailed: "Не вдалося підготувати фото."
        case .server(let status): "AI-сервер відповів помилкою (\(status))."
        case .invalidResponse: "AI-сервер повернув незрозумілу відповідь."
        case .timedOut: "AI-сервер не відповів вчасно."
        case .offline: "Немає з'єднання з AI-сервером."
        }
    }
}

enum FoodAIService {
    /// Longest side of the uploaded photo. Enough detail for the model, ~10× smaller than a full 12 MP shot.
    static let maxImageDimension: CGFloat = 1280

    /// Builds the `/analyze` URL from the base address the user entered.
    static func endpoint(from base: String) throws(FoodAIError) -> URL {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty else { throw .invalidServerURL }
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if !path.hasSuffix("/analyze") { path += "/analyze" }
        components.path = path
        guard let url = components.url else { throw .invalidServerURL }
        return url
    }

    static func analyze(_ image: UIImage, backendURL: String, session: URLSession = .shared) async throws -> FoodAnalysis {
        let url = try endpoint(from: backendURL)
        let jpeg = try await Task.detached(priority: .userInitiated) { () throws -> Data in
            guard let data = image.downscaled(maxDimension: maxImageDimension).jpegData(compressionQuality: 0.7) else {
                throw FoodAIError.imageEncodingFailed
            }
            return data
        }.value

        var request = URLRequest(url: url, timeoutInterval: 45)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["image_base64": jpeg.base64EncodedString()])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .timedOut: throw FoodAIError.timedOut
            case .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .dnsLookupFailed:
                throw FoodAIError.offline
            default: throw error
            }
        }
        guard let http = response as? HTTPURLResponse else { throw FoodAIError.invalidResponse }
        guard 200..<300 ~= http.statusCode else { throw FoodAIError.server(status: http.statusCode) }
        do {
            return try JSONDecoder().decode(FoodAnalysis.self, from: data)
        } catch {
            throw FoodAIError.invalidResponse
        }
    }
}

extension UIImage {
    /// Returns an upright copy whose longest side is at most `maxDimension` pixels.
    func downscaled(maxDimension: CGFloat) -> UIImage {
        let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)
        let longest = max(pixelSize.width, pixelSize.height)
        guard longest > maxDimension, longest > 0 else { return self }
        let ratio = maxDimension / longest
        let target = CGSize(width: (pixelSize.width * ratio).rounded(), height: (pixelSize.height * ratio).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
