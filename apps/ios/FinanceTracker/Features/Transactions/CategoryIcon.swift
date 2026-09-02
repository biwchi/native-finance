import SwiftUI

struct CategoryIcon: View {
    let category: TransactionCategory
    var size: CGFloat = 36

    var body: some View {
        AppIcon(category.displayIcon, size: size * 0.43)
            .foregroundStyle(category.displayColor)
            .frame(width: size, height: size)
            .background(
                category.displayColor.opacity(0.12),
                in: RoundedRectangle(cornerRadius: size * 0.28)
            )
            .accessibilityHidden(true)
    }
}

struct CategoryIconOption: Identifiable, Hashable {
    let symbol: String
    let title: String

    var id: String { symbol }
}

struct CategoryIconGroup: Identifiable, Hashable {
    let title: String
    let symbol: String
    let icons: [CategoryIconOption]

    var id: String { title }
}

enum CategoryIconCatalog {
    static let groups: [CategoryIconGroup] = [
        group("General", symbol: "view-grid", icons: [
            ("label", "Tag"),
            ("star", "Star"),
            ("heart", "Heart"),
            ("bookmark", "Bookmark"),
            ("white-flag", "Flag"),
            ("bell", "Bell"),
            ("pin", "Pin"),
            ("attachment", "Attachment"),
            ("folder", "Folder"),
            ("archive", "Archive"),
            ("gift", "Gift"),
            ("calendar", "Calendar"),
            ("clock", "Clock"),
            ("user", "Person"),
            ("more-horiz-circle", "Other"),
            ("view-grid", "Collection"),
        ]),
        group("Food", symbol: "cutlery", icons: [
            ("cutlery", "Meal"),
            ("coffee-cup", "Coffee"),
            ("pizza-slice", "Takeout"),
            ("cart", "Groceries"),
            ("birthday-cake", "Cake"),
            ("glass-half", "Drinks"),
            ("bread-slice", "Bread"),
            ("organic-food", "Produce"),
            ("cookie", "Snacks"),
            ("fish", "Seafood"),
            ("leaf", "Organic food"),
            ("egg", "Eggs"),
            ("fridge", "Refrigerator"),
            ("chocolate", "Chocolate"),
            ("droplet", "Water"),
            ("fire-flame", "Grill"),
        ]),
        group("Finance", symbol: "cash", icons: [
            ("cash", "Cash"),
            ("credit-card", "Credit card"),
            ("bank", "Bank"),
            ("dollar-circle", "Dollars"),
            ("coins", "Coins"),
            ("percentage", "Interest"),
            ("graph-up", "Growth"),
            ("percentage-circle", "Budget"),
            ("wallet", "Wallet"),
            ("page", "Receipt"),
            ("scan-barcode", "Barcode"),
            ("qr-code", "QR code"),
            ("coins-swap", "Transfer"),
            ("repeat", "Recurring payment"),
            ("undo", "Refund"),
            ("piggy-bank", "Savings"),
        ]),
        group("Travel", symbol: "airplane", icons: [
            ("airplane", "Flight"),
            ("car", "Car"),
            ("bus", "Bus"),
            ("train", "Train"),
            ("bicycle", "Bicycle"),
            ("skateboard", "Skateboard"),
            ("gas", "Fuel"),
            ("ev-station", "EV charging"),
            ("sea-waves", "Sea travel"),
            ("tram", "Tram"),
            ("delivery-truck", "Truck"),
            ("map", "Map"),
            ("map-pin", "Place"),
            ("suitcase", "Luggage"),
            ("bed", "Hotel"),
            ("trekking", "Hiking"),
        ]),
        group("Home", symbol: "home-simple", icons: [
            ("home-simple", "Home"),
            ("building", "Building"),
            ("sofa", "Furniture"),
            ("lamp", "Lighting"),
            ("key", "Keys"),
            ("lock", "Security"),
            ("light-bulb", "Electricity"),
            ("flash", "Power"),
            ("droplet", "Water"),
            ("wifi", "Internet"),
            ("phone", "Phone"),
            ("tv", "Television"),
            ("washing-machine", "Laundry"),
            ("tools", "Repairs"),
            ("hammer", "Renovation"),
            ("shield", "Insurance"),
        ]),
        group("Shopping", symbol: "shopping-bag", icons: [
            ("shopping-bag", "Shopping bag"),
            ("cart", "Shopping cart"),
            ("shop", "Store"),
            ("shirt", "Clothing"),
            ("sandals", "Footwear"),
            ("handbag", "Handbag"),
            ("glasses", "Glasses"),
            ("wristwatch", "Watch"),
            ("bright-star", "Accessories"),
            ("camera", "Camera"),
            ("headset", "Audio"),
            ("computer", "Computer"),
            ("laptop", "Laptop"),
            ("smartphone-device", "Phone"),
            ("package", "Delivery"),
            ("scissor", "Personal care"),
        ]),
        group("Health", symbol: "healthcare", icons: [
            ("healthcare", "Medical care"),
            ("health-shield", "Health insurance"),
            ("pharmacy-cross-circle", "Pharmacy"),
            ("pharmacy-cross-tag", "Prescriptions"),
            ("home-hospital", "Hospital"),
            ("cube-bandage", "First aid"),
            ("mask-square", "Mask"),
            ("eye", "Eye care"),
            ("voice", "Voice care"),
            ("brain", "Mental health"),
            ("activity", "Heart care"),
            ("walking", "Walking"),
            ("running", "Running"),
            ("gym", "Fitness"),
            ("yoga", "Wellness"),
            ("heart", "Heart"),
        ]),
        group("Leisure", symbol: "gamepad", icons: [
            ("bookmark-book", "Event"),
            ("movie", "Movies"),
            ("music-double-note", "Music"),
            ("antenna", "Radio"),
            ("gamepad", "Video games"),
            ("dice-five", "Games"),
            ("palette", "Art"),
            ("color-filter", "Color"),
            ("media-image", "Photos"),
            ("book", "Reading"),
            ("puzzle", "Puzzles"),
            ("cinema-old", "Cinema"),
            ("microphone", "Karaoke"),
            ("basketball", "Sports"),
            ("trophy", "Competition"),
            ("birthday-cake", "Celebration"),
        ]),
        group("Work", symbol: "graduation-cap", icons: [
            ("graduation-cap", "Education"),
            ("book-stack", "Books"),
            ("bag", "School bag"),
            ("edit-pencil", "Writing"),
            ("ruler", "Design"),
            ("sigma-function", "Mathematics"),
            ("page", "Document"),
            ("printer", "Printing"),
            ("mail", "Email"),
            ("send", "Message"),
            ("group", "Team"),
            ("stats-report", "Reports"),
            ("calendar", "Schedule"),
            ("input-field", "Typing"),
            ("computer", "Office computer"),
            ("building", "Office"),
        ]),
        group("Nature", symbol: "wolf", icons: [
            ("wolf", "Pets"),
            ("fish", "Fish"),
            ("jellyfish", "Marine life"),
            ("leaf", "Leaf"),
            ("tree", "Trees"),
            ("pine-tree", "Forest"),
            ("flower", "Flowers"),
            ("sun-light", "Sun"),
            ("half-moon", "Night"),
            ("rain", "Rain"),
            ("snow-flake", "Snow"),
            ("trekking", "Outdoors"),
            ("globe", "World"),
            ("sea-waves", "Sea"),
            ("sea-and-sun", "Beach"),
            ("cloud", "Cloud"),
        ]),
        group("Services", symbol: "settings", icons: [
            ("settings", "Service"),
            ("wrench", "Mechanic"),
            ("tools", "Maintenance"),
            ("hammer", "Construction"),
            ("color-filter", "Decorating"),
            ("trash", "Waste"),
            ("refresh", "Recycling"),
            ("network", "Network"),
            ("antenna", "Mobile service"),
            ("flash", "Energy"),
            ("shield-check", "Protection"),
            ("home-secure", "Secure service"),
            ("badge-check", "Verified service"),
            ("warning-triangle", "Urgent"),
            ("help-circle", "Support"),
            ("lifebelt", "Help"),
        ]),
    ]

    static let choices = groups.flatMap(\.icons).map(\.symbol)

    static func group(containing symbol: String) -> CategoryIconGroup? {
        groups.first { group in
            group.icons.contains { $0.symbol == AppIcons.canonicalName(symbol) }
        }
    }

    private static func group(
        _ title: String,
        symbol: String,
        icons: [(String, String)]
    ) -> CategoryIconGroup {
        CategoryIconGroup(
            title: title,
            symbol: symbol,
            icons: icons.map { icon in
                CategoryIconOption(symbol: icon.0, title: icon.1)
            }
        )
    }
}

struct CategoryIconPicker: View {
    @Binding var selection: String
    let color: CategoryColor
    @State private var selectedGroupID: String

    init(selection: Binding<String>, color: CategoryColor) {
        _selection = selection
        self.color = color
        _selectedGroupID = State(
            initialValue: CategoryIconCatalog.group(containing: selection.wrappedValue)?.id
                ?? CategoryIconCatalog.groups[0].id
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(CategoryIconCatalog.groups) { group in
                        groupButton(group)
                    }
                }
                .padding(.horizontal, 1)
            }
            .scrollIndicators(.hidden)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 40), spacing: 12)],
                spacing: 12
            ) {
                ForEach(selectedGroup.icons) { option in
                    iconButton(option)
                }
            }
            .id(selectedGroup.id)
        }
        .padding(.vertical, 4)
        .onChange(of: selection) { _, newSelection in
            if let group = CategoryIconCatalog.group(containing: newSelection) {
                selectedGroupID = group.id
            }
        }
    }

    private var selectedGroup: CategoryIconGroup {
        CategoryIconCatalog.groups.first { $0.id == selectedGroupID }
            ?? CategoryIconCatalog.groups[0]
    }

    private func groupButton(_ group: CategoryIconGroup) -> some View {
        let isSelected = group.id == selectedGroupID

        return Button {
            withAnimation(.snappy) {
                selectedGroupID = group.id
            }
        } label: {
            Label(group.title, icon: group.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? color.selectionForegroundColor : .primary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(
                    isSelected ? color.swiftUIColor : Color.secondary.opacity(0.12),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func iconButton(_ option: CategoryIconOption) -> some View {
        let isSelected = AppIcons.canonicalName(selection) == option.symbol

        return Button {
            selection = option.symbol
        } label: {
            AppIcon(option.symbol, size: 17)
                .foregroundStyle(isSelected ? color.selectionForegroundColor : color.swiftUIColor)
                .frame(width: 40, height: 40)
                .background(
                    isSelected ? color.swiftUIColor : Color.secondary.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 11)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct CategoryColorPicker: View {
    @Binding var selection: CategoryColor

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 34), spacing: 12)],
            spacing: 12
        ) {
            ForEach(CategoryColor.allCases) { choice in
                Button {
                    selection = choice
                } label: {
                    Circle()
                        .fill(choice.swiftUIColor)
                        .frame(width: 34, height: 34)
                        .overlay {
                            if selection == choice {
                                AppIcon("check", size: 12)
                                    .foregroundStyle(choice.selectionForegroundColor)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(choice.title)
                .accessibilityAddTraits(selection == choice ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

extension CategoryColor {
    var swiftUIColor: Color {
        switch self {
        case .red: .red
        case .coral: Color(red: 1.00, green: 0.38, blue: 0.35)
        case .orange: .orange
        case .amber: Color(red: 1.00, green: 0.69, blue: 0.10)
        case .yellow: .yellow
        case .lime: Color(red: 0.66, green: 0.86, blue: 0.16)
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .turquoise: Color(red: 0.10, green: 0.78, blue: 0.70)
        case .cyan: .cyan
        case .sky: Color(red: 0.25, green: 0.70, blue: 0.95)
        case .blue: .blue
        case .navy: Color(red: 0.13, green: 0.27, blue: 0.58)
        case .indigo: .indigo
        case .violet: Color(red: 0.49, green: 0.24, blue: 0.93)
        case .purple: .purple
        case .lavender: Color(red: 0.70, green: 0.55, blue: 0.96)
        case .pink: .pink
        case .rose: Color(red: 0.91, green: 0.23, blue: 0.45)
        case .brown: .brown
        case .slate: Color(red: 0.38, green: 0.45, blue: 0.55)
        case .gray: .gray
        }
    }

    var selectionForegroundColor: Color {
        switch self {
        case .amber, .yellow, .lime, .mint, .cyan, .sky, .lavender:
            Color.black.opacity(0.78)
        default:
            .white
        }
    }
}

extension TransactionCategory {
    var displayIcon: String {
        AppIcons.canonicalName(icon ?? legacyAppearance.symbol)
    }

    var displayColor: Color {
        displayCategoryColor.swiftUIColor
    }

    var displayCategoryColor: CategoryColor {
        color ?? legacyAppearance.color
    }

    private var legacyAppearance: (symbol: String, color: CategoryColor) {
        switch systemKey {
        case "expense.food-drink": ("cutlery", .orange)
        case "expense.groceries": ("cart", .green)
        case "expense.fuel": ("gas", .orange)
        case "expense.transport": ("car", .blue)
        case "expense.housing": ("home-simple", .indigo)
        case "expense.utilities": ("flash", .orange)
        case "expense.shopping": ("shopping-bag", .pink)
        case "expense.health": ("healthcare", .red)
        case "expense.insurance": ("shield", .teal)
        case "expense.entertainment": ("bookmark-book", .purple)
        case "expense.education": ("book", .indigo)
        case "expense.travel": ("airplane", .cyan)
        case "expense.subscriptions": ("repeat", .purple)
        case "expense.fees-charges": ("percentage", .gray)
        case "expense.gifts-donations": ("gift", .pink)
        case "income.salary": ("cash", .green)
        case "income.business-freelance": ("suitcase", .blue)
        case "income.investments": ("graph-up", .teal)
        case "income.refunds": ("undo", .orange)
        case "income.gifts-received": ("gift", .pink)
        default: ("label", kind == .income ? .green : .gray)
        }
    }
}
