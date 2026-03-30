import SwiftUI
import PhotosUI
import Photos
import UniformTypeIdentifiers
import QuickLook
import QuickLookThumbnailing
import LinkPresentation
import AVKit
import PDFKit
import SafariServices

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
    @State private var hasLoaded = false

    // Pagination
    @State private var isLoadingMore = false
    @State private var hasMore = true
    private let pageSize = 20

    // Posting status
    @State private var postStatus: PostStatus?
    @State private var postingTask: Task<Void, Never>?

    // Tile preview state
    @State private var quickLookURL: URL?
    @State private var isPreparingPreview = false
    @State private var safariURL: URL?
    @State private var textPreviewPost: WordPressPost?
    @State private var videoPreviewPost: WordPressPost?
    @State private var videoPreviewPlayer: AVPlayer?

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

    private var feedContent: some View {
        ScrollView {
            if (isLoading || !hasLoaded) && posts.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 300)
            } else if let error = loadError, posts.isEmpty {
                ContentUnavailableView {
                    Label("Couldn't Load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await loadPosts() } }
                }
            } else if !isLoading && hasLoaded && posts.isEmpty {
                ContentUnavailableView(
                    "Nothing here yet",
                    systemImage: "folder",
                    description: Text("Tap + to add your first post.")
                )
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                    spacing: 16
                ) {
                    ForEach(filteredPosts) { post in
                        Button {
                            handleTileTap(post)
                        } label: {
                            PostGridCard(post: post)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if hasMore && post.id == posts.last?.id {
                                Task { await loadMorePosts() }
                            }
                        }
                    }
                }
                .padding(16)
                if isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 16)
                } else if !hasMore && hasLoaded && !posts.isEmpty {
                    Text("All caught up")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 80)
                }
            }
        }
    }

    private var filterLabel: String? {
        switch activeFilter {
        case .photo:   return "Photos"
        case .message: return "Text"
        case .link:    return "Links"
        case .file:    return "Files"
        case nil:      return nil
        }
    }

    private var navigationTitleString: String {
        filterLabel.map { "Folder / \($0)" } ?? "Folder"
    }

    var body: some View {
        NavigationStack {
            feedContent
            .refreshable {
                // Run loadPosts() as an unstructured task so SwiftUI re-renders
                // during loading don't cancel it. Awaiting a non-throwing Task.value
                // is not interrupted by parent cancellation, keeping the spinner alive.
                await Task { await loadPosts() }.value
            }
            .navigationTitle(navigationTitleString)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAccount = true } label: {
                        AvatarButton(url: auth.user?.avatarURL)
                    }
                    .buttonStyle(.borderless)
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
                        Image(systemName: "line.3.horizontal.decrease")
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
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                    .menuStyle(.button)
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

        // Preview loading spinner (shown while downloading for QuickLook)
        .overlay {
            if isPreparingPreview {
                ZStack {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    ProgressView()
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isPreparingPreview)

        // QuickLook (photos, image files, other files)
        .quickLookPreview($quickLookURL)

        // Safari (links)
        .sheet(isPresented: Binding(
            get: { safariURL != nil },
            set: { if !$0 { safariURL = nil } }
        )) {
            if let url = safariURL {
                SafariSheet(url: url)
                    .ignoresSafeArea()
            }
        }

        // Text bottom sheet
        .sheet(item: $textPreviewPost) { post in
            TextTilePreviewSheet(post: post)
        }

        // Video full-screen cover
        .fullScreenCover(item: $videoPreviewPost) { _ in
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                if let player = videoPreviewPlayer {
                    VideoTilePreviewCover(player: player)
                        .ignoresSafeArea()
                } else {
                    ProgressView().tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Button { videoPreviewPost = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                        .padding()
                }
            }
        }
        .onChange(of: videoPreviewPost) { _, newPost in
            if newPost == nil {
                videoPreviewPlayer?.pause()
                videoPreviewPlayer = nil
            }
        }
    }

    // MARK: - Photo handling

    private func handlePhotosSelected(_ items: [PhotosPickerItem]) async {
        let captured = items
        selectedPhotoItems = []

        var photos: [(data: Data, filename: String)] = []
        for item in captured {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            var filename = "photo.jpg"
            if let identifier = item.itemIdentifier {
                let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
                if let asset = result.firstObject {
                    let resources = PHAssetResource.assetResources(for: asset)
                    if let resource = resources.first(where: { $0.type == .photo || $0.type == .fullSizePhoto }) {
                        filename = resource.originalFilename
                    }
                }
            }
            photos.append((data, filename))
        }
        guard let pm = postManager, !photos.isEmpty else { return }
        let label = photos.count == 1 ? "Photo" : "\(photos.count) photos"
        startPosting(label: label) {
            for photo in photos {
                try await pm.postPhoto(data: photo.data, filename: photo.filename, caption: "")
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
        defer { isLoading = false; hasLoaded = true }
        do {
            let fetched = try await pm.fetchPosts(number: pageSize)
            hasMore = fetched.count == pageSize
            posts = fetched
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: - Tile preview

    private func handleTileTap(_ post: WordPressPost) {
        let isFile = post.tagSlugs.contains("folder-file")
        let fileExt = (post.displayTitle as NSString).pathExtension.lowercased()

        if post.format == "link", let url = post.linkURL {
            safariURL = url
        } else if post.format == "aside" {
            textPreviewPost = post
        } else if post.format == "image",
                  let urlStr = post.featuredImageURL,
                  let url = URL(string: urlStr) {
            let filename = url.lastPathComponent.isEmpty ? "photo.jpg" : url.lastPathComponent
            Task { await prepareQuickLook(url: url, filename: filename, postId: post.id) }
        } else if isFile && PostRowView.videoExtensions.contains(fileExt) {
            Task { await prepareVideoPreview(post: post) }
        } else if isFile, let fileURL = post.fileURL {
            Task { await prepareQuickLook(url: fileURL, filename: post.displayTitle, postId: post.id) }
        }
    }

    private func prepareQuickLook(url: URL, filename: String, postId: Int) async {
        isPreparingPreview = true
        defer { isPreparingPreview = false }
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("folder_ql_\(postId)_\(filename)")
        do {
            if !FileManager.default.fileExists(atPath: dest.path) {
                let (tmp, _) = try await URLSession.shared.download(from: url)
                try FileManager.default.moveItem(at: tmp, to: dest)
            }
            quickLookURL = dest
        } catch {}
    }

    private func prepareVideoPreview(post: WordPressPost) async {
        guard let url = post.fileURL else { return }
        videoPreviewPost = post  // show cover immediately (buffering state)

        let guid: String?
        if url.scheme == "videopress" {
            guid = url.host
        } else if url.host == "videos.files.wordpress.com" {
            guid = url.pathComponents.dropFirst().first
        } else {
            guid = nil
        }

        let playbackURL: URL
        if let guid, !guid.isEmpty, let pm = postManager,
           let resolved = await pm.fetchVideoPressPlaybackURL(guid: guid) {
            playbackURL = resolved
        } else if url.scheme == "https" {
            playbackURL = url
        } else {
            videoPreviewPost = nil
            return
        }

        let player = AVPlayer(url: playbackURL)
        videoPreviewPlayer = player
        player.play()
    }

    private func loadMorePosts() async {
        guard !isLoadingMore, !isLoading, hasMore, let pm = postManager else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let fetched = try await pm.fetchPosts(number: pageSize, offset: posts.count)
            hasMore = fetched.count == pageSize
            posts.append(contentsOf: fetched)
        } catch {}
    }
}

// MARK: - Floating Status Bar

struct PostStatusBar: View {
    let status: PostStatus

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if status.kind == .posting {
                    ProgressView().tint(Color(.systemBackground))
                } else {
                    Image(systemName: status.kind == .success ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                }
            }
            .foregroundStyle(Color(.systemBackground))

            Text(status.message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(.systemBackground))
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

    private var dateText: String {
        if Calendar.current.isDateInToday(post.date) {
            return post.date.formatted(date: .omitted, time: .shortened)
        } else {
            return post.date.formatted(date: .abbreviated, time: .omitted)
        }
    }

    private var isFile: Bool { post.tagSlugs.contains("folder-file") }

    static func fileIcon(for filename: String) -> (symbol: String, color: Color) {
        let ext = (filename as NSString).pathExtension.lowercased()
        let symbol: String
        switch ext {
        case "pdf":                              symbol = "doc.richtext.fill"
        case "doc", "docx":                      symbol = "doc.text.fill"
        case "xls", "xlsx", "csv":               symbol = "tablecells.fill"
        case "ppt", "pptx":                      symbol = "rectangle.on.rectangle.fill"
        case "zip", "rar", "gz", "tar":          symbol = "archivebox.fill"
        case "mp3", "m4a", "wav", "aac":         symbol = "music.note"
        case "mp4", "mov", "avi", "mkv", "m4v":  symbol = "video.fill"
        case "txt", "md":                        symbol = "doc.plaintext.fill"
        case "jpg", "jpeg", "png", "gif", "heic":symbol = "photo.fill"
        default:                                 symbol = "doc.fill"
        }
        return (symbol, .blue)
    }

    static let videoExtensions: Set<String> = ["mp4", "mov", "avi", "mkv", "m4v"]
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "heic", "webp"]

    private func cachedFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("folder_\(post.id)_\(post.displayTitle)")
    }

    var body: some View {
        let fileInfo = PostRowView.fileIcon(for: post.displayTitle)
        HStack(spacing: 12) {
            if isFile {
                let ext = (post.displayTitle as NSString).pathExtension.lowercased()
                if PostRowView.imageExtensions.contains(ext), let url = post.fileURL {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                        else { Color.secondary.opacity(0.15) }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    FileThumbnailView(
                        remoteURL: post.fileURL,
                        localURL: cachedFileURL(),
                        symbol: fileInfo.symbol,
                        color: fileInfo.color,
                        isDownloading: false
                    )
                }
            } else if post.format == "aside" {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.08))
                    Image(systemName: "text.quote")
                        .font(.system(size: 22))
                        .foregroundStyle(.blue)
                }
                .frame(width: 56, height: 56)
            } else if post.format == "link", let url = post.linkURL {
                LinkThumbnailView(url: url)
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

// MARK: - Link Thumbnail

private let linkImageCache = NSCache<NSString, UIImage>()
private let videoThumbnailCache = NSCache<NSString, UIImage>()

struct LinkThumbnailView: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.1))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "link")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: url.absoluteString) {
            let key = url.absoluteString as NSString
            if let cached = linkImageCache.object(forKey: key) {
                image = cached
                return
            }
            let provider = LPMetadataProvider()
            provider.shouldFetchSubresources = true
            guard let meta = try? await provider.startFetchingMetadata(for: url) else { return }
            let itemProvider = meta.imageProvider ?? meta.iconProvider
            guard let itemProvider else { return }
            let cacheKey = url.absoluteString // Capture as Sendable String
            await withCheckedContinuation { cont in
                itemProvider.loadObject(ofClass: UIImage.self) { obj, _ in
                    if let img = obj as? UIImage {
                        linkImageCache.setObject(img, forKey: cacheKey as NSString)
                        Task { @MainActor in image = img }
                    }
                    cont.resume()
                }
            }
        }
    }
}

// MARK: - Grid Card

struct PostGridCard: View {
    let post: WordPressPost

    private var isFile: Bool { post.tagSlugs.contains("folder-file") }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Group {
                    if isFile {
                        FileGridCard(post: post)
                    } else if post.format == "aside" {
                        TextGridCard(post: post)
                    } else if post.format == "link" {
                        LinkGridCard(post: post)
                    } else {
                        PhotoGridCard(post: post)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator), lineWidth: 1))
    }
}

// MARK: Photo card

private struct PhotoGridCard: View {
    let post: WordPressPost

    var body: some View {
        GeometryReader { geo in
            if let urlStr = post.featuredImageURL, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    if let img = phase.image {
                        img.resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    } else {
                        Color(.systemGray5)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
            } else {
                Color(.systemGray5)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            GridTypeBadge(systemImage: "photo.fill").padding(8)
        }
    }
}

// MARK: Text card

private struct TextGridCard: View {
    let post: WordPressPost

    private var textContent: String {
        (post.rawContent ?? post.displayTitle)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(.systemGray6)
            Text(textContent)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .padding(16)
        }
        .overlay(alignment: .bottomTrailing) {
            GridTypeBadge(systemImage: "text.quote").padding(8)
        }
    }
}

// MARK: Link card

private struct LinkGridCard: View {
    let post: WordPressPost
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if let url = post.linkURL {
                LinkCardBackground(url: url)
            } else {
                Color(.systemGray6)
            }

            VStack {
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.system(size: 12, weight: .medium))
                    Text(post.displayTitle)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(colorScheme == .dark ? Color.black : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

// MARK: File card

private struct FileGridCard: View {
    let post: WordPressPost

    private var fileTypeLabel: String {
        let ext = (post.displayTitle as NSString).pathExtension.lowercased()
        switch ext {
        case "mp4", "mov", "avi", "mkv", "m4v": return "Video file"
        case "mp3", "m4a", "wav", "aac":        return "Audio file"
        case "pdf":                              return "PDF"
        case "doc", "docx":                      return "Document"
        case "xls", "xlsx", "csv":              return "Spreadsheet"
        case "zip", "rar", "gz", "tar":         return "Archive"
        default:                                return "File"
        }
    }

    private var isPhoto: Bool {
        let ext = (post.displayTitle as NSString).pathExtension.lowercased()
        return PostRowView.imageExtensions.contains(ext)
    }

    private var isVideo: Bool {
        let ext = (post.displayTitle as NSString).pathExtension.lowercased()
        return PostRowView.videoExtensions.contains(ext)
    }

    var body: some View {
        ZStack {
            if isPhoto, let url = post.fileURL {
                GeometryReader { geo in
                    AsyncImage(url: url) { phase in
                        if let img = phase.image {
                            img.resizable()
                                .scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        } else {
                            Color(.systemGray5)
                                .frame(width: geo.size.width, height: geo.size.height)
                        }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    GridTypeBadge(systemImage: "photo.fill").padding(8)
                }
            } else if isVideo, let url = post.fileURL {
                VideoThumbnailGridView(url: url)
                    .overlay(alignment: .bottomTrailing) {
                        GridTypeBadge(systemImage: "video.fill").padding(8)
                    }
            } else {
                Color(.systemGray6)
                VStack(spacing: 0) {
                    Spacer()
                    HStack(alignment: .bottom, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fileTypeLabel)
                                .font(.system(size: 15, weight: .medium))
                            Text(post.displayTitle)
                                .font(.system(size: 15, weight: .medium))
                                .lineLimit(1)
                        }
                        Spacer()
                        GridTypeBadge(systemImage: PostRowView.fileIcon(for: post.displayTitle).symbol)
                    }
                }
                .foregroundStyle(.primary)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: Shared grid subviews

private struct GridTypeBadge: View {
    let systemImage: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(colorScheme == .dark ? Color.black : Color.white)
                .frame(width: 44, height: 44)
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
        }
    }
}

private struct LinkCardBackground: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            } else {
                Color(.systemGray6)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .task(id: url.absoluteString) {
            let key = url.absoluteString as NSString
            if let cached = linkImageCache.object(forKey: key) { image = cached; return }
            let provider = LPMetadataProvider()
            provider.shouldFetchSubresources = true
            guard let meta = try? await provider.startFetchingMetadata(for: url) else { return }
            let itemProvider = meta.imageProvider ?? meta.iconProvider
            guard let itemProvider else { return }
            let cacheKey = url.absoluteString // Capture as Sendable String
            await withCheckedContinuation { cont in
                itemProvider.loadObject(ofClass: UIImage.self) { obj, _ in
                    if let img = obj as? UIImage {
                        linkImageCache.setObject(img, forKey: cacheKey as NSString)
                        Task { @MainActor in image = img }
                    }
                    cont.resume()
                }
            }
        }
    }
}

// MARK: - Video Thumbnail Grid View

private struct VideoThumbnailGridView: View {
    let url: URL
    @State private var thumbnail: UIImage?

    var body: some View {
        GeometryReader { geo in
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    Color(.systemGray5)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
        .task(id: url.absoluteString) {
            let key = url.absoluteString as NSString
            if let cached = videoThumbnailCache.object(forKey: key) {
                thumbnail = cached; return
            }
            guard let img = await fetchThumbnail(for: url) else { return }
            videoThumbnailCache.setObject(img, forKey: key)
            thumbnail = img
        }
    }

    private func fetchThumbnail(for url: URL) async -> UIImage? {
        if url.scheme == "videopress", let guid = url.host {
            return await fetchVideoPressThumb(guid: guid)
        }
        if url.host?.hasSuffix("videos.files.wordpress.com") == true,
           let guid = url.pathComponents.dropFirst().first {
            return await fetchVideoPressThumb(guid: guid)
        }
        return await frameFromURL(url)
    }

    private func fetchVideoPressThumb(guid: String) async -> UIImage? {
        struct VP: Decodable {
            let poster: String?
            let mp4: MP4?
            struct MP4: Decodable {
                let original: String?
                let hd: String?
                let std: String?
            }
        }
        let apiURL = URL(string: "https://public-api.wordpress.com/rest/v1.1/videos/\(guid)")!
        guard let (data, response) = try? await URLSession.shared.data(from: apiURL),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let vp = try? JSONDecoder().decode(VP.self, from: data) else { return nil }

        // Poster image is a cheap JPEG — try first
        if let posterStr = vp.poster,
           let posterURL = URL(string: posterStr),
           let (imgData, _) = try? await URLSession.shared.data(from: posterURL),
           let img = UIImage(data: imgData) { return img }

        // Fallback: extract a frame from the mp4 URL
        for urlStr in [vp.mp4?.original, vp.mp4?.hd, vp.mp4?.std].compactMap({ $0 }) {
            if let mp4URL = URL(string: urlStr), let img = await frameFromURL(mp4URL) {
                return img
            }
        }
        return nil
    }

    private func frameFromURL(_ url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 600, height: 600)
        guard let (cgImage, _) = try? await generator.image(at: .zero) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Post Detail View

private struct FullScreenVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.entersFullScreenWhenPlaybackBegins = true
        vc.exitsFullScreenWhenPlaybackEnds = true
        return vc
    }
    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        vc.player = player
    }
}

struct PostDetailView: View {
    let post: WordPressPost
    let token: String
    let site: WordPressSite
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var previewURL: URL?
    @State private var isDownloading = false
    @State private var videoPlayer: AVPlayer?
    @State private var fullscreenPhotoURL: URL? = nil

    @State private var pdfFirstPage: UIImage?

    private var postManager: WordPressPostManager { WordPressPostManager(token: token, site: site) }
    private var isFile: Bool { post.tagSlugs.contains("folder-file") }

    /// Title to show in the metadata row below content.
    /// - Text/link posts: nil (date only, no duplicate)
    /// - Photo posts: filename extracted from the featured image URL
    /// - File posts: the stored display title (filename)
    private var metadataTitle: String? {
        switch post.format {
        case "aside", "link": return nil
        case "image":
            if let urlString = post.featuredImageURL,
               let url = URL(string: urlString) {
                let name = url.lastPathComponent
                return name.isEmpty ? nil : name
            }
            return nil
        default: return post.displayTitle
        }
    }

    private func cachedFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("folder_\(post.id)_\(post.displayTitle)")
    }

    private var isVideoFile: Bool {
        isFile && PostRowView.videoExtensions.contains(fileExt)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                contentPreview
                    .frame(maxWidth: .infinity)

                Divider()
                    .padding(.top, (post.format == "image" || isImageFile || isVideoFile) ? 0 : 20)

                VStack(alignment: .leading, spacing: 4) {
                    if let label = metadataTitle {
                        Text(label)
                            .font(.headline)
                    }
                    Text(post.date.formatted(date: .long, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 16)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isDeleting {
                    ProgressView()
                } else {
                    Menu {
                        Button {
                            performCopy()
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
        .alert("Remove this item?", isPresented: $showDeleteConfirm) {
            Button("Remove", role: .destructive) { Task { await performDelete() } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Couldn't Remove", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK") { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
        .quickLookPreview($previewURL)
        .fullScreenCover(isPresented: Binding(
            get: { fullscreenPhotoURL != nil },
            set: { if !$0 { fullscreenPhotoURL = nil } }
        )) {
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                if let url = fullscreenPhotoURL {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFit()
                        } else if phase.error == nil {
                            ProgressView().tint(.white)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Button { fullscreenPhotoURL = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                        .padding()
                }
            }
            .ignoresSafeArea()
            .onTapGesture { fullscreenPhotoURL = nil }
        }
        .task {
            if PostRowView.videoExtensions.contains(fileExt) {
                await setupVideoPlayer()
            } else if fileExt == "pdf" {
                await loadPDFFirstPage()
            }
        }
    }

    private var fileExt: String {
        (post.displayTitle as NSString).pathExtension.lowercased()
    }
    private var isImageFile: Bool {
        isFile && PostRowView.imageExtensions.contains(fileExt)
    }

    @ViewBuilder
    private var contentPreview: some View {
        if post.format == "image", let urlString = post.featuredImageURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFit()
                case .failure: Color.secondary.opacity(0.1).frame(height: 200)
                default: Color.secondary.opacity(0.08).frame(height: 200).overlay { ProgressView() }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
            .onTapGesture { Task { await downloadAndPreviewPhoto(url: url) } }
        } else if post.format == "link", let url = post.linkURL {
            Button { UIApplication.shared.open(url) } label: {
                HStack(spacing: 14) {
                    LinkThumbnailView(url: url)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(post.displayTitle)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                        Text(url.host ?? url.absoluteString)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .foregroundStyle(.tertiary)
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding()
            }
            .buttonStyle(.plain)
        } else if isImageFile, let url = post.fileURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFit()
                case .failure: Color.secondary.opacity(0.1).frame(height: 200)
                default: Color.secondary.opacity(0.08).frame(height: 200).overlay { ProgressView() }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
            .onTapGesture { Task { await downloadAndPreviewPhoto(url: url) } }
        } else if isFile && PostRowView.videoExtensions.contains(fileExt) {
            GeometryReader { geo in
                let videoWidth = geo.size.width - 32
                let videoHeight = videoWidth * 9 / 16
                let containerHeight = videoHeight + 280
                ZStack {
                    Color(.systemGray6)
                        .frame(width: geo.size.width, height: containerHeight)
                    Group {
                        if let player = videoPlayer {
                            FullScreenVideoPlayer(player: player)
                                .frame(width: videoWidth, height: videoHeight)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            Color.secondary.opacity(0.08)
                                .frame(width: videoWidth, height: videoHeight)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay { ProgressView() }
                        }
                    }
                }
                .frame(width: geo.size.width, height: containerHeight)
                .position(x: geo.size.width / 2, y: containerHeight / 2)
            }
            .aspectRatio(16/9, contentMode: .fit)
            .padding(.horizontal, 16)
            .padding(.top, 8)
        } else if isFile && fileExt == "pdf" {
            VStack(spacing: 0) {
                if let page = pdfFirstPage {
                    Image(uiImage: page)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                } else {
                    Color.secondary.opacity(0.08)
                        .frame(height: 300)
                        .overlay { ProgressView() }
                }
                Button("Open File") { Task { await downloadAndPreview() } }
                    .buttonStyle(.bordered)
                    .padding(.top, 20)
                    .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity)
        } else if isFile {
            let fileInfo = PostRowView.fileIcon(for: post.displayTitle)
            VStack(spacing: 20) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(Color.blue.opacity(0.1))
                    Image(systemName: fileInfo.symbol)
                        .font(.system(size: 52))
                        .foregroundStyle(.blue)
                }
                .frame(width: 120, height: 120)
                if isDownloading {
                    ProgressView("Downloading…")
                } else {
                    Button("Preview File") { Task { await downloadAndPreview() } }
                        .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        } else {
            let raw = post.rawContent ?? ""
            let text = raw
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            Text(text.isEmpty ? post.displayTitle : text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
    }

    private func downloadAndPreviewPhoto(url: URL) async {
        let filename = url.lastPathComponent.isEmpty ? "photo.jpg" : url.lastPathComponent
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("folder_photo_\(post.id)_\(filename)")
        do {
            if !FileManager.default.fileExists(atPath: dest.path) {
                let (tmp, _) = try await URLSession.shared.download(from: url)
                try FileManager.default.moveItem(at: tmp, to: dest)
            }
            previewURL = dest
        } catch {}
    }

    private func performCopy() {
        switch post.format {
        case "aside":
            let raw = post.rawContent ?? ""
            let text = raw
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            UIPasteboard.general.string = text.isEmpty ? post.displayTitle : text
        case "link":
            UIPasteboard.general.string = post.linkURL?.absoluteString
        case "image":
            guard let urlString = post.featuredImageURL, let url = URL(string: urlString) else { return }
            Task {
                if let (data, _) = try? await URLSession.shared.data(from: url),
                   let image = UIImage(data: data) {
                    UIPasteboard.general.image = image
                }
            }
        default: // file
            UIPasteboard.general.string = post.fileURL?.absoluteString ?? post.url
        }
    }

    private func performDelete() async {
        isDeleting = true
        do {
            try await postManager.deletePost(id: post.id)
            onDelete()
            dismiss()
        } catch {
            deleteError = error.localizedDescription
            isDeleting = false
        }
    }

    private func setupVideoPlayer() async {
        guard let url = post.fileURL else {
            print("[Video] fileURL is nil for post '\(post.displayTitle)' — rawContent: \(post.rawContent?.prefix(200) ?? "nil")")
            return
        }

        // Resolve GUID-based URLs via the VideoPress API to get the actual CDN URL.
        let guid: String?
        if url.scheme == "videopress" {
            guid = url.host
        } else if url.host == "videos.files.wordpress.com" {
            guid = url.pathComponents.dropFirst().first
        } else {
            guid = nil
        }

        if let guid, !guid.isEmpty {
            if let playbackURL = await postManager.fetchVideoPressPlaybackURL(guid: guid) {
                videoPlayer = AVPlayer(url: playbackURL)
                return
            }
            if url.scheme == "https" { videoPlayer = AVPlayer(url: url) }
            return
        }

        guard url.scheme == "https" else { return }
        videoPlayer = AVPlayer(url: url)
    }

    private func loadPDFFirstPage() async {
        guard let remoteURL = post.fileURL else { return }
        let dest = cachedFileURL()
        do {
            if !FileManager.default.fileExists(atPath: dest.path) {
                let (tmp, _) = try await URLSession.shared.download(from: remoteURL)
                try FileManager.default.moveItem(at: tmp, to: dest)
            }
            guard let doc = PDFDocument(url: dest), let page = doc.page(at: 0) else { return }
            let bounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let renderer = UIGraphicsImageRenderer(size: size)
            let img = renderer.image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                ctx.cgContext.translateBy(x: 0, y: size.height)
                ctx.cgContext.scaleBy(x: scale, y: -scale)
                page.draw(with: .mediaBox, to: ctx.cgContext)
            }
            pdfFirstPage = img
        } catch {}
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
        } catch {}
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

    private func normalizedURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return trimmed }
        return "https://\(trimmed)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com", text: $url)
                        .keyboardType(.default)
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
                        let u = normalizedURL(url); let t = title; let d = linkDescription; let pm = postManager
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
            fetcher.schedule(urlString: normalizedURL(newURL))
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
                        Image(systemName: "person")
                            .resizable()
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Image(systemName: "person")
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
                        AvatarButton(url: auth.user?.avatarURL, size: 36)
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
                        HStack(spacing: 12) {
                            if let iconURLString = site.iconURL, let iconURL = URL(string: iconURLString) {
                                AsyncImage(url: iconURL) { phase in
                                    if let image = phase.image {
                                        image.resizable().scaledToFill()
                                    } else {
                                        Color.secondary.opacity(0.15)
                                    }
                                }
                                .frame(width: 36, height: 36)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(site.name).font(.headline)
                                Text(site.url).font(.footnote).foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            if let url = URL(string: site.url) {
                                Link(destination: url) {
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 16, weight: .medium))
                                }
                                .tint(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        dismiss()
                        Task {
                            try? await Task.sleep(for: .milliseconds(400))
                            auth.logout()
                        }
                    } label: {
                        Text("Disconnect")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .listSectionSpacing(8)
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
