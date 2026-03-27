import SwiftUI
import UniformTypeIdentifiers

// MARK: - SharedItem

enum SharedItem {
    case image(Data)
    case url(String)
    case text(String)
    case file(URL)
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

    var body: some View {
        NavigationStack {
            Form {
                // Preview section
                if let firstItem = items.first {
                    Section("Preview") {
                        itemPreview(firstItem)
                    }
                }

                // Note section
                Section("Note (optional)") {
                    TextField("Add a note…", text: $note, axis: .vertical)
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
            Label(urlString, systemImage: "link")
                .lineLimit(2)
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
        let manager = WordPressPostManager(token: token, site: site)

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
