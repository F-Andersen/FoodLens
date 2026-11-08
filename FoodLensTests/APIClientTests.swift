import Foundation
import Testing
import UIKit
@testable import FoodLens

/// Serves canned responses for requests made through a URLSession configured with it.
final class StubURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) -> (Int, Data)
    nonisolated(unsafe) static var handler: Handler?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var request = request
        // URLSession moves the body into a stream; read it back so tests can inspect it.
        if request.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            stream.close()
            request.httpBody = data
        }
        Self.requests.append(request)
        let (status, body) = Self.handler?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

final class MemoryCredentials: DeviceCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storedToken: String?
    let id = UUID().uuidString

    init(token: String? = nil) { storedToken = token }

    func installID() -> String { id }
    func token() -> String? { lock.withLock { storedToken } }
    func setToken(_ token: String?) { lock.withLock { storedToken = token } }
}

private let analysisJSON = Data("""
{"dish": "Плов", "estimatedGrams": 350, "caloriesPer100g": 160, "protein": 20, "carbs": 60, "fat": 14,
 "fiber": 3, "confidence": 0.7, "ingredients": []}
""".utf8)

private func smallImage() -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in
        UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
    }
}

@Suite("FoodLens API client", .serialized)
struct APIClientTests {
    init() {
        StubURLProtocol.requests = []
        StubURLProtocol.handler = nil
    }

    @Test func registersThenAnalyzesWithBearerToken() async throws {
        StubURLProtocol.handler = { request in
            switch request.url!.path {
            case "/v1/auth/register": (200, Data(#"{"token": "t1", "expiresAt": 1}"#.utf8))
            case "/v1/analyze": (200, analysisJSON)
            default: (404, Data())
            }
        }
        let credentials = MemoryCredentials()
        let api = FoodLensAPI(session: StubURLProtocol.session(), credentials: credentials)

        let analysis = try await api.analyze(smallImage(), baseURL: "https://api.test")

        #expect(analysis.dish == "Плов")
        #expect(credentials.token() == "t1")
        let paths = StubURLProtocol.requests.map(\.url!.path)
        #expect(paths == ["/v1/auth/register", "/v1/analyze"])
        let register = try JSONSerialization.jsonObject(with: StubURLProtocol.requests[0].httpBody!) as? [String: String]
        #expect(register?["installId"] == credentials.id)
        #expect(StubURLProtocol.requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer t1")
        let body = try JSONSerialization.jsonObject(with: StubURLProtocol.requests[1].httpBody!) as? [String: String]
        let jpeg = try #require(Data(base64Encoded: body?["image_base64"] ?? ""))
        #expect(jpeg.starts(with: [0xFF, 0xD8, 0xFF]))
    }

    @Test func reRegistersOnceWhenTokenIsRejected() async throws {
        StubURLProtocol.handler = { request in
            switch (request.url!.path, request.value(forHTTPHeaderField: "Authorization")) {
            case ("/v1/auth/register", _): (200, Data(#"{"token": "fresh", "expiresAt": 1}"#.utf8))
            case ("/v1/analyze", "Bearer fresh"): (200, analysisJSON)
            default: (401, Data(#"{"error": {"code": "unauthorized", "message": "x"}}"#.utf8))
            }
        }
        let credentials = MemoryCredentials(token: "stale")
        let api = FoodLensAPI(session: StubURLProtocol.session(), credentials: credentials)

        _ = try await api.analyze(smallImage(), baseURL: "https://api.test")

        #expect(StubURLProtocol.requests.map(\.url!.path) == ["/v1/analyze", "/v1/auth/register", "/v1/analyze"])
        #expect(credentials.token() == "fresh")
    }

    @Test func surfacesServerMessage() async {
        StubURLProtocol.handler = { _ in
            (429, Data(#"{"error": {"code": "rate_limited", "message": "Ліміт аналізу фото вичерпано."}}"#.utf8))
        }
        let api = FoodLensAPI(session: StubURLProtocol.session(), credentials: MemoryCredentials(token: "t"))
        await #expect(throws: FoodAIError.server(status: 429, message: "Ліміт аналізу фото вичерпано.")) {
            _ = try await api.analyze(smallImage(), baseURL: "https://api.test")
        }
    }

    @Test func recipesAreMappedForTheAssistantScreen() async throws {
        StubURLProtocol.handler = { _ in
            (200, Data("""
            {"message": "Добре", "shoppingList": ["зелень"], "recipes": [{"title": "Омлет", "mealType": "breakfast",
             "minutes": 10, "ingredients": [{"name": "яйця", "grams": 180, "calories": 260}],
             "steps": ["Збийте яйця.", "Смажте."], "calories": 260, "protein": 22, "carbs": 2, "fat": 18}]}
            """.utf8))
        }
        let api = FoodLensAPI(session: StubURLProtocol.session(), credentials: MemoryCredentials(token: "t"))
        let query = RecipeQuery(pantry: ["яйця"], mealType: "breakfast", caloriesLeft: 500, proteinLeft: 40,
                                diet: "balanced", avoid: [])

        let result = try await api.recipes(query, baseURL: "https://api.test").assistantResult

        let recipe = try #require(result.recipes.first)
        #expect(recipe.mealType == .breakfast)
        #expect(recipe.minutes == 10)
        #expect(recipe.steps == "1. Збийте яйця.\n2. Смажте.")
        #expect(result.shoppingList == ["зелень"])
        let sent = try JSONSerialization.jsonObject(with: StubURLProtocol.requests[0].httpBody!) as? [String: Any]
        #expect(sent?["mealType"] as? String == "breakfast")
    }

    @Test func healthCheckRequiresFoodLensResponse() async throws {
        StubURLProtocol.handler = { _ in (200, Data(#"{"status": "ok", "version": "0.3.0"}"#.utf8)) }
        let api = FoodLensAPI(session: StubURLProtocol.session(), credentials: MemoryCredentials())
        try await api.checkHealth(baseURL: "https://api.test")

        StubURLProtocol.handler = { _ in (200, Data("<html>".utf8)) }
        await #expect(throws: FoodAIError.invalidResponse) { try await api.checkHealth(baseURL: "https://api.test") }
    }

    @Test func pantryTextIsSplitIntoItems() {
        #expect(FoodAssistantView.items(from: "курка, гречка\nпомідори;  ,") == ["курка", "гречка", "помідори"])
    }
}
