# Folder iCloud Rebuild Execution Plan

## Objective

Ship an iCloud-native version of Folder without WordPress.com while keeping the current app experience and using only native iOS patterns.

## Delivery Strategy

Treat this as a staged core replacement.

Do not mix old and new persistence logic deeply.

The safest route is:

1. keep current UI where useful
2. build the new data stack beside it
3. migrate screens onto new use cases
4. remove WordPress code last

## Phase 0: Freeze Product Scope

Lock the v1 feature set:

- photos
- thoughts
- links
- files
- grid feed
- filters
- previews
- edit thoughts and links
- delete items
- share extension import

Do not expand scope during storage migration.

Avoid adding:

- collaboration
- shared folders
- custom tags
- full-text search
- cross-platform clients

## Phase 1: Build The New Core Domain

Create a backend-independent domain model.

Deliverables:

- `FolderItem`
- `Attachment`
- `LinkInfo`
- `SyncState`
- repository protocols
- create, update, delete, fetch use cases

Acceptance criteria:

- no `WordPress`, `post`, `site`, `token`, or HTML-driven semantics in domain code
- all use cases compile without SwiftUI imports

## Phase 2: Build The Local Database Layer

Use SwiftData for local indexed state.

Store:

- item records
- attachment records
- link metadata
- sort metadata
- tombstones
- sync state

Guidelines:

- map persistence models to domain entities in the repository layer
- never expose SwiftData models directly to views
- index for feed ordering and filter-by-kind

Acceptance criteria:

- feed can load entirely from local DB
- filter queries are local and fast
- updates and deletes are transactional

## Phase 3: Build The iCloud File Store

Implement a dedicated ubiquity-container file store.

Responsibilities:

- resolve app iCloud container URL
- create deterministic item directories
- coordinate reads and writes
- move staged files into canonical location
- expose file availability state
- support preview and export paths

Guidelines:

- use `NSFileCoordinator` for file mutations
- preserve original file names where useful
- separate originals from generated previews
- never rely on temporary files as durable storage

Acceptance criteria:

- photos, files, and sidecars are physically visible in the app folder in iCloud Drive
- previews can open from canonical paths

## Phase 4: Add Manifest Support

Every item directory should contain a manifest.

Manifest purpose:

- recovery
- integrity checks
- future migrations
- DB rebuild

Acceptance criteria:

- every create path writes a manifest
- every update path keeps manifest and DB aligned
- a repair task can identify missing DB records or missing files

## Phase 5: Add Cloud Sync

Sync metadata through CloudKit-backed SwiftData.

Important distinction:

- metadata sync and file sync are different systems
- UI must tolerate them completing at different times

Implement:

- sync state tracking
- file materialization status
- tombstones for deletes
- simple conflict policy

Conflict policy:

- mutable metadata uses last-writer-wins
- original attachments are immutable
- deletes are soft first, then finalized later

Acceptance criteria:

- changes appear on a second device
- missing local files can re-download from iCloud Drive
- deleted items do not ghost back

## Phase 6: Rebuild App Bootstrap

Replace WordPress auth flow with iCloud availability bootstrap.

New root states:

- loading
- iCloud unavailable
- library initializing
- ready

UI notes:

- no login screen
- no site picker
- settings should explain iCloud dependency clearly

Acceptance criteria:

- app launches cleanly without auth
- if iCloud is unavailable, the user sees an actionable state

## Phase 7: Rebuild Feed Feature

Create a new `FeedViewModel`.

Responsibilities:

- load feed from local DB
- filter by item kind
- handle delete actions
- surface preview routing
- expose sync/download state

Keep from current app:

- grid layout
- filters
- context menus
- status bar pattern if still useful

Replace:

- remote pagination
- WordPress format parsing
- WordPress file and video URL handling

Acceptance criteria:

- feed loads without network dependency
- filters use typed item kinds
- previews work from local or ubiquity-backed files

## Phase 8: Rebuild Compose Flows

Create separate compose view models:

- thought composer
- link composer
- photo import
- file import

Guidelines:

- compose flows call use cases only
- link metadata fetch remains a service
- imported files are staged first, then committed

Acceptance criteria:

- creating each item type updates the local feed immediately
- errors are localized to the active compose flow

## Phase 9: Rebuild Share Extension

Use an App Group inbox model.

Extension flow:

1. extract shared items
2. write payloads into `AppGroup/Inbox/<request-id>/`
3. write import request manifest
4. complete extension quickly

App flow:

1. scan inbox on launch and foreground
2. import each request into canonical store
3. persist DB records
4. clean imported inbox folders

Why this is the best approach:

- safer than running live DB and iCloud mutations inside extension lifetime
- easier to recover partial imports
- easier to test

Acceptance criteria:

- shares from Safari, Photos, Files, and text sources import reliably
- failed imports can be retried

## Phase 10: Add Repair And Maintenance Tools

Implement internal maintenance flows:

- rebuild DB from manifests
- identify orphan DB records
- identify orphan files
- regenerate previews
- clean old inbox payloads

These can be debug-only at first.

Acceptance criteria:

- a damaged local DB can be repopulated from on-disk manifests
- missing previews do not require data loss

## Keep / Rewrite / Delete

### Keep And Adapt

- `MainGridView.swift`
- tile preview flows
- file and photo picker integration
- link metadata fetchers
- share item extraction logic

### Rewrite

- root app state
- feed loading state management
- all composer backend calls
- preview resolution logic
- account/settings flow
- share compose submission logic

### Delete

- WordPress auth
- WordPress site models
- WordPress token storage
- WordPress media upload session
- WordPress post parsing model

## Implementation Order

Recommended order of engineering work:

1. domain entities and repository interfaces
2. SwiftData schema and repositories
3. iCloud file store
4. manifest writer and reader
5. create and fetch use cases
6. feed view model
7. thought and link composers
8. photo and file imports
9. previews
10. share extension inbox flow
11. sync edge cases and repair tools
12. remove WordPress code

## Testing Strategy

Test the infrastructure first.

Priority tests:

- deterministic path generation
- manifest encode and decode
- file write and move coordination
- DB transaction behavior
- import retry behavior
- delete tombstone behavior
- DB rebuild from manifests

Feature tests:

- create thought
- create link with metadata
- import photo
- import file
- edit thought
- edit link
- delete item
- preview existing file

Manual device tests:

- iCloud disabled
- low connectivity
- second device sync
- large file import
- share extension with app terminated

## Risks To Manage Early

Top risks:

- iCloud file availability timing
- SwiftData plus CloudKit sync edge cases
- extension-to-app handoff reliability
- file coordination bugs
- stale previews after rename or delete

Mitigation:

- explicit sync and availability state in the model
- immutable original attachment policy
- inbox-based extension architecture
- manifest-driven repair path

## Suggested Repository Documentation Rules

As you build:

- keep one architecture doc updated
- add ADRs for storage and sync decisions
- document every schema change
- version the manifest schema from day one

## Release Gate

Before deleting WordPress code, confirm:

- all four item types work
- the share extension is stable
- local feed is fully DB-backed
- files are in the iCloud folder
- second-device sync is acceptable
- repair tooling exists at least in debug builds

Only then should the old backend code be removed.

