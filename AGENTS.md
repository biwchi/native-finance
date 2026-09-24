# Project instructions

## Commit messages

Use `type(scope): short description`, followed by a body explaining the details.
Examples of types: `feat`, `fix`, `chore`, `migrate`, `refactor`.

## iOS colors and contrast

- Reuse `AccentSelectionButton`, `PrimaryActionButton`, and `PrimaryIconButton` from `UI/AccentControls.swift` for accent-filled controls.
- Keep foreground, fill, and spinner colors inside those components; update `AccentColor` and `OnAccentColor` together.
- Check changed controls in light/dark mode, including selected, disabled, pressed, and loading states; report any unverified states.

Before changing quick entry, scan interpretation, or transaction features they must support, read and follow [the transaction prompt maintenance guide](docs/transaction-prompt-maintenance.md). Keep prompts, extraction schemas, application rules, and draft review behavior aligned. Use local verification; do not add or run tests that call real AI unless the user explicitly authorizes that work.

## Verification

- Use the smallest verification that covers the changed code. Do not run the full iOS test suite after every change.
- For isolated logic changes, run only the related test class or test method with `-only-testing:FinanceTrackerTests/<TestClass>[/<testMethod>]`.
- For UI changes, build the app first. Run simulator rendering tests only for the changed screen or a shared component that the change affects.
- Do not run screenshot-attachment tests as routine verification. Run them only when the related UI changed or the user requests visual verification, and inspect their screenshots when they are run.
- Run `AccentControlContrastTests` only when accent colors, shared accent controls, or their states change.
- Run the full iOS suite only when the user requests it, when a change broadly affects shared persistence, navigation, design-system, or application infrastructure, or when performing release verification.
- Reuse DerivedData. Do not use clean builds or delete build caches unless diagnosing a build-cache problem.
- Report which checks ran and which broader checks were skipped.
