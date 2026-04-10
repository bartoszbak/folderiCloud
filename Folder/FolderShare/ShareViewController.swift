import UIKit
import SwiftUI
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
    private let writer = ShareInboxWriter()
    private lazy var hostingController = UIHostingController(
        rootView: ShareImportProgressView(message: "Preparing your shared items.")
    )

    override func viewDidLoad() {
        super.viewDidLoad()
        installProgressView()

        Task {
            let items = await extractItems()

            if items.isEmpty {
                await MainActor.run {
                    self.cancelWithError("No supported share items were found.")
                }
                return
            }

            do {
                try writer.writeRequest(items)
                await MainActor.run {
                    self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
                }
            } catch {
                await MainActor.run {
                    self.cancelWithError(error.localizedDescription)
                }
            }
        }
    }

    private func installProgressView() {
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hostingController.didMove(toParent: self)
    }

    // MARK: - Cancel

    private func cancelWithError(_ message: String?) {
        if let message {
            let alert = UIAlertController(title: "FolderShare", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                self?.extensionContext?.cancelRequest(withError: NSError(
                    domain: "com.bartbak.fastapp.FolderShare",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: message]
                ))
            })
            present(alert, animated: true)
        } else {
            extensionContext?.cancelRequest(withError: NSError(
                domain: "com.bartbak.fastapp.FolderShare",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cancelled"]
            ))
        }
    }

    // MARK: - Extract Items

    func extractItems() async -> [SharedImportPayload] {
        guard let inputItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            return []
        }

        var results: [SharedImportPayload] = []

        for item in inputItems {
            guard let attachments = item.attachments else { continue }

            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if let data = await loadImageData(from: provider) {
                        let contentType = imageContentType(for: provider)
                        results.append(
                            .image(
                                data: data,
                                filename: suggestedFilename(for: provider, fallbackExtension: contentType.preferredFilenameExtension ?? "jpg"),
                                uti: contentType.identifier,
                                mimeType: contentType.preferredMIMEType ?? "image/jpeg"
                            )
                        )
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = await loadURL(from: provider) {
                        results.append(.url(url.absoluteString))
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = await loadText(from: provider) {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let url = URL(string: trimmed), url.scheme == "https" || url.scheme == "http" {
                            // Avoid duplicating a URL already captured via the url-type provider
                            let alreadyHave = results.contains { if case .url(let u) = $0 { return u == trimmed }; return false }
                            if !alreadyHave { results.append(.url(trimmed)) }
                        } else {
                            results.append(.text(text))
                        }
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
                    if let fileURL = await loadFile(from: provider) {
                        let contentType = UTType(filenameExtension: fileURL.pathExtension) ?? .data
                        results.append(
                            .file(
                                sourceURL: fileURL,
                                filename: fileURL.lastPathComponent,
                                uti: contentType.identifier,
                                mimeType: contentType.preferredMIMEType ?? "application/octet-stream"
                            )
                        )
                    }
                }
            }
        }

        return results
    }

    // MARK: - Private Loaders

    private func loadImageData(from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                continuation.resume(returning: item as? URL)
            }
        }
    }

    private func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                continuation.resume(returning: item as? String)
            }
        }
    }

    private func loadFile(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.data.identifier) { item, _ in
                continuation.resume(returning: item as? URL)
            }
        }
    }

    private func imageContentType(for provider: NSItemProvider) -> UTType {
        provider.registeredTypeIdentifiers
            .compactMap(UTType.init)
            .first(where: { $0.conforms(to: .image) }) ?? .jpeg
    }

    private func suggestedFilename(for provider: NSItemProvider, fallbackExtension: String) -> String {
        let baseName = provider.suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stem = (baseName?.isEmpty == false ? baseName : "shared-image") ?? "shared-image"
        let ext = (stem as NSString).pathExtension
        if ext.isEmpty {
            return "\(stem).\(fallbackExtension)"
        }
        return stem
    }
}
