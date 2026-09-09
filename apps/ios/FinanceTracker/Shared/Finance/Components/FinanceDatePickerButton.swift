import SwiftUI

struct FinanceDatePickerButton: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Binding var selection: FinanceDateFilter
    @State private var isShowingFilter = false
    @State private var savedCustom: FinanceDateFilter?

    var body: some View {
        HStack(spacing: 0) {
            periodButton("Previous period", symbol: "chevron.backward", offset: -1)

            Button {
                isShowingFilter = true
            } label: {
                Text(selection.label(calendar: calendar, locale: locale))
                    .font(.footnote.weight(.regular))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
                    .frame(minHeight: AppControlSize.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Choose date filter")
            .accessibilityIdentifier("date-filter-menu")
            .accessibilityValue(selection.label(calendar: calendar, locale: locale))
            .accessibilityHint("Opens period filters and custom date ranges")

            periodButton("Next period", symbol: "chevron.forward", offset: 1)
        }
        .buttonStyle(ControlButtonStyle())
        .background {
            containerBackground
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .sheet(isPresented: $isShowingFilter) {
            FinanceDateFilterSheet(selection: selection, savedCustom: savedCustom, calendar: calendar) { result, custom in
                selection = result
                savedCustom = custom
            }
        }
        .onAppear { rememberCustom(selection) }
        .onChange(of: selection) { _, filter in rememberCustom(filter) }
    }

    private func periodButton(_ title: String, symbol: String, offset: Int) -> some View {
        Button {
            selection = selection.shifted(by: offset, calendar: calendar)
        } label: {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: AppControlSize.minimumTapTarget, height: AppControlSize.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .disabled(selection.preset == .allTime)
        .accessibilityLabel(Text(title))
        .accessibilityIdentifier(offset < 0 ? "date-filter-previous" : "date-filter-next")
    }

    @ViewBuilder
    private var containerBackground: some View {
        if reduceTransparency {
            Capsule().fill(AppColor.controlFill)
        } else if #available(iOS 26.0, *) {
            Capsule().fill(.clear)
                .glassEffect(.clear, in: Capsule())
        } else {
            Capsule().fill(.ultraThinMaterial)
        }
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
