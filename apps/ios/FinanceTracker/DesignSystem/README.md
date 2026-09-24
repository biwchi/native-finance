# FinanceTracker UI architecture

UI dependencies flow in one direction:

1. `DesignSystem/Tokens` owns app-wide semantic values such as accent, surface, spacing, radius, and control size.
2. `DesignSystem/Primitives` owns small reusable controls with no finance or feature knowledge.
3. `DesignSystem/Components` owns generic compositions built only from tokens and primitives.
4. `Shared/Finance` owns reusable finance-domain presentation such as summary cards and section headers.
5. `Features/<Feature>/Components` owns UI that is meaningful only inside that feature.
6. `Features/<Feature>/Screens` composes components and owns navigation, loading, and feature state.

Lower layers must not depend on higher layers. In particular, the design system must not refer to accounts, budgets, categories, or transactions.

## Adding or changing UI

- Choose semantic roles, not literal values. Add a global color to `AppColor.swift` and its asset catalog entry, then use the token everywhere.
- Change `AccentColor` and `OnAccentColor` together so accent-filled controls retain readable foregrounds.
- Reuse `AccentSelectionButton`, `PrimaryActionButton`, and `PrimaryIconButton` for accent-filled interactions.
- Keep one primary type per Swift file and name the file after that type.
- Put a view in `DesignSystem` only when it is generic. Put finance-wide presentation in `Shared/Finance`; otherwise keep it inside the owning feature.
- Keep state transitions, persistence, and navigation in screens or view models rather than generic primitives.
- Use `IconPicker(selection:)` for icon selection. It scrolls continuously through labeled groups from `AppIconCatalog`, with spacing between groups and fades at both horizontal edges. Categories, accounts, debt recipients, and goals share this catalog and its four-row layout. Use `CategoryColorPicker(selection:)` above it in the same `AppSection("Icon")` for the category, recipient, and goal palette; selected swatches use the shared contrasting checkmark. Its `AccentSelectionButton` tiles use accent fill when selected and accent artwork on a secondary background otherwise.
- Keep `AppIconCatalog` focused on recognizable entities, purchases, and financial purposes. Groups can have different sizes. Prefer one placement per icon; repeat only where it helps discovery, such as groceries/shopping, drinking water/utilities, and seafood/aquariums. Retire choices from the catalog without removing or remapping saved identifiers in `AppIcons`. Use a new identifier for different artwork, such as `luggage`, while the saved `suitcase` identifier keeps its business briefcase.
- `AccentSelectionButton` supports `.iconBadge` for suggested icons. Selected badges use an opaque palette fill with contrasting artwork; unselected badges use tinted artwork on a translucent fill. Hide suggestions when the editor name is empty.
- Apply `SwitchToggleStyle(tint: AppColor.switchTrack)` to forms with switches. The native white thumb needs a separate track color from the app accent in dark mode.
- Use `AppColor.foreground(on:)` for labels and checkmarks on opaque palette fills, and `AppColor.iconForeground(for:)` for colored artwork on native surfaces or translucent badges.
- Primary action buttons keep an opaque fill when disabled and loading. Use `AppColor.disabledControlFill` and the muted `AppColor.disabledControlForeground` for the disabled state. Other custom filled controls composite their label and background before applying opacity.

Use `AppRowActions` for trailing row actions. It shows one or two actions as separate accessible buttons and three or more in a menu. Supply each action once with its title, icon, role, and callback. Scan drafts share `ScanDraftActions` between the sheet and floating control so action availability and ordering stay aligned.

## Verification

Run `AccentControlContrastTests` after changing accent assets or shared controls. `DesignSystemArchitectureTests` prevents named colors from bypassing `AppColor` and prevents unrelated top-level types from accumulating in one production file.

## Older iOS versions

All app pages use soft top and bottom edges through `ScrollEdgeFadeModifier` and `ScrollEdgeBlurView`. `AppList` and `AppForm` apply them automatically; other vertical scroll screens use `.scrollEdgeFades()`. On iOS 26, the native `.soft` top edge keeps expanded and collapsed navigation titles above its effect. Do not place a custom top overlay over those scroll containers: iOS 26 hosts large titles inside the scrolling content. Older versions retain the dashboard's custom top fade. The native navigation background stays hidden. All versions use the custom bottom fade, with the native bottom effect hidden on iOS 26. Bottom overlays extend behind floating controls and allow touches through. Only the bottom overlay ignores the keyboard safe area, keeping its fade behind the keyboard while the page content still avoids it. Do not add opaque `.bar` backgrounds to bottom controls.

Gradient pages use `AppList(usesScrollEdgeFades: false)` with `.financePage()`, which owns a single pair of fades and supplies its moving background to the top edge.

Home has no native page title and uses `usesNativeTopEdge: false` on the detached-content overload of `.financePage()`. Its custom fade covers the summary glass drawn outside the list as well as the rows. Keep the default native top edge on pages with navigation titles.

Use `AppList`, `AppForm`, and `AppSection` for every grouped screen, including sheets. Do not introduce native `List`, `Form`, or `Section` in feature code. `AppList` owns the inset-grouped container and 16-point horizontal margins on every version. `AppSection` owns 15-point row padding, trailing separator alignment, and explicit header/footer typography, casing, and insets. It compensates for the older list header margins inside the component so screens do not need version checks. Older systems adapt section corners to the same 26-point continuous radius. Put custom row insets and backgrounds on the row itself so summary cards and spacers retain their layout. `DesignSystemArchitectureTests` prevents screens from bypassing these containers.

For dynamic sections, apply `.animateListChanges(value: items.map(\.id))` to the containing `AppList` or `AppForm`. This shares the transaction list's 0.3-second removal and gap-closing animation, including asynchronous removals and empty section headers. Observe stable item IDs so status and text updates do not trigger row animations. The modifier respects Reduce Motion.

Section headers preserve their original casing and use the same body semibold font on every version. Keep `.textCase(nil)` on the section itself: older lists can reapply uppercase after scrolling when the modifier is only on the header label. Home uses `AppList(usesCompactTopSpacing: true)` for its eight-point gap below the legacy toolbar.

`AppForm` uses `AppList` on every version, with a 52-point minimum row height, 16-point vertical row insets, and eight additional points above section labels. These defaults are scoped to forms. Native multiline controls can collapse their row insets when a minimum height is set; the Settings currency label owns its vertical padding to preserve both lines and their spacing.

`LegacyListAppearance` observes only the backing collection view of its own list. It updates public layer properties, preserves UIKit's corner masks, and never replaces the list delegate or data source. Its observations end when the view leaves the window. `AppNavigationLink` applies the shared destination toolbar on iOS 17 through 25. Apply `.legacyNavigationDestination()` inside programmatic `navigationDestination` builders too. The 44-point back control uses `LegacyGlassSurface`, appears in the first transition frame, and retains a long-press ancestor menu. `LegacyNavigationAppearance` preserves the native navigation controller delegate and adapts only the pop gesture delegate. Use `.appBackNavigationDisabled(isSaving)` when a screen must block Back during a save. iOS 26 retains its native back button.

Use `legacyToolbarIcon()` for standalone icon toolbar buttons. It fixes both dimensions at 44 points and uses a circle. Use `legacyToolbarControl()` for text capsules and grouped toolbar items. Already shaped controls own their fallback through `LegacyGlassSurface`. Liquid Glass and system-presented menu internals remain supplied by the installed OS; the older fallback uses materials and matching app geometry.

Run `LegacyAppearanceTests`, `AccentControlContrastTests`, `FinanceToolbarBlurTests`, and `DesignSystemArchitectureTests` on both iOS 18 and iOS 26 after changing these adapters. The rendering tests attach light/dark screenshots; the compatibility tests also exercise cell reuse and explicit row insets.

## Sheets

Present every app-owned sheet with `appSheet`. Both overloads forward the binding and `onDismiss` to SwiftUI. `AppSheet` owns the presentation corner radius through `AppRadius.sheet` on iOS 17 and later, and defaults to `AppColor.sheetBackground`. This fallback background resolves the grouped page color at the base interface level. A screen can retain its own page background, including the elevated grouped background of navigation lists.

```swift
.appSheet(isPresented: $showsEditor, onDismiss: reload) {
    EditorView()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSaving)
}

.appSheet(item: $selection, background: AppColor.elevatedSurface, onDismiss: selectionDidDismiss) { item in
    DetailView(item: item)
}
```

Keep detents, drag indicators, interactive dismissal rules, navigation stacks, and content safe areas at their existing owners inside the content closure. `@Environment(\.dismiss)` dismisses the current sheet. Apply `appSheet` inside another sheet's content to present a nested sheet. The presenter adds no navigation stack or clipping. Below iOS 26, its default `.navigation` layout adds 10 points to the presented hosting controller's top safe area so the toolbar clears the grabber. Navigation content still fills the sheet bounds, allowing its background to continue behind the grabber. Do not replace this with outer padding, which exposes a contrasting band above elevated backgrounds. This applies to both binding forms and each nested sheet independently. iOS 26 retains native spacing.

Navigation sheets need no spacing modifier. The default is part of `AppSheet`, so new sheets get it automatically. Use `layout: .content` only for content that owns its top spacing and has no navigation bar. The camera and measured date filter are the current exceptions:

```swift
.appSheet(isPresented: $showsCamera, layout: .content, background: AppColor.cameraBackground) {
    CameraView()
}
```

Do not add per-screen toolbar padding or restore `appSheetToolbarSpacing()`. The architecture tests require shared presentation styling and flag new content-layout exceptions for review. The simulator suite measures toolbar placement and compares rendered pixels above and below the inset boundary in light and dark mode.

Choose an explicit `background:` token when required. The date filter uses `AppColor.elevatedSurface`; the receipt camera uses `AppColor.cameraBackground` and retains its dark appearance. Content backgrounds and scroll backgrounds still belong to their views. Do not put `presentationCornerRadius` or `presentationBackground` in feature views or list adapters. `DesignSystemArchitectureTests` checks that the shared presenter owns them.

See [the sheet audit and simulator verification](../../../../docs/app-sheets.md) for presentation coverage and native OS differences.
