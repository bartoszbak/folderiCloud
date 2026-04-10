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
                            Task {
                                await viewModel.load(force: true)
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
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
                            Button("All") { viewModel.activeFilter = nil }
                            Button("Photos") { viewModel.activeFilter = .photo }
                            Button("Thoughts") { viewModel.activeFilter = .thought }
                            Button("Links") { viewModel.activeFilter = .link }
                            Button("Files") { viewModel.activeFilter = .file }
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
                            Button("Photos") {
                                photoPickerPresented = true
                            }
                            Button("Thoughts") {
                                thoughtComposer.reset()
                                showThoughtComposer = true
                            }
                            Button("Links") {
                                linkComposer.reset()
                                showLinkComposer = true
                            }
                            Button("Files") {
                                showFileImporter = true
                            }
                        } label: {
                            Image(systemName: "plus")
                                .fontWeight(.semibold)
                        }
                    }
                }
        }
        .task {
            await viewModel.load()
        }
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
                if importedCount > 0 {
                    await viewModel.load(force: true)
                }
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
                SafariSheet(url: url)
                    .ignoresSafeArea()
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
            Button("OK", role: .cancel) {
                photoImportViewModel.clearError()
            }
        } message: {
            Text(photoImportViewModel.errorMessage ?? "")
        }
        .alert("File Import Failed", isPresented: Binding(
            get: { fileImportViewModel.errorMessage != nil },
            set: { if !$0 { fileImportViewModel.clearError() } }
        )) {
            Button("OK", role: .cancel) {
                fileImportViewModel.clearError()
            }
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
                Label("Couldn’t Load Library", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") {
                    Task {
                        await viewModel.load(force: true)
                    }
                }
            }
        } else if viewModel.filteredItems.isEmpty {
            ContentUnavailableView(
                "Nothing Here Yet",
                systemImage: "folder",
                description: Text(viewModel.emptyDescription)
            )
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                    spacing: 16
                ) {
                    ForEach(viewModel.filteredItems) { item in
                        Button {
                            Task {
                                await viewModel.handleTap(item)
                            }
                        } label: {
                            FeedGridCard(item: item)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Open") {
                                Task {
                                    await viewModel.handleTap(item)
                                }
                            }
                            Button("Delete", role: .destructive) {
                                Task {
                                    await viewModel.delete(itemID: item.id)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .refreshable {
                await viewModel.load(force: true)
            }
        }
    }
}

private struct FeedGridCard: View {
    let item: FeedItemViewData

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                FeedThumbnailView(state: item.thumbnailState)
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                FeedSyncBadgeView(badge: item.syncBadge)
                    .padding(10)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Text(item.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FeedThumbnailView: View {
    let state: FeedThumbnailState

    var body: some View {
        switch state {
        case .none:
            placeholder(symbol: "tray")
        case let .symbol(name):
            placeholder(symbol: name)
        case let .monogram(text):
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.22), Color.cyan.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text(text)
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.blue)
            }
        case let .localImage(url):
            if let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder(symbol: "photo")
            }
        }
    }

    private func placeholder(symbol: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    LinearGradient(
                        colors: [Color.secondary.opacity(0.12), Color.secondary.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct FeedSyncBadgeView: View {
    let badge: FeedSyncBadge

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbolName)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(backgroundColor, in: Capsule())
        .foregroundStyle(foregroundColor)
    }

    private var symbolName: String {
        switch badge {
        case .localOnly:
            "arrow.uturn.backward.circle"
        case .syncing:
            "arrow.triangle.2.circlepath"
        case .synced:
            "checkmark.circle"
        case .conflicted:
            "exclamationmark.triangle"
        case .pendingDelete:
            "trash.circle"
        case .cloudOnly:
            "icloud"
        case .downloading:
            "icloud.and.arrow.down"
        }
    }

    private var title: String {
        switch badge {
        case .localOnly:
            "Local"
        case .syncing:
            "Syncing"
        case .synced:
            "Synced"
        case .conflicted:
            "Check"
        case .pendingDelete:
            "Deleting"
        case .cloudOnly:
            "Cloud"
        case .downloading:
            "Downloading"
        }
    }

    private var backgroundColor: Color {
        switch badge {
        case .localOnly, .syncing, .cloudOnly, .downloading:
            .blue.opacity(0.12)
        case .synced:
            .green.opacity(0.12)
        case .conflicted, .pendingDelete:
            .orange.opacity(0.14)
        }
    }

    private var foregroundColor: Color {
        switch badge {
        case .synced:
            .green
        case .conflicted, .pendingDelete:
            .orange
        default:
            .blue
        }
    }
}

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
            .navigationTitle(preview.title.isEmpty ? "Thought" : preview.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.fraction(1.0 / 3.0), .large])
        .presentationDragIndicator(.visible)
    }
}

private struct FeedStatusBar: View {
    let status: FeedViewModel.FeedStatus

    var body: some View {
        Text(status.message)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(backgroundColor, in: Capsule())
    }

    private var backgroundColor: Color {
        switch status.kind {
        case .info:
            .blue
        case .success:
            .green
        case .failure:
            .red
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
