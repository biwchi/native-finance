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


struct FinanceMonthHeader: View {
    let title: String
    @Binding var month: Date
    @State private var isShowingPicker = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center) {
                heading.fixedSize()
                Spacer(minLength: 12)
                monthButton
            }
            VStack(alignment: .leading, spacing: 8) {
                heading
                monthButton
            }
        }
        .padding(.vertical, 8)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var heading: some View {
        Text(title)
            .font(.largeTitle.bold())
            .accessibilityAddTraits(.isHeader)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var monthButton: some View {
        Button {
            isShowingPicker = true
        } label: {
            HStack(spacing: 6) {
                Text(month.formatted(.dateTime.month(.abbreviated).year()))
                AppIcon("nav-arrow-down", size: 11)
            }
            .font(.subheadline.weight(.medium))
            .frame(minHeight: 32)
            .fixedSize()
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(.primary)
        .accessibilityLabel("Choose month")
        .accessibilityValue(month.formatted(.dateTime.month(.wide).year()))
        .popover(isPresented: $isShowingPicker) {
            DashboardMonthPicker(selection: $month, range: range)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var range: ClosedRange<Date> {
        let current = BudgetMonth.start(of: .now)
        let first = Calendar.current.date(byAdding: .month, value: -12, to: current) ?? current
        let last = Calendar.current.date(byAdding: .month, value: 2, to: current) ?? current
        return first...last
    }
}

struct FinanceMetricCards: View {
    struct Metric {
        let title: String
        let amount: Decimal
        var signed = false
    }
    let first: Metric
    let second: Metric
    let currency: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stackedCards
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        card(first, wrapsAmount: false)
                        card(second, wrapsAmount: false)
                    }
                    stackedCards
                }
            }
        }
        .padding(.vertical, 6)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var stackedCards: some View {
        VStack(alignment: .leading, spacing: 12) {
            card(first, wrapsAmount: true)
            card(second, wrapsAmount: true)
        }
    }

    private func card(_ metric: Metric, wrapsAmount: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(metric.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(MoneyFormatter.format(metric.amount, currency: currency, showPositiveSign: metric.signed))
                .font(.headline)
                .monospacedDigit()
                .contentTransition(.numericText())
                .fixedSize(horizontal: !wrapsAmount, vertical: true)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.title)
        .accessibilityValue(MoneyFormatter.spoken(metric.amount, currency: currency, locale: locale))
    }
}

struct FinanceSummaryUnavailable: View {
    let state: TransactionStore.State
    let rateState: ExchangeRateStore.State

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                ProgressView("Loading summary")
            case .failed:
                Label("Summary unavailable", icon: "wifi-warning")
            case .loaded:
                switch rateState {
                case .idle, .loading: ProgressView("Converting amounts")
                case .failed: Label("Couldn’t convert currencies", icon: "wifi-warning")
                case .loaded: Label("Some amounts could not be converted", icon: "warning-triangle")
                }
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 20)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

struct FinanceSectionMargins: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content.listSectionMargins(.vertical, 0) }
        else { content }
    }
}

extension View {
    func leadingAccountSelectorToolbar() -> some View {
        navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarLeading) {
                        AccountSelector(compact: true).padding(.leading, -12)
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarLeading) { AccountSelector(compact: true) }
                }
            }
    }
}

struct ComingUpSection: View {
    @EnvironmentObject private var transactionStore: TransactionStore
    var allAccounts = false
    let onEdit: (UpcomingTransaction) -> Void

    private var transactions: [UpcomingTransaction] {
        allAccounts ? transactionStore.allUpcomingTransactions : transactionStore.upcomingTransactions
    }

    var body: some View {
        if transactionStore.upcomingState == .loaded, !transactions.isEmpty {
            Section {
                UpcomingTransactionsContent(limit: 4, allAccounts: allAccounts, onEdit: onEdit)
            } header: {
                HStack {
                    Text("Coming up")
                    Spacer()
                    NavigationLink {
                        RecurringTransactionsView(allAccounts: allAccounts)
                    } label: {
                        Text("See all")
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.primary)
                    .accessibilityLabel("See all recurring transactions")
                }
                .textCase(nil)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 0, trailing: 16))
            }
        }
    }
}
