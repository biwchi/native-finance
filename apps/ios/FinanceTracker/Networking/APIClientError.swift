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
