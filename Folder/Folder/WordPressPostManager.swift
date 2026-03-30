import Foundation

struct WordPressPostManager {
    let token: String
    let site: WordPressSite
    var useBackgroundSession: Bool = true

    // MARK: - Fetch

    func fetchPosts(number: Int = 20, offset: Int = 0) async throws -> [WordPressPost] {
        var components = URLComponents(string: "https://public-api.wordpress.com/rest/v1.1/sites/\(site.id)/posts")!
        components.queryItems = [
            URLQueryItem(name: "number", value: "\(number)"),
            URLQueryItem(name: "offset", value: "\(offset)")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let detail = String(data: data, encoding: .utf8) ?? "no body"
            throw PostError.fetchFailed("\(status): \(detail)")
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

    func postLink(url: String, title: String, description: String = "") async throws {
        let resolvedTitle = title.isEmpty ? (URL(string: url)?.host ?? url) : title
        var content = "<a href=\"\(url)\">\(resolvedTitle)</a>"
        if !description.isEmpty { content += "\n\n<p>\(description)</p>" }
        try await createPost(title: resolvedTitle, content: content, format: "link")
    }

    func postPhoto(data: Data, filename: String = "photo.jpg", caption: String) async throws {
        let mimeType = filename.lowercased().hasSuffix(".png") ? "image/png" : "image/jpeg"
        let (mediaID, _) = try await uploadMedia(data: data, mimeType: mimeType, filename: filename)
        let title = (filename as NSString).deletingPathExtension
        let content = caption.isEmpty ? "" : "<p>\(caption)</p>"
        try await createPost(title: title.isEmpty ? Self.timestampTitle("Photo") : title, content: content, featuredMediaID: mediaID, format: "image")
    }

    func deletePost(id: Int) async throws {
        let url = URL(string: "https://public-api.wordpress.com/rest/v1.1/sites/\(site.id)/posts/\(id)/delete")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let detail = String(data: data, encoding: .utf8) ?? "unknown"
            throw PostError.postFailed(detail)
        }
    }

    func updateMessage(id: Int, text: String) async throws {
        let title = text.isEmpty
            ? Self.timestampTitle("Note")
            : String(text.prefix(60)).trimmingCharacters(in: .whitespacesAndNewlines)
        try await updatePost(id: id, params: ["title": title, "content": text, "format": "aside"])
    }

    func updateLink(id: Int, url: String, title: String, description: String = "") async throws {
        let resolvedTitle = title.isEmpty ? (URL(string: url)?.host ?? url) : title
        var content = "<a href=\"\(url)\">\(resolvedTitle)</a>"
        if !description.isEmpty { content += "\n\n<p>\(description)</p>" }
        try await updatePost(id: id, params: ["title": resolvedTitle, "content": content, "format": "link"])
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

    private func updatePost(id: Int, params: [String: Any]) async throws {
        let url = URL(string: "https://public-api.wordpress.com/rest/v1.1/sites/\(site.id)/posts/\(id)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body = params
        body["status"] = "publish"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let detail = String(data: data, encoding: .utf8) ?? "unknown"
            throw PostError.postFailed(detail)
        }
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

        let (responseData, response): (Data, HTTPURLResponse)
        if useBackgroundSession {
            (responseData, response) = try await MediaUploadSession.shared.upload(body: body, request: request)
        } else {
            request.httpBody = body
            let (data, urlResponse) = try await URLSession.shared.data(for: request)
            guard let httpResponse = urlResponse as? HTTPURLResponse else { throw PostError.uploadFailed("Invalid response") }
            (responseData, response) = (data, httpResponse)
        }
        guard response.statusCode == 200 else {
            let detail = String(data: responseData, encoding: .utf8) ?? "unknown"
            throw PostError.uploadFailed(detail)
        }

        let mediaResponse = try Self.decoder.decode(MediaUploadResponse.self, from: responseData)
        guard let item = mediaResponse.media.first else { throw PostError.uploadFailed("No media returned") }

        // For VideoPress uploads, poll for the GUID with exponential backoff.
        // VideoPress transcoding can take 30s+, so retry up to 4 times.
        var resolvedItem = item
        if mimeType.hasPrefix("video/") && item.videoPressGuid == nil {
            let delays: [UInt64] = [3_000_000_000, 6_000_000_000, 12_000_000_000, 24_000_000_000]
            for delay in delays {
                try? await Task.sleep(nanoseconds: delay)
                if let fetched = await fetchMediaItem(mediaID: item.id), fetched.videoPressGuid != nil {
                    resolvedItem = fetched
                    break
                }
            }
        }

        let resolvedURL: String?
        if let guid = resolvedItem.videoPressGuid {
            // Fetch the actual CDN URL from VideoPress API — VideoPress generates its own
            // filename that differs from the uploaded filename, so never construct the URL manually.
            resolvedURL = await fetchVideoPressPlaybackURL(guid: guid)?.absoluteString ?? resolvedItem.url
        } else {
            resolvedURL = resolvedItem.url
        }
        return (item.id, resolvedURL)
    }

    /// Fetches the current state of a media item (used to poll for VideoPress GUID).
    private func fetchMediaItem(mediaID: Int) async -> MediaUploadResponse.MediaItem? {
        let url = URL(string: "https://public-api.wordpress.com/rest/v1.1/sites/\(site.id)/media/\(mediaID)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? Self.decoder.decode(MediaUploadResponse.MediaItem.self, from: data)
    }

    /// Returns the playback URL for a VideoPress video.
    /// Tries the VideoPress API first, then scans the site's video media library by GUID.
    func fetchVideoPressPlaybackURL(guid: String) async -> URL? {
        // 1. VideoPress API
        let vpURL = URL(string: "https://public-api.wordpress.com/rest/v1.1/videos/\(guid)")!
        var vpRequest = URLRequest(url: vpURL)
        vpRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let (data, response) = try? await URLSession.shared.data(for: vpRequest),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let info = try? Self.decoder.decode(VideoPressInfo.self, from: data),
           let url = info.bestURL {
            print("[VideoPress] API resolved \(guid) → \(url)")
            return url
        }
        print("[VideoPress] API failed for \(guid), scanning media library…")

        // 2. Fallback: fetch all video media and match by videopress_guid.
        //    The GUID is NOT in the filename, so text search won't work — we need mime_type scan.
        var components = URLComponents(string: "https://public-api.wordpress.com/rest/v1.1/sites/\(site.id)/media")!
        components.queryItems = [
            URLQueryItem(name: "mime_type", value: "video"),
            URLQueryItem(name: "number", value: "100"),
            URLQueryItem(name: "fields", value: "ID,URL,videopress_guid")
        ]
        var mediaRequest = URLRequest(url: components.url!)
        mediaRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: mediaRequest),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            print("[VideoPress] Media library fetch failed for \(guid)")
            return nil
        }
        guard let list = try? Self.decoder.decode(MediaListResponse.self, from: data) else {
            print("[VideoPress] Media library decode failed for \(guid)")
            return nil
        }
        guard let item = list.media.first(where: { $0.videoPressGuid == guid }),
              let urlString = item.url,
              let url = URL(string: urlString) else {
            print("[VideoPress] GUID \(guid) not found in \(list.media.count) media items")
            return nil
        }
        print("[VideoPress] Media library resolved \(guid) → \(url)")
        return url
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
        case postFailed(String), uploadFailed(String), fetchFailed(String)
        var errorDescription: String? {
            switch self {
            case .postFailed(let d):  "Failed to create post: \(d)"
            case .uploadFailed(let d): "Upload rejected: \(d)"
            case .fetchFailed(let d): "Failed to load posts. \(d)"
            }
        }
    }
}

// MARK: - Post model

struct WordPressPost: Identifiable, Decodable, Equatable {
    let id: Int
    let title: String
    let date: Date
    let url: String
    let featuredImageURL: String?
    let format: String?
    let rawContent: String?
    private let tags: [String: TagStub]?
    
    static func == (lhs: WordPressPost, rhs: WordPressPost) -> Bool {
        lhs.id == rhs.id
    }

    var fileURL: URL? {
        guard let raw = rawContent else { return nil }

        // 1. Plain URL stored directly in content (our default for non-video files)
        let stripped = raw
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: stripped), url.scheme != nil {
            return url
        }

        // 2. WordPress converts video URLs into VideoPress blocks — find any src="https://..." in the HTML
        if let regex = try? NSRegularExpression(pattern: #"\bsrc="(https?://[^"]+)""#, options: .caseInsensitive),
           let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
           let range = Range(match.range(at: 1), in: raw) {
            return URL(string: String(raw[range]))
        }

        // 3. VideoPress shortcode [videopress guid="abc123"] — URL resolved asynchronously by the player
        if let regex = try? NSRegularExpression(pattern: #"\[videopress[^\]]*guid="([^"]+)""#, options: .caseInsensitive),
           let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
           let range = Range(match.range(at: 1), in: raw) {
            return URL(string: "videopress://\(String(raw[range]))")
        }

        // 4. VideoPress iframe embed: src='https://videopress.com/embed/{guid}...'
        if let regex = try? NSRegularExpression(pattern: #"videopress\.com/embed/([A-Za-z0-9]+)"#),
           let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
           let range = Range(match.range(at: 1), in: raw) {
            return URL(string: "videopress://\(String(raw[range]))")
        }

        // 5. Gutenberg VideoPress block: <!-- wp:videopress/video {"guid":"abc","src":"https:\/\/..."} /-->
        //    Try src first (the correct CDN URL), fall back to guid for API resolution.
        if let srcRegex = try? NSRegularExpression(pattern: #""src"\s*:\s*"(https?(?:\\\/|\/)[^"]+)""#, options: []),
           let match = srcRegex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
           let range = Range(match.range(at: 1), in: raw) {
            let urlString = String(raw[range]).replacingOccurrences(of: "\\/", with: "/")
            if let url = URL(string: urlString) { return url }
        }
        if let guidRegex = try? NSRegularExpression(pattern: #"wp:videopress/video\s+\{[^}]*"guid"\s*:\s*"([^"]+)""#, options: []),
           let match = guidRegex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
           let range = Range(match.range(at: 1), in: raw) {
            return URL(string: "videopress://\(String(raw[range]))")
        }

        return nil
    }

    var linkURL: URL? {
        guard format == "link", let raw = rawContent else { return nil }
        guard let regex = try? NSRegularExpression(pattern: #"href="([^"]+)""#),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let range = Range(match.range(at: 1), in: raw) else { return nil }
        return URL(string: String(raw[range]))
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

private struct VideoPressInfo: Decodable {
    let original: String?
    let mp4: MP4Formats?
    struct MP4Formats: Decodable {
        let original: String?  // VideoPress-generated filename — the primary URL
        let hd: String?
        let std: String?
    }
    var bestURL: URL? {
        [mp4?.original, mp4?.hd, mp4?.std, original]
            .lazy.compactMap { $0 }.compactMap { URL(string: $0) }.first
    }
}

private struct MediaListResponse: Decodable {
    let media: [MediaUploadResponse.MediaItem]
}

private struct MediaUploadResponse: Decodable {
    let media: [MediaItem]
    struct MediaItem: Decodable {
        let id: Int
        let url: String?
        let videoPressGuid: String?
        enum CodingKeys: String, CodingKey {
            case id = "ID"
            case url = "URL"
            case videoPressGuid = "videopress_guid"
        }
    }
}
