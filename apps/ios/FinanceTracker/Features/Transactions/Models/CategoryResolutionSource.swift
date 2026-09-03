import Foundation

enum CategoryResolutionSource: String, Equatable {
    case exactHistory
    case fuzzyHistory
    case seed
    case embedding
    case foundationModel
}
