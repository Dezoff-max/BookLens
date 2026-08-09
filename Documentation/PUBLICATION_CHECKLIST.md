# Public repository checklist

The public repository root is `Source/BookLens`, never the surrounding
`BookLens-Transfer` directory.

## Before the first push

- [x] Runtime `App/` and `Data/` directories are outside the repository root.
- [x] Imported books, SwiftData stores, preferences, logs, DMGs, and app bundles
  are blocked by `.gitignore` and `script/check_publication.sh`.
- [x] No Codex/ChatGPT credentials, API keys, auth files, or private absolute
  paths are tracked.
- [x] Privacy, security, contributing, conduct, notices, and source-available
  license documents are present.
- [x] CI builds the SwiftPM product and runs all tests.
- [ ] Confirm the desired long-term license. The current license is
  source-available and all rights reserved, not an open-source license.
- [ ] Create the GitHub repository and enable private vulnerability reporting,
  secret scanning, push protection, and branch protection for `main`.
- [ ] Review the staged first commit with `git status` and
  `./script/check_publication.sh --test`.

## Binary releases

Source publication does not make the app binary release-ready. Before attaching
a DMG to GitHub Releases, complete the unchecked Developer ID, notarization,
clean-profile authentication, accessibility, and clean-machine gates in
`Documentation/RELEASE_CHECKLIST.md`.
