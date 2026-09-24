import SwiftUI

/// Keep small action sets visible. Larger sets share the same labels and roles in a menu.
struct AppRowActions: View {
    struct Action: Identifiable {
        let title: String
        let icon: String
        var role: ButtonRole? = nil
        let perform: () -> Void

        var id: String { title }
    }

    let actions: [Action]

    var body: some View {
        if actions.count > 2 {
            Menu {
                ForEach(actions) { action in
                    Button(role: action.role, action: action.perform) {
                        Label(action.title, icon: action.icon)
                    }
                }
            } label: {
                icon("more-vertical", title: "Actions", tint: .primary)
            }
            .accessibilityLabel("Actions")
        } else {
            HStack(spacing: AppSpacing.small) {
                ForEach(actions) { action in
                    Button(role: action.role, action: action.perform) {
                        icon(action.icon, title: action.title,
                             tint: action.role == .destructive ? AppColor.destructive : .primary)
                    }
                    .buttonStyle(ActionButtonStyle())
                    .accessibilityLabel(action.title)
                }
            }
        }
    }

    private func icon(_ name: String, title: String, tint: Color) -> some View {
        AppIcon(name, size: AppControlSize.iconButtonGlyph)
            .foregroundStyle(AppColor.iconForeground(for: tint))
            .frame(width: AppControlSize.minimumTapTarget, height: AppControlSize.minimumTapTarget)
            .background(tint.opacity(0.10), in: Circle())
            .modifier(CapsuleControlBackground(appearance: .glass))
            .contentShape(Circle())
            .accessibilityLabel(title)
    }

    private struct ActionButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .opacity(configuration.isPressed ? 0.78 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}
