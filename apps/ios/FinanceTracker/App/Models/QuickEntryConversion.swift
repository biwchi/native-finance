import Foundation

struct QuickEntryConversion: Codable, Equatable {
    let originalAmount: String
    let originalCurrency: String
    let convertedAmount: String
    let convertedCurrency: String
    let rate: String
    let effectiveDate: String
    let stale: Bool
}
