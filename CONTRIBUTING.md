# Contributing

BookLens is currently source-available rather than open source. Issues and
security reports are welcome; code contributions require prior approval from
the copyright holder.

Before proposing a change:

1. Do not include real books, databases, generated user images, logs, account
   data, or credentials.
2. Use synthetic fixtures for importer and AI-boundary tests.
3. Run `./script/check_publication.sh --test`.
4. Keep ChatGPT-only authentication and explicit AI consent intact.
5. Do not weaken import limits, output-path validation, subprocess limits, or
   diagnostic redaction.

Security reports must follow [SECURITY.md](SECURITY.md), not public issues.
