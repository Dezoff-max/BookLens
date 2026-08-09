# Codex compatibility

## Compatibility adapter

- Live-tested Codex CLI: `0.146.0`.
- Minimum accepted version: `0.146.0`.
- Newer versions are accepted only provisionally; the live handshake and every used method still have to succeed through the typed adapter.
- Architecture: `arm64`.
- Protocol: `codex app-server --stdio`, newline-delimited JSON messages.
- Auto-update: disabled by design.

Executable search order:

1. helper beside the BookLens executable;
2. native npm executable under `/opt/homebrew` or `/usr/local`;
3. `/opt/homebrew/bin/codex`;
4. `/usr/local/bin/codex`.

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

## Live observations

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
