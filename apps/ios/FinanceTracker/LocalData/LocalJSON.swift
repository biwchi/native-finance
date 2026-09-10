import Foundation
import CryptoKit

enum LocalJSON {
    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer(); try c.encode(timestamp(date))
        }
        return e
    }
    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer(); let value = try c.decode(String.self)
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: value) { return date }
            f.formatOptions = [.withInternetDateTime]
            if let date = f.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid stored date")
        }
        return d
    }
    static func timestamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
    static func object<T: Encodable>(_ value: T) throws -> [String: JSONValue] {
        normalizeIDs(try decoder.decode([String: JSONValue].self, from: encoder.encode(value)))
    }
    private static func normalizeIDs(_ object: [String: JSONValue]) -> [String: JSONValue] {
        Dictionary(uniqueKeysWithValues: object.map { key, value in
            let normalized: JSONValue
            switch value {
            case .string(let text): normalized = (key == "id" || key.hasSuffix("Id")) && UUID(uuidString: text) != nil ? .string(text.lowercased()) : value
            case .object(let nested): normalized = .object(normalizeIDs(nested))
            case .array(let values): normalized = .array(values.map { if case .object(let nested) = $0 { return .object(normalizeIDs(nested)) }; return $0 })
            default: normalized = value
            }
            return (key, normalized)
        })
    }

    static func decode<T: Decodable>(_ type: T.Type, _ value: [String: JSONValue]) throws -> T {
        try decoder.decode(type, from: encoder.encode(value))
    }
}
