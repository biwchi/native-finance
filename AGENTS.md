# Project instructions

## Commit messages

Use `type(scope): short description`, followed by a body explaining the details.
Examples of types: `feat`, `fix`, `chore`, `migrate`, `refactor`.

## iOS colors and contrast

- Reuse `AccentSelectionButton`, `PrimaryActionButton`, and `PrimaryIconButton` from `UI/AccentControls.swift` for accent-filled controls.
- Keep foreground, fill, and spinner colors inside those components; update `AccentColor` and `OnAccentColor` together.
- Check changed controls in light/dark mode, including selected, disabled, pressed, and loading states; report any unverified states.
- Run `AccentControlContrastTests` when changing shared controls or their colors.
