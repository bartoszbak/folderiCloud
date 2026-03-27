import Foundation
import LinkPresentation
import UIKit

/// Fetches page title, description, and favicon for a URL.
/// - Title and favicon come from LPMetadataProvider (same engine as iMessage previews).
/// - Description is extracted from og:description / meta description via a lightweight HTML fetch.
/// Debounces requests by 700 ms so it only fires after the user stops typing.
@Observable
final class LinkMetadataFetcher {
    var isFetching = false
    var fetchedTitle: String?
    var fetchedDescription: String?
    var favicon: UIImage?

    private var debounceTask: Task<Void, Never>?

    func schedule(urlString: String) {
        debounceTask?.cancel()
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              url.scheme == "https" || url.scheme == "http" else {
            clear()
            return
        }
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await fetch(url: url)
        }
    }

    func clear() {
        debounceTask?.cancel()
        isFetching = false
        fetchedTitle = nil
        fetchedDescription = nil
        favicon = nil
    }

    // MARK: - Private

    @MainActor
    private func fetch(url: URL) async {
        isFetching = true
        async let lpResult = fetchLPMetadata(url: url)
        async let descResult = fetchDescription(url: url)
        let (lp, desc) = await (lpResult, descResult)
        guard !Task.isCancelled else { isFetching = false; return }
        fetchedTitle = lp?.title
        fetchedDescription = desc
        isFetching = false
        if let iconProvider = lp?.iconProvider {
            iconProvider.loadObject(ofClass: UIImage.self) { [weak self] obj, _ in
                if let img = obj as? UIImage {
                    Task { @MainActor [weak self] in self?.favicon = img }
                }
            }
        }
    }

    private func fetchLPMetadata(url: URL) async -> LPLinkMetadata? {
        let provider = LPMetadataProvider()
        provider.shouldFetchSubresources = false
        return try? await provider.startFetchingMetadata(for: url)
    }

    private func fetchDescription(url: URL) async -> String? {
        var request = URLRequest(url: url, timeoutInterval: 10)
        // Identify as a mobile browser so sites return full HTML rather than app-store redirect pages
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else { return nil }
        // Prefer OG description, fall back to standard meta description
        return ["og:description", "description"]
            .lazy
            .compactMap { self.metaContent(in: html, attribute: $0) }
            .first
            .map(decodeHTMLEntities)
    }

    /// Extracts the content="…" value of a <meta> tag that has a matching property or name attribute.
    private func metaContent(in html: String, attribute: String) -> String? {
        let esc = NSRegularExpression.escapedPattern(for: attribute)
        let attrPattern = "(?:property|name)=[\"']\(esc)[\"']"
        // Two orderings: attribute before content, and content before attribute
        let patterns = [
            "<meta[^>]+\(attrPattern)[^>]+content=[\"']([^\"'\\r\\n]*)[\"'][^>]*>",
            "<meta[^>]+content=[\"']([^\"'\\r\\n]*)[\"'][^>]+\(attrPattern)[^>]*>"
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html) else { continue }
            let value = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }

    private func decodeHTMLEntities(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
    }
}
