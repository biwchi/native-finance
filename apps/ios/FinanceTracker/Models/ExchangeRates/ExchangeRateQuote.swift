import Foundation

struct ExchangeRateQuote: Codable, Equatable, Sendable {
    let currency: String
    let rate: String
    let effectiveDate: String
}
