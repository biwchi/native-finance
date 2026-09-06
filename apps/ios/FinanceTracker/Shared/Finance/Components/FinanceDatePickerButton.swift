import SwiftUI

struct FinanceDatePickerButton: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var selection: FinanceDateFilter
    @State private var editor: Editor?
    @State private var savedCustom: FinanceDateFilter?

    private enum Editor: String, Identifiable {
        case custom, date
        var id: Self { self }
    }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.extraSmall))
            : AnyLayout(HStackLayout(spacing: AppSpacing.small))

        layout {
            periodMenu
                .sheet(item: $editor) { editor in
                    FinanceDateFilterSheet(
                        selection: editor == .custom ? (savedCustom ?? selection) : selection,
                        isCustom: editor == .custom,
                        calendar: calendar
                    ) { result in
                        selection = result
                        if result.preset == .custom { savedCustom = result }
                    }
                    .presentationDetents(editor == .custom ? [.medium, .large] : [.large])
                    .presentationDragIndicator(.visible)
                }
                .onAppear {
                    if selection.preset == .custom { savedCustom = selection }
                }
                .onChange(of: selection) { _, filter in
                    if filter.preset == .custom { savedCustom = filter }
                }
            HStack(spacing: AppSpacing.small) {
                navigationButton(forward: false)
                navigationButton(forward: true)
            }
            .fixedSize()
            .disabled(selection.preset == .allTime)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func navigationButton(forward: Bool) -> some View {
        Button {
            selection = selection.shifted(by: forward ? 1 : -1, calendar: calendar)
        } label: {
            AppIcon(forward ? "nav-arrow-right" : "nav-arrow-left", size: 20)
                .foregroundStyle(AppColor.accent)
                .frame(width: AppControlSize.minimumTapTarget, height: AppControlSize.minimumTapTarget)
                .modifier(CapsuleControlBackground(appearance: .glass))
                .contentShape(Circle())
        }
        .buttonStyle(ControlButtonStyle())
        .accessibilityLabel(forward ? "Next period" : "Previous period")
        .accessibilityIdentifier(forward ? "date-filter-next" : "date-filter-previous")
        .accessibilityHint(selection.shifted(by: forward ? 1 : -1, calendar: calendar)
            .label(calendar: calendar, locale: locale))
    }

    private var periodMenu: some View {
        Menu {
            ForEach(FinanceDateFilter.Preset.allCases.filter { $0 != .custom }) { preset in
                Button {
                    selection = FinanceDateFilter(preset: preset)
                } label: {
                    if selection.preset == preset {
                        Label(preset.rawValue, systemImage: "checkmark")
                    } else {
                        Text(preset.rawValue)
                    }
                }
            }

            if selection.preset.canNavigate {
                Section {
                    Button("Choose date…") { editor = .date }
                }
            }

            Section("Custom") {
                if let custom = selection.preset == .custom ? selection : savedCustom {
                    Button {
                        selection = custom
                    } label: {
                        if selection.preset == .custom {
                            Label(custom.label(calendar: calendar, locale: locale), systemImage: "checkmark")
                        } else {
                            Text(custom.label(calendar: calendar, locale: locale))
                        }
                    }
                    Button("Edit…") { editor = .custom }
                } else {
                    Button("Custom…") { editor = .custom }
                }
            }
        } label: {
            HStack(alignment: .center, spacing: AppSpacing.small) {
                Text(selection.label(calendar: calendar, locale: locale))
                    .font(.largeTitle.bold())
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                AppIcon("nav-arrow-down", size: 18)
                    .foregroundStyle(.secondary)
                    .frame(width: AppControlSize.minimumTapTarget, height: AppControlSize.minimumTapTarget)
                    .modifier(CapsuleControlBackground(appearance: .glass))
                    .fixedSize()
                    .accessibilityHidden(true)
            }
            .frame(minHeight: AppControlSize.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(ControlButtonStyle())
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("Choose date filter")
        .accessibilityIdentifier("date-filter-menu")
        .accessibilityValue(selection.label(calendar: calendar, locale: locale))
    }

    private struct ControlButtonStyle: ButtonStyle {
        @Environment(\.isEnabled) private var isEnabled

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.35)
        }
    }
}
