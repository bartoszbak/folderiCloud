import Foundation

struct WordPressPostManager {
    let token: String
    let site: WordPressSite

    // MARK: - Fetch

    func fetchPosts(number: Int = 20) async throws -> [WordPressPost] {
        var components = URLComponents(string: "https://public-api.wordpress.com/rest/v1.1/sites/\(site.id)/posts")!
        components.queryItems = [URLQueryItem(name: "number", value: "\(number)")]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw PostError.fetchFailed
        }

        return try Self.decoder.decode(PostsListResponse.self, from: data).posts
    }

    // MARK: - Post

    func postMessage(_ text: String) async throws {
        let title = text.isEmpty
            ? Self.timestampTitle("Note")
            : String(text.prefix(60)).trimmingCharacters(in: .whitespacesAndNewlines)
        try await createPost(title: title, content: text, format: "aside")
    }

    func postLink(url: String, title: String) async throws {
        let resolvedTitle = title.isEmpty ? (URL(string: url)?.host ?? url) : title
        let content = "<a href=\"\(url)\">\(resolvedTitle)</a>"
        try await createPost(title: resolvedTitle, content: content, format: "link")
    }

    func postPhoto(data: Data, caption: String) async throws {
        let (mediaID, _) = try await uploadMedia(data: data, mimeType: "image/jpeg", filename: "photo.jpg")
        let content = caption.isEmpty ? "" : "<p>\(caption)</p>"
        try await createPost(title: Self.timestampTitle("Photo"), content: content, featuredMediaID: mediaID, format: "image")
    }

    func postFile(data: Data, filename: String, mimeType: String) async throws {
        let (_, mediaURL) = try await uploadMedia(data: data, mimeType: mimeType, filename: filename)
        let content = mediaURL ?? ""
        try await createPost(title: filename, content: content, format: "standard", tags: ["folder-file"])
    }

    // MARK: - Private helpers

    private static func timestampTitle(_ prefix: String) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return "\(prefix) – \(f.string(from: Date()))"
    }

    private func createPost(title: String, content: String, featuredMediaID: Int? = nil, format: String? = nil, tags: [String] = []) async throws {
        let url = URL(string: "https://public-api.wordpress.com/rest/v1.1/sites/\(site.id)/posts/new")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = ["title": title, "content": content, "status": "publish"]
        if let mediaID = featuredMediaID { body["featured_image"] = mediaID }
        if let format { body["format"] = format }
        if !tags.isEmpty { body["tags"] = tags }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let detail = String(data: data, encoding: .utf8) ?? "unknown"
            throw PostError.postFailed(detail)
        }
    }

    private func uploadMedia(data: Data, mimeType: String, filename: String) async throws -> (Int, String?) {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        let header = "--\(boundary)\r\nContent-Disposition: form-data; name=\"media[]\"; filename=\"\(filename)\"\r\nContent-Type: \(mimeType)\r\n\r\n"
        body.append(Data(header.utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        let url = URL(string: "https://public-api.wordpress.com/rest/v1.1/sites/\(site.id)/media/new")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Upload via background URLSession so the transfer continues if the user switches apps.
        let (responseData, response) = try await MediaUploadSession.shared.upload(body: body, request: request)
        guard response.statusCode == 200 else {
            let detail = String(data: responseData, encoding: .utf8) ?? "unknown"
            throw PostError.uploadFailed(detail)
        }

        let mediaResponse = try Self.decoder.decode(MediaUploadResponse.self, from: responseData)
        guard let item = mediaResponse.media.first else { throw PostError.uploadFailed("No media returned") }
        return (item.id, item.url)
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { dec in
            let str = try dec.singleValueContainer().decode(String.self)
            return iso.date(from: str) ?? Date()
        }
        return d
    }()

    // MARK: - Errors

    enum PostError: LocalizedError {
        case postFailed(String), uploadFailed(String), fetchFailed
        var errorDescription: String? {
            switch self {
            case .postFailed(let d):  "Failed to create post: \(d)"
            case .uploadFailed(let d): "Upload rejected: \(d)"
            case .fetchFailed:         "Failed to load posts."
            }
        }
    }
}

// MARK: - Post model

struct WordPressPost: Identifiable, Decodable {
    let id: Int
    let title: String
    let date: Date
    let url: String
    let featuredImageURL: String?
    let format: String?
    let rawContent: String?
    private let tags: [String: TagStub]?

    var fileURL: URL? {
        guard let raw = rawContent else { return nil }
        let stripped = raw
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: stripped)
    }

    private struct TagStub: Decodable {}

    var tagSlugs: [String] { Array(tags?.keys ?? [:].keys) }

    var displayTitle: String {
        let stripped = title
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? "Untitled" : stripped
    }

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case title, date, format
        case url = "URL"
        case featuredImageURL = "featured_image"
        case rawContent = "content"
        case tags
    }
}

// MARK: - Private response models

private struct PostsListResponse: Decodable {
    let posts: [WordPressPost]
}

private struct MediaUploadResponse: Decodable {
    let media: [MediaItem]
    struct MediaItem: Decodable {
        let id: Int
        let url: String?
        enum CodingKeys: String, CodingKey {
            case id = "ID"
            case url = "URL"
        }
    }
}
