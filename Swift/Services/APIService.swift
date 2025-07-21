import Foundation

class APIService {
    static let shared = APIService()
    
    private let networkManager = NetworkManager.shared
    
    private init() {}
    
    func fetchUsers() async throws -> [User] {
        return try await networkManager.fetchData(from: "/users", type: [User].self)
    }
    
    func fetchUser(by id: Int) async throws -> User {
        return try await networkManager.fetchData(from: "/users/\(id)", type: User.self)
    }
    
    func createUser(_ user: User) async throws -> User {
        
        
        return user
    }
    
    func updateUser(_ user: User) async throws -> User {
        
        
        return user
    }
    
    func deleteUser(by id: Int) async throws {
        
        
    }
}
