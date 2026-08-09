# Developer ID and notarization

Notarization is required only for a public binary release, not for local debug
builds or source publication.

## One-time setup

1. Install a `Developer ID Application` certificate in the login keychain.
2. Store Apple notarization credentials in Keychain, never in the repository:

   ```bash
   xcrun notarytool store-credentials booklens-notary
   ```

3. Confirm the identity:

   ```bash
   security find-identity -v -p codesigning
   ```

## Build, sign, submit, and staple

```bash
export BOOKLENS_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export BOOKLENS_NOTARY_PROFILE="booklens-notary"
./script/notarize_release.sh
```

The script builds a Release app with Hardened Runtime, creates and verifies the
DMG, submits it through `notarytool`, staples and validates the ticket, runs a
Gatekeeper assessment, and refreshes the SHA-256 file.

Do not store Apple ID passwords, app-specific passwords, issuer IDs, private
keys, `.p12` files, or notary API keys in GitHub. If release automation is added
later, use encrypted GitHub Actions secrets and temporary keychains.
