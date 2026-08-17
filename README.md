# Filzer

A fully-featured iOS file manager built with SwiftUI and [PartyUI](https://github.com/jailbreakdotparty/PartyUI).

## Features

- **File Browsing** — List and grid views, sorting, search, hidden files toggle
- **File Operations** — Create, rename, copy, move, delete, duplicate, symbolic/hard links
- **Multi-Select** — Batch copy, cut, compress, share, delete with a bottom action bar
- **Archive Support** — Create and extract ZIP, TAR, TAR.GZ, TAR.BZ2. Extract RAR, 7Z, GZIP, BZIP2, XZ
- **Text Editor** — Plain-text editing with find/replace
- **Hex Editor** — Byte-level viewer/editor with find, go-to-offset, inline byte editing
- **Plist Editor** — Full property list editor with type changing, key rename, add/delete
- **Image Viewer** — Pinch-to-zoom, pan, double-tap reset, metadata strip
- **Media Player** — Audio/video playback with metadata display
- **SQLite Viewer** — Browse tables, run free-form SQL queries
- **IPA Inspector** — App icon, bundle ID, version, minimum iOS, browse contents
- **Provisioning Profile Viewer** — Profile details, validity, devices, entitlements
- **Web Viewer** — Local HTML rendering with relative asset support
- **Quick Look** — Fallback viewer for PDFs, Office docs, and unknown types
- **Network Locations** — WebDAV, FTP/FTPS, SMB file shares, Dropbox, Google Drive, OneDrive
- **Bookmarks** — Pin any path for quick access
- **Recents** — Every opened file tracked with timestamps
- **Biometric Lock** — Face ID / Touch ID app lock with configurable timeout
- **Permissions Editor** — POSIX rwx per owner/group/others, special bits, recursive apply
- **File Info** — Size calculation, dates, ownership, symlink destination, media metadata
- **Clipboard** — Cut/copy/paste with a persistent banner
- **Go to Folder** — Jump to any absolute path with live autosuggest
- **Settings** — Appearance theme, view mode, hidden files, search subfolder toggle, file associations
- **Backup & Restore** — Export/import all settings as JSON (if enabled)

## TrollStore

The `.tipa` build includes unsandboxed entitlements (`com.apple.private.security.no-sandbox`, `platform-application`) for full filesystem read/write when installed via [TrollStore](https://github.com/opa334/TrollStore).

## Building

Requires Xcode with iOS SDK and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
open Filzer.xcodeproj
```

CI builds unsigned IPA and TrollStore TIPA automatically on every push.

## Credits

- [PartyUI](https://github.com/jailbreakdotparty/PartyUI) — UI component library
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) — ZIP archive support
- [SWCompression](https://github.com/tsolomko/SWCompression) — TAR/GZIP/BZIP2/7Z extraction
- [Unrar.swift](https://github.com/mtgto/Unrar.swift) — RAR archive extraction
- [AMSMB2](https://github.com/amosavian/AMSMB2) — SMB network location support

## License

MIT
