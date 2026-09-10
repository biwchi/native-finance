import Foundation
import CryptoKit

struct SyncRecurrenceAction: Codable, Sendable {
    let scheduleId: UUID
    let action: String
    let targetScheduledFor: Date
    let retainedTransactionId: UUID?
    var effectiveAt: Date? = nil
}
