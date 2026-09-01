import SwiftUI

struct CategoryIcon: View {
    let category: TransactionCategory
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: category.displayIcon)
            .font(.system(size: size * 0.43, weight: .medium))
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
        group("General", symbol: "square.grid.2x2.fill", icons: [
            ("tag.fill", "Tag"),
            ("star.fill", "Star"),
            ("heart.fill", "Heart"),
            ("bookmark.fill", "Bookmark"),
            ("flag.fill", "Flag"),
            ("bell.fill", "Bell"),
            ("pin.fill", "Pin"),
            ("paperclip", "Paperclip"),
            ("folder.fill", "Folder"),
            ("tray.fill", "Tray"),
            ("archivebox.fill", "Archive"),
            ("gift.fill", "Gift"),
            ("calendar", "Calendar"),
            ("clock.fill", "Clock"),
            ("person.fill", "Person"),
            ("ellipsis.circle.fill", "Other"),
        ]),
        group("Food", symbol: "fork.knife", icons: [
            ("fork.knife", "Meal"),
            ("cup.and.saucer.fill", "Coffee"),
            ("takeoutbag.and.cup.and.straw.fill", "Takeout"),
            ("basket.fill", "Groceries"),
            ("birthday.cake.fill", "Cake"),
            ("wineglass.fill", "Drinks"),
            ("mug.fill", "Hot drink"),
            ("carrot.fill", "Produce"),
            ("popcorn.fill", "Snacks"),
            ("fish.fill", "Seafood"),
            ("leaf.fill", "Organic food"),
            ("frying.pan.fill", "Cooking"),
            ("refrigerator.fill", "Refrigerator"),
            ("oven.fill", "Oven"),
            ("waterbottle.fill", "Water"),
            ("flame.fill", "Grill"),
        ]),
        group("Finance", symbol: "banknote.fill", icons: [
            ("banknote.fill", "Cash"),
            ("creditcard.fill", "Credit card"),
            ("building.columns.fill", "Bank"),
            ("dollarsign.circle.fill", "Dollars"),
            ("centsign.circle.fill", "Coins"),
            ("percent", "Interest"),
            ("chart.line.uptrend.xyaxis", "Growth"),
            ("chart.pie.fill", "Budget"),
            ("wallet.pass.fill", "Wallet"),
            ("receipt.fill", "Receipt"),
            ("barcode", "Barcode"),
            ("qrcode", "QR code"),
            ("arrow.left.arrow.right", "Transfer"),
            ("repeat", "Recurring payment"),
            ("arrow.uturn.backward", "Refund"),
            ("briefcase.fill", "Business"),
        ]),
        group("Travel", symbol: "airplane", icons: [
            ("airplane", "Flight"),
            ("car.fill", "Car"),
            ("bus.fill", "Bus"),
            ("tram.fill", "Train"),
            ("bicycle", "Bicycle"),
            ("scooter", "Scooter"),
            ("fuelpump.fill", "Fuel"),
            ("ev.charger.fill", "EV charging"),
            ("ferry.fill", "Ferry"),
            ("cablecar.fill", "Cable car"),
            ("sailboat.fill", "Boat"),
            ("map.fill", "Map"),
            ("mappin.and.ellipse", "Place"),
            ("suitcase.rolling.fill", "Luggage"),
            ("bed.double.fill", "Hotel"),
            ("tent.fill", "Camping"),
        ]),
        group("Home", symbol: "house.fill", icons: [
            ("house.fill", "Home"),
            ("building.2.fill", "Building"),
            ("sofa.fill", "Furniture"),
            ("lamp.table.fill", "Lighting"),
            ("key.fill", "Keys"),
            ("lock.fill", "Security"),
            ("lightbulb.fill", "Electricity"),
            ("bolt.fill", "Power"),
            ("drop.fill", "Water"),
            ("wifi", "Internet"),
            ("phone.fill", "Phone"),
            ("tv.fill", "Television"),
            ("washer.fill", "Laundry"),
            ("wrench.and.screwdriver.fill", "Repairs"),
            ("hammer.fill", "Renovation"),
            ("shield.fill", "Insurance"),
        ]),
        group("Shopping", symbol: "bag.fill", icons: [
            ("bag.fill", "Shopping bag"),
            ("cart.fill", "Shopping cart"),
            ("storefront.fill", "Store"),
            ("tshirt.fill", "Clothing"),
            ("shoe.fill", "Shoes"),
            ("handbag.fill", "Handbag"),
            ("sunglasses", "Accessories"),
            ("watch.analog", "Watch"),
            ("diamond.fill", "Jewelry"),
            ("camera.fill", "Camera"),
            ("headphones", "Audio"),
            ("desktopcomputer", "Computer"),
            ("laptopcomputer", "Laptop"),
            ("smartphone", "Phone"),
            ("shippingbox.fill", "Delivery"),
            ("scissors", "Personal care"),
        ]),
        group("Health", symbol: "cross.case.fill", icons: [
            ("cross.case.fill", "Medical care"),
            ("heart.text.square.fill", "Health record"),
            ("pill.fill", "Medicine"),
            ("pills.fill", "Prescriptions"),
            ("stethoscope", "Doctor"),
            ("bandage.fill", "First aid"),
            ("syringe.fill", "Vaccination"),
            ("facemask.fill", "Mask"),
            ("eye.fill", "Eye care"),
            ("ear.fill", "Hearing"),
            ("brain.head.profile", "Mental health"),
            ("waveform.path.ecg", "Heart care"),
            ("figure.walk", "Walking"),
            ("figure.run", "Running"),
            ("dumbbell.fill", "Fitness"),
            ("figure.mind.and.body", "Wellness"),
        ]),
        group("Leisure", symbol: "ticket.fill", icons: [
            ("ticket.fill", "Event"),
            ("film.fill", "Movies"),
            ("music.note.list", "Music"),
            ("radio.fill", "Radio"),
            ("gamecontroller.fill", "Video games"),
            ("dice.fill", "Games"),
            ("paintpalette.fill", "Art"),
            ("paintbrush.fill", "Painting"),
            ("photo.fill", "Photos"),
            ("book.fill", "Reading"),
            ("puzzlepiece.fill", "Puzzles"),
            ("theatermasks.fill", "Theater"),
            ("mic.fill", "Karaoke"),
            ("sportscourt.fill", "Sports"),
            ("trophy.fill", "Competition"),
            ("party.popper.fill", "Celebration"),
        ]),
        group("Work", symbol: "graduationcap.fill", icons: [
            ("graduationcap.fill", "Education"),
            ("books.vertical.fill", "Books"),
            ("backpack.fill", "School"),
            ("pencil", "Writing"),
            ("ruler", "Design"),
            ("function", "Mathematics"),
            ("doc.fill", "Document"),
            ("printer.fill", "Printing"),
            ("envelope.fill", "Email"),
            ("paperplane.fill", "Message"),
            ("person.2.fill", "Team"),
            ("chart.bar.fill", "Reports"),
            ("calendar.badge.clock", "Schedule"),
            ("keyboard.fill", "Keyboard"),
            ("display", "Office computer"),
            ("building.fill", "Office"),
        ]),
        group("Nature", symbol: "pawprint.fill", icons: [
            ("pawprint.fill", "Pets"),
            ("dog.fill", "Dog"),
            ("cat.fill", "Cat"),
            ("bird.fill", "Bird"),
            ("hare.fill", "Small pet"),
            ("tortoise.fill", "Tortoise"),
            ("ladybug.fill", "Insects"),
            ("ant.fill", "Ant"),
            ("tree.fill", "Trees"),
            ("camera.macro", "Flowers"),
            ("sun.max.fill", "Sun"),
            ("moon.stars.fill", "Night"),
            ("cloud.rain.fill", "Rain"),
            ("snowflake", "Snow"),
            ("mountain.2.fill", "Outdoors"),
            ("globe.americas.fill", "World"),
        ]),
        group("Services", symbol: "gearshape.fill", icons: [
            ("gearshape.fill", "Service"),
            ("wrench.fill", "Mechanic"),
            ("screwdriver.fill", "Maintenance"),
            ("hammer.circle.fill", "Construction"),
            ("paintbrush.pointed.fill", "Decorating"),
            ("trash.fill", "Waste"),
            ("arrow.3.trianglepath", "Recycling"),
            ("network", "Network"),
            ("antenna.radiowaves.left.and.right", "Mobile service"),
            ("bolt.circle.fill", "Energy"),
            ("shield.checkered", "Protection"),
            ("lock.shield.fill", "Secure service"),
            ("checkmark.seal.fill", "Verified service"),
            ("exclamationmark.triangle.fill", "Urgent"),
            ("questionmark.circle.fill", "Support"),
            ("lifepreserver.fill", "Help"),
        ]),
    ]

    static let choices = groups.flatMap(\.icons).map(\.symbol)

    static func group(containing symbol: String) -> CategoryIconGroup? {
        groups.first { group in
            group.icons.contains { $0.symbol == symbol }
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
            Label(group.title, systemImage: group.symbol)
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
        let isSelected = selection == option.symbol

        return Button {
            selection = option.symbol
        } label: {
            Image(systemName: option.symbol)
                .font(.body.weight(.semibold))
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
                                Image(systemName: "checkmark")
                                    .font(.caption.bold())
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
        icon ?? legacyAppearance.symbol
    }

    var displayColor: Color {
        displayCategoryColor.swiftUIColor
    }

    var displayCategoryColor: CategoryColor {
        color ?? legacyAppearance.color
    }

    private var legacyAppearance: (symbol: String, color: CategoryColor) {
        switch systemKey {
        case "expense.food-drink": ("fork.knife", .orange)
        case "expense.groceries": ("basket.fill", .green)
        case "expense.fuel": ("fuelpump.fill", .orange)
        case "expense.transport": ("car.fill", .blue)
        case "expense.housing": ("house.fill", .indigo)
        case "expense.utilities": ("bolt.fill", .orange)
        case "expense.shopping": ("bag.fill", .pink)
        case "expense.health": ("cross.case.fill", .red)
        case "expense.insurance": ("shield.fill", .teal)
        case "expense.entertainment": ("ticket.fill", .purple)
        case "expense.education": ("book.fill", .indigo)
        case "expense.travel": ("airplane", .cyan)
        case "expense.subscriptions": ("repeat", .purple)
        case "expense.fees-charges": ("percent", .gray)
        case "expense.gifts-donations": ("gift.fill", .pink)
        case "income.salary": ("banknote.fill", .green)
        case "income.business-freelance": ("briefcase.fill", .blue)
        case "income.investments": ("chart.line.uptrend.xyaxis", .teal)
        case "income.refunds": ("arrow.uturn.backward", .orange)
        case "income.gifts-received": ("gift.fill", .pink)
        default: ("tag.fill", kind == .income ? .green : .gray)
        }
    }
}
