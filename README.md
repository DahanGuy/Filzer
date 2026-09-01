# Filzer

A fully-featured iOS/iPadOS 15+ file manager inspired by [Filza](https://www.tigisoftware.com/default/?page_id=78), built with SwiftUI and [PartyUI](https://github.com/jailbreakdotparty/PartyUI).

## Why make this

"Filza is already a great iOS/iPadOS file manager, why make an alternative?" well because... Filza is kinda old.
As of my understanding, Filza was made for iOS/iPadOS 16 and older. And running it on newer versions causes the UI to look weird, in my opinion Filza's UI already looks kinda confusing.

And Filza also isnt open source, meaning to add an exploit to it you have to make a Tweak to the app which is not intuitive.

And thats how Filzer was made.

## Features

- **Archive Support** - Create ZIP, TAR, TAR.GZ and TAR.BZ2 and extract RAR, 7Z, GZIP, BZIP2 and XZ
- **Text Editor** - Plain-text editing with find/replace
- **Hex Editor** - Byte-level viewer/editor with find, go-to-offset and inline byte editing
- **Plist Editor** - Full Plist editor with type changing, key renaming and more
- **Image Viewer** - Image displaying and metadata
- **Media Player** - Audio/video playback and metadata
- **SQLite Viewer** - Browse tables and run SQL queries
- **IPA Inspector** - App icon, bundle ID, version, minimum iOS and extract or browse contents
- **Provisioning Profile Viewer** - Profile details, validity, devices and entitlements
- **Web Viewer** - uses WebKit to display HTML files
- **Network Locations** - WebDAV, FTP/FTPS and SMB file shares, and Dropbox, Google Drive and OneDrive as Cloud Network Locations
- **Biometric Lock** - Face ID / Touch ID or Passcode app lock
- **Permissions Editor** - set read/write or execute permissions for owner, group and others.

## Requirements

- Xcode 13+ (with iOS/iPadOS SDK)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## TODO

- [ ] Make small UI Changes and fix small UI Bugs (mostly)
- [ ] Fix Trollstore version cannot access entire filesystem
- [ ] Fix Network Locations (possibly not working)
- [ ] Change app icon
- [ ] Use [mpv](https://github.com/mpv-player/mpv) for video playback
- [ ] Use [swift-archive](https://github.com/marcprux/swift-archive) instead of SWCompression, ZIPFoundation and Unrar.swift for archive handling
- [ ] Add Tabs
- [ ] Add more viewers (like a PDF viewer or a Microsoft Document Viewer etc..)
- [ ] Maybe Add Sandbox Escape Exploits (like bad_query, MobileHouseArrest, MDC, Darksword and Coruna)

## AI Disclosure

Filzer was made with AI, why? well Filzer was supposed to be a personal project and using AI is way easier, but i decided to make it public because why not.

## Credits

- [PartyUI](https://github.com/jailbreakdotparty/PartyUI) - UI library
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) - ZIP support
- [SWCompression](https://github.com/tsolomko/SWCompression) - TAR/GZIP/BZIP2/7Z extraction
- [Unrar.swift](https://github.com/mtgto/Unrar.swift) - RAR extraction
- [AMSMB2](https://github.com/amosavian/AMSMB2) - SMB support
- [Filza](https://www.tigisoftware.com/default/?page_id=78) - Inspiration
