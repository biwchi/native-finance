import Foundation

struct APIErrorResponse: Decodable {
    let message: String
    let code: String?
}
