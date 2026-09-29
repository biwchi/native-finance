import SwiftUI

struct FinanceDateFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft: Draft
    @State private var contentHeight: CGFloat = 260
    @State private var navigationDirection: CGFloat = 1

    let onApply: (FinanceDateFilter, FinanceDateFilter?) -> Void

    static func background(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? AppColor.sheetBackground : AppColor.elevatedSurface
    }

    init(
        selection: FinanceDateFilter,
        savedCustom: FinanceDateFilter? = nil,
        calendar: Calendar,
        onApply: @escaping (FinanceDateFilter, FinanceDateFilter?) -> Void
    ) {
        _draft = State(initialValue: Draft(selection: selection, savedCustom: savedCustom, calendar: calendar))
        self.onApply = onApply
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.doubleExtraLarge) {
                header

                if draft.selection.preset == .custom {
                    customDates
                } else if draft.selection.preset != .allTime {
                    periodNavigation
                }

                PrimaryActionButton("Apply") {
                    onApply(draft.selection, draft.savedCustom)
                    dismiss()
                }
                .accessibilityIdentifier("date-filter-apply")
            }
            .padding(.horizontal, AppSpacing.doubleExtraLarge)
            .padding(.top, AppSpacing.doubleExtraLarge)
            .padding(.bottom, AppSpacing.doubleExtraLarge + AppSpacing.small)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                if height > 0 { contentHeight = ceil(height) }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollEdgeFades(background: Self.background(for: colorScheme))
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(contentHeight)])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.selection, trigger: draft.selection)
    }

    private var header: some View {
        HStack(spacing: AppSpacing.medium) {
            Menu {
                Picker("Period", selection: Binding(
                    get: { draft.selection.preset },
                    set: {
                        navigationDirection = 0
                        draft.select($0, calendar: calendar)
                    }
                )) {
                    ForEach(FinanceDateFilter.Preset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
            } label: {
                HStack(spacing: AppSpacing.small) {
                    Text(presetTitle)
                        .font(.subheadline.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    AppIcon("nav-arrow-down", size: 12)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, AppSpacing.medium)
                .padding(.vertical, AppSpacing.small)
                .frame(minHeight: AppControlSize.minimumTapTarget)
                .background(AppColor.controlFill, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Period type")
            .accessibilityValue(presetTitle)
            .accessibilityIdentifier("date-filter-preset-picker")

            Spacer(minLength: 0)

            Button { dismiss() } label: {
                AppIcon("xmark", size: 18)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(PeriodControlStyle())
            .accessibilityLabel("Cancel")
            .accessibilityIdentifier("date-filter-cancel")
        }
    }

    private var customDates: some View {
        VStack(spacing: AppSpacing.small) {
            VStack(spacing: AppSpacing.medium) {
                customDateField("From", selection: customStart, identifier: "date-filter-from")
                Divider()
                customDateField("To", selection: customEnd, minimumDate: draft.selection.anchor,
                                identifier: "date-filter-to")
            }
            .datePickerStyle(.compact)
            .padding(AppSpacing.large)
            .background(AppColor.controlFill, in: RoundedRectangle(cornerRadius: AppRadius.large))

            Text("Includes both dates")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func customDateField(
        _ title: String,
        selection: Binding<Date>,
        minimumDate: Date = .distantPast,
        identifier: String
    ) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.small))
            : AnyLayout(HStackLayout(spacing: AppSpacing.medium))
        return layout {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize()
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            DatePicker(title, selection: selection, in: minimumDate..., displayedComponents: .date)
                .labelsHidden()
                .accessibilityIdentifier(identifier)
        }
    }

    private var periodNavigation: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: AppSpacing.large) {
                    periodLabel
                    HStack {
                        navigationButton(forward: false)
                        Spacer()
                        navigationButton(forward: true)
                    }
                }
            } else {
                HStack(spacing: AppSpacing.medium) {
                    navigationButton(forward: false)
                    periodLabel
                    navigationButton(forward: true)
                }
            }
        }
    }

    private var periodLabel: some View {
        ZStack {
            periodText
                .id(periodTitle)
                .transition(periodTransition)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.small)
        .clipped()
        .animation(reduceMotion ? .easeOut(duration: 0.16) : .smooth(duration: 0.32), value: periodTitle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(periodTitle)
        .accessibilityIdentifier("date-filter-selected-period")
    }

    private var periodText: some View {
        VStack(spacing: AppSpacing.extraSmall) {
            Text(draft.selection.preset == .month ? monthComponent("LLLL") : periodTitle)
                .font(.title2.weight(.semibold))
                .tracking(-0.4)
                .foregroundStyle(.primary)
            if draft.selection.preset == .month {
                Text(monthComponent("y"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }

    private var periodTransition: AnyTransition {
        guard !reduceMotion, navigationDirection != 0 else { return .opacity }
        let distance = AppSpacing.doubleExtraLarge * navigationDirection
        return .asymmetric(
            insertion: .modifier(
                active: PeriodLabelEffect(offset: distance, blur: 3, opacity: 0),
                identity: PeriodLabelEffect(offset: 0, blur: 0, opacity: 1)
            ),
            removal: .modifier(
                active: PeriodLabelEffect(offset: -distance, blur: 3, opacity: 0),
                identity: PeriodLabelEffect(offset: 0, blur: 0, opacity: 1)
            )
        )
    }

    private struct PeriodLabelEffect: ViewModifier {
        let offset: CGFloat
        let blur: CGFloat
        let opacity: Double

        func body(content: Content) -> some View {
            content
                .blur(radius: blur)
                .opacity(opacity)
                .offset(x: offset)
        }
    }

    private var presetTitle: String {
        guard draft.selection.rollingAnchor != nil else { return draft.selection.preset.rawValue }
        return draft.selection.preset == .last7Days ? "7 Days" : "30 Days"
    }

    private var periodTitle: String {
        let selection = draft.selection
        if selection.preset == .month {
            return monthComponent("LLLL y")
        }
        if selection.preset == .last7Days || selection.preset == .last30Days,
           let interval = selection.interval(calendar: calendar),
           let end = calendar.date(byAdding: .day, value: -1, to: interval.end) {
            return FinanceDateFilter(preset: .custom, anchor: interval.start, customEnd: end)
                .label(calendar: calendar, locale: locale)
        }
        return selection.label(calendar: calendar, locale: locale)
    }

    private func monthComponent(_ template: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: draft.selection.anchor)
    }

    private func navigationButton(forward: Bool) -> some View {
        Button {
            navigationDirection = forward ? 1 : -1
            draft.shift(by: forward ? 1 : -1, calendar: calendar)
        } label: {
            AppIcon(forward ? "nav-arrow-right" : "nav-arrow-left", size: 18)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(.primary)
        }
        .buttonStyle(PeriodControlStyle())
        .accessibilityLabel(forward ? "Next period" : "Previous period")
        .accessibilityIdentifier(forward ? "date-filter-next" : "date-filter-previous")
        .accessibilityHint(draft.selection.shifted(by: forward ? 1 : -1, calendar: calendar)
            .label(calendar: calendar, locale: locale))
    }

    private struct PeriodControlStyle: ButtonStyle {
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .frame(width: AppControlSize.minimumTapTarget, height: AppControlSize.minimumTapTarget)
                .background(AppColor.controlFill, in: Circle())
                .overlay {
                    if configuration.isPressed {
                        Circle().fill(AppColor.controlFill)
                    }
                }
                .compositingGroup()
                .opacity(isEnabled ? 1 : 0.45)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
                .frame(width: AppControlSize.minimumTapTarget, height: AppControlSize.minimumTapTarget)
                .contentShape(Circle())
        }
    }

    private var customStart: Binding<Date> {
        Binding(get: { draft.selection.anchor }, set: { draft.setStart($0, calendar: calendar) })
    }

    private var customEnd: Binding<Date> {
        Binding(get: { draft.selection.customEnd }, set: { draft.setEnd($0, calendar: calendar) })
    }

    struct Draft {
        var selection: FinanceDateFilter
        private(set) var savedCustom: FinanceDateFilter?

        init(selection: FinanceDateFilter, savedCustom: FinanceDateFilter? = nil, calendar: Calendar) {
            self.selection = selection
            self.savedCustom = savedCustom
            if selection.preset == .custom {
                setCustom(start: min(selection.anchor, selection.customEnd),
                          end: max(selection.anchor, selection.customEnd), calendar: calendar)
            }
        }

        mutating func select(_ preset: FinanceDateFilter.Preset, now: Date = .now, calendar: Calendar) {
            if preset == .custom {
                if let savedCustom {
                    setCustom(start: min(savedCustom.anchor, savedCustom.customEnd),
                              end: max(savedCustom.anchor, savedCustom.customEnd), calendar: calendar)
                } else {
                    let interval = selection.interval(now: now, calendar: calendar)
                    let start = interval?.start ?? now
                    let end = interval.flatMap { calendar.date(byAdding: .day, value: -1, to: $0.end) } ?? start
                    setCustom(start: start, end: end, calendar: calendar)
                }
            } else {
                selection = FinanceDateFilter(preset: preset, anchor: now)
            }
        }

        mutating func shift(by amount: Int, now: Date = .now, calendar: Calendar) {
            selection = selection.shifted(by: amount, now: now, calendar: calendar)
            if selection.preset == .custom { savedCustom = selection }
        }

        mutating func setStart(_ date: Date, calendar: Calendar) {
            setCustom(start: date, end: max(date, selection.customEnd), calendar: calendar)
        }

        mutating func setEnd(_ date: Date, calendar: Calendar) {
            setCustom(start: selection.anchor, end: max(selection.anchor, date), calendar: calendar)
        }

        private mutating func setCustom(start: Date, end: Date, calendar: Calendar) {
            selection = FinanceDateFilter(preset: .custom, anchor: calendar.startOfDay(for: start),
                                          customEnd: calendar.startOfDay(for: end))
            savedCustom = selection
        }
    }
}
