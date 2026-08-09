# Design QA — BookLens onboarding

## Visual truth

- Surface: native macOS SwiftUI first-run onboarding.
- Public language: English only.
- Public captures:
  - `Documentation/screenshots/01-onboarding-account-and-limit.png`
  - `Documentation/screenshots/02-onboarding-privacy.png`
  - `Documentation/screenshots/03-english-only-settings.png`
  - `Documentation/screenshots/04-onboarding-dark.png`
- States: connected ChatGPT account with plan limit, expanded privacy disclosure, English-only Settings, and automatic readiness checking in Dark Mode.

## Resolved findings

1. P1 — packaged hero artwork was initially missing because the resource was resolved through the wrong bundle. Resource loading now uses `Bundle.module`.
2. P2 — the connection pane was too narrow and vertically centered. The final layout uses a 54/46 split, a wider top-aligned panel, and larger controls.
3. P1 — selecting the connected ChatGPT account could persist consent without leaving the onboarding screen. The disclosure version and completion flag now update together in `RootView`.
4. Product clarity — the account card now states that BookLens uses the user's existing ChatGPT subscription and plan limits, with no API key or separate OpenAI API billing.
5. Public-language pass — the shipping bundle, interface, analysis output, prompts, Settings, README, and screenshots are English-only.

## Final verification

- The remaining plan percentage, progress bar, limit window, and reset time are visible before the user enters the app.
- Account readiness checking sends no book file or excerpt.
- Both **Use this ChatGPT account** and **Continue without AI** transition to the main interface.
- Primary and secondary choices are exposed as named accessibility buttons; privacy details are exposed as a disclosure control.
- The main window opens at the active display's full visible size and uses the same size for the system Zoom action.
- The four public screenshots contain no private library content.

## Result

Passed. No blocking visual, interaction, privacy, or public-language issues remain.
