import Foundation

enum APIClientError: LocalizedError {
    case invalidResponse
    case requestFailed(status: Int, message: String?, code: String? = nil)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The backend returned an invalid response."
        case let .requestFailed(status, message, _):
            message ?? "The request failed with HTTP status \(status)."
        }
    }
}
