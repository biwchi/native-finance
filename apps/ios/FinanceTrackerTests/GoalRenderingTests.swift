import SwiftUI
import XCTest
@testable import FinanceTracker

@MainActor
final class GoalRenderingTests: XCTestCase {
    func testFullSwipeRequestsConfirmationBeforeDeletingGoal() async throws {
        let repository = try LocalTestData.repository()
        let account = try LocalTestData.account(repository)
        let goals = GoalStore(repository: repository)
        let goal = try goals.save(name: "Dream car", accountID: account.id, targetAmount: "25000", icon: "car", color: .blue, deadline: nil)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = UIHostingController(rootView: NavigationStack { GoalsView() }
            .environmentObject(goals)
            .environmentObject(AccountStore(repository: repository))
            .environmentObject(TransactionStore(repository: repository)))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(600))
        let probe = try XCTUnwrap(swipeObservers(in: window).first)
        let width = probe.bounds.width
        probe.configuration.onBegin()
        probe.configuration.onChange(-width * 0.9, width)
        probe.configuration.onEnd(0, width, false)
        try await Task.sleep(for: .milliseconds(1000))
        XCTAssertNotNil(repository.snapshot.goals[goal.id], "Swiping must not delete before confirmation")
        let alert = try XCTUnwrap(window.rootViewController?.presentedViewController as? UIAlertController)
        XCTAssertEqual(alert.title, "Delete Dream car?")
        XCTAssertTrue(alert.actions.contains { $0.title == "Delete goal" && $0.style == .destructive })
        XCTAssertTrue(alert.actions.contains { $0.title == "Cancel" && $0.style == .cancel })
        let attachment = XCTAttachment(image: UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        })
        attachment.name = "Goals-delete-confirmation"
        attachment.lifetime = .keepAlways
        add(attachment)
        alert.dismiss(animated: false)
        XCTAssertNotNil(repository.snapshot.accounts[account.id])
        XCTAssertNotNil(repository.snapshot.goals[goal.id])
    }

    func testGoalsAndEditorsInBothAppearances() async throws {
        let repository = try LocalTestData.repository()
        let account = try repository.edit { try $0.saveAccount(name: "Dream car", currency: "USD", icon: "car", color: .blue, initialBalance: "14000") }
        let goals = GoalStore(repository: repository)
        let goal = try goals.save(name: "Dream car", accountID: account.id, targetAmount: "25000", icon: "car", color: .blue, deadline: "2026-12-31")
        let safety = try repository.edit { try $0.saveAccount(name: "Safety net", currency: "USD", icon: "shield-check", color: .purple, initialBalance: "6750") }
        _ = try goals.save(name: "Emergency fund", accountID: safety.id, targetAmount: "10000", icon: "shield-check", color: .purple, deadline: nil)
        let travel = try repository.edit { try $0.saveAccount(name: "Travel", currency: "USD", icon: "airplane", color: .orange, initialBalance: "3000") }
        _ = try goals.save(name: "Japan trip", accountID: travel.id, targetAmount: "3000", icon: "airplane", color: .amber, deadline: nil)
        let accounts = AccountStore(repository: repository)
        let transactions = TransactionStore(repository: repository)
        let emptyGoals = GoalStore(repository: try LocalTestData.repository())
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for scheme in [ColorScheme.light, .dark] {
            for size in [DynamicTypeSize.large, .accessibility3] {
                for (name, content) in [
                    ("List", AnyView(goalsPage)),
                    ("Empty", AnyView(goalsPage.environmentObject(emptyGoals))),
                    ("New", AnyView(Color.clear.appSheet(isPresented: .constant(true)) {
                        GoalEditorView(initialAccountID: account.id).presentationDetents([.large]).presentationDragIndicator(.visible)
                    })),
                    ("Edit", AnyView(Color.clear.appSheet(isPresented: .constant(true)) {
                        GoalEditorView(goal: goal).presentationDetents([.large]).presentationDragIndicator(.visible)
                    })),
                    ("Category-reference", AnyView(Color.clear.appSheet(isPresented: .constant(true)) {
                        CategoryEditorView(editor: CategoryEditor(category: nil, kind: .expense))
                            .presentationDetents([.large]).presentationDragIndicator(.visible)
                    })),
                    ("Recipient-reference", AnyView(Color.clear.appSheet(isPresented: .constant(true)) {
                        DebtEditorView(onSave: { _ in })
                            .presentationDetents([.large]).presentationDragIndicator(.visible)
                    }))
                ] {
                    let view = content.environmentObject(goals).environmentObject(accounts).environmentObject(transactions)
                        .environment(\.dynamicTypeSize, size).preferredColorScheme(scheme)
                    let controller = UIHostingController(rootView: view)
                    let window = UIWindow(windowScene: scene)
                    window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
                    window.rootViewController = controller
                    window.makeKeyAndVisible()
                    controller.view.frame = window.bounds
                    try await Task.sleep(for: .milliseconds(850))
                    controller.view.layoutIfNeeded()
                    if name == "New" || name == "Edit" {
                        let fields = textFields(in: window)
                        XCTAssertTrue(fields.contains { $0.isFirstResponder && $0.placeholder == "Goal name" })
                    }
                    window.endEditing(true)
                    // Hosted test windows do not reliably deliver the keyboard's hide notification.
                    NotificationCenter.default.post(name: UIResponder.keyboardDidHideNotification, object: nil)
                    try await Task.sleep(for: .milliseconds(350))
                    let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                        XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
                    }
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "Goals-\(name)-\(scheme)-\(size)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                    window.endEditing(true)
                    window.isHidden = true
                    window.rootViewController = nil
                }
            }
        }
    }

    private var goalsPage: some View {
        NavigationStack(path: .constant(["goals"])) {
            Text("Finances")
                .navigationDestination(for: String.self) { _ in GoalsView().legacyNavigationDestination() }
        }
    }

    private func textFields(in view: UIView) -> [UITextField] {
        (view as? UITextField).map { [$0] } ?? view.subviews.flatMap { textFields(in: $0) }
    }

    private func swipeObservers(in view: UIView) -> [CircleSwipeGesture.ObserverView] {
        (view as? CircleSwipeGesture.ObserverView).map { [$0] } ?? view.subviews.flatMap { swipeObservers(in: $0) }
    }
}
