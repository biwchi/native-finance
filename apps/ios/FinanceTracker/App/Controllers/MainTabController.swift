import SwiftUI
import UIKit

struct MainTabController: UIViewControllerRepresentable {
    let accountStore: AccountStore
    let budgetStore: BudgetStore
    let exchangeRateStore: ExchangeRateStore
    let transactionStore: TransactionStore
    var onAdd: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onAdd: onAdd)
    }

    func makeUIViewController(context: Context) -> UITabBarController {
        let controller = UITabBarController()
        let coordinator = context.coordinator
        controller.delegate = context.coordinator
        controller.view.tintColor = UIColor(AppColor.accent)

        // Keep the same hosting controllers (and navigation/scroll state) when the sheet opens.
        let home = hostingController(DashboardView(), title: "Home", iconName: "home-simple")
        let activity = hostingController(ActivityView(), title: "Activity", iconName: "list")
        let plan = hostingController(PlanView(), title: "Plan", iconName: "percentage-circle")
        let settingsView = SettingsView { [weak controller, weak coordinator] isVisible in
            if #available(iOS 18.0, *) {
                controller?.setTabBarHidden(isVisible, animated: true)
            } else {
                controller?.tabBar.isHidden = isVisible
            }
            coordinator?.setAddButtonHidden(isVisible)
        }
        let settings = hostingController(settingsView, title: "Settings", iconName: "settings")
        let add = context.coordinator.addViewController
        add.tabBarItem = UITabBarItem(title: "Add", image: AppIcons.uiImage(named: "plus"), tag: 0)

        if #available(iOS 18.0, *) {
            let addTab = UISearchTab { _ in add }
            if #available(iOS 26.0, *) {
                // Keep the search-tab slot only for its native trailing placement. A real
                // prominent-glass button is laid over it below.
                addTab.title = ""
                addTab.image = UIImage()
                addTab.isEnabled = false
            } else {
                addTab.title = "Add"
                addTab.image = AppIcons.uiImage(named: "plus")
            }
            controller.tabs = [
                UITab(title: "Home", image: home.tabBarItem.image, identifier: "home") { _ in home },
                UITab(title: "Activity", image: activity.tabBarItem.image, identifier: "activity") { _ in activity },
                UITab(title: "Plan", image: plan.tabBarItem.image, identifier: "plan") { _ in plan },
                UITab(title: "Settings", image: settings.tabBarItem.image, identifier: "settings") { _ in settings },
                addTab
            ]
            if #available(iOS 26.0, *) {
                installAddButton(in: controller, coordinator: coordinator)
            }
        } else {
            controller.viewControllers = [home, activity, plan, settings, add]
        }
        return controller
    }

    @available(iOS 26.0, *)
    private func installAddButton(
        in controller: UITabBarController,
        coordinator: Coordinator
    ) {
        let buttonController = UIHostingController(
            rootView: PrimaryIconButton(
                "Add",
                iconName: "plus",
                iconSize: 26,
                appearance: .glassProminent
            ) { [weak coordinator] in
                coordinator?.onAdd()
            }
            .dynamicTypeSize(.large)
            .frame(width: 62, height: 62)
        )
        buttonController.view.backgroundColor = .clear
        buttonController.view.translatesAutoresizingMaskIntoConstraints = false

        controller.addChild(buttonController)
        controller.view.addSubview(buttonController.view)
        buttonController.didMove(toParent: controller)

        NSLayoutConstraint.activate([
            buttonController.view.widthAnchor.constraint(equalToConstant: 62),
            buttonController.view.heightAnchor.constraint(equalToConstant: 62),
            buttonController.view.trailingAnchor.constraint(
                equalTo: controller.view.safeAreaLayoutGuide.trailingAnchor,
                constant: -21
            ),
            buttonController.view.topAnchor.constraint(equalTo: controller.tabBar.topAnchor),
        ])
        coordinator.addButtonView = buttonController.view
    }

    func updateUIViewController(_ controller: UITabBarController, context: Context) {
        context.coordinator.onAdd = onAdd
    }

    private func hostingController<Content: View>(
        _ content: Content, title: String, iconName: String
    ) -> UIViewController {
        let controller = UIHostingController(
            rootView: content
                .tint(AppColor.accent)
                .environmentObject(accountStore)
                .environmentObject(budgetStore)
                .environmentObject(exchangeRateStore)
                .environmentObject(transactionStore)
        )
        controller.tabBarItem = UITabBarItem(title: title, image: AppIcons.uiImage(named: iconName), tag: 0)
        return controller
    }

    final class Coordinator: NSObject, UITabBarControllerDelegate {
        let addViewController = UIViewController()
        weak var addButtonView: UIView?
        var onAdd: () -> Void

        init(onAdd: @escaping () -> Void) {
            self.onAdd = onAdd
        }

        func setAddButtonHidden(_ isHidden: Bool) {
            addButtonView?.isHidden = isHidden
        }

        @available(iOS 18.0, *)
        func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
            shouldSelect(tab.viewController)
        }

        func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
            shouldSelect(viewController)
        }

        private func shouldSelect(_ viewController: UIViewController?) -> Bool {
            guard viewController === addViewController else { return true }

            // Veto selection before UIKit transitions to the empty Add tab. Rejecting a
            // SwiftUI selection binding happens too late to prevent a visible flash.
            onAdd()
            return false
        }
    }
}
