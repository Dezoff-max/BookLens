# BookLens 1.1.0 Preview

BookLens uses **your own ChatGPT account, subscription, and plan limits** through the installed Codex CLI. No API key or separate OpenAI API billing is used. Your local library is preserved when updating.

## What's new

- GPT-6.1-Sol, GPT-6-Astra, GPT-6-Sol, and GPT-6-Luna support, subject to account availability.
- Live, paginated model discovery without family-name restrictions. Future visible models can appear without another BookLens update.
- Full model names in Settings and Studio; reasoning levels follow the selected model's capabilities.
- Available saved selections are preserved. Removed models use Codex's recommended default. Failed refreshes retain the previous selection.
- Localized catalog status and reasoning labels in English, Russian, and Spanish.
- Updated English Settings and About screenshots.

## Verification

- 66 automated tests passed on Apple Silicon.
- Live Codex 0.162.1 handshake, ChatGPT account check, limits, and model catalog passed.
- All four new models completed a tool-free, schema-constrained synthetic text request through the BookLens adapter; no user book content was sent.
- Native Settings model selection and model-specific reasoning controls checked. Switching from Astra's ultra effort to Luna resets to a supported effort; refreshing keeps the selected model.
- Release DMG mounted read-only; its app passed strict code-signature verification and matched the installed app executable.

## Install

Download `BookLens-1.1.0.dmg`, open it, and drag BookLens to Applications. Quit an older running BookLens first. macOS 15 or later and Apple Silicon are required for this binary. Codex CLI 0.146.0 or later must expose the compatible app-server protocol; this release was tested with 0.162.1.

The preview is **ad-hoc signed, not Developer ID signed or notarized**. Gatekeeper can require explicit approval. The accompanying `.sha256` file verifies download integrity.

Image generation and clean-profile sign-in/sign-out were not repeated for this update. Existing image-generation smoke evidence is historical; see `CODEX_COMPATIBILITY.md`.
