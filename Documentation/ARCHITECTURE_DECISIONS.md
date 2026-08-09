# Architecture decisions

## ADR-001 — SwiftPM-first macOS app

Status: accepted for prototype.

The repository initially contained only product documents and visual references, with no Xcode project. A multi-target SwiftPM package gives reproducible Swift 6 builds and tests without generating a large `.xcodeproj`. `script/build_and_run.sh` stages a real `.app` bundle for foreground launch.

## ADR-002 — External pinned Codex

Status: accepted for prototype.

BookLens discovers an external Codex installation from a small trusted-prefix allowlist and supports version `0.146.0` or newer; the live-verified baseline is `0.146.0`. The app does not update Codex and does not bundle auth state. Compatibility is confirmed again by the real app-server handshake and typed protocol calls.

## ADR-003 — No production fixtures

Status: accepted.

Fixture transport exists only for automated tests. Production onboarding, account status, progress, turn state, cancellation and image success are driven by real process/protocol/filesystem events.

## ADR-004 — Evidence before Studio

Status: accepted.

Studio remains unavailable until the selected character has at least one confirmed/probable trait with evidence IDs. PromptBuilder revalidates those IDs before building the prompt.

## ADR-005 — EPUB without third-party dependency

Status: provisional.

The prototype validates archive metadata and paths, then invokes the macOS `/usr/bin/unzip`. This avoids a new package dependency but must be replaced or security-reviewed before distribution, especially under App Sandbox/notarization constraints.
