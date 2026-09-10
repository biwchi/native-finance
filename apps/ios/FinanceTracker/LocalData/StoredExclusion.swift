import Foundation
import GRDB

struct StoredExclusion: Codable, Equatable, Sendable { let id: UUID; let scheduleId: UUID; let scheduledFor: Date }
