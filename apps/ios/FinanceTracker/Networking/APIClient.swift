import Foundation

enum APIClientError: LocalizedError {
    case invalidResponse
    case requestFailed(status: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The backend returned an invalid response."
        case let .requestFailed(status, message):
            message ?? "The request failed with HTTP status \(status)."
        }
    }
}

struct APIClient: Sendable {
    let baseURL: URL
    let session: URLSession

    init(
        baseURL: URL = APIClient.configuredBaseURL,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func health() async throws -> HealthResponse {
        let url = baseURL.appending(path: "health")
        return try await get(url: url)
    }

    func accounts() async throws -> [Account] {
        try await get(url: apiURL.appending(path: "accounts"))
    }

    func createAccount(_ account: AccountRequest) async throws -> Account {
        var request = URLRequest(url: apiURL.appending(path: "accounts"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(account)

        return try await send(request)
    }

    func updateAccount(id: UUID, with account: AccountRequest) async throws -> Account {
        var request = URLRequest(
            url: apiURL
                .appending(path: "accounts")
                .appending(path: id.uuidString)
        )
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(account)

        return try await send(request)
    }

    func transactions(accountID: UUID?) async throws -> [FinanceTransaction] {
        var components = URLComponents(
            url: apiURL.appending(path: "transactions"),
            resolvingAgainstBaseURL: false
        )

        if let accountID {
            components?.queryItems = [
                URLQueryItem(name: "accountId", value: accountID.uuidString),
            ]
        }

        guard let url = components?.url else {
            throw APIClientError.invalidResponse
        }

        return try await get(url: url)
    }

    private var apiURL: URL {
        baseURL
            .appending(path: "api")
            .appending(path: "v1")
    }

    private func get<Response: Decodable>(url: URL) async throws -> Response {
        try await send(URLRequest(url: url))
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = try? JSONDecoder().decode(ErrorResponse.self, from: data).message
            throw APIClientError.requestFailed(
                status: httpResponse.statusCode,
                message: message
            )
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }

    private static var configuredBaseURL: URL {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
            let url = URL(string: value)
        else {
            preconditionFailure("API_BASE_URL is missing or invalid")
        }

        return url
    }
}

private struct ErrorResponse: Decodable {
    let message: String
}
