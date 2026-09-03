import Foundation

struct CategoryResolution: Equatable {
    let categoryID: UUID
    let confidence: Double
    let source: CategoryResolutionSource
}
