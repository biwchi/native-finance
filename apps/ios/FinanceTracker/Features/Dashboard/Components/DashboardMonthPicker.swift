import SwiftUI

struct DashboardMonthPicker: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selection: Date
    let range: ClosedRange<Date>

    @State private var displayedYear: Int

    private let calendar = Calendar.current
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 8),
        count: 3
    )

    init(selection: Binding<Date>, range: ClosedRange<Date>) {
        _selection = selection
        self.range = range
        _displayedYear = State(
            initialValue: Calendar.current.component(.year, from: selection.wrappedValue)
        )
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button {
                    displayedYear -= 1
                } label: {
                    AppIcon("nav-arrow-left")
                        .frame(width: 44, height: 44)
                }
                .disabled(displayedYear <= earliestYear)
                .accessibilityLabel("Previous year")

                Spacer()

                Text(verbatim: String(displayedYear))
                    .font(.headline)

                Spacer()

                Button {
                    displayedYear += 1
                } label: {
                    AppIcon("nav-arrow-right")
                        .frame(width: 44, height: 44)
                }
                .disabled(displayedYear >= latestYear)
                .accessibilityLabel("Next year")
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(months, id: \.self) { month in
                    AccentSelectionButton(
                        month.formatted(.dateTime.month(.abbreviated)),
                        isSelected: isSelected(month)
                    ) {
                        selection = month
                        dismiss()
                    }
                    .disabled(!isAvailable(month))
                    .accessibilityLabel(month.formatted(.dateTime.month(.wide).year()))
                }
            }
        }
        .padding(16)
        .frame(width: 300)
        .onAppear {
            displayedYear = calendar.component(.year, from: selection)
        }
    }

    private var earliestYear: Int {
        calendar.component(.year, from: range.lowerBound)
    }

    private var latestYear: Int {
        calendar.component(.year, from: range.upperBound)
    }

    private var months: [Date] {
        (1...12).compactMap { month in
            calendar.date(from: DateComponents(year: displayedYear, month: month, day: 1))
        }
    }

    private func isAvailable(_ month: Date) -> Bool {
        month >= range.lowerBound && month <= range.upperBound
    }

    private func isSelected(_ month: Date) -> Bool {
        calendar.isDate(month, equalTo: selection, toGranularity: .month)
    }
}
