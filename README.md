# triliage

A modern, native desktop client for [Trilium Notes](https://github.com/zadam/trilium), built with Flutter.

## Why

Trilium is a capable self-hosted note-taking app — full-text search, arbitrarily nested notes, revision history, attributes, encryption — exposed through a documented REST API (ETAPI). But its official client is the only client: a dated, Electron-derived UI with no real third-party alternatives.

`triliage` talks to any Trilium instance over ETAPI and gives it a UI built from scratch, independent of Trilium's own frontend code. The goal is a general-purpose client anyone running Trilium can use, not a single-user tool tied to one setup.

## Status

Early scaffold. Toolchain verified (Flutter beta channel + Visual Studio 2026 Build Tools), builds and runs as a Windows desktop app. Feature work — ETAPI integration, note tree, search, rendering — not yet started.

## Requirements

- Flutter SDK (beta channel — stable does not yet support the VS 2026 CMake generator on Windows; will move to stable once that support ships)
- Visual Studio Build Tools with the Desktop development with C++ workload (Windows target)
- A running Trilium instance with ETAPI enabled, and an ETAPI token

## Running

```
flutter run -d windows
```

## Building

```
flutter build windows
```

Produces `build\windows\x64\runner\Release\triliage.exe`.

## Planned features

### Core / connectivity

- [ ] ETAPI client (auth via token, base request/response handling)
- [ ] Multi-instance support (connect to more than one Trilium server, switch between them)
- [ ] Connection settings UI (server URL, token, test connection)

### Browsing

- [ ] Note tree view (arbitrary nesting, multiple parents/clones)
- [ ] Breadcrumb / path navigation
- [ ] Recently viewed / recently updated notes
- [ ] Note attributes (labels/relations) view

### Search

- [ ] Full-text search across notes
- [ ] Trilium search syntax support (attribute-based queries)
- [ ] Search result highlighting

### Reading

- [ ] Markdown rendering
- [ ] Rich-text (HTML) note rendering
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

- [ ] Light/dark theme
- [ ] Keyboard shortcuts / command palette
- [ ] Offline/cached reading mode

## Contributing

Not yet accepting external contributions — still pre-alpha. Will open up once the core ETAPI client and basic browsing UI are working.

## License

TBD.
