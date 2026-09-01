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

    func categories(kind: TransactionKind? = nil) async throws -> [TransactionCategory] {
        var components = URLComponents(
            url: apiURL.appending(path: "categories"),
            resolvingAgainstBaseURL: false
        )

        if let kind {
            components?.queryItems = [
                URLQueryItem(name: "kind", value: kind.rawValue),
            ]
        }

        guard let url = components?.url else {
            throw APIClientError.invalidResponse
        }

        return try await get(url: url)
    }

    func createCategory(_ category: CreateCategoryRequest) async throws -> TransactionCategory {
        try await post(
            category,
            to: apiURL.appending(path: "categories")
        )
    }

    func updateCategory(id: UUID, with category: UpdateCategoryRequest) async throws -> TransactionCategory {
        var request = URLRequest(
            url: apiURL.appending(path: "categories").appending(path: id.uuidString)
        )
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.jsonEncoder.encode(category)
        return try await send(request)
    }

    func deleteCategory(id: UUID) async throws -> DeleteCategoryResponse {
        var request = URLRequest(
            url: apiURL.appending(path: "categories").appending(path: id.uuidString)
        )
        request.httpMethod = "DELETE"
        return try await send(request)
    }

    func categorySuggestions(
        description: String,
        kind: TransactionKind
    ) async throws -> CategorySuggestionsResponse {
        try await post(
            CategorySuggestionsRequest(description: description, kind: kind),
            to: apiURL
                .appending(path: "categories")
                .appending(path: "suggest")
        )
    }

    func createTransaction(
        _ transaction: TransactionRequest
    ) async throws -> FinanceTransaction {
        try await post(
            transaction,
            to: apiURL.appending(path: "transactions")
        )
    }

    func createTransfer(_ transfer: TransferRequest) async throws -> TransferResponse {
        try await post(
            transfer,
            to: apiURL.appending(path: "transactions").appending(path: "transfer")
        )
    }

    func monthlyBudget(month: String, accountID: UUID?) async throws -> MonthlyBudget? {
        var components = URLComponents(
            url: apiURL.appending(path: "budgets").appending(path: "monthly"),
            resolvingAgainstBaseURL: false
        )
        var queryItems = [URLQueryItem(name: "month", value: month)]
        if let accountID {
            queryItems.append(URLQueryItem(name: "accountId", value: accountID.uuidString))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw APIClientError.invalidResponse
        }
        return try await get(url: url)
    }

    func saveMonthlyBudget(_ budget: MonthlyBudgetRequest) async throws -> MonthlyBudget? {
        var request = URLRequest(
            url: apiURL.appending(path: "budgets").appending(path: "monthly")
        )
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.jsonEncoder.encode(budget)
        return try await send(request)
    }

    private var apiURL: URL {
        baseURL
            .appending(path: "api")
            .appending(path: "v1")
    }

    func updateTransaction(
        id: UUID,
        with transaction: TransactionRequest
    ) async throws -> FinanceTransaction {
        var request = URLRequest(url: apiURL.appending(path: "transactions").appending(path: id.uuidString))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.jsonEncoder.encode(transaction)
        return try await send(request)
    }

    private func get<Response: Decodable>(url: URL) async throws -> Response {
        try await send(URLRequest(url: url))
    }

    private func post<Body: Encodable, Response: Decodable>(
        _ body: Body,
        to url: URL
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.jsonEncoder.encode(body)

        return try await send(request)
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

        return try Self.jsonDecoder.decode(Response.self, from: data)
    }

    private static var jsonEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }

    private static var jsonDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [
                .withInternetDateTime,
                .withFractionalSeconds,
            ]

            if let date = fractionalFormatter.date(from: value) {
                return date
            }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO 8601 date: \(value)"
            )
        }
        return decoder
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
