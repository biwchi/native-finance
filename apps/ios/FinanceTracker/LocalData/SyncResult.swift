import Foundation
import CryptoKit

struct SyncResult: Codable, Sendable {
    let mutationId: UUID
    let status: String
    let generation: Int
    let records: [SyncRecord]
    let message: String?
}
