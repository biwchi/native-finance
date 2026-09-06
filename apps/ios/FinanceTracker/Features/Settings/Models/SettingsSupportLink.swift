import Foundation

enum SettingsSupportLink: String, CaseIterable, Identifiable {
    case review = "Review in App Store"
    case help = "Help and support"
    case privacy = "Privacy policy"
    case terms = "Terms of use"

    var id: Self { self }
    var icon: String {
        switch self {
        case .review: "star"
        case .help: "help-circle"
        case .privacy: "shield"
        case .terms: "page"
        }
    }

    var configurationKey: String {
        switch self {
        case .review: "APP_STORE_REVIEW_URL"
        case .help: "SUPPORT_URL"
        case .privacy: "PRIVACY_POLICY_URL"
        case .terms: "TERMS_OF_USE_URL"
        }
    }

    func url(bundle: Bundle = .main) -> URL? {
        guard let value = bundle.object(forInfoDictionaryKey: configurationKey) as? String,
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              (scheme == "https" && url.host != nil) || (self == .help && scheme == "mailto")
        else { return nil }
        return url
    }
}
