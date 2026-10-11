# Live smoke test

## Preconditions

- Use a disposable permitted test book.
- Confirm `codex --version` is `0.146.0` or newer and that BookLens completes the app-server handshake.
- Do not inspect or copy auth files.
- Ensure the ChatGPT account has enough quota for one image.

## Automated live harness

Run each command from the repository root:

```bash
swift run BookLensSpike probe
swift run BookLensSpike models
swift run BookLensSpike tool-free
swift run BookLensSpike text
swift run BookLensSpike text gpt-6.1-sol
swift run BookLensSpike text gpt-6-astra
swift run BookLensSpike text gpt-6-sol
swift run BookLensSpike text gpt-6-luna
swift run BookLensSpike cancel
swift run BookLensSpike image
```

`tool-free` validates that the installed app-server accepts the restricted
thread configuration used for local-book analysis without sending book content
or starting a model turn.

`models` is read-only and prints only catalog metadata. `text [model-id]` requires ChatGPT account mode and a visible model, uses an isolated temporary workspace with tools disabled, and sends only the small synthetic probe. It consumes a small amount of the user's ChatGPT plan limit. With no model argument it uses the server's default. Do not run `all` just to test model selection: it also generates an image.

Expected evidence:

1. `probe`
   - installation compatible;
   - handshake event;
   - account type `chatgpt` or an explicit authentication-required result;
   - rate-limit snapshot present when capability is available.
2. `text`
   - `turn/start` succeeds;
   - final status is `completed`;
   - local validation confirms `{ "probe": "booklens", "value": 42 }`.
3. `cancel`
   - real long-running turn starts;
   - `turn/interrupt` is sent;
   - final status is `interrupted`;
   - `lateSuccess` is false.
4. `image`
   - unique `.booklens-spike/Jobs/<uuid>/output` is created;
   - `$imagegen` turn completes;
   - exactly one new PNG/JPEG is found, including files with BSD hidden flag;
   - path and symlink boundary passes;
   - ImageIO returns width/height;
   - SHA-256 is printed.

Fixtures never count as live success.

## App smoke

```bash
./script/build_and_run.sh --verify
```

Then verify manually:

1. Onboarding displays detected Codex version and real account state.
2. Settings and the sidebar show the remaining primary Codex limit, window period and reset time.
3. Select GPT-6.1-Sol, GPT-6-Astra, GPT-6-Sol, and GPT-6-Luna (when available); verify full names and only supported reasoning levels in both Settings and Studio. Click Check again and restart: an available saved selection must remain unchanged.
4. Import a permitted TXT, text PDF and EPUB.
5. Open the Apple Books import sheet and verify local personal EPUB/PDF files appear with import buttons; a downloaded FairPlay item, when present, must appear locked. Verify the Finder-folder button and rejection of a dropped `books.apple.com` store link.
6. For a PDF with zero automatic name candidates, add a Cyrillic name manually and confirm real local excerpts appear.
7. Cancel one import and confirm no partial library record remains.
8. Open a book and select evidence.
9. Save a confirmed trait and open it in context.
10. Start Studio generation, cancel once, and verify no artwork record is created.
11. Retry and wait for a verified artwork.
12. Restart BookLens and verify persisted books/artworks and model selection.
13. Exercise copy/export/Finder/compare/delete confirmation.

## Clean-profile auth smoke

Not yet executed. Before release:

1. Use an isolated test profile where disrupting Codex auth is acceptable.
2. Complete browser login.
3. Logout through app-server.
4. Complete device-code login.
5. Restart BookLens and re-read account status.

Do not record email, tokens, cookies, codes or raw auth responses.
