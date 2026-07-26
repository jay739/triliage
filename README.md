# triliage

A modern, native desktop client for [Trilium Notes](https://github.com/zadam/trilium), built with Flutter.

## Why

Trilium is a capable self-hosted note-taking app, with full-text search, arbitrarily nested notes, revision history, attributes, and encryption, exposed through a documented REST API (ETAPI). But its official client is the only client: a dated, Electron-derived UI with no real third-party alternatives.

triliage talks to any Trilium instance over ETAPI and gives it a UI built from scratch, independent of Trilium's own frontend code. The goal is a general-purpose client anyone running Trilium can use, not a single-user tool tied to one setup.

## Status

Early, but usable for reading. triliage connects to a Trilium instance, remembers the connection, browses the full note tree, and renders text and code notes. Editing does not exist yet, and neither does search, so treat this as a reader rather than a replacement for the Trilium UI.

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

## Planned features

### Core / connectivity

- [x] ETAPI client (auth via token, base request/response handling)
- [x] Connection UI (server URL, token or password, verified before saving)
- [x] Credentials persisted in the OS credential store, restored on launch
- [ ] Multi-instance support (connect to more than one Trilium server, switch between them)

### Browsing

- [x] Note tree view (lazily loaded, arbitrary nesting)
- [ ] Clone-aware tree (a note appearing under several parents)
- [ ] Breadcrumb / path navigation
- [ ] Recently viewed / recently updated notes
- [x] Note attributes (labels/relations) view

### Search

The client method exists and is tested; none of it is wired to the UI yet.

- [ ] Full-text search across notes
- [ ] Trilium search syntax support (attribute-based queries)
- [ ] Search result highlighting

### Reading

- [x] Rich-text (HTML) note rendering
- [x] Code note rendering (monospaced, unhighlighted)
- [ ] Markdown rendering
- [ ] Code block syntax highlighting
- [ ] Image and attachment rendering
- [ ] Internal note links (jump between linked notes)

### Editing

- [ ] Create / edit / delete notes
- [ ] Markdown editing mode
- [ ] Note revision history browsing and rollback
- [ ] Attribute editing

### Platform

- [x] Windows desktop build
- [ ] macOS build
- [ ] Linux build
- [ ] Auto-update mechanism

### Polish

- [x] Light/dark theme (follows the system setting)
- [ ] Keyboard shortcuts / command palette
- [ ] Offline/cached reading mode

## Notes it cannot show

Protected notes are encrypted at rest and ETAPI has no way to unlock them, so triliage lists them in the tree but cannot render their contents. That is a limit of the API, not something a future version can work around. Image, file, and canvas notes are listed but not yet rendered, and those are just unfinished.

## Contributing and security

Pre-alpha, so expect churn. Small fixes are welcome any time; for anything larger, open an issue or discussion first so effort is not wasted. See [CONTRIBUTING.md](CONTRIBUTING.md). Report vulnerabilities privately per [SECURITY.md](SECURITY.md).

## License

MIT, see [LICENSE](LICENSE).
