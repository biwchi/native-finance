import Iconoir
import SwiftUI
import UIKit

/// Resolves current Iconoir names and names stored by earlier SF Symbols clients.
enum AppIcons {
    static func resolve(_ name: String) -> Iconoir {
        legacyNames[name] ?? Iconoir(rawValue: name) ?? .label
    }

    static func canonicalName(_ name: String) -> String {
        resolve(name).rawValue
    }

    static func uiImage(named name: String) -> UIImage? {
        resolve(name).asUIImage?.withRenderingMode(.alwaysTemplate)
    }

    // Keep persisted icon identifiers readable without rewriting account/category data.
    static let legacyNames: [String: Iconoir] = [
        "ant.fill": .leaf,
        "antenna.radiowaves.left.and.right": .antenna,
        "archivebox.fill": .archive,
        "arrow.3.trianglepath": .refresh,
        "arrow.down.left": .arrowDownLeft,
        "arrow.left.arrow.right": .coinsSwap,
        "arrow.triangle.2.circlepath": .refreshDouble,
        "arrow.turn.down.right": .arrowRight,
        "arrow.up": .arrowUp,
        "arrow.up.right": .arrowUpRight,
        "arrow.uturn.backward": .undo,
        "backpack.fill": .bag,
        "bag.fill": .shoppingBag,
        "bandage.fill": .cubeBandage,
        "banknote": .cash,
        "banknote.fill": .cash,
        "barcode": .scanBarcode,
        "basket.fill": .cart,
        "bed.double.fill": .bed,
        "bell.fill": .bell,
        "bird.fill": .leaf,
        "birthday.cake.fill": .birthdayCake,
        "bolt.circle.fill": .flash,
        "bolt.fill": .flash,
        "book.fill": .book,
        "bookmark.fill": .bookmark,
        "books.vertical.fill": .bookStack,
        "brain.head.profile": .brain,
        "briefcase.fill": .suitcase,
        "building.2.fill": .building,
        "building.columns": .bank,
        "building.columns.fill": .bank,
        "building.fill": .building,
        "bus.fill": .bus,
        "cablecar.fill": .tram,
        "calendar.badge.clock": .calendar,
        "calendar.badge.minus": .calendarMinus,
        "camera.fill": .camera,
        "camera.macro": .flower,
        "car.fill": .car,
        "carrot.fill": .organicFood,
        "cart.fill": .cart,
        "cat.fill": .wolf,
        "centsign.circle.fill": .coins,
        "chart.bar.fill": .statsReport,
        "chart.line.uptrend.xyaxis": .graphUp,
        "chart.pie": .percentageCircle,
        "chart.pie.fill": .percentageCircle,
        "checkmark": .check,
        "checkmark.circle.fill": .checkCircle,
        "checkmark.seal.fill": .badgeCheck,
        "chevron.down": .navArrowDown,
        "chevron.forward": .navArrowRight,
        "chevron.left": .navArrowLeft,
        "chevron.right": .navArrowRight,
        "circle.lefthalf.filled": .brightness,
        "circle.slash": .prohibition,
        "clock.fill": .clock,
        "cloud.rain.fill": .rain,
        "creditcard": .creditCard,
        "creditcard.fill": .creditCard,
        "cross.case.fill": .healthcare,
        "cup.and.saucer.fill": .coffeeCup,
        "delete.left": .erase,
        "desktopcomputer": .computer,
        "diamond.fill": .brightStar,
        "dice.fill": .diceFive,
        "display": .computer,
        "doc.fill": .page,
        "dog.fill": .wolf,
        "dollarsign.circle": .dollarCircle,
        "dollarsign.circle.fill": .dollarCircle,
        "drop.fill": .droplet,
        "dumbbell.fill": .gym,
        "ear.fill": .voice,
        "ellipsis.circle.fill": .moreHorizCircle,
        "envelope.fill": .mail,
        "ev.charger.fill": .evStation,
        "exclamationmark.triangle": .warningTriangle,
        "exclamationmark.triangle.fill": .warningTriangle,
        "eye.fill": .eye,
        "facemask.fill": .maskSquare,
        "ferry.fill": .seaWaves,
        "figure.mind.and.body": .yoga,
        "figure.run": .running,
        "figure.walk": .walking,
        "film.fill": .movie,
        "fish.fill": .fish,
        "flag.fill": .whiteFlag,
        "flame.fill": .fireFlame,
        "folder.fill": .folder,
        "fork.knife": .cutlery,
        "frying.pan.fill": .cutlery,
        "fuelpump.fill": .gas,
        "function": .sigmaFunction,
        "gamecontroller.fill": .gamepad,
        "gearshape": .settings,
        "gearshape.fill": .settings,
        "gift.fill": .gift,
        "globe.americas.fill": .globe,
        "graduationcap.fill": .graduationCap,
        "hammer.circle.fill": .hammer,
        "hammer.fill": .hammer,
        "handbag.fill": .handbag,
        "hare.fill": .wolf,
        "headphones": .headset,
        "heart.fill": .heart,
        "heart.text.square.fill": .healthShield,
        "house": .homeSimple,
        "house.fill": .homeSimple,
        "key.fill": .key,
        "keyboard.fill": .inputField,
        "ladybug.fill": .flower,
        "lamp.table.fill": .lamp,
        "laptopcomputer": .laptop,
        "leaf.fill": .leaf,
        "lifepreserver.fill": .lifebelt,
        "lightbulb.fill": .lightBulb,
        "list.bullet.rectangle": .list,
        "lock.fill": .lock,
        "lock.shield.fill": .homeSecure,
        "map.fill": .map,
        "mappin.and.ellipse": .mapPin,
        "mic.fill": .microphone,
        "moon.fill": .halfMoon,
        "moon.stars.fill": .halfMoon,
        "mountain.2.fill": .trekking,
        "mug.fill": .coffeeCup,
        "music.note.list": .musicDoubleNote,
        "oven.fill": .fridge,
        "paintbrush.fill": .colorFilter,
        "paintbrush.pointed.fill": .colorFilter,
        "paintpalette.fill": .palette,
        "paperclip": .attachment,
        "paperplane.fill": .send,
        "party.popper.fill": .birthdayCake,
        "pawprint.fill": .wolf,
        "pencil": .editPencil,
        "percent": .percentage,
        "person.2.fill": .group,
        "person.fill": .user,
        "phone.fill": .phone,
        "photo.fill": .mediaImage,
        "pill.fill": .pharmacyCrossCircle,
        "pills.fill": .pharmacyCrossTag,
        "pin.fill": .pin,
        "popcorn.fill": .cookie,
        "printer.fill": .printer,
        "puzzlepiece.fill": .puzzle,
        "qrcode": .qrCode,
        "questionmark.circle.fill": .helpCircle,
        "radio.fill": .antenna,
        "receipt.fill": .page,
        "refrigerator.fill": .fridge,
        "sailboat.fill": .seaWaves,
        "scissors": .scissor,
        "scooter": .skateboard,
        "screwdriver.fill": .tools,
        "shield.checkered": .shieldCheck,
        "shield.fill": .shield,
        "shippingbox.fill": .package,
        "shoe.fill": .sandals,
        "smartphone": .smartphoneDevice,
        "snowflake": .snowFlake,
        "sofa.fill": .sofa,
        "sparkles": .sparks,
        "sportscourt.fill": .basketball,
        "square.3.layers.3d": .creditCards,
        "square.grid.2x2": .viewGrid,
        "square.grid.2x2.fill": .viewGrid,
        "square.stack.3d.up.fill": .creditCards,
        "star.fill": .star,
        "stethoscope": .healthcare,
        "storefront.fill": .shop,
        "suitcase.rolling.fill": .suitcase,
        "sun.max.fill": .sunLight,
        "sunglasses": .glasses,
        "syringe.fill": .healthShield,
        "tag": .label,
        "tag.fill": .label,
        "takeoutbag.and.cup.and.straw.fill": .pizzaSlice,
        "tent.fill": .trekking,
        "text.badge.checkmark": .clipboardCheck,
        "text.badge.plus": .pagePlus,
        "text.cursor": .inputField,
        "theatermasks.fill": .cinemaOld,
        "ticket.fill": .bookmarkBook,
        "tortoise.fill": .jellyfish,
        "tram.fill": .train,
        "trash.fill": .trash,
        "tray.fill": .archive,
        "tree.fill": .tree,
        "trophy.fill": .trophy,
        "tshirt.fill": .shirt,
        "tv.fill": .tv,
        "wallet.pass.fill": .wallet,
        "washer.fill": .washingMachine,
        "watch.analog": .wristwatch,
        "waterbottle.fill": .droplet,
        "waveform.path.ecg": .activity,
        "wifi.exclamationmark": .wifiWarning,
        "wineglass.fill": .glassHalf,
        "wrench.and.screwdriver.fill": .tools,
        "wrench.fill": .wrench,
    ]
}

/// Asset images need explicit sizing; unlike SF Symbols, they do not inherit a font size.
struct AppIcon: View {
    let name: String
    @ScaledMetric private var size: CGFloat

    init(_ name: String, size: CGFloat = 20, relativeTo textStyle: Font.TextStyle = .body) {
        self.name = name
        _size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
    }

    var body: some View {
        AppIcons.resolve(name).asImage
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

extension Label where Title == Text, Icon == Image {
    init(_ title: LocalizedStringKey, icon: String) {
        self.init { Text(title) } icon: { AppIcons.resolve(icon).asImage }
    }

    init<S: StringProtocol>(_ title: S, icon: String) {
        self.init { Text(title) } icon: { AppIcons.resolve(icon).asImage }
    }
}

extension ContentUnavailableView where Label == SwiftUI.Label<Text, AppIcon>, Description == Text, Actions == EmptyView {
    init(_ title: LocalizedStringKey, iconName: String, description: Text) {
        self.init {
            SwiftUI.Label { Text(title) } icon: { AppIcon(iconName, size: 48, relativeTo: .largeTitle) }
        } description: {
            description
        }
    }
}
