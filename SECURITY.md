# Security policy

## Supported version

Security fixes are currently provided for the latest commit on `main`.

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability or include private
book content, diagnostics, account information, credentials, or proof-of-concept
data in an issue.

Use GitHub's **Security → Report a vulnerability** private reporting flow. If
private vulnerability reporting is not yet enabled, open a public issue that
contains only a request for a private contact channel and no vulnerability
details.

Include the affected version, macOS version, reproduction steps, impact, and a
minimal synthetic test file when possible. Never send a real private book.

## Security boundaries

- BookLens supports ChatGPT account authentication through an installed Codex
  app-server. API-key authentication is intentionally rejected.
- BookLens does not read or store Codex credentials, tokens, `auth.json`,
  `credentials.json`, cookies, or `.env` files.
- Imported books are untrusted input. AI processing requires explicit user
  confirmation and uses an isolated temporary workspace.
- Public source packages must never contain the private `App/` or `Data/`
  transfer directories, imported books, databases, preferences, or logs.

See [Documentation/PRIVACY.md](Documentation/PRIVACY.md) and
[Documentation/PUBLICATION_CHECKLIST.md](Documentation/PUBLICATION_CHECKLIST.md).
