import Foundation

protocol RateTransport: Sendable { func fullExchangeRateTable() async throws -> ExchangeRateSnapshot }
