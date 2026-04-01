# Folder

An iOS app for quickly saving and organising content — photos, links, thoughts, and files — backed by iCloud. Save anything from any app in seconds using the system Share Extension. Your library syncs automatically across all your devices.

## Features

- **2-column grid feed** with live filters by content type
- **Four content types**
  - **Photos** — pick from your library, stored in iCloud
  - **Thoughts** — quick text notes
  - **Links** — saves URLs with auto-fetched title, description, and favicon preview
  - **Files** — stores any file (PDF, video, audio, documents, archives)
- **Tap to preview**
  - Photos and files open in QuickLook
  - Links open in an in-app SFSafariViewController
  - Thoughts open in a bottom sheet
- **Long press context menu** — Open · Delete on every tile
- **iOS Share Extension** — share URLs, images, and files from any app directly into Folder
- **iCloud sync** — library syncs across devices via iCloud Documents + CloudKit
- **Sync state badges** — each tile shows its current sync state (Local · Syncing · Synced · Downloading · Cloud)
- **Pull to refresh**

## Tech Stack

| | |
|---|---|
| Language | Swift 5.0 |
| UI | SwiftUI + `@Observable` |
| Min iOS | iOS 26.2 |
| Architecture | MVVM + Clean Architecture (Use Cases, Repositories) |
| Storage | iCloud Documents (files) · SwiftData + CloudKit (metadata) |
| Auth | None — library is personal and iCloud-scoped |
| Dependencies | None — framework-only |

## Project Structure

```
Folder/
├── Folder/                          # Main app target
│   ├── FolderApp.swift              # @main entry point
│   ├── ContentView.swift            # Root view — bootstraps the library
│   ├── FolderBootstrapView.swift    # Loading / iCloud unavailable / ready states
│   ├── FolderLibraryBootstrapModel.swift  # State machine for startup
│   ├── FolderRuntimeConfiguration.swift   # Wires live iCloud or local dev fallback
│   ├── FolderAppGroup.swift         # App group identifier constant
│   ├── Domain/                      # Entities, repository protocols, use cases
│   │   ├── Entities/                # FolderItem, Attachment, LinkInfo, FolderItemManifest
│   │   └── UseCases/                # Create, Fetch, Update, Delete, Sync, Repair, Import
│   ├── Data/                        # Concrete implementations
│   │   ├── FileStore/               # FolderUbiquityFileStore — iCloud Documents via NSFileCoordinator
│   │   ├── SwiftData/               # FolderLocalStore, SwiftDataFolderRepository, CloudKit sync
│   │   └── Manifests/               # JSONFolderManifestStore — JSON manifests in iCloud
│   ├── Presentation/                # SwiftUI views and view models
│   │   ├── Feed/                    # FolderFeedView, FeedViewModel, FeedItemViewData
│   │   ├── Compose/                 # Thought / Link / Photo / File composers
│   │   ├── Maintenance/             # Debug repair tooling
│   │   └── Preview/                 # SafariSheet
│   └── ShareInbox/                  # FolderSharedInboxStore, FolderSharedInboxImporter
├── FolderShare/                     # Share Extension target
│   ├── ShareViewController.swift    # Extracts NSExtensionItem attachments
│   ├── ShareComposeView.swift       # Progress UI inside the extension
│   └── ShareInboxWriter.swift       # Writes payloads to the App Group inbox
├── FolderTests/                     # Unit tests
└── Folder.xcodeproj/
```

## How iCloud Sync Works

The library uses two complementary storage layers:

1. **iCloud Documents (ubiquity container)** — raw files (photos, attachments, manifests) stored under `iCloud.com.bartbak.fastapp.Folder/Documents/`. Each item gets a canonical path: `Kind/Year/Month/UUID/role/filename`. File access is coordinated via `NSFileCoordinator`.

2. **SwiftData + CloudKit** — a local SQLite database (`FolderItemEntity`, `AttachmentEntity`, `LinkInfoEntity`) synced across devices via CloudKit private database. Acts as the fast query layer for the feed.

3. **JSON Manifests** — each item writes a complete manifest (metadata + attachment paths) to the ubiquity container. Manifests are the source of truth used to rebuild the database after reinstall or corruption (`RebuildFolderDatabaseFromManifestsUseCase`).

4. **Share Extension inbox** — the Share Extension writes payloads to the App Group container (`group.com.bartbak.fastapp.folder/Inbox/`). The main app imports pending requests on every foreground activation.

## Getting Started

### Prerequisites

- Xcode 26.2+
- An Apple Developer account with iCloud (paid membership required)
- iCloud container `iCloud.com.bartbak.fastapp.Folder` registered in the [Apple Developer portal](https://developer.apple.com/account/resources/identifiers/list)

### Setup

1. Clone the repo and open `Folder/Folder.xcodeproj` in Xcode.
2. In the Apple Developer portal, enable the **iCloud** capability on app ID `com.bartbak.fastapp.Folder` and attach the container `iCloud.com.bartbak.fastapp.Folder`.
3. Regenerate and download provisioning profiles for both targets.
4. Select the **Folder** scheme, choose an iOS 26.2+ simulator or device, and run.

> **Local development fallback:** In `DEBUG` builds, if iCloud is unavailable (e.g. simulator without a signed-in account), the app automatically falls back to a local on-device library with no CloudKit sync.

## Bundle Identifiers

| Target | Bundle ID |
|---|---|
| Main app | `com.bartbak.fastapp.Folder` |
| Share Extension | `com.bartbak.fastapp.Folder.FolderShare` |
| App Group | `group.com.bartbak.fastapp.folder` |
| iCloud Container | `iCloud.com.bartbak.fastapp.Folder` |
| Team | `TJ3ALYQV5G` |

## Running Tests

```bash
xcodebuild test \
  -project Folder/Folder.xcodeproj \
  -scheme Folder \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```
