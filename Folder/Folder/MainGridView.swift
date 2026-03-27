import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import QuickLook
import QuickLookThumbnailing

// MARK: - Post Status

struct PostStatus: Equatable {
    enum Kind { case posting, success, failure }
    let kind: Kind
    let message: String
}

// MARK: - Post Type

enum PostType { case photo, message, link, file }

// MARK: - Main Screen

struct MainGridView: View {
    @Environment(WordPressAuthManager.self) private var auth

    // Feed
    @State private var posts: [WordPressPost] = []
    @State private var isLoading = false
    @State private var loadError: String?

    // Account
    @State private var showAccount = false

    // Sheet presentations
    @State private var showTextComposer = false
    @State private var showLinkComposer = false
    @State private var showFilePicker = false
    @State private var photoPickerPresented = false

    // Photo
    @State private var selectedPhotoItems: [PhotosPickerItem] = []

    // Filter
    @State private var activeFilter: PostType? = nil

    // Posting status
    @State private var postStatus: PostStatus?
    @State private var postingTask: Task<Void, Never>?

    private var filteredPosts: [WordPressPost] {
        guard let filter = activeFilter else { return posts }
        return posts.filter { post in
            switch filter {
            case .photo:   return post.format == "image"
            case .message: return post.format == "aside"
            case .link:    return post.format == "link"
            case .file:    return post.tagSlugs.contains("folder-file")
            }
        }
    }

    private var postManager: WordPressPostManager? {
        guard let token = auth.token, let site = auth.selectedSite else { return nil }
        return WordPressPostManager(token: token, site: site)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && posts.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = loadError, posts.isEmpty {
                    ContentUnavailableView {
                        Label("Couldn't Load", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") { Task { await loadPosts() } }
                    }
                } else if posts.isEmpty {
                    ContentUnavailableView(
                        "Nothing here yet",
                        systemImage: "folder",
                        description: Text("Tap + to add your first post.")
                    )
                } else {
                    List(filteredPosts) { post in PostRowView(post: post) }
                        .listStyle(.plain)
                        .refreshable { await loadPosts() }
                }
            }
            .navigationTitle("Folder")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAccount = true } label: {
                        AvatarButton(url: auth.user?.avatarURL)
                    }
                    .buttonStyle(.plain)
                }
                ToolbarItem(placement: .bottomBar) {
                    Menu {
                        Button { activeFilter = nil } label: {
                            Label("All", systemImage: "tray.full")
                        }
                        Button { activeFilter = .photo } label: {
                            Label("Photos", systemImage: "photo")
                        }
                        Button { activeFilter = .message } label: {
                            Label("Text", systemImage: "text.bubble")
                        }
                        Button { activeFilter = .link } label: {
                            Label("Links", systemImage: "link")
                        }
                        Button { activeFilter = .file } label: {
                            Label("Files", systemImage: "doc")
                        }
                    } label: {
                        Image(systemName: activeFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                            .fontWeight(.semibold)
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Spacer()
                }
                ToolbarItem(placement: .bottomBar) {
                    Menu {
                        Button { photoPickerPresented = true } label: {
                            Label("Photos", systemImage: "photo")
                        }
                        Button { showTextComposer = true } label: {
                            Label("Text", systemImage: "text.bubble")
                        }
                        Button { showLinkComposer = true } label: {
                            Label("Links", systemImage: "link")
                        }
                        Button { showFilePicker = true } label: {
                            Label("Files", systemImage: "doc")
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.black)
                                .frame(width: 44, height: 44)
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                }
            }
        }
        .task {
            if auth.user == nil { try? await auth.fetchUser() }
            await loadPosts()
        }
        .sheet(isPresented: $showAccount) { AccountSheet() }

        // Multi-photo picker
        .photosPicker(
            isPresented: $photoPickerPresented,
            selection: $selectedPhotoItems,
            maxSelectionCount: 0,
            matching: .images
        )
        .onChange(of: selectedPhotoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await handlePhotosSelected(items) }
        }

        // Composer modals
        .sheet(isPresented: $showTextComposer) {
            if let token = auth.token, let site = auth.selectedSite {
                TextComposerSheet(token: token, site: site) { label, action in
                    startPosting(label: label, action: action)
                }
            }
        }
        .sheet(isPresented: $showLinkComposer) {
            if let token = auth.token, let site = auth.selectedSite {
                LinkComposerSheet(token: token, site: site) { label, action in
                    startPosting(label: label, action: action)
                }
            }
        }

        // File importer
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.item]) { result in
            handleFileSelected(result)
        }

        // Floating status bar
        .overlay(alignment: .bottom) {
            if let status = postStatus {
                PostStatusBar(status: status)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4), value: postStatus)
    }

    // MARK: - Photo handling

    private func handlePhotosSelected(_ items: [PhotosPickerItem]) async {
        let captured = items
        selectedPhotoItems = []

        var photos: [Data] = []
        for item in captured {
            if let data = try? await item.loadTransferable(type: Data.self) {
                photos.append(data)
            }
        }
        guard let pm = postManager, !photos.isEmpty else { return }
        let label = photos.count == 1 ? "Photo" : "\(photos.count) photos"
        startPosting(label: label) {
            for data in photos {
                try await pm.postPhoto(data: data, caption: "")
            }
        }
    }

    // MARK: - File handling

    private func handleFileSelected(_ result: Result<URL, Error>) {
        guard let pm = postManager else { return }
        startPosting(label: "File") {
            let fileURL = try result.get()
            guard fileURL.startAccessingSecurityScopedResource() else { return }
            defer { fileURL.stopAccessingSecurityScopedResource() }
            let data = try Data(contentsOf: fileURL)
            let name = fileURL.lastPathComponent
            let mime = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            try await pm.postFile(data: data, filename: name, mimeType: mime)
        }
    }

    // MARK: - Posting

    func startPosting(label: String, action: @escaping () async throws -> Void) {
        postingTask?.cancel()
        postStatus = PostStatus(kind: .posting, message: "Posting \(label.lowercased())…")
        postingTask = Task {
            do {
                try await action()
                guard !Task.isCancelled else { return }
                postStatus = PostStatus(kind: .success, message: "\(label) posted!")
                await loadPosts()
            } catch {
                guard !Task.isCancelled else { return }
                postStatus = PostStatus(kind: .failure, message: error.localizedDescription)
            }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            postStatus = nil
        }
    }

    // MARK: - Feed

    private func loadPosts() async {
        guard let pm = postManager else { return }
        isLoading = true
        loadError = nil
        do {
            posts = try await pm.fetchPosts()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Floating Status Bar

struct PostStatusBar: View {
    let status: PostStatus

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if status.kind == .posting {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: status.kind == .success ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                }
            }
            .foregroundStyle(.white)

            Text(status.message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            {
                switch status.kind {
                case .posting: Color(.label)
                case .success: Color.green
                case .failure: Color.red
                }
            }(),
            in: RoundedRectangle(cornerRadius: 14)
        )
    }
}

// MARK: - Post Row

struct PostRowView: View {
    let post: WordPressPost

    @State private var previewURL: URL?
    @State private var isDownloading = false
    @State private var downloadError: String?

    private var dateText: String {
        if Calendar.current.isDateInToday(post.date) {
            return post.date.formatted(date: .omitted, time: .shortened)
        } else {
            return post.date.formatted(date: .abbreviated, time: .omitted)
        }
    }

    private var isFile: Bool { post.tagSlugs.contains("folder-file") }

    private static func fileIcon(for filename: String) -> (symbol: String, color: Color) {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf":                              return ("doc.richtext.fill",           .red)
        case "doc", "docx":                      return ("doc.text.fill",               .blue)
        case "xls", "xlsx", "csv":               return ("tablecells.fill",             .green)
        case "ppt", "pptx":                      return ("rectangle.on.rectangle.fill", .orange)
        case "zip", "rar", "gz", "tar":          return ("archivebox.fill",             .brown)
        case "mp3", "m4a", "wav", "aac":         return ("music.note",                  .pink)
        case "mp4", "mov", "avi", "mkv":         return ("video.fill",                  .purple)
        case "txt", "md":                        return ("doc.plaintext.fill",          .secondary)
        case "jpg", "jpeg", "png", "gif", "heic":return ("photo.fill",                  .teal)
        default:                                 return ("doc.fill",                    .secondary)
        }
    }

    private func cachedFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("folder_\(post.id)_\(post.displayTitle)")
    }

    var body: some View {
        let fileInfo = PostRowView.fileIcon(for: post.displayTitle)

        Button {
            guard isFile, post.fileURL != nil else { return }
            Task { await downloadAndPreview() }
        } label: {
            HStack(spacing: 12) {
                if isFile {
                    FileThumbnailView(
                        remoteURL: post.fileURL,
                        localURL: cachedFileURL(),
                        symbol: fileInfo.symbol,
                        color: fileInfo.color,
                        isDownloading: isDownloading
                    )
                } else if let urlString = post.featuredImageURL, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                        else { Color.secondary.opacity(0.15) }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(post.displayTitle)
                        .font(.body)
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                    Text(dateText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .quickLookPreview($previewURL)
        .alert("Preview failed", isPresented: Binding(
            get: { downloadError != nil },
            set: { if !$0 { downloadError = nil } }
        )) {
            Button("OK", role: .cancel) { downloadError = nil }
        } message: {
            Text(downloadError ?? "")
        }
    }

    private func downloadAndPreview() async {
        guard let remoteURL = post.fileURL else { return }
        isDownloading = true
        defer { isDownloading = false }
        do {
            let dest = cachedFileURL()
            if !FileManager.default.fileExists(atPath: dest.path) {
                let (tmpURL, _) = try await URLSession.shared.download(from: remoteURL)
                try FileManager.default.moveItem(at: tmpURL, to: dest)
            }
            previewURL = dest
        } catch {
            downloadError = error.localizedDescription
        }
    }
}

// MARK: - File Thumbnail

struct FileThumbnailView: View {
    let remoteURL: URL?
    let localURL: URL
    let symbol: String
    let color: Color
    let isDownloading: Bool

    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.12))
            if isDownloading {
                ProgressView()
            } else if let thumb = thumbnail {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 24))
                    .foregroundStyle(color)
            }
        }
        .frame(width: 56, height: 56)
        .task(id: localURL.path) {
            await generateThumbnail()
        }
    }

    private func generateThumbnail() async {
        guard let remoteURL else { return }
        do {
            if !FileManager.default.fileExists(atPath: localURL.path) {
                let (tmpURL, _) = try await URLSession.shared.download(from: remoteURL)
                try FileManager.default.moveItem(at: tmpURL, to: localURL)
            }
            let request = QLThumbnailGenerator.Request(
                fileAt: localURL,
                size: CGSize(width: 112, height: 112),
                scale: 2,
                representationTypes: .thumbnail
            )
            let rep = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            thumbnail = rep.uiImage
        } catch {
            // Fall back to icon silently
        }
    }
}

// MARK: - Type Selection Sheet

struct TypeSelectionSheet: View {
    let onSelect: (PostType) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text("Add to Folder")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)

            Divider()
            actionRow(icon: "photo.stack",            label: "Post a photo")  { onSelect(.photo) }
            Divider().padding(.leading, 56)
            actionRow(icon: "link.circle.fill",       label: "Add a link")    { onSelect(.link) }
            Divider().padding(.leading, 56)
            actionRow(icon: "text.document",          label: "Upload a file") { onSelect(.file) }
            Divider().padding(.leading, 56)
            actionRow(icon: "character.text.justify", label: "Post text")     { onSelect(.message) }
            Divider().padding(.top, 8)

            Button { dismiss() } label: {
                Text("Cancel")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .presentationDetents([.height(375)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGroupedBackground))
    }

    private func actionRow(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(.primary)
                    .frame(width: 28)
                Text(label).font(.body).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Text Composer Sheet

struct TextComposerSheet: View {
    let token: String
    let site: WordPressSite
    let onPost: (String, @escaping () async throws -> Void) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private var postManager: WordPressPostManager { WordPressPostManager(token: token, site: site) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What's on your mind?", text: $text, axis: .vertical)
                        .lineLimit(8...)
                        .focused($focused)
                }
            }
            .navigationTitle("Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        let t = text; let pm = postManager
                        onPost("Text") { try await pm.postMessage(t) }
                        dismiss()
                    }
                }
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            focused = true
        }
    }
}

// MARK: - Link Composer Sheet

struct LinkComposerSheet: View {
    let token: String
    let site: WordPressSite
    let onPost: (String, @escaping () async throws -> Void) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var title = ""
    @State private var linkDescription = ""
    @State private var fetcher = LinkMetadataFetcher()
    @FocusState private var focused: Bool

    private var postManager: WordPressPostManager { WordPressPostManager(token: token, site: site) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com", text: $url)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($focused)

                    if fetcher.isFetching {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.75)
                            Text("Fetching page info…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if fetcher.fetchedTitle != nil || fetcher.fetchedDescription != nil {
                        HStack(alignment: .top, spacing: 10) {
                            Group {
                                if let favicon = fetcher.favicon {
                                    Image(uiImage: favicon)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    Image(systemName: "globe")
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }
                            .frame(width: 24, height: 24)
                            .clipShape(RoundedRectangle(cornerRadius: 5))

                            VStack(alignment: .leading, spacing: 2) {
                                if let t = fetcher.fetchedTitle {
                                    Text(t).font(.subheadline).lineLimit(2)
                                }
                                if let d = fetcher.fetchedDescription {
                                    Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Title (optional)") {
                    TextField("Add a title", text: $title)
                }

                Section("Description (optional)") {
                    TextField("Add a description", text: $linkDescription, axis: .vertical)
                        .lineLimit(3...)
                }
            }
            .navigationTitle("Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        let u = url; let t = title; let d = linkDescription; let pm = postManager
                        onPost("Link") { try await pm.postLink(url: u, title: t, description: d) }
                        dismiss()
                    }
                    .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            focused = true
        }
        .onChange(of: url) { _, newURL in
            // Clear fields and re-fetch whenever the URL changes
            title = ""
            linkDescription = ""
            fetcher.schedule(urlString: newURL)
        }
        .onChange(of: fetcher.fetchedTitle) { _, newTitle in
            title = newTitle ?? ""
        }
        .onChange(of: fetcher.fetchedDescription) { _, newDesc in
            linkDescription = newDesc ?? ""
        }
    }
}

// MARK: - Avatar Button

struct AvatarButton: View {
    let url: String?
    var size: CGFloat = 30

    var body: some View {
        Group {
            if let urlString = url, let avatarURL = URL(string: urlString) {
                AsyncImage(url: avatarURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

// MARK: - Account Sheet

struct AccountSheet: View {
    @Environment(WordPressAuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let uiImage = UIImage(named: "AppIconDisplay") {
                    Section {
                        HStack {
                            Spacer()
                            Image(uiImage: uiImage)
                                .resizable()
                                .frame(width: 96, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                Section("Logged as") {
                    HStack(spacing: 14) {
                        AvatarButton(url: auth.user?.avatarURL, size: 72)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(auth.user?.displayName ?? "WordPress.com")
                                .font(.headline)
                            if let user = auth.user {
                                Text(user.username.isEmpty ? user.email : "@\(user.username)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let site = auth.selectedSite {
                    Section("Posting to") {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(site.name).font(.body)
                            Text(site.url).font(.footnote).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section {
                    Button("Disconnect", role: .destructive) {
                        dismiss()
                        auth.logout()
                    }
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
