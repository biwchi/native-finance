import Foundation
import CryptoKit

struct PendingMutation: Identifiable, Sendable {
    var id: UUID { mutation.mutationId }
    var mutation: SyncMutation
    var dependencies: [UUID]
    var attempts: Int
    var nextAttempt: Date
    var sent: Bool
    var issue: String?
}
