import QuickLook
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct FolderFeedView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: FeedViewModel
    @State private var thoughtComposer: ThoughtComposerViewModel
    @State private var linkComposer: LinkComposerViewModel
    @State private var photoImportViewModel: PhotoImportViewModel
    @State private var fileImportViewModel: FileImportViewModel
    @State private var showThoughtComposer = false
    @State private var showLinkComposer = false
    @State private var showFileImporter = false
    @State private var showMaintenance = false
    @State private var photoPickerPresented = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    private let runtime: FolderRuntimeConfiguration

    init(readyState: FolderLibraryBootstrapModel.FolderReadyState) {
        self.runtime = readyState.runtime
        _viewModel = State(initialValue: FeedViewModel(runtime: readyState.runtime))
        _thoughtComposer = State(initialValue: ThoughtComposerViewModel(runtime: readyState.runtime))
        _linkComposer = State(initialValue: LinkComposerViewModel(runtime: readyState.runtime))
        _photoImportViewModel = State(initialValue: PhotoImportViewModel(runtime: readyState.runtime))
        _fileImportViewModel = State(initialValue: FileImportViewModel(runtime: readyState.runtime))
    }

    var body: some View {
        NavigationStack {
            feedContent
                .navigationTitle(viewModel.navigationTitle)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await viewModel.load(force: true) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .fontWeight(.semibold)
                        }
                    }
#if DEBUG
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showMaintenance = true
                        } label: {
                            Image(systemName: "wrench.and.screwdriver")
                        }
                    }
#endif
                    ToolbarItem(placement: .bottomBar) {
                        Menu {
                            Button {
                                viewModel.activeFilter = nil
                            } label: {
                                Label("All Items", systemImage: "square.grid.2x2")
                            }
                            Button {
                                viewModel.activeFilter = .photo
                            } label: {
                                Label("Photos", systemImage: "photo.on.rectangle")
                            }
                            Button {
                                viewModel.activeFilter = .thought
                            } label: {
                                Label("Ideas", systemImage: "lightbulb")
                            }
                            Button {
                                viewModel.activeFilter = .link
                            } label: {
                                Label("Links", systemImage: "link")
                            }
                            Button {
                                viewModel.activeFilter = .file
                            } label: {
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
                            Button {
                                photoPickerPresented = true
                            } label: {
                                Label("Photo", systemImage: "photo.on.rectangle.angled")
                            }
                            Button {
                                thoughtComposer.reset()
                                showThoughtComposer = true
                            } label: {
                                Label("Idea", systemImage: "lightbulb")
                            }
                            Button {
                                linkComposer.reset()
                                showLinkComposer = true
                            } label: {
                                Label("Link", systemImage: "link.badge.plus")
                            }
                            Button {
                                showFileImporter = true
                            } label: {
                                Label("File", systemImage: "doc.badge.plus")
                            }
                        } label: {
                            Image(systemName: "plus")
                                .fontWeight(.semibold)
                        }
                    }
                }
        }
        .task { await viewModel.load() }
        .task(id: scenePhase) {
            if scenePhase == .active {
                await viewModel.processPendingShareImports()
            }
        }
        .photosPicker(
            isPresented: $photoPickerPresented,
            selection: $selectedPhotoItems,
            maxSelectionCount: 0,
            matching: .images
        )
        .onChange(of: selectedPhotoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                let importedCount = await photoImportViewModel.importItems(items)
                selectedPhotoItems = []
                if importedCount > 0 { await viewModel.load(force: true) }
            }
        }
        .sheet(isPresented: $showThoughtComposer) {
            FolderThoughtComposerSheet(viewModel: thoughtComposer) {
                await viewModel.load(force: true)
            }
        }
        .sheet(isPresented: $showLinkComposer) {
            FolderLinkComposerSheet(viewModel: linkComposer) {
                await viewModel.load(force: true)
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item]) { result in
            Task {
                if await fileImportViewModel.importFile(from: result) {
                    await viewModel.load(force: true)
                }
            }
        }
#if DEBUG
        .sheet(isPresented: $showMaintenance) {
            if let repository = try? runtime.makeRepository() {
                FolderMaintenanceView(
                    viewModel: FolderMaintenanceViewModel(
                        repository: repository,
                        fileStore: runtime.makeFileStore(),
                        inboxStore: runtime.makeInboxStore()
                    ) {
                        await viewModel.load(force: true)
                    }
                )
            } else {
                ContentUnavailableView(
                    "Maintenance Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("The local library could not be opened.")
                )
            }
        }
#endif
        .quickLookPreview($viewModel.quickLookURL)
        .sheet(item: $viewModel.thoughtPreview) { preview in
            FolderThoughtPreviewSheet(preview: preview)
        }
        .sheet(isPresented: Binding(
            get: { viewModel.safariURL != nil },
            set: { if !$0 { viewModel.safariURL = nil } }
        )) {
            if let url = viewModel.safariURL {
                SafariSheet(url: url).ignoresSafeArea()
            }
        }
        .overlay(alignment: .bottom) {
            if let status = viewModel.status {
                FeedStatusBar(status: status)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35), value: viewModel.status)
        .alert("Photo Import Failed", isPresented: Binding(
            get: { photoImportViewModel.errorMessage != nil },
            set: { if !$0 { photoImportViewModel.clearError() } }
        )) {
            Button("OK", role: .cancel) { photoImportViewModel.clearError() }
        } message: {
            Text(photoImportViewModel.errorMessage ?? "")
        }
        .alert("File Import Failed", isPresented: Binding(
            get: { fileImportViewModel.errorMessage != nil },
            set: { if !$0 { fileImportViewModel.clearError() } }
        )) {
            Button("OK", role: .cancel) { fileImportViewModel.clearError() }
        } message: {
            Text(fileImportViewModel.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var feedContent: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.loadError, viewModel.items.isEmpty {
            ContentUnavailableView {
                Label("Couldn't Load Library", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") {
                    Task { await viewModel.load(force: true) }
                }
            }
        } else if viewModel.filteredItems.isEmpty {
            emptyStateView
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14)
                    ],
                    spacing: 14
                ) {
                    ForEach(viewModel.filteredItems) { item in
                        Button {
                            Task { await viewModel.handleTap(item) }
                        } label: {
                            FeedCubeTile(item: item)
                        }
                        .buttonStyle(CubeTileButtonStyle())
                        .contextMenu {
                            Button {
                                Task { await viewModel.handleTap(item) }
                            } label: {
                                Label("Open", systemImage: "arrow.up.right.square")
                            }
                            Divider()
                            Button(role: .destructive) {
                                Task { await viewModel.delete(itemID: item.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .refreshable { await viewModel.load(force: true) }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 32) {
            Spacer()
            HStack(spacing: 14) {
                ForEach(EmptyStateTile.all) { tile in
                    VStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(tile.gradient)
                                .aspectRatio(1, contentMode: .fit)
                                .glassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            Image(systemName: tile.symbol)
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        Text(tile.label)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 32)
            VStack(spacing: 6) {
                Text("Nothing Here Yet")
                    .font(.title3.weight(.semibold))
                Text(viewModel.emptyDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Spacer()
        }
    }
}

// MARK: - Cube Tile

private struct FeedCubeTile: View {
    let item: FeedItemViewData

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                // Background layer
                tileBackground
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                // Glass overlay with content
                VStack(alignment: .leading, spacing: 0) {
                    Spacer()
                    tileFooter
                        .padding(12)
                }
                .frame(width: geo.size.width, height: geo.size.width)

                // Sync badge
                FeedSyncBadgeView(badge: item.syncBadge)
                    .padding(10)
                    .frame(width: geo.size.width, height: geo.size.width, alignment: .topTrailing)
            }
            .frame(width: geo.size.width, height: geo.size.width)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private var tileBackground: some View {
        switch item.thumbnailState {
        case .none:
            ZStack {
                item.kind.tileGradient
                    .opacity(0.85)
                Image(systemName: item.kind.tileSymbol)
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.25))
            }

        case let .symbol(name):
            ZStack {
                item.kind.tileGradient
                    .opacity(0.85)
                Image(systemName: name)
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }

        case let .monogram(text):
            ZStack {
                item.kind.tileGradient
                    .opacity(0.85)
                Text(text)
                    .font(.system(size: 72, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
            }

        case let .localImage(url):
            if let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    item.kind.tileGradient
                    Image(systemName: "photo")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
        }
    }

    private var tileFooter: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(.white)
            Text(item.subtitle)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .glassEffect(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Button style with press animation

private struct CubeTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Kind visual tokens

private extension FolderItemKind {
    var tileGradient: LinearGradient {
        switch self {
        case .photo:
            return LinearGradient(
                colors: [Color(red: 1.0, green: 0.42, blue: 0.42), Color(red: 1.0, green: 0.65, blue: 0.3)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .thought:
            return LinearGradient(
                colors: [Color(red: 0.3, green: 0.72, blue: 0.58), Color(red: 0.18, green: 0.55, blue: 0.88)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .link:
            return LinearGradient(
                colors: [Color(red: 0.45, green: 0.35, blue: 0.95), Color(red: 0.72, green: 0.35, blue: 0.95)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .file:
            return LinearGradient(
                colors: [Color(red: 0.18, green: 0.52, blue: 0.98), Color(red: 0.28, green: 0.72, blue: 0.98)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    var tileSymbol: String {
        switch self {
        case .photo:   return "photo.on.rectangle"
        case .thought: return "lightbulb.fill"
        case .link:    return "link"
        case .file:    return "doc.fill"
        }
    }
}

// MARK: - Sync badge

private struct FeedSyncBadgeView: View {
    let badge: FeedSyncBadge

    var body: some View {
        Label(title, systemImage: symbolName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .foregroundStyle(foregroundColor)
            .glassEffect(in: Capsule())
    }

    private var symbolName: String {
        switch badge {
        case .localOnly:     "internaldrive"
        case .syncing:       "arrow.triangle.2.circlepath"
        case .synced:        "checkmark.icloud"
        case .conflicted:    "exclamationmark.triangle"
        case .pendingDelete: "trash.circle"
        case .cloudOnly:     "icloud"
        case .downloading:   "icloud.and.arrow.down"
        }
    }

    private var title: String {
        switch badge {
        case .localOnly:     "Local"
        case .syncing:       "Syncing"
        case .synced:        "Synced"
        case .conflicted:    "Check"
        case .pendingDelete: "Deleting"
        case .cloudOnly:     "Cloud"
        case .downloading:   "Downloading"
        }
    }

    private var foregroundColor: Color {
        switch badge {
        case .synced:               .green
        case .conflicted,
             .pendingDelete:        .orange
        default:                    .white
        }
    }
}

// MARK: - Empty state tiles

private struct EmptyStateTile: Identifiable {
    let id = UUID()
    let symbol: String
    let label: String
    let gradient: LinearGradient

    static let all: [EmptyStateTile] = [
        .init(symbol: "photo.on.rectangle", label: "Photos",
              gradient: LinearGradient(colors: [Color(red: 1.0, green: 0.42, blue: 0.42), Color(red: 1.0, green: 0.65, blue: 0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)),
        .init(symbol: "lightbulb.fill", label: "Ideas",
              gradient: LinearGradient(colors: [Color(red: 0.3, green: 0.72, blue: 0.58), Color(red: 0.18, green: 0.55, blue: 0.88)], startPoint: .topLeading, endPoint: .bottomTrailing)),
        .init(symbol: "link", label: "Links",
              gradient: LinearGradient(colors: [Color(red: 0.45, green: 0.35, blue: 0.95), Color(red: 0.72, green: 0.35, blue: 0.95)], startPoint: .topLeading, endPoint: .bottomTrailing)),
        .init(symbol: "doc.fill", label: "Files",
              gradient: LinearGradient(colors: [Color(red: 0.18, green: 0.52, blue: 0.98), Color(red: 0.28, green: 0.72, blue: 0.98)], startPoint: .topLeading, endPoint: .bottomTrailing)),
    ]
}

// MARK: - Thought preview sheet

private struct FolderThoughtPreviewSheet: View {
    let preview: FeedViewModel.ThoughtPreview
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(preview.body.isEmpty ? preview.title : preview.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .navigationTitle(preview.title.isEmpty ? "Idea" : preview.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.fraction(1.0 / 3.0), .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Status bar

private struct FeedStatusBar: View {
    let status: FeedViewModel.FeedStatus

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: statusSymbol)
                .font(.footnote.weight(.semibold))
            Text(status.message)
                .font(.footnote.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(backgroundColor, in: Capsule())
        .glassEffect(in: Capsule())
    }

    private var statusSymbol: String {
        switch status.kind {
        case .info:    "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .failure: "xmark.circle.fill"
        }
    }

    private var backgroundColor: Color {
        switch status.kind {
        case .info:    .blue.opacity(0.75)
        case .success: .green.opacity(0.75)
        case .failure: .red.opacity(0.75)
        }
    }
}

#Preview {
    FolderFeedView(
        readyState: .init(
            syncSnapshot: .init(
                localOnlyCount: 0,
                syncingCount: 0,
                syncedCount: 0,
                conflictedCount: 0,
                pendingDeleteCount: 0
            ),
            libraryLocationDescription: "On-Device Library",
            runtime: try! .localDevelopmentFallback(),
            launchMessage: nil
        )
    )
}
