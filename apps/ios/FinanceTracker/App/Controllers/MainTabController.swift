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
        controller.delegate = context.coordinator
        controller.view.tintColor = UIColor(AppColor.accent)

        // Keep the same hosting controllers (and navigation/scroll state) when the sheet opens.
        let home = hostingController(DashboardView(), title: "Home", iconName: "home-simple")
        let activity = hostingController(ActivityView(), title: "Activity", iconName: "list")
        let plan = hostingController(PlanView(), title: "Plan", iconName: "percentage-circle")
        let settingsView = SettingsView { [weak controller] isVisible in
            if #available(iOS 18.0, *) {
                controller?.setTabBarHidden(isVisible, animated: true)
            } else {
                controller?.tabBar.isHidden = isVisible
            }
        }
        let settings = hostingController(settingsView, title: "Settings", iconName: "settings")
        let add = context.coordinator.addViewController
        add.tabBarItem = UITabBarItem(title: "Add", image: AppIcons.uiImage(named: "plus"), tag: 0)

        if #available(iOS 18.0, *) {
            let addTab = UISearchTab { _ in add }
            addTab.title = "Add"
            addTab.image = AppIcons.uiImage(named: "plus")
            controller.tabs = [
                UITab(title: "Home", image: home.tabBarItem.image, identifier: "home") { _ in home },
                UITab(title: "Activity", image: activity.tabBarItem.image, identifier: "activity") { _ in activity },
                UITab(title: "Plan", image: plan.tabBarItem.image, identifier: "plan") { _ in plan },
                UITab(title: "Settings", image: settings.tabBarItem.image, identifier: "settings") { _ in settings },
                addTab
            ]
        } else {
            controller.viewControllers = [home, activity, plan, settings, add]
        }
        return controller
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
        var onAdd: () -> Void

        init(onAdd: @escaping () -> Void) {
            self.onAdd = onAdd
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
