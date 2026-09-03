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

## Verification

Run `AccentControlContrastTests` after changing accent assets or shared controls. `DesignSystemArchitectureTests` prevents named colors from bypassing `AppColor` and prevents unrelated top-level types from accumulating in one production file.
