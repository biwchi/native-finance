import Foundation

struct ExchangeRateQuote: Codable, Equatable {
    let currency: String
    let rate: String
    let effectiveDate: String
}
