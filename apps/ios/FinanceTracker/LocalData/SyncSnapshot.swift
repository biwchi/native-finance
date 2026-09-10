import Foundation
import CryptoKit

struct SyncSnapshot: Codable, Sendable {
    let workspaceId: UUID
    let generation: Int
    let cursor: String
    let records: [SyncRecord]
    var hasMore: Bool? = nil
    var reset: Bool? = nil
}
