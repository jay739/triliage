# triliage

A modern, native desktop client for [Trilium Notes](https://github.com/zadam/trilium), built with Flutter.

## Why

Trilium is a capable self-hosted note-taking app, with full-text search, arbitrarily nested notes, revision history, attributes, and encryption, exposed through a documented REST API (ETAPI). But its official client is the only client: a dated, Electron-derived UI with no real third-party alternatives.

triliage talks to any Trilium instance over ETAPI and gives it a UI built from scratch, independent of Trilium's own frontend code. The goal is a general-purpose client anyone running Trilium can use, not a single-user tool tied to one setup.

## Status

Early, but usable for reading. triliage connects to a Trilium instance, remembers the connection, browses the full note tree, searches it with Trilium's own query syntax, and renders text and code notes. Editing does not exist yet, so treat this as a reader rather than a replacement for the Trilium UI.

## Requirements

| Requirement               | Notes                                                                                                                  |
| ------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| Flutter SDK               | Beta channel; stable does not yet support the VS 2026 CMake generator on Windows. Will move to stable once that ships. |
| Visual Studio Build Tools | Desktop development with C++ workload, plus the ATL component (see below)                                              |
| A Trilium instance        | ETAPI enabled, plus an ETAPI token                                                                                     |

### The ATL component

`flutter_secure_storage`, which keeps your token out of a plain file, compiles against ATL on Windows. Without it the build fails at `flutter_secure_storage_windows_plugin.cpp` with:

```
error C1083: Cannot open include file: 'atlstr.h'
```

Add it in the Visual Studio Installer under Individual components, "C++ ATL for latest build tools", or from an elevated prompt:

```
vs_installer.exe modify ^
  --installPath "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools" ^
  --add Microsoft.VisualStudio.Component.VC.ATL --passive --norestart
```

If several Visual Studio instances are installed, add it to the one `flutter doctor -v` names, which is not necessarily the one `vswhere -latest` reports. Run `flutter clean` afterwards, because CMake caches the include paths it saw at configure time and will keep failing otherwise. GitHub's Windows runners already ship ATL, so release builds are unaffected.

## Running

```
flutter run -d windows
```

## Building

```
flutter build windows --release
```

Produces `build\windows\x64\runner\Release\`. Note that `triliage.exe` there is a small launcher, not a standalone binary: the engine lives in `flutter_windows.dll` and the compiled app in `data\app.so`, so the whole folder has to stay together.

### Installer

```
pwsh installer/build-installer.ps1 -Version 0.1.0
```

Produces `dist\triliage-0.1.0-windows-x64-setup.exe` using [Inno Setup](https://jrsoftware.org/isinfo.php), installing it via Chocolatey if it is not already present. The script is the same one CI runs, so a locally built installer matches a released one.

The installer is per-user by default, needing no admin rights and raising no UAC prompt, and offers a machine-wide install from the wizard. It adds a Start Menu entry and a working uninstaller.

CI compiles the installer on every pull request, so packaging cannot quietly break between releases. Tagged releases (`v*.*.*`) publish both the installer and a portable zip. Both are unsigned, so SmartScreen warns on first run.

## Configuration

Everything lives in-app. There are no configuration files and no environment variables.

| Setting     | Meaning                                                                                                                    |
| ----------- | -------------------------------------------------------------------------------------------------------------------------- |
| Server URL  | Your Trilium instance, e.g. `https://notes.example.com`                                                                    |
| ETAPI token | Created in Trilium under Options, ETAPI. Or sign in with your Trilium password and triliage exchanges it for a token once. |

The server URL is forgiving: a bare host gets `https://`, and a trailing slash or `/etapi` is trimmed. Reverse-proxied sub-path installs such as `https://example.com/trilium` work too.

The token is stored in the operating system credential store, which is DPAPI on Windows, Keychain on macOS, and libsecret on Linux. If you authenticate with a password, only the resulting token is kept; the password is never written anywhere. An ETAPI token grants full read and write access to every note on the instance, so revoke it in Trilium if you stop using this machine.

Note that Disconnect currently only forgets the token on this machine. It does not yet deactivate it server side, so a token you have disconnected stays valid until you revoke it in Trilium under Options, ETAPI. Closing that gap is the first item on the roadmap below.

## Planned features

The roadmap below is scoped against what Trilium's ETAPI actually exposes, and the endpoint behind each non-obvious item is named so it is clear the feature is possible rather than aspirational. ETAPI publishes about forty operations across twenty-five paths, and triliage currently calls five of them, so most of what follows is wiring rather than invention.

**Next up, in order:** revoke the token on disconnect, then attachment and image rendering, then revision browsing. The first closes a real security gap, and the other two are the largest gaps in reading that need no write access.

### Core / connectivity

- [x] ETAPI client (auth via token, base request/response handling)
- [x] Connection UI (server URL, token or password, verified before saving)
- [x] Credentials persisted in the OS credential store, restored on launch
- [ ] Deactivate the token server side on disconnect (`POST /etapi/auth/logout`), instead of only forgetting it locally
- [ ] Multi-instance support (connect to more than one Trilium server, switch between them)
- [ ] Instance statistics panel (`GET /etapi/metrics?format=json`, which returns counts and version only, never note content)

### Browsing

- [x] Note tree view (lazily loaded, arbitrary nesting)
- [ ] Clone-aware tree (`GET /etapi/branches/{branchId}`; a note's placement is a Branch, so one note can legitimately sit under several parents)
- [ ] Honour Trilium's own child ordering and branch prefixes (`notePosition` and `prefix` on Branch)
- [ ] Breadcrumb / path navigation
- [ ] Recent changes view (`GET /etapi/notes/history`, scopeable to a subtree with `ancestorNoteId`)
- [ ] Day, week, month and year note navigation (`GET /etapi/calendar/days/{date}` and siblings, plus `GET /etapi/inbox/{date}`)
- [x] Note attributes (labels/relations) view

### Search

The sidebar switches between the tree and search with the Tree/Search buttons, or Ctrl+F from anywhere in the window. Queries are Trilium's own syntax, so `homelab`, `#book`, `#year >= 2020`, `"exact phrase"`, and `note.title *=* wiki` all work. Two toggles cover the flags that have no query-syntax equivalent: **Titles only** searches titles rather than full text, which is much faster on a large instance, and **Archived** includes notes Trilium leaves out by default. Results are capped at 100 per search and the pane says when that cap was reached.

- [x] Full-text search across notes
- [x] Trilium search syntax support (attribute-based queries)
- [ ] Scope a search to the selected subtree (the `ancestorNoteId` parameter the client already accepts)
- [ ] Search result highlighting
- [ ] Reveal a search result in the tree
- [ ] Recent query history, and saving a query as a Trilium search note

### Reading

- [x] Rich-text (HTML) note rendering
- [x] Code note rendering (monospaced, unhighlighted)
- [ ] Image and attachment rendering (`GET /etapi/notes/{noteId}/attachments`, then `GET /etapi/attachments/{attachmentId}/content`)
- [ ] Markdown rendering
- [ ] Code block syntax highlighting
- [ ] Internal note links (jump between linked notes)

### History and recovery

All read-only except the snapshot, so this whole section is reachable without the app ever writing a note body.

- [ ] Browse a note's revisions (`GET /etapi/notes/{noteId}/revisions`, `GET /etapi/revisions/{revisionId}`)
- [ ] Read and diff a revision against the current content (`GET /etapi/revisions/{revisionId}/content`)
- [ ] Take a snapshot before editing (`POST /etapi/notes/{noteId}/revision`)
- [ ] Restore a deleted note (`POST /etapi/notes/{noteId}/undelete`; `RecentChange.canBeUndeleted` says which ones qualify)

### Export and backup

- [ ] Export a subtree to ZIP (`GET /etapi/notes/{noteId}/export?format=html|markdown|share`, passing `root` to export everything)
- [ ] Import a ZIP under a note (`POST /etapi/notes/{noteId}/import`)
- [ ] Trigger a server-side backup (`PUT /etapi/backup/{backupName}`)

### Editing

- [ ] Create / edit / delete notes (`POST /etapi/create-note`, `PATCH /etapi/notes/{noteId}`, `PUT /etapi/notes/{noteId}/content`, `DELETE /etapi/notes/{noteId}`)
- [ ] Markdown editing mode
- [ ] Attribute editing (`POST`, `PATCH` and `DELETE` on `/etapi/attributes`)
- [ ] Move and clone notes by editing their branches (`POST /etapi/branches`, `PATCH` and `DELETE` on `/etapi/branches/{branchId}`)

### Platform

- [x] Windows desktop build
- [ ] macOS build
- [ ] Linux build
- [ ] Auto-update mechanism

### Polish

- [x] Light/dark theme (follows the system setting)
- [x] Ctrl+F jumps to search from anywhere in the window
- [ ] Fuller keyboard shortcuts and a command palette
- [ ] Offline/cached reading mode
- [ ] Remember the last selected note and sidebar width between launches

### Known gaps in what exists

Not roadmap items so much as honest limits of the current build.

- Hidden notes never appear. Trilium keeps system notes in a `_hidden` subtree which is not a child of `root`, and the tree starts at `root`. The fix is probably to offer `_hidden` as a second root, but that should be verified over ETAPI before it is designed.
- Protected notes are listed but unreadable, which is permanent. See below.
- A search result opens in the reader without revealing where it sits in the tree.
- Nothing is cached between launches, so every run re-fetches the tree from scratch.

## Notes it cannot show

Protected notes are encrypted at rest and ETAPI has no way to unlock them, so triliage lists them in the tree but cannot render their contents. That is a limit of the API, not something a future version can work around. Image, file, and canvas notes are listed but not yet rendered, and those are just unfinished.

## Contributing and security

Pre-alpha, so expect churn. Small fixes are welcome any time; for anything larger, open an issue or discussion first so effort is not wasted. See [CONTRIBUTING.md](CONTRIBUTING.md). Report vulnerabilities privately per [SECURITY.md](SECURITY.md).

## License

MIT, see [LICENSE](LICENSE).
