# Folder iCloud Rebuild Guidance

## Goal

Rebuild Folder so it keeps the current product behavior and native iOS feel, but removes the WordPress.com backend entirely.

The new app should:

- store user files in a dedicated iCloud folder
- store queryable metadata in a proper local database
- sync metadata across devices through Apple's stack
- preserve offline behavior and fast feed rendering
- keep the share extension and current interaction model

## Core Recommendation

Do not start from scratch.

Do not try to "swap the backend" inside the current architecture either.

Best approach:

1. Keep the current app as a UX reference and partial UI donor.
2. Replace the backend-shaped core with a new domain, persistence, and sync architecture.
3. Migrate screen by screen onto the new storage model.

This is a rebuild of the core, not a greenfield rewrite of the whole app.

## What To Keep

These parts are worth reusing or adapting:

- the overall product shape: feed, filters, composers, previews, context menus
- SwiftUI presentation patterns already used in the app
- native system integrations: `PhotosPicker`, `fileImporter`, `QuickLook`, `SFSafariViewController`, `AVPlayer`
- share extension item extraction flow
- current visual direction: minimal, native, system-first

Best candidates for reuse:

- `MainGridView.swift`
- composer sheets in `MainGridView.swift`
- `TilePreviewSheet.swift`
- `ShareViewController.swift`
- parts of `ShareComposeView.swift`
- link metadata helpers

## What To Replace Completely

These parts should not survive the new architecture:

- `WordPressAuthManager.swift`
- `WordPressPostManager.swift`
- `WordPressSite.swift`
- `WordPressSecrets.swift`
- token and site mirroring logic used only for WordPress auth

Reason:

The current core is not an app domain. It is a WordPress transport layer. The app's business objects, feed loading, edit semantics, and media handling are all encoded in WordPress-specific concepts like post formats, tags, HTML content, and remote media IDs.

## Recommended Architecture

Use `Clean Architecture + MVVM`.

Why:

- `Clean Architecture` gives you a clean separation between UI, domain, local DB, iCloud files, and sync.
- `MVVM` remains the right presentation pattern for SwiftUI screens and sheet-heavy flows.
- A lightweight app coordinator is useful for root flow, onboarding, and modal routing, but it should stay thin.

### Layering

```text
App/
  AppContainer
  AppCoordinator
  Bootstrap

Domain/
  Entities/
  Repositories/
  UseCases/

Data/
  SwiftData/
  CloudSync/
  FileStore/
  Manifests/
  Metadata/

Presentation/
  Feed/
  Compose/
  Preview/
  Settings/
  Shared/

ShareExtension/
  Inbox/
  Compose/
  ImportBridge/
```

## Storage Strategy

Do not use only iCloud Drive files.

Do not use only CloudKit records.

Use a hybrid model:

- iCloud ubiquity container for canonical user files
- SwiftData for local indexed state and fast rendering
- CloudKit private database for metadata sync
- per-item manifest files for repairability and portability

### Why Hybrid Is The Correct Choice

Using only files:

- makes filtering and feed queries clumsy
- makes conflict handling weak
- forces expensive file scans
- makes UI state restoration poor

Using only database records:

- does not satisfy the dedicated iCloud folder requirement
- makes file recovery and user visibility weaker
- hides the actual stored artifacts behind database assets

Using both gives:

- user-owned, inspectable storage
- fast local feed queries
- good offline behavior
- multi-device metadata sync
- a repair path if either layer drifts

## Canonical Data Model

Define the domain around `FolderItem`, not around posts.

### Core Entity

```text
FolderItem
- id: UUID
- kind: photo | thought | link | file
- title: String
- note: String?
- createdAt: Date
- updatedAt: Date
- sortDate: Date
- syncState: localOnly | syncing | synced | conflicted | pendingDelete
- isDeleted: Bool
```

### Attachments

```text
Attachment
- id: UUID
- itemID: UUID
- role: original | preview | favicon | poster | sidecar
- relativePath: String
- uti: String
- mimeType: String
- byteSize: Int64
- checksum: String?
```

### Link Metadata

```text
LinkMetadata
- itemID: UUID
- sourceURL: URL
- displayHost: String
- pageTitle: String?
- summary: String?
- faviconPath: String?
```

## iCloud Folder Layout

Use deterministic paths under one app-owned folder:

```text
iCloud Drive/Folder/
  Thoughts/2026/03/<uuid>/
    manifest.json
    body.md
  Links/2026/03/<uuid>/
    manifest.json
    link.json
    favicon.png
  Photos/2026/03/<uuid>/
    manifest.json
    original.heic
    preview.jpg
  Files/2026/03/<uuid>/
    manifest.json
    original.pdf
    preview.jpg
```

Rules:

- one item, one folder
- immutable original attachments after write
- generated previews can be replaced
- every item folder must contain a `manifest.json`

## Manifest Design

Each item folder should contain a small manifest that mirrors the important DB state.

Suggested fields:

- item ID
- item kind
- title
- note
- created and updated timestamps
- relative attachment paths
- link metadata if applicable
- schema version

Purpose:

- rebuild the local DB if needed
- detect broken DB references
- support integrity checks
- support future migration tooling

## Persistence Rules

Write order for create flows:

1. create item ID
2. write files into staging location
3. move staged files into iCloud folder with coordination
4. write manifest
5. persist SwiftData records
6. mark sync state

Write order for updates:

1. update mutable metadata first in memory
2. rewrite manifest if needed
3. update DB transactionally
4. enqueue sync state changes

Write order for deletes:

1. mark tombstone in DB
2. update manifest or add delete marker if needed
3. remove files only after delete operation is durable

## Sync Model

Metadata sync should be CloudKit-backed through SwiftData.

Files sync through iCloud Drive.

That means:

- DB records synchronize independently from file transfer timing
- previews and UI must tolerate file-not-yet-downloaded states
- views should show placeholders while ubiquity items materialize locally

Conflict strategy:

- metadata: last-writer-wins for simple fields
- attachments: originals are immutable, new versions create new sidecars or replace generated previews only
- deletes: use tombstones, not immediate hard delete

## Share Extension Strategy

The extension should not write directly into the main app's live database.

Best approach:

- extension extracts shared items
- extension writes them into an App Group `Inbox/` folder
- extension writes a small import request manifest
- main app imports inbox items into the canonical iCloud folder and DB

Benefits:

- safer process boundaries
- less SwiftData and CloudKit risk inside extension lifecycle
- easier retry and recovery
- easier debugging

## Feed And UX Strategy

Keep the feed behavior, but stop deriving UX from backend strings such as `format == "link"` or tags like `folder-file`.

The feed should render typed view data:

- `FeedItemViewData`
- `kind`
- `title`
- `subtitle`
- `thumbnailState`
- `previewAction`
- `syncBadge`

The current UX to preserve:

- 2-column grid
- filter menu
- quick compose actions
- previews for photos, files, videos, thoughts, links
- edit thoughts and links in place
- long-press remove
- pull to refresh semantics replaced by local reload and sync refresh

## Native iOS 26 Design Principles

Use native patterns aggressively.

Rules:

- prefer system materials and hierarchy over custom branding
- keep sheets and previews standard
- keep motion subtle and functional
- use large titles, content-unavailable views, context menus, QuickLook, native media playback
- use glass sparingly and only where it improves structure
- keep typography and spacing aligned with system defaults
- do not imitate web-app admin UI patterns

The product should feel like a first-party personal archive app, not like a backend client.

## Recommended Module Breakdown

### Domain

- `FolderItem`
- `Attachment`
- `LinkInfo`
- `ItemRepository`
- `FileRepository`
- `ImportInboxRepository`
- `FetchFeedUseCase`
- `CreateThoughtUseCase`
- `CreateLinkUseCase`
- `CreatePhotoUseCase`
- `CreateFileUseCase`
- `UpdateThoughtUseCase`
- `UpdateLinkUseCase`
- `DeleteItemUseCase`
- `RepairLibraryUseCase`

### Data

- `SwiftDataItemRepository`
- `UbiquityFileStore`
- `ManifestStore`
- `InboxStore`
- `LinkMetadataService`
- `ThumbnailService`
- `VideoPosterService`
- `SyncCoordinator`

### Presentation

- `FeedViewModel`
- `ComposeThoughtViewModel`
- `ComposeLinkViewModel`
- `ImportProgressViewModel`
- `PreviewCoordinator`
- `SettingsViewModel`

## Migration Strategy

Do this as a parallel architecture migration, not an in-place mutation of old services.

Recommended path:

1. introduce the new domain models
2. introduce the new repository protocols
3. build iCloud file store and SwiftData store
4. build new feature view models
5. rebind existing views to the new view models
6. rebuild share extension import path
7. remove WordPress dependencies only after the new flow is complete

## Anti-Patterns To Avoid

- using iCloud files as the only query source
- exposing SwiftData models directly to SwiftUI views
- letting views perform file system work
- letting the share extension write into the same live store as the app
- storing raw HTML or backend-style content blobs as app state
- keying app logic off presentation strings
- depending on opportunistic iCloud download timing without explicit state handling

## Definition Of Done

The rebuild is done when:

- the app can create, edit, preview, and delete thoughts, links, photos, and files without WordPress
- all content is stored in a dedicated iCloud folder
- the feed is backed by a local indexed database
- the share extension imports content reliably
- the app works offline for already-known content
- the UI no longer depends on WordPress concepts anywhere

