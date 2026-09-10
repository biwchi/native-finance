import Foundation
import CryptoKit

struct SyncRecord: Codable, Equatable, Sendable {
    let entity: String
    let key: String
    let version: String
    let data: [String: JSONValue]?
    var identity: String { "\(entity):\(key)" }
}
