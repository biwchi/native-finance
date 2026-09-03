import Foundation

enum CategoryModelGate {
    static var isEnabled: Bool {
        Bundle.main.object(forInfoDictionaryKey: "FOUNDATION_CATEGORY_RESOLVER_ENABLED") as? Bool ?? false
    }
}
