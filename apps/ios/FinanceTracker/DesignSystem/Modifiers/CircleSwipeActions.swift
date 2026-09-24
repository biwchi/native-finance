import SwiftUI
import UIKit

/// Actions are declared from right to left, matching the native trailing-swipe order.
extension View {
    func circleSwipeActions(isEnabled: Bool = true, usesCardLayout: Bool = false,
                            @CircleSwipeActionBuilder actions: () -> [CircleSwipeAction]) -> some View {
        modifier(CircleSwipeActions(isEnabled: isEnabled, usesCardLayout: usesCardLayout, actions: actions()))
    }
}

private struct CircleSwipeActions: ViewModifier {
    @Environment(\.isEnabled) private var environmentEnabled
    @Environment(\.editMode) private var editMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var motion = CircleSwipeMotion()
    @State private var isPerforming = false
    @State private var isRemoving = false
    @State private var rowWidth: CGFloat = 0
    @State private var removalStart: CGFloat = 0
    @State private var dragStart: CGFloat = 0
    @State private var isArmed = false
    @State private var id = UUID()
    let isEnabled: Bool
    let usesCardLayout: Bool
    let actions: [CircleSwipeAction]

    private var enabled: Bool { isEnabled && environmentEnabled && editMode?.wrappedValue.isEditing != true }
    private var reveal: CGFloat { motion.reveal }
    private var railWidth: CGFloat { CGFloat(actions.count) * CircleSwipeMetrics.actionWidth }
    private var expansion: CGFloat { max(0, reveal - railWidth) }
    private var actionOpacity: CGFloat {
        let revealOpacity = min(1, reveal / 20)
        guard isRemoving else { return revealOpacity }
        let remaining = (rowWidth - reveal) / max(1, rowWidth - removalStart)
        return revealOpacity * min(1, max(0, remaining))
    }
    private static let didOpen = Notification.Name("CircleSwipeActions.didOpen")

    func body(content: Content) -> some View {
        if actions.isEmpty {
            content
        } else {
            content
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, usesCardLayout ? 0 : AppSpacing.large)
                .padding(.vertical, usesCardLayout ? 0 : 15)
                .offset(x: -reveal)
                .allowsHitTesting(reveal == 0)
                .overlay(alignment: .trailing) {
                    HStack(spacing: 0) {
                        ForEach(actions.indices.reversed(), id: \.self) { index in
                            let action = actions[index]
                            let growth = index == 0 ? expansion : 0
                            Button { perform(action) } label: {
                                VStack(spacing: 4) {
                                    AppIcon(action.icon, size: 22)
                                        .frame(width: 44 + growth, height: 44)
                                        .background(action.tint.opacity(0.14), in: Capsule())
                                    Text(action.title)
                                        .font(.caption)
                                        .foregroundStyle(Color.primary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.65)
                                }
                                .frame(width: CircleSwipeMetrics.actionWidth + growth)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(CircleSwipeButtonStyle(tint: action.tint))
                            .accessibilityLabel(action.title)
                            .accessibilityIdentifier("circle-swipe-action.\(index)")
                            .disabled(!enabled || isPerforming || !action.isEnabled)
                        }
                    }
                    .frame(width: railWidth + expansion)
                    .offset(x: max(0, railWidth - reveal))
                    .opacity(actionOpacity)
                    .allowsHitTesting(reveal > 0)
                    .accessibilityHidden(reveal == 0)
                }
                .clipped()
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { rowWidth = $0 }
                .listRowInsets(EdgeInsets())
                .alignmentGuide(.listRowSeparatorLeading) { _ in AppSpacing.large }
                .listRowSeparator(usesCardLayout || reveal > 0 ? .hidden : .automatic)
                .listRowBackground(
                    Group {
                        if usesCardLayout {
                            // Cards supply their own surface, which moves with the content.
                            Color.clear
                        } else {
                            // Move the surface by exactly the same distance as its content.
                            // Native cell masks retain the section corners while closed;
                            // the exposed trailing edge uses the app radius during a swipe.
                            UnevenRoundedRectangle(
                                bottomTrailingRadius: min(1, reveal / 32) * AppRadius.groupedSection,
                                topTrailingRadius: min(1, reveal / 32) * AppRadius.groupedSection,
                                style: .continuous
                            )
                            .fill(AppColor.elevatedSurface)
                            .offset(x: -reveal)
                            .clipped()
                        }
                    }
                )
                .background {
                    CircleSwipeGesture(isEnabled: enabled && !isPerforming, revealedWidth: reveal,
                                       onBegin: {
                        guard enabled, !isPerforming else { return }
                        motion.beginDrag()
                        dragStart = reveal
                        NotificationCenter.default.post(name: Self.didOpen, object: id)
                    }, onChange: { translation, width in
                        guard enabled, !isPerforming else { return }
                        motion.drag(to: min(width, max(0, dragStart - translation)))
                        let armed = actions.first?.isEnabled == true && reveal >= CircleSwipeMetrics.fullSwipeThreshold(
                            width: width, actionCount: actions.count)
                        if armed != isArmed {
                            isArmed = armed
                            if armed { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
                        }
                    }, onEnd: { velocity, width, cancelled in
                        guard enabled else { close(); return }
                        let destination = cancelled ? .closed : CircleSwipeMetrics.destination(
                            reveal: reveal, velocity: velocity, width: width, actionCount: actions.count,
                            canCommit: enabled && actions.first?.isEnabled == true)
                        switch destination {
                        case .commit:
                            if let action = actions.first {
                                perform(action, fullSwipeWidth: width, velocity: -velocity)
                            }
                        case .open:
                            isArmed = false
                            motion.settle(to: railWidth, velocity: -velocity, reduceMotion: reduceMotion)
                        case .closed: close(velocity: cancelled ? 0 : -velocity)
                        }
                    }, onClose: { close() })
                }
                .accessibilityActions {
                    ForEach(actions.indices, id: \.self) { index in
                        let action = actions[index]
                        if enabled && action.isEnabled {
                            Button(action.title) { perform(action) }
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: Self.didOpen)) { notification in
                    if notification.object as? UUID != id { close() }
                }
                .onChange(of: enabled) { _, value in
                    if !value, !isRemoving {
                        isPerforming = false
                        close()
                    }
                }
                .onDisappear {
                    // List keeps the disappearing cell alive during its collapse.
                    // Let its horizontal exit continue while the following rows move up.
                    if !isRemoving {
                        motion.reset()
                        isArmed = false
                        isPerforming = false
                    }
                }
        }
    }

    private func close(velocity: CGFloat = 0) {
        guard !isPerforming else { return }
        isArmed = false
        motion.settle(to: 0, velocity: velocity, reduceMotion: reduceMotion)
    }

    private func perform(_ action: CircleSwipeAction, fullSwipeWidth: CGFloat? = nil, velocity: CGFloat = 0) {
        guard enabled, action.isEnabled, !isPerforming else { return }
        if let deletion = action.deletion {
            remove(using: deletion, width: fullSwipeWidth ?? rowWidth, velocity: velocity)
            return
        }
        isPerforming = true
        isArmed = false
        // Let the gesture finish before deletion or sheet presentation changes the row.
        // Full swipes finish expanding; button taps first tuck the actions away.
        motion.settle(to: fullSwipeWidth ?? 0, velocity: velocity, reduceMotion: reduceMotion) {
            action.action()
            isPerforming = false
            // Confirmation and edit actions leave the row in the list.
            motion.settle(to: 0, reduceMotion: reduceMotion)
        }
    }

    private func remove(using deletion: @escaping () async -> Bool, width: CGFloat, velocity: CGFloat) {
        isPerforming = true
        isRemoving = true
        isArmed = false
        removalStart = reveal
        // Start the write alongside the exit so List can close the gap immediately.
        // This task also survives navigation away from the disappearing row.
        motion.settle(to: width, velocity: velocity, reduceMotion: reduceMotion)
        Task { @MainActor in
            let removed = await deletion()
            guard isRemoving else { return }
            if !removed {
                isRemoving = false
                isPerforming = false
                motion.settle(to: 0, reduceMotion: reduceMotion)
            }
        }
    }
}
