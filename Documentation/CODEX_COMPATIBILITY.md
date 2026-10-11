# Codex compatibility

## Compatibility adapter

- Current live-tested Codex CLI: `0.162.1` (BookLens 1.1.0, 2026-10-11). Historical baseline: `0.146.0`.
- Minimum accepted version: `0.146.0`.
- Newer versions are accepted only provisionally; the live handshake and every used method still have to succeed through the typed adapter.
- Architecture: `arm64`.
- Protocol: `codex app-server --stdio`, newline-delimited JSON messages.
- Auto-update: disabled by design.

Executable search order: the native npm executable under `/opt/homebrew`, then `/usr/local`, for the current architecture. BookLens does not execute npm JavaScript wrappers or arbitrary binaries on `PATH`.

Environment overrides, arbitrary `PATH` entries, npm JavaScript wrappers, executables resolving outside those roots, group/other-writable binaries, and binaries without the OpenAI Developer ID Team ID `2DC432GLL2` are rejected. BookLens displays the resolved path, version, architecture and verified Team ID.

The child `app-server` receives a deterministic GUI-safe `PATH` containing the
user npm bin plus Homebrew and system locations. BookLens displays path, version,
architecture and compatibility without reading any auth file.

## Verified protocol surface

The `0.146.0` JSON Schema was generated locally with `codex app-server generate-json-schema --experimental`. BookLens pins only this used subset:

- `initialize` / `initialized`;
- `account/read`;
- `account/rateLimits/read`;
- `model/list`;
- `account/login/start` for `chatgpt` and `chatgptDeviceCode`;
- `account/login/cancel` and `account/logout`;
- `thread/start` with optional selected `model`;
- `turn/start` with optional `outputSchema` and selected reasoning `effort`;
- `turn/interrupt`;
- `item/completed` and `turn/completed` notifications.

Unknown fields are tolerated. Optional methods are called only through the compatibility adapter and failures do not leak protocol method names into Domain.

## Current model discovery (1.1.0)

BookLens uses [`model/list`](https://learn.chatgpt.com/docs/app-server#list-models-modellist) with `includeHidden: false`, follows pagination, removes duplicate IDs, and preserves server ordering. Model names are not filtered by family. Reasoning options and defaults are taken from each model entry, not inferred from its name.

The 2026-10-11 live catalog returned GPT-6.1-Sol (default), GPT-6-Astra, GPT-6-Sol, GPT-6-Luna, and the still-available GPT-5.6 Sol/Terra/Luna models. Catalog visibility depends on Codex and account access; this is not a guarantee for every user.

With Codex 0.162.1, the app's adapter successfully completed:

- executable signature/version checks and `initialize`;
- `account/read` in ChatGPT mode and `account/rateLimits/read`;
- all visible models and their reasoning levels via `model/list`;
- `thread/start` and `turn/start` with each of the four new model IDs;
- a schema-constrained `{ "probe": "booklens", "value": 42 }` response from each new model, at `low` effort with tools disabled, in isolated temporary workspaces.

No user books or credentials were used for these probes. Image generation, clean-profile login, and logout were not repeated for this model update; earlier evidence below is historical.

## Historical live observations (0.146.0)

- Handshake returned macOS/arm64 and Codex `0.146.0` user agent.
- A ChatGPT account was present.
- A rate-limit snapshot was readable.
- The primary `codex` window exposed used percent, duration and reset time; BookLens derives and displays the remaining percent without reading auth files.
- The live model catalog exposed Luna, Terra and Sol with their supported reasoning efforts; the selection is forwarded to real `thread/start` / `turn/start` requests.
- Structured output constrained by a local JSON Schema returned the expected object.
- `turn/interrupt` produced `interrupted`, not late success.
- `$imagegen` produced one PNG in the job output.
- The PNG was `1254 × 1254`, `3,403,461` bytes and decoded through ImageIO.
- SHA-256: `52611fb866567bb778df9bb9da23afba8389057b196c48e0591d8d40efe08a64`.

The generated artifact carried the macOS BSD `hidden` flag. Output discovery was corrected to include non-dot files regardless of that flag; validated artwork copies clear the hidden resource value.

## Not live-verified

- completing browser login on a clean logged-out profile;
- completing device-code login;
- logout/re-login round trip (not run to avoid disrupting the user's active global Codex session);
- a real rate-limit exhaustion response;
- an incompatible installed Codex binary;
- protocol behavior after app-server crashes mid-imagegen.

These remain release blockers even though fixture/unit boundaries and typed errors exist.
