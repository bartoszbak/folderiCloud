import Foundation
import SwiftData

@Model
final class LinkInfoEntity {
    var itemID: UUID = UUID()
    var sourceURL: URL = URL(string: "about:blank")!
    var displayHost: String = ""
    var pageTitle: String?
    var summary: String?
    var faviconPath: String?

    init(
        itemID: UUID,
        sourceURL: URL,
        displayHost: String,
        pageTitle: String?,
        summary: String?,
        faviconPath: String?
    ) {
        self.itemID = itemID
        self.sourceURL = sourceURL
        self.displayHost = displayHost
        self.pageTitle = pageTitle
        self.summary = summary
        self.faviconPath = faviconPath
    }
}
