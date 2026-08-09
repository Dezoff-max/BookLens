# BookLens feasibility spike result

Status: **CORE PASSED / RELEASE GATE BLOCKED**.

Date: 2026-08-04. Tested Codex: `0.146.0`, `arm64`, macOS.

| Gate item | Status | Evidence |
| --- | --- | --- |
| Locate/version Codex | PASSED | Resolver returned compatible `0.146.0`, arm64 |
| Start app-server | PASSED | Swift `Process` + separate stdio pipes |
| Handshake | PASSED | `initialize` response and `initialized` notification |
| Capabilities | PASSED FOR PINNED SUBSET | Local generated schema plus successful optional rate-limit call |
| Account status | PASSED | ChatGPT account present; no token/auth-file access |
| Rate limits | PASSED | Real snapshot read |
| Browser login completion | NOT RUN | Active global login preserved |
| Device-code completion | NOT RUN | Active global login preserved |
| Text turn | PASSED | Real completed turn |
| Structured output | PASSED | Local schema value validated |
| `$imagegen` | PASSED | New PNG created in isolated job output |
| Deterministic output discovery | PASSED | Exactly one new allowed file; BSD hidden flag handled |
| ImageIO decode | PASSED | `1254 × 1254` |
| SHA-256 | PASSED | `52611fb866567bb778df9bb9da23afba8389057b196c48e0591d8d40efe08a64` |
| Real cancellation | PASSED | `turn/interrupt` → `interrupted`, no late success |
| Rate-limit live error | NOT RUN | Would require exhausting user quota |
| Auth error live case | NOT RUN | Would require isolated logged-out profile |
| Incompatible version live case | NOT RUN | No incompatible binary supplied |
| Restart recovery | BLOCKED | In-flight job recovery not yet wired |

The core technical premise is proven: app-server can be driven from Swift, structured output can be validated, a real image file can be created and verified, and an active turn can be interrupted. The product must not be called release-ready until the blocked auth/recovery/distribution items are completed.
