import SwiftUI

struct FinanceDateFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var draft: Draft
    @State private var contentHeight: CGFloat = 260

    let onApply: (FinanceDateFilter, FinanceDateFilter?) -> Void

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
            .padding(.bottom, AppSpacing.large)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                if height > 0 { contentHeight = ceil(height) }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollEdgeFades(background: AppColor.elevatedSurface)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(contentHeight)])
        .presentationDragIndicator(.visible)
        .legacySheetAppearance()
        .presentationBackground(AppColor.elevatedSurface)
    }

    private var header: some View {
        HStack(spacing: AppSpacing.medium) {
            Menu {
                Picker("Period", selection: Binding(
                    get: { draft.selection.preset },
                    set: { draft.select($0, calendar: calendar) }
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
                    AppIcon("nav-arrow-down", size: 14)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, AppSpacing.large)
                .padding(.vertical, AppSpacing.small)
                .frame(minHeight: AppControlSize.minimumTapTarget)
                .modifier(CapsuleControlBackground(appearance: .glass))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Period type")
            .accessibilityValue(presetTitle)
            .accessibilityIdentifier("date-filter-preset-picker")

            Spacer(minLength: 0)

            Button { dismiss() } label: {
                AppIcon("xmark", size: 18)
                    .foregroundStyle(.secondary)
                    .frame(width: AppControlSize.minimumTapTarget, height: AppControlSize.minimumTapTarget)
                    .modifier(CapsuleControlBackground(appearance: .glass))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
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
        Text(periodTitle)
            .font(.title3.weight(.medium))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("date-filter-selected-period")
    }

    private var presetTitle: String {
        guard draft.selection.rollingAnchor != nil else { return draft.selection.preset.rawValue }
        return draft.selection.preset == .last7Days ? "7 Days" : "30 Days"
    }

    private var periodTitle: String {
        let selection = draft.selection
        if selection.preset == .month {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = locale
            formatter.timeZone = calendar.timeZone
            formatter.setLocalizedDateFormatFromTemplate("LLLL y")
            return formatter.string(from: selection.anchor)
        }
        if selection.preset == .last7Days || selection.preset == .last30Days,
           let interval = selection.interval(calendar: calendar),
           let end = calendar.date(byAdding: .day, value: -1, to: interval.end) {
            return FinanceDateFilter(preset: .custom, anchor: interval.start, customEnd: end)
                .label(calendar: calendar, locale: locale)
        }
        return selection.label(calendar: calendar, locale: locale)
    }

    private func navigationButton(forward: Bool) -> some View {
        PrimaryIconButton(
            forward ? "Next period" : "Previous period",
            iconName: forward ? "nav-arrow-right" : "nav-arrow-left",
            iconSize: 18,
            appearance: .glass
        ) {
            draft.shift(by: forward ? 1 : -1, calendar: calendar)
        }
        .controlSize(.small)
        .accessibilityIdentifier(forward ? "date-filter-next" : "date-filter-previous")
        .accessibilityHint(draft.selection.shifted(by: forward ? 1 : -1, calendar: calendar)
            .label(calendar: calendar, locale: locale))
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
