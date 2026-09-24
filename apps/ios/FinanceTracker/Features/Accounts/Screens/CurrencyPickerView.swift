import SwiftUI

struct CurrencyPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppPreferences.favoriteCurrenciesKey) private var savedFavorites = "USD,EUR"
    @StateObject private var rates: ExchangeRateStore

    @Binding var selection: String
    let currencyCodes: [String]
    let title: String

    @State private var query = ""
    @State private var showsRateHelp = false
    @State private var isRefreshing = false
    @FocusState private var isSearchFocused: Bool

    init(selection: Binding<String>, currencyCodes: [String], title: String = "Currency",
         rateStore: ExchangeRateStore? = nil) {
        _selection = selection
        self.currencyCodes = currencyCodes
        self.title = title
        _rates = StateObject(wrappedValue: rateStore ?? ExchangeRateStore())
    }

    var body: some View {
        let catalog = CurrencyPickerCatalog(
            currencyCodes: currencyCodes, selection: selection,
            favorites: favorites, query: query
        )

        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.doubleExtraLarge) {
                rateStatus

                if catalog.isEmpty {
                    ContentUnavailableView(
                        "No currencies found", iconName: "search",
                        description: Text("No results for \"\(query)\".")
                    )
                } else {
                    currencySection("Selected", codes: catalog.selected)
                    currencySection("Favorites", codes: catalog.favorites)
                    currencySection(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "All currencies" : "Search results", codes: catalog.others)
                }
            }
            .padding(.horizontal, AppSpacing.large)
            .padding(.top, AppSpacing.medium)
            .padding(.bottom, AppSpacing.large)
        }
        .background(AppColor.groupedBackground)
        .scrollEdgeFades()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isSearchFocused = false
                    showsRateHelp = true
                } label: {
                    AppIcon("help-circle", size: 22)
                }
                .accessibilityLabel("About exchange rates")
                .accessibilityIdentifier("currencyRateHelp")
                .legacyToolbarIcon()
            }
        }
        .safeAreaInset(edge: .bottom) {
            searchField
                .padding(.horizontal, AppSpacing.extraLarge)
                .padding(.vertical, AppSpacing.medium)
        }
        .appSheet(isPresented: $showsRateHelp) {
            CurrencyRateHelpView()
        }
        .task {
            isRefreshing = true
            await rates.load(currencies: [], reportingCurrency: selection)
            isRefreshing = false
        }
    }

    private var rateStatus: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text("Exchange rates for 1 \(selection)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            HStack(spacing: AppSpacing.compact) {
                if isRefreshing {
                    ProgressView().controlSize(.mini)
                        .accessibilityLabel("Updating exchange rates")
                } else {
                    AppIcon("clock", size: 14, relativeTo: .caption)
                        .accessibilityHidden(true)
                }
                if let snapshot = rates.snapshot {
                    Text("Updated: \(snapshot.fetchedAt.formatted(Self.updateFormat))")
                } else {
                    Text(isRefreshing ? "Updating rates…" : "Updated: Not yet available")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, AppSpacing.extraSmall)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func currencySection(_ title: String, codes: [String]) -> some View {
        if !codes.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppSpacing.extraSmall)
                    .accessibilityAddTraits(.isHeader)
                LazyVStack(spacing: AppSpacing.small) {
                    ForEach(codes, id: \.self) { code in
                        CurrencyPickerRow(
                            code: code,
                            name: Locale.current.localizedString(forCurrencyCode: code) ?? code,
                            rate: rates.convert(1, from: selection, to: code),
                            baseCurrency: selection,
                            isSelected: selection == code,
                            isFavorite: favorites.contains(code),
                            select: {
                                selection = code
                                dismiss()
                            },
                            toggleFavorite: { toggleFavorite(code) }
                        )
                    }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: AppSpacing.medium) {
            AppIcon("search", size: 20)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Code or currency name", text: $query)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isSearchFocused)
                .onSubmit { isSearchFocused = false }
                .accessibilityLabel("Search currencies")
                .accessibilityIdentifier("currencySearch")

            if !query.isEmpty {
                Button {
                    query = ""
                    isSearchFocused = true
                } label: {
                    AppIcon("xmark", size: 16)
                        .foregroundStyle(.secondary)
                        .frame(width: AppControlSize.minimumTapTarget, height: AppControlSize.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, AppSpacing.extraLarge)
        .padding(.trailing, query.isEmpty ? AppSpacing.extraLarge : AppSpacing.extraSmall)
        .frame(minHeight: 54)
        .background(AppColor.elevatedSurface.opacity(0.9), in: Capsule())
        .modifier(CapsuleControlBackground(appearance: .glass))
        .contentShape(Capsule())
        .onTapGesture { isSearchFocused = true }
    }

    private var favorites: Set<String> {
        Set(savedFavorites.split(separator: ",").map(String.init))
    }

    private func toggleFavorite(_ code: String) {
        var updated = favorites
        if updated.contains(code) { updated.remove(code) } else { updated.insert(code) }
        savedFavorites = updated.sorted().joined(separator: ",")
    }

    private static let updateFormat = Date.FormatStyle(date: .abbreviated, time: .shortened)
}
