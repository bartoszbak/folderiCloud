import UIKit
import SwiftUI
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    private let appGroupID = "group.com.bartbak.fastapp.folder"

    override func viewDidLoad() {
        super.viewDidLoad()

        guard
            let defaults = UserDefaults(suiteName: appGroupID),
            let token = defaults.string(forKey: "shared_token"),
            let siteData = defaults.data(forKey: "shared_site"),
            let site = try? JSONDecoder().decode(WordPressSite.self, from: siteData)
        else {
            cancelWithError("Not logged in. Please open the app and sign in first.")
            return
        }

        Task {
            let items = await extractItems()
            await MainActor.run {
                let hostingController = UIHostingController(
                    rootView: ShareComposeView(
                        token: token,
                        site: site,
                        items: items,
                        onComplete: { [weak self] in
                            self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
                        },
                        onCancel: { [weak self] in
                            self?.cancelWithError(nil)
                        }
                    )
                    .fontDesign(.rounded)
                )
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
        }
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

    func extractItems() async -> [SharedItem] {
        guard let inputItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            return []
        }

        var results: [SharedItem] = []

        for item in inputItems {
            guard let attachments = item.attachments else { continue }

            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if let data = await loadImageData(from: provider) {
                        results.append(.image(data))
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
                        results.append(.file(fileURL))
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
}
