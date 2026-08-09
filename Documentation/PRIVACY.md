# Privacy

## Local data

BookLens stores in `Application Support/BookLens`:

- copied source books;
- normalized chapters and evidence in SwiftData;
- job workspaces;
- validated artworks;
- identifiers and, only after opt-in, redacted technical diagnostics.

The original source selected by the user is never modified. Deleting from BookLens requires confirmation and does not delete the external original.

## Data sent to Codex

An imported book is analyzed only after the user confirms the point-of-use disclosure. BookLens sends:

- a bounded representative selection of chapter text (up to 96,000 characters);
- book title, author and chapter titles;
- The output language selected in BookLens (English, Russian, or Spanish).

The confirmation shows the actual selected character count. The original file is not uploaded and is never modified. Local-book analysis runs in a temporary empty workspace with shell, browser, computer-use, image, app, and dynamic tools disabled; unexpected tool events fail the turn. For online discovery, BookLens sends only the user's title/author/character query after AI has been enabled; Codex may research legal public sources in any language, while the structured result is returned in the language selected in BookLens.

Before image generation, BookLens shows a separate confirmation. If accepted, it sends:

- selected evidence fragments;
- evidence-bound trait values;
- composition/style controls;
- explicit artistic additions;
- selected reference identifiers/files when that feature is used;
- the isolated job output path.

Exact source quotations may remain in the original language. BookLens does not download complete copyrighted books during online discovery.

## Authentication

Authentication is owned by `codex app-server`. BookLens does not ask for or inspect an API key and does not read/copy/log:

- tokens;
- cookies;
- `.env`;
- `auth.json`;
- `credentials.json`;
- browser credential stores.

Browser/device-code URLs and codes are accepted only over HTTPS on official `openai.com` or `chatgpt.com` hosts and are held only in transient UI state for the active login flow.

BookLens accepts only `account.type == "chatgpt"`. API-key account modes are rejected. Login and logout affect the global Codex session on the Mac; disabling AI in BookLens does not log the user out of Codex.

BookLens-owned runtime data, including its SwiftData store and imported source copies, is stored under `~/Library/Application Support/BookLens/`. A private transfer package may include that folder only when explicitly prepared by the user; it must never be published. Codex credentials and BookLens diagnostic logs remain excluded.

## Apple Books

BookLens performs a read-only enumeration of two known file locations: the user's iCloud Books `Documents` folder and the local Apple Books downloaded-book folder. It reads only file names, sizes, basic EPUB metadata and the presence of Apple DRM markers needed to decide whether an item is importable.

BookLens does not inspect the private Apple Books database, account metadata, credentials or tokens. A user can import a discovered personal EPUB/PDF, drag a local file or select it explicitly. DRM-protected Apple Books content is shown as locked and is never decrypted or imported.

## Diagnostics

Diagnostics are disabled by default. If the user opts in, allowed fields are:

- request ID;
- method;
- duration;
- result code;
- message size;
- job UUID;
- protocol version;
- Codex version and architecture.

Forbidden content:

- email;
- full book text or full excerpts;
- full prompt;
- auth data;
- binary image data;
- unredacted absolute user paths.

`Redactor` is applied at the diagnostic sink and removes email-shaped strings, bearer/token values and user/volume paths. OSLog messages are private. Account plan and quota values are not written to the diagnostic file. Raw stderr is bounded and drained but not logged.

## Retention and control

Imported books, extracted text, generated images, and the SwiftData store remain local until the user deletes them. Disabling AI stops BookLens from starting new AI operations but does not delete local data or change the global Codex login. Diagnostic files can be viewed from Settings and are never included in public-source or private-transfer publication checks.
