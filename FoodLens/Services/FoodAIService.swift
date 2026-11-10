import Foundation
import Security
import UIKit

enum AppConfig {
    /// Production API, e.g. "https://api.foodlens.example". Set after deploying `backend/`.
    /// While empty, the app analyses photos on the device unless a custom address is set in Settings.
    static let defaultAPIBaseURL = "https://foodlens.130.61.111.249.sslip.io"

    /// The custom address from Settings if set, otherwise the built-in one; nil when neither exists.
    static func apiBaseURL(override: String) -> String? {
        let custom = override.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom }
        return defaultAPIBaseURL.isEmpty ? nil : defaultAPIBaseURL
    }
}

// MARK: - Models

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

struct RecipeQuery: Encodable, Sendable {
    var pantry: [String]
    var mealType: String?
    var caloriesLeft: Int
    var proteinLeft: Int
    var diet: String
    var avoid: [String]
}

struct RemoteRecipes: Decodable, Sendable {
    struct Ingredient: Decodable, Sendable { var name: String; var grams: Int; var calories: Int }
    struct Recipe: Decodable, Sendable {
        var title: String
        var mealType: String
        var minutes: Int
        var ingredients: [Ingredient]
        var steps: [String]
        var calories: Int
        var protein: Int
        var carbs: Int
        var fat: Int
    }

    var message: String
    var recipes: [Recipe]
    var shoppingList: [String]

    /// Converts to the model the assistant screen already renders.
    var assistantResult: AssistantResult {
        AssistantResult(
            message: message,
            recipes: recipes.map { recipe in
                AssistantRecipe(
                    title: recipe.title,
                    mealType: MealEntry.MealType(rawValue: recipe.mealType) ?? .lunch,
                    ingredients: recipe.ingredients.map { RecipeIngredient(name: $0.name, grams: $0.grams, calories: $0.calories) },
                    steps: recipe.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"),
                    calories: recipe.calories,
                    protein: recipe.protein,
                    minutes: recipe.minutes
                )
            },
            shoppingList: shoppingList
        )
    }
}

enum FoodAIError: LocalizedError, Equatable {
    case invalidServerURL
    case imageEncodingFailed
    /// The server's own Ukrainian message, shown as is.
    case server(status: Int, message: String?)
    case invalidResponse
    case timedOut
    case offline

    var errorDescription: String? {
        switch self {
        case .invalidServerURL: "Некоректна адреса AI-сервера."
        case .imageEncodingFailed: "Не вдалося підготувати фото."
        case .server(let status, let message): message ?? "AI-сервер відповів помилкою (\(status))."
        case .invalidResponse: "AI-сервер повернув незрозумілу відповідь."
        case .timedOut: "AI-сервер не відповів вчасно."
        case .offline: "Немає з'єднання з AI-сервером."
        }
    }
}

// MARK: - Device credentials

protocol DeviceCredentialStore: Sendable {
    func installID() -> String
    func token() -> String?
    func setToken(_ token: String?)
}

/// Keeps the install id and device token in the Keychain (this device only, available after first unlock).
struct KeychainCredentialStore: DeviceCredentialStore {
    private let service = "com.argusstrauf.foodlens.api"

    func installID() -> String {
        if let existing = read("installId") { return existing }
        let id = UUID().uuidString
        write("installId", id)
        return id
    }

    func token() -> String? { read("token") }

    func setToken(_ token: String?) {
        if let token { write("token", token) } else { delete("token") }
    }

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    private func read(_ account: String) -> String? {
        var item: CFTypeRef?
        var query = query(account)
        query[kSecReturnData as String] = true
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func write(_ account: String, _ value: String) {
        delete(account)
        var attributes = query(account)
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}

// MARK: - API client

/// Talks to the FoodLens backend. Registers the device on first use and once more if the token is rejected.
actor FoodLensAPI {
    static let shared = FoodLensAPI()

    /// Longest side of the uploaded photo. Enough detail for the model, ~10× smaller than a full 12 MP shot.
    static let maxImageDimension: CGFloat = 1280

    private let session: URLSession
    private let credentials: any DeviceCredentialStore

    init(session: URLSession = .shared, credentials: any DeviceCredentialStore = KeychainCredentialStore()) {
        self.session = session
        self.credentials = credentials
    }

    /// Builds `<base>/v1/<path>`, accepting addresses with or without a trailing slash.
    static func endpoint(base: String, path: String) throws(FoodAIError) -> URL {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty else { throw .invalidServerURL }
        var basePath = components.path
        while basePath.hasSuffix("/") { basePath.removeLast() }
        components.path = basePath + "/" + path
        guard let url = components.url else { throw .invalidServerURL }
        return url
    }

    func analyze(_ image: UIImage, baseURL: String) async throws -> FoodAnalysis {
        let jpeg = try await Task.detached(priority: .userInitiated) { () throws -> Data in
            guard let data = image.downscaled(maxDimension: FoodLensAPI.maxImageDimension).jpegData(compressionQuality: 0.7) else {
                throw FoodAIError.imageEncodingFailed
            }
            return data
        }.value
        let body = try JSONEncoder().encode(["image_base64": jpeg.base64EncodedString()])
        return try await send(path: "v1/analyze", body: body, baseURL: baseURL, timeout: 90)
    }

    func recipes(_ query: RecipeQuery, baseURL: String) async throws -> RemoteRecipes {
        try await send(path: "v1/recipes", body: try JSONEncoder().encode(query), baseURL: baseURL, timeout: 90)
    }

    /// Checks that the address points at a running FoodLens server.
    func checkHealth(baseURL: String) async throws {
        var request = URLRequest(url: try Self.endpoint(base: baseURL, path: "health"), timeoutInterval: 10)
        request.httpMethod = "GET"
        let (data, response) = try await perform(request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], json["status"] as? String == "ok"
        else { throw FoodAIError.invalidResponse }
    }

    // MARK: Private

    private func send<T: Decodable>(path: String, body: Data, baseURL: String, timeout: TimeInterval) async throws -> T {
        let url = try Self.endpoint(base: baseURL, path: path)
        for attempt in 0..<2 {
            let token = try await validToken(baseURL: baseURL, forceRefresh: attempt > 0)
            var request = URLRequest(url: url, timeoutInterval: timeout)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = body
            let (data, response) = try await perform(request)
            guard let http = response as? HTTPURLResponse else { throw FoodAIError.invalidResponse }
            if http.statusCode == 401 && attempt == 0 { continue }  // token expired or secret rotated: register again
            guard 200..<300 ~= http.statusCode else { throw Self.serverError(status: http.statusCode, data: data) }
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw FoodAIError.invalidResponse
            }
        }
        throw FoodAIError.server(status: 401, message: nil)
    }

    private func validToken(baseURL: String, forceRefresh: Bool) async throws -> String {
        if !forceRefresh, let token = credentials.token() { return token }
        credentials.setToken(nil)
        var request = URLRequest(url: try Self.endpoint(base: baseURL, path: "v1/auth/register"), timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["installId": credentials.installID()])
        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else { throw FoodAIError.invalidResponse }
        guard 200..<300 ~= http.statusCode else { throw Self.serverError(status: http.statusCode, data: data) }
        struct TokenResponse: Decodable { var token: String }
        guard let token = try? JSONDecoder().decode(TokenResponse.self, from: data).token else { throw FoodAIError.invalidResponse }
        credentials.setToken(token)
        return token
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .timedOut: throw FoodAIError.timedOut
            case .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .dnsLookupFailed,
                 .appTransportSecurityRequiresSecureConnection, .secureConnectionFailed:
                throw FoodAIError.offline
            default: throw error
            }
        }
    }

    static func serverError(status: Int, data: Data) -> FoodAIError {
        struct Envelope: Decodable { struct Detail: Decodable { var message: String }; var error: Detail }
        let message = try? JSONDecoder().decode(Envelope.self, from: data).error.message
        return .server(status: status, message: message)
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
