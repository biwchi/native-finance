import SwiftUI
import UIKit

/// SwiftUI has no section corner-radius API before iOS 26. Scope the UIKit
/// adjustment to this list and preserve its native corner masks and behavior.
struct LegacyListAppearance: UIViewRepresentable {
    func makeUIView(context: Context) -> ObserverView { ObserverView() }
    func updateUIView(_ view: ObserverView, context: Context) { view.scheduleUpdate() }
    static func dismantleUIView(_ view: ObserverView, coordinator: ()) { view.stopObserving() }

    final class ObserverView: UIView {
        private weak var collectionView: UICollectionView?
        private var observations: [NSKeyValueObservation] = []
        private var cornerObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]
        private var updateScheduled = false
        private weak var styledNavigationController: UINavigationController?
        private var navigationObservations: [NSKeyValueObservation] = []
        private var navigationItemObservations: [NSKeyValueObservation] = []
        private var navigationItems: [ObjectIdentifier] = []
        private var navigationStyle: UIUserInterfaceStyle?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: ObserverView, _: UITraitCollection) in
                view.scheduleUpdate()
            }
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }


        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { stopObserving() } else { scheduleUpdate() }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            scheduleUpdate()
        }

        func stopObserving() {
            observations.removeAll()
            cornerObservations.removeAll()
            collectionView = nil
            navigationObservations.removeAll()
            navigationItemObservations.removeAll()
            navigationItems.removeAll()
            styledNavigationController = nil
            navigationStyle = nil
        }

        func scheduleUpdate() {
            guard !updateScheduled else { return }
            updateScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.updateScheduled = false
                guard self.window != nil else { return }
                self.updateList()
            }
        }

        private func updateList() {
            var responder: UIResponder? = next
            while let current = responder {
                if let controller = current as? UIViewController,
                   let navigation = controller.navigationController {
                    if navigation !== styledNavigationController {
                        styledNavigationController = navigation
                        // SwiftUI can replace these appearances when toolbar visibility changes.
                        navigationObservations = [
                            navigation.navigationBar.observe(\.standardAppearance) { [weak self] _, _ in self?.scheduleUpdate() },
                            navigation.navigationBar.observe(\.compactAppearance) { [weak self] _, _ in self?.scheduleUpdate() },
                            navigation.navigationBar.observe(\.scrollEdgeAppearance) { [weak self] _, _ in self?.scheduleUpdate() },
                            navigation.navigationBar.observe(\.compactScrollEdgeAppearance) { [weak self] _, _ in self?.scheduleUpdate() },
                            navigation.navigationBar.observe(\.items) { [weak self] _, _ in self?.scheduleUpdate() }
                        ]
                    }
                    let items = navigation.viewControllers.map(\.navigationItem)
                    let identifiers = items.map(ObjectIdentifier.init)
                    if identifiers != navigationItems {
                        navigationItems = identifiers
                        navigationItemObservations = items.flatMap { item in
                            [item.observe(\.standardAppearance) { [weak self] _, _ in self?.scheduleUpdate() },
                             item.observe(\.compactAppearance) { [weak self] _, _ in self?.scheduleUpdate() },
                             item.observe(\.scrollEdgeAppearance) { [weak self] _, _ in self?.scheduleUpdate() },
                             item.observe(\.compactScrollEdgeAppearance) { [weak self] _, _ in self?.scheduleUpdate() }]
                        }
                    }
                    if navigationStyle != traitCollection.userInterfaceStyle || LegacyNavigationAppearance.needsUpdate(navigation) {
                        navigationStyle = traitCollection.userInterfaceStyle
                        LegacyNavigationAppearance.apply(to: navigation)
                    }
                    break
                }
                responder = current.next
            }
            if collectionView == nil {
                var ancestor = superview
                while let candidate = ancestor {
                    if let list = Self.findCollection(in: candidate) {
                        collectionView = list
                        observations = [
                            list.observe(\.contentOffset) { [weak self] _, _ in self?.scheduleUpdate() },
                            list.observe(\.contentSize) { [weak self] _, _ in self?.scheduleUpdate() },
                            list.observe(\.bounds) { [weak self] _, _ in self?.scheduleUpdate() }
                        ]
                        break
                    }
                    ancestor = candidate.superview
                }
            }
            guard let collectionView else { return }
            let visibleCells = collectionView.visibleCells
            let identifiers = Set(visibleCells.map { ObjectIdentifier($0.layer) })
            cornerObservations = cornerObservations.filter { identifiers.contains($0.key) }
            for cell in visibleCells {
                let layer = cell.layer
                // Headers and deliberately square/transparent rows remain untouched.
                guard layer.cornerRadius > 0 else { continue }
                Self.round(layer)
                let id = ObjectIdentifier(layer)
                if cornerObservations[id] == nil {
                    cornerObservations[id] = layer.observe(\.cornerRadius) { layer, _ in
                        Self.round(layer)
                    }
                }
            }
        }

        private static func round(_ layer: CALayer) {
            guard layer.cornerRadius > 0, layer.cornerRadius != AppRadius.groupedSection else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.cornerRadius = AppRadius.groupedSection
            layer.cornerCurve = .continuous
            CATransaction.commit()
        }

        private static func findCollection(in view: UIView) -> UICollectionView? {
            if let collection = view as? UICollectionView { return collection }
            for child in view.subviews {
                if let collection = findCollection(in: child) { return collection }
            }
            return nil
        }
    }
}

extension View {
    @ViewBuilder
    func legacyListAppearance(usesCompactTopSpacing: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            self
                .legacySheetAppearance()
                .contentMargins(.horizontal, AppSpacing.large, for: .scrollContent)
                .contentMargins(.top, usesCompactTopSpacing ? AppSpacing.small : nil, for: .scrollContent)
                .textCase(nil)
                .background(LegacyListAppearance().allowsHitTesting(false).accessibilityHidden(true))
        }
    }

    @ViewBuilder
    func legacyListRows(verticalPadding: CGFloat = 15) -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            self.listRowInsets(EdgeInsets(top: verticalPadding, leading: AppSpacing.large,
                                         bottom: verticalPadding, trailing: AppSpacing.large))
        }
    }

}
