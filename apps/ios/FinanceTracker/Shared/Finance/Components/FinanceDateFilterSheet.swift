import SwiftUI

struct FinanceDateFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @State private var start: Date
    @State private var end: Date

    let selection: FinanceDateFilter
    let isCustom: Bool
    let onApply: (FinanceDateFilter) -> Void

    init(selection: FinanceDateFilter, isCustom: Bool, calendar: Calendar, onApply: @escaping (FinanceDateFilter) -> Void) {
        self.selection = selection
        self.isCustom = isCustom
        self.onApply = onApply
        let interval = selection.interval(calendar: calendar)
        _start = State(initialValue: interval?.start ?? calendar.startOfDay(for: .now))
        _end = State(initialValue: interval.flatMap { calendar.date(byAdding: .day, value: -1, to: $0.end) } ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                if isCustom {
                    Section {
                        DatePicker("Start date", selection: $start, displayedComponents: .date)
                        DatePicker("End date", selection: $end, in: start..., displayedComponents: .date)
                    } footer: {
                        VStack(alignment: .leading, spacing: AppSpacing.small) {
                            Text(result.label(calendar: calendar, locale: locale))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("Includes both the start and end date.")
                        }
                    }
                } else {
                    DatePicker("Date", selection: $start, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .listRowInsets(EdgeInsets())
                }

                if !isCustom {
                    Section {
                        LabeledContent("Selected period", value: result.label(calendar: calendar, locale: locale))
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryActionButton("Apply") {
                    onApply(result)
                    dismiss()
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle(isCustom ? "Custom period" : "Choose date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: start) { _, newStart in
                if end < newStart { end = newStart }
            }
        }
    }

    private var result: FinanceDateFilter {
        FinanceDateFilter(preset: isCustom ? .custom : selection.preset, anchor: start, customEnd: max(start, end))
    }
}
