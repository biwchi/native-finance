import Foundation
import CryptoKit

struct SyncMutation: Codable, Sendable {
    let clientId: UUID
    var mutationId: UUID
    var generation: Int
    let authoredAt: Date
    var changes: [SyncChange]
    var reset: Bool = false
    var workspaceId: UUID? = nil
    var recurrenceActions: [SyncRecurrenceAction]? = nil
}
