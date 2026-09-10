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
- Apply `SwitchToggleStyle(tint: AppColor.switchTrack)` to forms with switches. The native white thumb needs a separate track color from the app accent in dark mode.
- Use `AppColor.foreground(on:)` for labels and checkmarks on opaque palette fills, and `AppColor.iconForeground(for:)` for colored artwork on native surfaces or translucent badges.
- Composite custom filled controls before applying disabled or pressed opacity so the label and background fade together.

## Verification

Run `AccentControlContrastTests` after changing accent assets or shared controls. `DesignSystemArchitectureTests` prevents named colors from bypassing `AppColor` and prevents unrelated top-level types from accumulating in one production file.

## Older iOS versions

All app pages use soft top and bottom edges through `ScrollEdgeFadeModifier` and `ScrollEdgeBlurView`. `AppList` and `AppForm` apply them automatically; other vertical scroll screens use `.scrollEdgeFades()`. On iOS 26, the native `.soft` top edge keeps expanded and collapsed navigation titles above its effect. Do not place a custom top overlay over those scroll containers: iOS 26 hosts large titles inside the scrolling content. Older versions retain the dashboard's custom top fade. The native navigation background stays hidden. All versions use the custom bottom fade, with the native bottom effect hidden on iOS 26. Bottom overlays extend behind floating controls, allow touches through, and respect the keyboard's safe area. Do not add opaque `.bar` backgrounds to bottom controls.

Gradient pages use `AppList(usesScrollEdgeFades: false)` with `.financePage()`, which owns a single pair of fades and supplies its moving background to the top edge.

Home has no native page title and uses `usesNativeTopEdge: false` on the detached-content overload of `.financePage()`. Its custom fade covers the summary glass drawn outside the list as well as the rows. Keep the default native top edge on pages with navigation titles.

Use `AppList`, `AppForm`, and `AppSection` for grouped screens. iOS 26 keeps its native containers. On iOS 17 and 18, the wrappers use 16-point horizontal insets, 15-point row padding, 26-point continuous section corners, and explicit header/footer spacing. Put custom row insets and backgrounds on the row itself so summary cards and spacers retain their layout.

Section headers preserve their original casing and use the iOS 26 text size. Keep `.textCase(nil)` on the legacy section itself: older lists can reapply uppercase after scrolling when the modifier is only on the header label. Home uses `AppList(usesCompactTopSpacing: true)` for its eight-point gap below the legacy toolbar.

`AppForm` gives legacy forms a 52-point minimum row height, 16-point vertical row insets, and eight additional points above section labels. These defaults are scoped to forms. Native multiline controls can collapse their row insets when a minimum height is set; the Settings currency label owns its vertical padding to preserve both lines and their spacing.

`LegacyListAppearance` observes only the backing collection view of its own list. It updates public layer properties, preserves UIKit's corner masks, and never replaces the list delegate or data source. Its observations end when the view leaves the window. `LegacyNavigationAppearance` styles the native back indicator and keeps native navigation handling.

Use `legacyToolbarControl()` for toolbar items that rely on the system's iOS 26 glass background. Already shaped controls own their fallback through `LegacyGlassSurface`. Use `legacySheetAppearance()` on custom sheet content. Liquid Glass and system-presented menu internals remain supplied by the installed OS; the older fallback uses materials and matching app geometry.

Run `LegacyAppearanceTests`, `AccentControlContrastTests`, `FinanceToolbarBlurTests`, and `DesignSystemArchitectureTests` on both iOS 18 and iOS 26 after changing these adapters. The rendering tests attach light/dark screenshots; the compatibility tests also exercise cell reuse and explicit row insets.
