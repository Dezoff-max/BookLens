# Release checklist

## Build and tests

- [x] Swift 6 Debug build.
- [x] Swift 6 Release build in the current checkout.
- [x] Automated unit/integration-oriented tests.
- [x] SwiftPM `.app` bundle launch verification.
- [x] Local development bundle passes strict verification with an ad-hoc signature.
- [ ] Full Release build on a clean checkout.
- [ ] UI automation target and accessibility navigation run.
- [ ] Clean macOS 15 test machine.

## Feasibility

- [x] Real app-server handshake.
- [x] Real account status and rate-limit snapshot.
- [x] Real structured text turn.
- [x] Real `$imagegen` output file.
- [x] ImageIO decode and SHA-256.
- [x] Real turn interruption without late success.
- [ ] Browser login completion on clean profile.
- [ ] Device-code login completion.
- [ ] Rate-limit exhaustion live case.
- [ ] Process crash during turn.

## Import and data

- [x] TXT importer test.
- [x] PDF no-text typed failure test.
- [x] EPUB container/OPF/spine test.
- [x] Original-preservation pipeline test.
- [ ] Large/bomb EPUB adversarial corpus.
- [ ] Interrupted import recovery after process termination.
- [ ] In-flight generation recovery after restart.

## Privacy and security

- [x] No API-key UI.
- [x] No auth file access in BookLens code.
- [x] Versioned first-run AI disclosure and local-only mode.
- [x] Per-book and per-image point-of-use confirmation.
- [x] Local book analysis uses an isolated workspace and rejects tool events.
- [x] TXT/PDF/EPUB limits and bounded unzip process.
- [x] Bounded JSON-RPC frames and authentication URL allowlist.
- [x] Diagnostics default off; sink-level redaction and private OSLog.
- [x] Metadata-only redactor tests.
- [x] Output path/symlink/ImageIO validation.
- [x] Transfer preparation excludes diagnostic logs.
- [ ] App Sandbox design and security review for `/usr/bin/unzip`.

## Distribution

- [x] Bundle identifier and versioning for the 1.1.0 (5) preview release.
- [x] 1024 px master app icon and complete macOS ICNS size set.
- [x] Hardened Runtime in the packaged app signature.
- [x] Entitlements review; the current local build requests no extra entitlements.
- [x] Verified local DMG with an `/Applications` install link and SHA-256.
- [ ] Developer ID signing.
- [ ] Notarization and stapling.
- [x] Reproducible local notarization script using Keychain credentials, without secrets in the repository.
- [ ] License/legal review for external Codex + paid app model.
