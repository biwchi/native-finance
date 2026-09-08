import SwiftUI

struct FinanceDatePickerButton: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Binding var selection: FinanceDateFilter
    @State private var isShowingFilter = false
    @State private var savedCustom: FinanceDateFilter?

    var body: some View {
        Button {
            isShowingFilter = true
        } label: {
            Text(selection.label(calendar: calendar, locale: locale))
                .font(.subheadline.weight(.regular))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, AppSpacing.large)
                .padding(.vertical, AppSpacing.small)
                .frame(minHeight: AppControlSize.minimumTapTarget)
                .modifier(CapsuleControlBackground(appearance: .glass))
                .contentShape(Capsule())
        }
        .buttonStyle(ControlButtonStyle())
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityLabel("Choose date filter")
        .accessibilityIdentifier("date-filter-menu")
        .accessibilityValue(selection.label(calendar: calendar, locale: locale))
        .accessibilityHint("Opens period filters and custom date ranges")
        .sheet(isPresented: $isShowingFilter) {
            FinanceDateFilterSheet(selection: selection, savedCustom: savedCustom, calendar: calendar) { result, custom in
                selection = result
                savedCustom = custom
            }
        }
        .onAppear { rememberCustom(selection) }
        .onChange(of: selection) { _, filter in rememberCustom(filter) }
    }

    private func rememberCustom(_ filter: FinanceDateFilter) {
        if filter.preset == .custom { savedCustom = filter }
    }

    private struct ControlButtonStyle: ButtonStyle {
        @Environment(\.isEnabled) private var isEnabled

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.35)
        }
    }
}
