import SwiftUI
import UIKit
import UniformTypeIdentifiers
import LinkPresentation

// MARK: - SharedItem

enum SharedItem {
    case image(Data)
    case url(String)
    case text(String)
    case file(URL)
}

// MARK: - Share Link Fetcher

@Observable
final class ShareLinkFetcher {
    var isFetching = false
    var fetchedTitle: String?
    var favicon: UIImage?

    func fetch(urlString: String) {
        guard let url = URL(string: urlString),
              url.scheme == "https" || url.scheme == "http" else { return }
        isFetching = true
        Task { @MainActor in
            let provider = LPMetadataProvider()
            provider.shouldFetchSubresources = false
            if let meta = try? await provider.startFetchingMetadata(for: url) {
                self.fetchedTitle = meta.title
                if let iconProvider = meta.iconProvider {
                    iconProvider.loadObject(ofClass: UIImage.self) { obj, _ in
                        if let img = obj as? UIImage {
                            Task { @MainActor in self.favicon = img }
                        }
                    }
                }
            }
            self.isFetching = false
        }
    }
}

// MARK: - ShareComposeView

struct ShareComposeView: View {
    let token: String
    let site: WordPressSite
    let items: [SharedItem]
    let onComplete: () -> Void
    let onCancel: () -> Void

    @State private var note: String = ""
    @State private var isPosting = false
    @State private var errorMessage: String? = nil
    @State private var linkFetcher = ShareLinkFetcher()

    private var isURL: Bool {
        if case .url = items.first { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                // Preview section
                if let firstItem = items.first {
                    Section("Preview") {
                        itemPreview(firstItem)
                    }
                }

                // Note / Title section
                Section(isURL ? "Title (optional)" : "Note (optional)") {
                    TextField(isURL ? "Add a title…" : "Add a note…", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }

                // Error section
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add to \(site.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .disabled(isPosting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isPosting {
                        ProgressView()
                    } else {
                        Button("Post") {
                            Task { await post() }
                        }
                        .bold()
                    }
                }
            }
            .interactiveDismissDisabled(isPosting)
        }
        .task {
            if case .url(let urlString) = items.first {
                linkFetcher.fetch(urlString: urlString)
            }
        }
        .onChange(of: linkFetcher.fetchedTitle) { _, title in
            if note.isEmpty, let title { note = title }
        }
    }

    // MARK: - Item Preview

    @ViewBuilder
    private func itemPreview(_ item: SharedItem) -> some View {
        switch item {
        case .image(let data):
            if let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Label("Image", systemImage: "photo")
            }
        case .url(let urlString):
            if linkFetcher.isFetching {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.75)
                    Text("Fetching link info…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    Group {
                        if let favicon = linkFetcher.favicon {
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
                        if let title = linkFetcher.fetchedTitle {
                            Text(title).font(.subheadline).lineLimit(2)
                        }
                        Text(urlString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 4)
            }
        case .text(let text):
            Text(text)
                .lineLimit(4)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .file(let url):
            Label(url.lastPathComponent, systemImage: "doc")
                .lineLimit(1)
        }
    }

    // MARK: - Posting

    private func post() async {
        isPosting = true
        errorMessage = nil
        let manager = WordPressPostManager(token: token, site: site, useBackgroundSession: false)

        do {
            for item in items {
                switch item {
                case .image(let data):
                    try await manager.postPhoto(data: data, caption: note)
                case .url(let urlString):
                    try await manager.postLink(url: urlString, title: note)
                case .text(let text):
                    let combined = note.isEmpty ? text : "\(text)\n\n\(note)"
                    try await manager.postMessage(combined)
                case .file(let url):
                    let data = try Data(contentsOf: url)
                    let mimeType = mimeType(for: url)
                    try await manager.postFile(data: data, filename: url.lastPathComponent, mimeType: mimeType)
                }
            }
            onComplete()
        } catch {
            errorMessage = error.localizedDescription
            isPosting = false
        }
    }

    // MARK: - Helpers

    private func mimeType(for url: URL) -> String {
        if let utType = UTType(filenameExtension: url.pathExtension),
           let mime = utType.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }
}
