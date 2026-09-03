import SwiftUI

/// Asset images need explicit sizing; unlike SF Symbols, they do not inherit a font size.
struct AppIcon: View {
    let name: String
    @ScaledMetric private var size: CGFloat

    init(_ name: String, size: CGFloat = 20, relativeTo textStyle: Font.TextStyle = .body) {
        self.name = name
        _size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
    }

    var body: some View {
        AppIcons.resolve(name).image().renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
