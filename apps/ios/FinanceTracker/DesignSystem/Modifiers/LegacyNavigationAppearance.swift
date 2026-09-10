import UIKit

/// Styles the native back item, retaining UIKit's pop gesture and navigation menu.
enum LegacyNavigationAppearance {
    static func needsUpdate(_ navigationController: UINavigationController) -> Bool {
        let bar = navigationController.navigationBar
        let itemAppearances = navigationController.viewControllers.flatMap { controller in
            let item = controller.navigationItem
            return [item.standardAppearance, item.compactAppearance, item.scrollEdgeAppearance, item.compactScrollEdgeAppearance]
        }
        return ([bar.standardAppearance, bar.compactAppearance, bar.scrollEdgeAppearance, bar.compactScrollEdgeAppearance] + itemAppearances)
            .compactMap { $0 }
            .contains { $0.backIndicatorImage.size.width != AppControlSize.minimumTapTarget }
    }

    static func apply(to navigationController: UINavigationController) {
        let bar = navigationController.navigationBar
        let image = backImage(traits: bar.traitCollection)
        func appearance(_ original: UINavigationBarAppearance?, transparent: Bool = false) -> UINavigationBarAppearance {
            let result = original?.copy() ?? UINavigationBarAppearance()
            if original == nil, transparent { result.configureWithTransparentBackground() }
            result.setBackIndicatorImage(image, transitionMaskImage: image)
            return result
        }
        bar.standardAppearance = appearance(bar.standardAppearance)
        bar.compactAppearance = appearance(bar.compactAppearance)
        bar.scrollEdgeAppearance = appearance(bar.scrollEdgeAppearance, transparent: true)
        bar.compactScrollEdgeAppearance = appearance(bar.compactScrollEdgeAppearance, transparent: true)
        navigationController.viewControllers.forEach { controller in
            let item = controller.navigationItem
            item.backButtonDisplayMode = .minimal
            if let original = item.standardAppearance { item.standardAppearance = appearance(original) }
            if let original = item.compactAppearance { item.compactAppearance = appearance(original) }
            if let original = item.scrollEdgeAppearance { item.scrollEdgeAppearance = appearance(original) }
            if let original = item.compactScrollEdgeAppearance { item.compactScrollEdgeAppearance = appearance(original) }
        }
    }

    private static func backImage(traits: UITraitCollection) -> UIImage {
        let size = CGSize(width: AppControlSize.minimumTapTarget, height: AppControlSize.minimumTapTarget)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let circle = UIBezierPath(ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5))
            UIColor.secondarySystemGroupedBackground.resolvedColor(with: traits).withAlphaComponent(0.9).setFill()
            circle.fill()
            UIColor.label.resolvedColor(with: traits).withAlphaComponent(0.08).setStroke()
            circle.lineWidth = 0.5
            circle.stroke()
            let chevron = UIImage(systemName: "chevron.backward", withConfiguration:
                UIImage.SymbolConfiguration(pointSize: 20, weight: .medium))?
                .withTintColor(UIColor.label.resolvedColor(with: traits), renderingMode: .alwaysOriginal)
            if let chevron {
                chevron.draw(at: CGPoint(x: (size.width - chevron.size.width) / 2,
                                        y: (size.height - chevron.size.height) / 2))
            }
        }
        .withRenderingMode(.alwaysOriginal)
        .withAlignmentRectInsets(UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 12))
    }
}
