# Folio for Mac

A native SwiftUI + PDFKit starting point for Folio: your paper library, a focused reader, and notes beside the source. Runs as its own Mac application without Edge, Chrome, Node, a web server, or a login screen.

This is a working native port with a glass-inspired library, PDF editing and user-triggered AI chat, paper lookup and cited overviews, **not full feature parity** with Folio web. Review analysis, concept graphs, streaming, rendered LaTeX and web-data migration remain incomplete. See the [feature-by-feature porting map](docs/PORTING.md).

## Run

Requires macOS 14 or later and Xcode 15.3 or later (select Xcode in `xcode-select`). No external packages to install.

```sh
open Package.swift
```

Choose the FolioMac executable scheme and Run in Xcode. Or build a standalone application:

```sh
scripts/build-app.sh
open .build/Folio.app
```

The bundle can run after Terminal and your browser close. It is locally ad-hoc signed; distribution signing and notarization are not configured. Release: `scripts/build-app.sh release`. [Development and verification](docs/DEVELOPMENT.md) explain the package, bundle and sandboxed build options.

## Try it

Use **Sample paper**, or **Import PDF** (⌘O). Select a passage and click Highlight or Underline. Add a written PDF comment with Note (⇧⌘N), star a page (⌘D), search (⌘F), use the embedded outline, and export a PDF copy (⇧⌘S). Annotation Undo/Redo buttons are scoped to Folio marks; text editors retain native text undo. The library offers table/grid layouts and Notes/Starred pages filters. Settings (⌘,) controls light/dark/system and green/blue accents.

Imports make managed copies under `~/Library/Application Support/FolioMac/Documents/`; annotations save to those copies. `library.json` stores titles, positions, stars and last-opened dates. There is no background network activity. Browser drafts, conversations and recents are separate and are not migrated. Repeated imports create separate entries. Explicit export uses the native save panel and can replace a file only through its normal confirmation.

## Continue development

Start with [AGENTS.md](AGENTS.md), [current handoff](handoff.md), and [context map](docs/README.md). Ask `python3 scripts/context.py "annotations"` for relevant owners and checks. The repository includes a bounded context router/checker, scoped rules, Claude imports, parity map, architecture decisions, verification notes, and macOS CI.

The original web reference is [sonarpratik5/folio](https://github.com/sonarpratik5/folio). This repository is independent: no sibling directory is needed to build or run it. The copied app icon is credited in [reference notes](docs/WEB_REFERENCE.md).
