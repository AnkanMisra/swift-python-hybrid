import Foundation

class UserManager {
    private var users: [User] = []
    
    struct User {
        let id: UUID
        let name: String
        let email: String
        let createdAt: Date
        
        init(name: String, email: String) {
            self.id = UUID()
            self.name = name
            self.email = email
            self.createdAt = Date()
        }
    }
    
    func addUser(name: String, email: String) -> User {
        let newUser = User(name: name, email: email)
        users.append(newUser)
        print("User \(name) added successfully!")
        return newUser
    }
    
    func getUserById(_ id: UUID) -> User? {
        return users.first { $0.id == id }
    }
    
    func getAllUsers() -> [User] {
        return users
    }
    
    func removeUser(_ id: UUID) -> Bool {
        if let index = users.firstIndex(where: { $0.id == id }) {
            users.remove(at: index)
            return true
        }
        return false
    }
    
    func getUserCount() -> Int {
        return users.count
    }
}
