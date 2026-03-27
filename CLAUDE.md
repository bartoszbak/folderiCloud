# CLAUDE.md

## Project Overview

**Folder** is an iOS app for quickly saving and sharing content (photos, links, text, files) to a WordPress.com blog. It uses the WordPress.com REST API and leverages iOS Share Extension for system-wide sharing from any app.

## Tech Stack

- **Language:** Swift 5.0
- **UI:** SwiftUI with `@Observable` state management
- **Min iOS:** iOS 26.2
- **Architecture:** MVVM — views are in `Folder/`, state/logic in manager classes
- **Backend:** WordPress.com REST API v1.1 (`public-api.wordpress.com`)
- **Auth:** OAuth 2.0 via `ASWebAuthenticationSession`
- **Storage:** Keychain (auth token), UserDefaults via App Group (site/user prefs shared with extension)
- **Dependencies:** None (no CocoaPods/SPM external packages — framework-only)

## Project Structure

```
Folder/
├── Folder/                     # Main app target
│   ├── FolderApp.swift         # @main entry point
│   ├── ContentView.swift       # Root view (login → site picker → main feed)
│   ├── MainGridView.swift      # Primary feed UI with compose menus and filters
│   ├── SitePickerView.swift    # Site selection after login
│   ├── WordPressAuthManager.swift   # OAuth flow + site/user data
│   ├── WordPressPostManager.swift   # API client (posts, media uploads)
│   ├── WordPressSite.swift     # Data models (Site, User, Post)
│   └── KeychainHelper.swift    # Token storage + App Group sharing
├── FolderShare/                # Share Extension target
│   ├── ShareViewController.swift    # Extension container, extracts shared items
│   └── ShareComposeView.swift       # Composer UI for shared content
├── FolderTests/                # Unit tests (minimal)
├── FolderUITests/              # UI tests (minimal)
└── Folder.xcodeproj/           # Xcode project
patch_project.py                # Patches .xcodeproj to add FolderShare target
```

## Build & Run

1. Open `Folder/Folder.xcodeproj` in Xcode 26.2+
2. Create `Folder/Folder/WordPressSecrets.swift` (git-ignored) with:
   ```swift
   enum WordPressSecrets {
       static let clientID = "<your-client-id>"
       static let clientSecret = "<your-client-secret>"
       static let redirectURI = "com.bartbak.fastapp.folder://"
   }
   ```
3. Select the **Folder** scheme and run on iOS 26.2+ device or simulator

To add the Share Extension target to a fresh Xcode project:
```bash
python3 patch_project.py
```

## Key Implementation Details

### Authentication Flow
- `WordPressAuthManager` handles OAuth login, token exchange, and stores the token in Keychain
- The token is shared with the Share Extension via `UserDefaults(suiteName: "group.com.bartbak.fastapp.folder")`
- App Group ID: `group.com.bartbak.fastapp.folder`

### Post Types
All posts go to WordPress via `WordPressPostManager`:
- **Photo** — uploads media first, then creates post with featured image
- **Text** — plain text post with `format: aside`
- **Link** — post with `format: link`, stores URL in `meta.links.origin`
- **File** — uploads file as media, tagged `folder-file`

### Share Extension
- `ShareViewController` (UIViewController) extracts `NSExtensionItem` attachments
- Passes extracted data to `ShareComposeView` (SwiftUI)
- Reads auth token from shared UserDefaults (not Keychain directly)
- Bundle ID: `com.bartbak.fastapp.Folder.FolderShare`

### Bundle IDs
- Main app: `com.bartbak.fastapp.Folder`
- Share extension: `com.bartbak.fastapp.Folder.FolderShare`
- App Group: `group.com.bartbak.fastapp.folder`
- Team ID: `TJ3ALYQV5G`

## Testing

Run tests via Xcode or:
```bash
xcodebuild test -project Folder/Folder.xcodeproj -scheme Folder -destination 'platform=iOS Simulator,name=iPhone 16'
```

Note: Test coverage is currently minimal (placeholder files only).

## Common Tasks

- **Add a new post type:** Add a case to the post creation flow in `WordPressPostManager.swift`, add a compose button in `MainGridView.swift`
- **Change API behavior:** `WordPressPostManager.swift` contains all API calls
- **Modify auth flow:** `WordPressAuthManager.swift`
- **Update share extension UI:** `ShareComposeView.swift`
- **Change data models:** `WordPressSite.swift`
