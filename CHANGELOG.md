# Changelog

## 1.1.0 — 2026-10-11

- Added GPT-6.1-Sol, GPT-6-Astra, GPT-6-Sol, and GPT-6-Luna to the bundled fallback list; live account availability comes from Codex.
- Removed the Luna/Terra/Sol-only filter. All visible models are now loaded in server order, including future families and paginated results.
- Settings and Studio now display full model names in a menu rather than ambiguous family-only segments.
- Preserved available saved models and reasoning choices; retired models use the server default, and unsupported efforts use the selected model's default.
- Kept the previous selection on catalog refresh failure and added localized offline/refresh status in English, Russian, and Spanish.
- Verified Codex 0.162.1 handshake, ChatGPT account, plan limits, live catalog, and tool-free structured responses from all four new models.
- Updated the application bundle to version 1.1.0 (5). Authentication, subscription billing, and local book storage are unchanged.

## 1.0.1

- Added explicit first-run disclosure and local-only mode for ChatGPT features.
- Added per-operation confirmation before book analysis and image generation.
- Isolated local-book analysis and reject unexpected tool use.
- Added bounded TXT/PDF/EPUB import and bounded unzip subprocess output/time.
- Hardened Codex executable discovery and authentication URL validation.
- Bounded JSON-RPC frames and made diagnostics opt-in with mandatory redaction.
- Added publication guardrails, CI, security policy, and privacy documentation.
