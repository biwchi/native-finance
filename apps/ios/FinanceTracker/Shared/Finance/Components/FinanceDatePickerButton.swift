import SwiftUI

struct FinanceDatePickerButton: View {
    private static let maximumSwipePeriods = 3

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Binding var selection: FinanceDateFilter
    @State private var isShowingFilter = false
    @State private var savedCustom: FinanceDateFilter?
    @GestureState private var isDragging = false
    @State private var contentOffset: CGFloat = 0
    @State private var isSettling = false
    @State private var labelWidth: CGFloat = 1
    @State private var isPressed = false
    @State private var isHolding = false
    @State private var allowsMultiplePeriods = false

    var body: some View {
        HStack(spacing: 0) {
            periodButton("Previous period", symbol: "chevron.backward", offset: -1)

            Button {
                guard !isSettling else { return }
                isShowingFilter = true
            } label: {
                labelSizing
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Choose date filter")
            .accessibilityIdentifier("date-filter-menu")
            .accessibilityValue(selection.label(calendar: calendar, locale: locale))
            .accessibilityHint(selection.preset == .allTime
                ? "Opens period filters and custom date ranges"
                : "Tap to choose a date range. Swipe right for the previous period or left for the next. Keep holding while you swipe to scroll up to three periods.")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: navigate(by: 1)
                case .decrement: navigate(by: -1)
                @unknown default: break
                }
            }

            periodButton("Next period", symbol: "chevron.forward", offset: 1)
        }
        .buttonStyle(ControlButtonStyle(isPressed: $isPressed))
        .overlay { periodLabels }
        .modifier(ContainerSurface(reduceTransparency: reduceTransparency, isEnabled: isEnabled))
        .contentShape(Capsule())
        .highPriorityGesture(periodDrag)
        .frame(maxWidth: .infinity, alignment: .center)
        .sheet(isPresented: $isShowingFilter) {
            FinanceDateFilterSheet(selection: selection, savedCustom: savedCustom, calendar: calendar) { result, custom in
                selection = result
                savedCustom = custom
            }
        }
        .onAppear { rememberCustom(selection) }
        .task(id: isPressActive) {
            guard isPressActive else {
                if !isSettling {
                    isHolding = false
                    allowsMultiplePeriods = false
                }
                return
            }
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            guard !Task.isCancelled, isPressActive else { return }
            isHolding = true
            // A sustained touch qualifies even while the finger is moving.
            // Keep this choice until the gesture settles.
            allowsMultiplePeriods = true
        }
        .onChange(of: selection) { _, filter in rememberCustom(filter) }
        .onChange(of: isDragging) { _, dragging in
            // A cancelled gesture should settle back just like a short swipe.
            if !dragging, !isSettling, contentOffset != 0 {
                navigate(by: 0)
            }
        }
    }

    private func periodButton(_ title: String, symbol: String, offset: Int) -> some View {
        Button {
            navigate(by: offset)
        } label: {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .opacity(isInteracting ? 0 : 1)
                .scaleEffect(isInteracting && !reduceMotion ? 0.8 : 1)
                .animation(interactionAnimation, value: isInteracting)
                .frame(width: AppControlSize.minimumTapTarget, height: AppControlSize.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .disabled(selection.preset == .allTime)
        .accessibilityLabel(Text(title))
        .accessibilityIdentifier(offset < 0 ? "date-filter-previous" : "date-filter-next")
    }

    private var isInteracting: Bool {
        isHolding
    }

    private var isPressActive: Bool {
        isEnabled && (isPressed || isDragging)
    }

    private var interactionAnimation: Animation? {
        reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.25)
    }

    private var pageStride: CGFloat { labelWidth + 12 }

    private var previewOffsets: ClosedRange<Int> {
        // Keep one extra label at each end of the longest possible jump.
        -(Self.maximumSwipePeriods + 1)...(Self.maximumSwipePeriods + 1)
    }

    private var swipePeriodLimit: Int {
        allowsMultiplePeriods ? Self.maximumSwipePeriods : 1
    }

    private var maximumDragDistance: CGFloat {
        // The strip always exposes its neighbors. Only the release decision
        // uses the one-period limit for a quick swipe.
        CGFloat(Self.maximumSwipePeriods) * pageStride
    }

    private var settlingAnimation: Animation {
        .spring(response: 0.42, dampingFraction: 0.86)
    }

    private var labelSizing: some View {
        // Keep the current and adjacent periods at the same size throughout a swipe.
        ZStack {
            ForEach(previewOffsets, id: \.self) { offset in
                label(for: offset).hidden()
            }
        }
        .accessibilityHidden(true)
    }

    private var periodLabels: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width - AppControlSize.minimumTapTarget * 2)
            ZStack {
                ForEach(previewOffsets, id: \.self) { offset in
                    label(for: offset)
                        .frame(width: width, height: geometry.size.height)
                        .opacity(offset != 0 && selection.preset == .allTime ? 0 : 1)
                        .offset(x: CGFloat(offset) * (width + 12) + visibleOffset)
                        // The dashboard suppresses list animations. Apply settling
                        // locally so the label still glides after the finger lifts.
                        .animation(isSettling ? settlingAnimation : nil, value: contentOffset)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .onAppear { labelWidth = width }
            .onChange(of: width) { _, width in labelWidth = width }
        }
        .mask {
            // Reveal adjacent periods in the space vacated by the chevrons.
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: isInteracting ? 28 : 12)
                Rectangle().fill(.black)
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: isInteracting ? 28 : 12)
            }
            .padding(.horizontal, isInteracting ? 8 : AppControlSize.minimumTapTarget)
            .animation(interactionAnimation, value: isInteracting)
        }
        .opacity(isEnabled ? 1 : 0.35)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func label(for offset: Int) -> some View {
        PeriodLabel(selection: selection, offset: offset, calendar: calendar, locale: locale)
            .equatable()
    }

    private var visibleOffset: CGFloat {
        reduceMotion ? 0 : contentOffset
    }

    private var periodDrag: some Gesture {
        DragGesture(minimumDistance: 16)
            .updating($isDragging) { _, dragging, _ in
                guard isEnabled, selection.preset != .allTime, !isSettling else { return }
                dragging = true
            }
            .onChanged { value in
                guard isEnabled, selection.preset != .allTime, !isSettling,
                      abs(value.translation.width) > abs(value.translation.height) else { return }
                // Persist the last displayed position across GestureState's reset.
                contentOffset = max(-maximumDragDistance, min(maximumDragDistance, value.translation.width))
            }
            .onEnded { value in
                guard isEnabled, selection.preset != .allTime, !isSettling,
                      abs(value.translation.width) > abs(value.translation.height) else { return }
                let distance = value.translation.width
                let projected = value.predictedEndTranslation.width
                let threshold = min(60, labelWidth * 0.3)
                let shouldAdvance = abs(distance) >= threshold
                    || (abs(projected) >= threshold && distance * projected > 0)
                // Let the drag determine the distance. Momentum can contribute
                // at most half a label, so a short, fast flick still moves one step.
                let momentum = distance * projected > 0
                    ? min(max(0, abs(projected) - abs(distance)), pageStride * 0.5)
                    : 0
                let travel = min(abs(distance) + momentum, maximumDragDistance)
                let periods = min(swipePeriodLimit, max(1, Int((travel / pageStride).rounded())))
                let step = shouldAdvance ? (distance > 0 ? -periods : periods) : 0
                navigate(by: step)
            }
    }

    private func navigate(by step: Int) {
        guard isEnabled, selection.preset != .allTime, !isSettling else { return }
        let original = selection
        let target = step == 0 ? selection : selection.shifted(by: step, calendar: calendar)
        guard !reduceMotion else {
            selection = target
            contentOffset = 0
            isHolding = false
            allowsMultiplePeriods = false
            return
        }

        isSettling = true
        withAnimation(settlingAnimation, completionCriteria: .removed) {
            contentOffset = -CGFloat(step) * pageStride
        } completion: {
            // An external filter change takes precedence over an animation in flight.
            // Rebase the pager without a slide, while allowing the summary's
            // value-driven numeric transitions to animate the new amounts.
            withTransaction(Transaction(animation: nil)) {
                if selection == original { selection = target }
                contentOffset = 0
                isSettling = false
                isHolding = false
                allowsMultiplePeriods = false
            }
        }
    }

    private struct PeriodLabel: View, Equatable {
        let selection: FinanceDateFilter
        let offset: Int
        let calendar: Calendar
        let locale: Locale

        var body: some View {
            // Formatting only reruns when the period or locale changes, rather
            // than for every drag frame across the larger set of labels.
            Text(selection.shifted(by: offset, calendar: calendar).label(calendar: calendar, locale: locale))
                .font(.footnote.weight(.regular))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)
                .padding(.horizontal, 12)
                .frame(minHeight: AppControlSize.minimumTapTarget)
        }
    }

    private struct ContainerSurface: ViewModifier {
        let reduceTransparency: Bool
        let isEnabled: Bool

        @ViewBuilder
        func body(content: Content) -> some View {
            if #available(iOS 26.0, *), !reduceTransparency {
                // Apply interactive glass to the whole control, keeping its inset
                // capsule and the buttons' full-size touch targets.
                content
                    .padding(-4)
                    .glassEffect(.clear.interactive(isEnabled), in: Capsule())
                    .padding(4)
            } else {
                content.background {
                    Group {
                        if reduceTransparency {
                            Capsule().fill(AppColor.controlFill)
                        } else {
                            Capsule().fill(.ultraThinMaterial)
                        }
                    }
                    .padding(4)
                }
            }
        }
    }

    private func rememberCustom(_ filter: FinanceDateFilter) {
        if filter.preset == .custom { savedCustom = filter }
    }

    private struct ControlButtonStyle: ButtonStyle {
        @Environment(\.isEnabled) private var isEnabled
        @Binding var isPressed: Bool

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .opacity(isEnabled ? 1 : 0.35)
                .onChange(of: configuration.isPressed) { _, pressed in
                    isPressed = pressed
                }
        }
    }
}
