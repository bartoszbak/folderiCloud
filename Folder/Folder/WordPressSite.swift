import Foundation

struct WordPressSite: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let url: String

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case name
        case url = "URL"
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
