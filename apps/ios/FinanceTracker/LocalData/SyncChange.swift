import Foundation
import CryptoKit

struct SyncChange: Codable, Equatable, Sendable {
    let entity: String
    let key: String
    var baseVersion: String?
    var data: [String: JSONValue]?
    var identity: String { "\(entity):\(key)" }
    var origin: String? = nil
    enum CodingKeys: String, CodingKey { case entity, key, baseVersion, data, origin }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(entity, forKey: .entity); try c.encode(key, forKey: .key)
        try c.encode(baseVersion, forKey: .baseVersion); try c.encode(data, forKey: .data); try c.encodeIfPresent(origin, forKey: .origin)
    }
}
