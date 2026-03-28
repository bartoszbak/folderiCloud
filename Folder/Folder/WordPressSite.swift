import Foundation

struct WordPressSite: Identifiable, Hashable {
    let id: Int
    let name: String
    let url: String
    let iconURL: String?
}

extension WordPressSite: Codable {
    private struct Icon: Codable {
        let img: String?
    }

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case name
        case url = "URL"
        case icon
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        url = try c.decode(String.self, forKey: .url)
        iconURL = try c.decodeIfPresent(Icon.self, forKey: .icon)?.img
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(url, forKey: .url)
    }
}

struct SitesResponse: Decodable {
    let sites: [WordPressSite]
}

// MARK: - User

struct WordPressUser: Codable {
    let displayName: String
    let username: String
    let email: String
    let avatarURL: String

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case username
        case email
        case avatarURL = "avatar_URL"
    }
}
