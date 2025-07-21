import Foundation

struct User: Codable {
    let id: Int
    let name: String
    let email: String
    let avatar: String?
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case email
        case avatar
        case createdAt = "created_at"
    }
}

extension User {
    static func mock() -> User {
        return User(
            id: 1,
            name: "John Doe",
            email: "john@example.com",
            avatar: nil,
            createdAt: Date()
        )
    }
}
