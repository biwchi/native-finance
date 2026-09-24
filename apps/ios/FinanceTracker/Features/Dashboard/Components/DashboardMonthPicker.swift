import SwiftUI

struct DashboardMonthPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var selection: Date
    let range: ClosedRange<Date>

    @State private var displayedYear: Int
    @State private var contentOffset: CGFloat = 0
    @State private var isSettling = false

    private let calendar = Calendar.current
    private let pageWidth: CGFloat = 268
    private let pageSpacing: CGFloat = 16
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
            HStack(spacing: 0) {
                yearButton(step: -1)
                yearTitle
                yearButton(step: 1)
            }

            monthPages
        }
        .frame(width: pageWidth)
        .padding(16)
        .onAppear {
            displayedYear = calendar.component(.year, from: selection)
        }
    }

    private func yearButton(step: Int) -> some View {
        Button {
            navigate(by: step)
        } label: {
            AppIcon(step < 0 ? "nav-arrow-left" : "nav-arrow-right")
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .disabled(step < 0 ? displayedYear <= earliestYear : displayedYear >= latestYear)
        .accessibilityLabel(step < 0 ? "Previous year" : "Next year")
    }

    private var yearTitle: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(visibleYears, id: \.self) { year in
                    Text(verbatim: String(year))
                        .font(.headline)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .offset(x: pagePosition(for: year) * geometry.size.width)
                        .opacity(reduceMotion && year != displayedYear ? 0 : 1)
                }
            }
        }
        .frame(height: 44)
        .clipped()
        .animation(isSettling ? settlingAnimation : nil, value: contentOffset)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Year")
        .accessibilityValue(String(displayedYear))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: navigate(by: 1)
            case .decrement: navigate(by: -1)
            @unknown default: break
            }
        }
    }

    private var monthPages: some View {
        ZStack {
            ForEach(visibleYears, id: \.self) { year in
                monthGrid(for: year)
                    .offset(x: pagePosition(for: year) * pageStride)
                    .opacity(reduceMotion && year != displayedYear ? 0 : 1)
                    .allowsHitTesting(year == displayedYear && !isSettling)
                    .accessibilityHidden(year != displayedYear)
            }
        }
        .clipped()
        .animation(isSettling ? settlingAnimation : nil, value: contentOffset)
    }

    private func monthGrid(for year: Int) -> some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(months(in: year), id: \.self) { month in
                AccentSelectionButton(
                    month.formatted(.dateTime.month(.abbreviated)),
                    isSelected: isSelected(month)
                ) {
                    guard !isSettling else { return }
                    withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.25)) {
                        selection = month
                        dismiss()
                    }
                }
                .disabled(!isAvailable(month))
                .accessibilityLabel(month.formatted(.dateTime.month(.wide).year()))
            }
        }
        .frame(width: pageWidth)
    }

    private func navigate(by step: Int) {
        guard isEnabled, !isSettling else { return }
        let targetYear = min(latestYear, max(earliestYear, displayedYear + step))
        let actualStep = targetYear - displayedYear
        guard actualStep != 0 else { return }

        if reduceMotion {
            displayedYear = targetYear
            contentOffset = 0
            return
        }

        isSettling = true
        withAnimation(settlingAnimation, completionCriteria: .removed) {
            contentOffset = -CGFloat(actualStep) * pageStride
        } completion: {
            // The arriving page stays in place as it becomes the new center page.
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                displayedYear = targetYear
                contentOffset = 0
                isSettling = false
            }
        }
    }

    private var pageStride: CGFloat { pageWidth + pageSpacing }

    private var settlingAnimation: Animation {
        .spring(response: 0.36, dampingFraction: 0.88)
    }

    private var visibleYears: [Int] {
        ((displayedYear - 1)...(displayedYear + 1)).filter {
            $0 >= earliestYear && $0 <= latestYear
        }
    }

    private func pagePosition(for year: Int) -> CGFloat {
        CGFloat(year - displayedYear) + (reduceMotion ? 0 : contentOffset / pageStride)
    }

    private var earliestYear: Int {
        calendar.component(.year, from: range.lowerBound)
    }

    private var latestYear: Int {
        calendar.component(.year, from: range.upperBound)
    }

    private func months(in year: Int) -> [Date] {
        (1...12).compactMap { month in
            calendar.date(from: DateComponents(year: year, month: month, day: 1))
        }
    }

    private func isAvailable(_ month: Date) -> Bool {
        month >= range.lowerBound && month <= range.upperBound
    }

    private func isSelected(_ month: Date) -> Bool {
        calendar.isDate(month, equalTo: selection, toGranularity: .month)
    }
}
