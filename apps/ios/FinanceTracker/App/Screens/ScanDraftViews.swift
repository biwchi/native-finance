import SwiftUI
import UIKit

struct BottomBarBlurModifier: AnimatableModifier {
    var radius: CGFloat

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}

enum BottomBarVisibilityMotion {
    static func transition(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }

        let clearBlur = BottomBarBlurModifier(radius: 0)
        return .asymmetric(
            insertion: .scale(scale: 0.82, anchor: .bottom)
                .combined(with: .opacity)
                .combined(with: .modifier(
                    active: BottomBarBlurModifier(radius: 10),
                    identity: clearBlur
                )),
            removal: .scale(scale: 0.88, anchor: .bottom)
                .combined(with: .opacity)
                .combined(with: .modifier(
                    active: BottomBarBlurModifier(radius: 7),
                    identity: clearBlur
                ))
        )
    }

    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: 0.12)
            : .spring(duration: 0.38, bounce: 0.16)
    }
}

extension View {
    func reportScanDraftBottomBarHeight(_ action: @escaping (CGFloat) -> Void) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { action(proxy.size.height) }
                    .onChange(of: proxy.size.height) { _, height in action(height) }
            }
        }
        .onDisappear { action(0) }
    }
}

struct ScanDraftActivityPill: View {
    @EnvironmentObject private var store: ScanDraftStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onReview: (UUID) -> Void
    let onOpenDrafts: () -> Void
    let onReplace: (UUID) -> Void
    let onManualEntry: (UUID) -> Void
    var excludingID: UUID? = nil
    var isVisible = true
    @State private var discardID: UUID?
    @State private var retainedPillHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            if isVisible, let item = foregroundItem {
                HStack(spacing: AppSpacing.small) {
                    ScanDraftThumbnail(item: item)

                    Button(action: primaryAction) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(status(for: item))
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .contentTransition(.opacity)
                            if let detail = detail(for: item) {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .contentTransition(.opacity)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .animation(.easeInOut(duration: 0.18), value: store.revision)
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: AppControlSize.minimumTapTarget)

                    actions(for: item)
                }
                .padding(.leading, AppSpacing.compact)
                .padding(.trailing, AppSpacing.small)
                .padding(.vertical, AppSpacing.compact)
                .frame(maxWidth: 560)
                .background(.regularMaterial, in: Capsule())
                .overlay { Capsule().strokeBorder(Color.secondary.opacity(0.16), lineWidth: 1) }
                .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
                .padding(.horizontal, AppSpacing.medium)
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { retainPillHeight(proxy.size.height) }
                            .onChange(of: proxy.size.height) { _, height in
                                retainPillHeight(height)
                            }
                    }
                }
                .animation(
                    reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.32, bounce: 0.12),
                    value: store.revision
                )
                .confirmationDialog(
                    "Discard these drafts?",
                    isPresented: Binding(
                        get: { discardID != nil },
                        set: { if !$0 { discardID = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Discard", role: .destructive) {
                        if let discardID { store.remove(discardID) }
                        discardID = nil
                    }
                    Button("Keep drafts", role: .cancel) { discardID = nil }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(accessibilityLabel(for: item))
                .transition(BottomBarVisibilityMotion.transition(reduceMotion: reduceMotion))
            }
        }
        .frame(maxWidth: .infinity, minHeight: retainedPillHeight, alignment: .bottom)
        .animation(
            BottomBarVisibilityMotion.animation(reduceMotion: reduceMotion),
            value: isVisible && foregroundItem != nil
        )
    }

    private func retainPillHeight(_ height: CGFloat) {
        guard height > retainedPillHeight else { return }
        retainedPillHeight = height
    }

    @ViewBuilder
    private func actions(for item: ScanDraftItem) -> some View {
        if visibleItems.count > 1 {
            AppRowActions(actions: [
                .init(title: "Open drafts", icon: "more-vertical") { onOpenDrafts() },
            ])
        } else {
            ScanDraftActions(item: item, onReview: onReview, onReplace: onReplace,
                             onManualEntry: onManualEntry, onDiscard: { discardID = $0 })
        }
    }

    private func primaryAction() {
        guard let item = foregroundItem else { return }
        if visibleItems.count == 1, item.state == .ready, item.review != nil {
            onReview(item.id)
        } else {
            onOpenDrafts()
        }
    }

    private func status(for item: ScanDraftItem) -> String {
        guard visibleItems.count == 1 else {
            return "\(visibleItems.count) drafts"
        }

        return itemStatus(for: item)
    }

    private func itemStatus(for item: ScanDraftItem) -> String {
        let base: String
        switch item.state {
        case .preparing: base = "Preparing draft"
        case .queued: base = "Draft queued"
        case .running: base = "Reading transactions"
        case .ready:
            let count = item.review?.drafts.count ?? 0
            base = "\(count) draft\(count == 1 ? "" : "s") ready"
        case .failed: base = item.failure?.code == .emptyExtraction ? "No transactions found" : "Draft needs attention"
        case .interrupted: base = "Draft interrupted"
        }
        return base
    }

    private func detail(for item: ScanDraftItem) -> String? {
        if visibleItems.count > 1 {
            let ready = visibleItems.filter { $0.state == .ready }.count
            let waiting = visibleItems.filter { $0.state == .preparing || $0.state == .queued }.count
            let counts = [
                ready > 0 ? "\(ready) ready" : nil,
                waiting > 0 ? "\(waiting) waiting" : nil,
            ].compactMap { $0 }
            return counts.isEmpty ? nil : counts.joined(separator: ", ")
        }
        if item.state == .failed || item.state == .interrupted {
            return item.failure?.message
        }
        return item.source.displayName
    }

    private func accessibilityLabel(for item: ScanDraftItem) -> String {
        if visibleItems.count > 1 {
            return [status(for: item), detail(for: item), itemStatus(for: item)]
                .compactMap { $0 }
                .joined(separator: ". ")
        }
        return [status(for: item), detail(for: item)].compactMap { $0 }.joined(separator: ". ")
    }

    private var visibleItems: [ScanDraftItem] {
        store.items.filter { $0.id != excludingID }
    }

    private var foregroundItem: ScanDraftItem? {
        visibleItems.first(where: { $0.state == .running })
            ?? visibleItems.first(where: { $0.state == .preparing || $0.state == .queued })
            ?? visibleItems.first(where: { $0.state == .ready })
            ?? visibleItems.first
    }
}

private struct ScanDraftThumbnail: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: ScanDraftItem
    @State private var pulses = false

    var body: some View {
        Group {
            if let data = item.thumbnailData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                AppIcon(item.source.kind == .quickEntry ? "edit-pencil" : item.source.kind == .document ? "file" : "media-image", size: 20)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 40, height: 40)
        .background(Color.secondary.opacity(0.10), in: Circle())
        .clipShape(Circle())
        .scaleEffect(isProcessing && !reduceMotion && pulses ? 0.94 : 1)
        .onAppear { updatePulse() }
        .onChange(of: item.state) { _, _ in updatePulse() }
        .accessibilityHidden(true)
    }

    private var isProcessing: Bool {
        item.state == .preparing || item.state == .queued || item.state == .running
    }

    private func updatePulse() {
        pulses = false
        guard isProcessing, !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
            pulses = true
        }
    }
}

struct ScanDraftsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ScanDraftStore
    let onReview: (UUID) -> Void
    let onReplace: (UUID) -> Void
    let onManualEntry: (UUID) -> Void
    @State private var discardID: UUID?

    var body: some View {
        NavigationStack {
            AppList {
                AppSection {
                    ForEach(store.items) { item in
                        HStack(spacing: AppSpacing.medium) {
                            ScanDraftThumbnail(item: item)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.source.displayName)
                                    .font(.headline)
                                    .lineLimit(2)
                                Text(rowStatus(item))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                if let message = item.failure?.message,
                                   item.state == .failed || item.state == .interrupted {
                                    Text(message)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            rowAction(item)
                        }
                        .padding(.vertical, AppSpacing.extraSmall)
                    }
                }
            }
            .animateListChanges(value: store.items.map(\.id))
            .onChange(of: store.items.isEmpty) { _, isEmpty in
                if isEmpty { dismiss() }
            }
            .navigationTitle("Drafts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .legacyToolbarControl()
                }
            }
            .confirmationDialog(
                "Discard these drafts?",
                isPresented: Binding(
                    get: { discardID != nil },
                    set: { if !$0 { discardID = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Discard", role: .destructive) {
                    if let discardID { store.remove(discardID) }
                    self.discardID = nil
                }
                Button("Keep drafts", role: .cancel) { discardID = nil }
            }
        }
    }

    private func rowAction(_ item: ScanDraftItem) -> some View {
        ScanDraftActions(
            item: item,
            onReview: onReview,
            onReplace: { id in dismiss(); onReplace(id) },
            onManualEntry: { id in dismiss(); onManualEntry(id) },
            onDiscard: { discardID = $0 }
        )
    }

    private func rowStatus(_ item: ScanDraftItem) -> String {
        switch item.state {
        case .preparing: return "Preparing"
        case .queued: return "Queued"
        case .running: return "Reading transactions"
        case .ready:
            let count = item.review?.drafts.count ?? 0
            return "\(count) draft\(count == 1 ? "" : "s") ready"
        case .failed: return item.failure?.code == .emptyExtraction ? "No transactions found" : "Failed"
        case .interrupted: return "Interrupted"
        }
    }
}
