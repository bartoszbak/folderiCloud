import Foundation

struct LinkInfo: Codable, Hashable, Sendable {
    let itemID: UUID
    var sourceURL: URL
    var displayHost: String
    var pageTitle: String?
    var summary: String?
    var faviconPath: String?

    nonisolated init(
        itemID: UUID,
        sourceURL: URL,
        displayHost: String? = nil,
        pageTitle: String? = nil,
        summary: String? = nil,
        faviconPath: String? = nil
    ) {
        self.itemID = itemID
        self.sourceURL = sourceURL
        self.displayHost = displayHost ?? sourceURL.host() ?? sourceURL.absoluteString
        self.pageTitle = pageTitle
        self.summary = summary
        self.faviconPath = faviconPath
    }
}
