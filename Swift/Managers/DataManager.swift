import Foundation
import Combine


class DataManager: ObservableObject {
    static let shared = DataManager()
    
    @Published var isLoading = false
    @Published var error: Error?
    
    private var cancellables = Set<AnyCancellable>()
    private let networkService = NetworkService()
    private let cacheManager = CacheManager()
    
    private init() {
        setupNotifications()
    }
    
    private func setupNotifications() {
        NotificationCenter.default.publisher(for: .NSApplicationWillTerminate)
            .sink { [weak self] _ in
                self?.saveData()
            }
            .store(in: &cancellables)
    }
    
    func fetchData<T: Codable>(from endpoint: String, type: T.Type) -> AnyPublisher<T, Error> {
        isLoading = true
        
        return networkService.request(endpoint: endpoint)
            .decode(type: type, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .handleEvents(
                receiveCompletion: { [weak self] _ in
                    self?.isLoading = false
                },
                receiveCancel: { [weak self] in
                    self?.isLoading = false
                }
            )
            .eraseToAnyPublisher()
    }
    
    func saveData() {
        
        cacheManager.saveToCache()
    }
}


class NetworkService {
    private let session = URLSession.shared
    private let baseURL = "https://api.example.com"
    
    func request(endpoint: String) -> AnyPublisher<Data, Error> {
        guard let url = URL(string: "\(baseURL)/\(endpoint)") else {
            return Fail(error: NetworkError.invalidURL)
                .eraseToAnyPublisher()
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        return session.dataTaskPublisher(for: request)
            .map(\.data)
            .mapError { error in
                NetworkError.networkFailed(error)
            }
            .eraseToAnyPublisher()
    }
    
    func post<T: Codable>(endpoint: String, data: T) -> AnyPublisher<Data, Error> {
        guard let url = URL(string: "\(baseURL)/\(endpoint)") else {
            return Fail(error: NetworkError.invalidURL)
                .eraseToAnyPublisher()
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONEncoder().encode(data)
        } catch {
            return Fail(error: NetworkError.encodingFailed)
                .eraseToAnyPublisher()
        }
        
        return session.dataTaskPublisher(for: request)
            .map(\.data)
            .mapError { error in
                NetworkError.networkFailed(error)
            }
            .eraseToAnyPublisher()
    }
}


class CacheManager {
    private let cache = NSCache<NSString, NSData>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    init() {
        let urls = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = urls[0].appendingPathComponent("AppCache")
        
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
        
        setupCacheConfiguration()
    }
    
    private func setupCacheConfiguration() {
        cache.countLimit = 100
        cache.totalCostLimit = 50 * 1024 * 1024 
    }
    
    func store(data: Data, forKey key: String) {
        cache.setObject(data as NSData, forKey: key as NSString)
        
        let fileURL = cacheDirectory.appendingPathComponent(key)
        try? data.write(to: fileURL)
    }
    
    func retrieve(forKey key: String) -> Data? {
        if let cachedData = cache.object(forKey: key as NSString) {
            return cachedData as Data
        }
        
        let fileURL = cacheDirectory.appendingPathComponent(key)
        return try? Data(contentsOf: fileURL)
    }
    
    func removeObject(forKey key: String) {
        cache.removeObject(forKey: key as NSString)
        
        let fileURL = cacheDirectory.appendingPathComponent(key)
        try? fileManager.removeItem(at: fileURL)
    }
    
    func clearCache() {
        cache.removeAllObjects()
        
        let contents = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
        contents?.forEach { url in
            try? fileManager.removeItem(at: url)
        }
    }
    
    func saveToCache() {
        
        print("Saving data to cache...")
    }
}


enum NetworkError: Error, LocalizedError {
    case invalidURL
    case networkFailed(Error)
    case encodingFailed
    case decodingFailed
    case noData
    case serverError(Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkFailed(let error):
            return "Network failed: \(error.localizedDescription)"
        case .encodingFailed:
            return "Encoding failed"
        case .decodingFailed:
            return "Decoding failed"
        case .noData:
            return "No data received"
        case .serverError(let code):
            return "Server error with code: \(code)"
        }
    }
}


struct User: Codable, Identifiable {
    let id: UUID
    let name: String
    let email: String
    let avatar: String?
    let createdAt: Date
    let updatedAt: Date
    
    init(id: UUID = UUID(), name: String, email: String, avatar: String? = nil) {
        self.id = id
        self.name = name
        self.email = email
        self.avatar = avatar
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

struct Post: Codable, Identifiable {
    let id: UUID
    let title: String
    let content: String
    let authorId: UUID
    let tags: [String]
    let createdAt: Date
    let updatedAt: Date
    let isPublished: Bool
    
    init(title: String, content: String, authorId: UUID, tags: [String] = []) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.authorId = authorId
        self.tags = tags
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isPublished = false
    }
}

struct Comment: Codable, Identifiable {
    let id: UUID
    let content: String
    let authorId: UUID
    let postId: UUID
    let createdAt: Date
    let updatedAt: Date
    
    init(content: String, authorId: UUID, postId: UUID) {
        self.id = UUID()
        self.content = content
        self.authorId = authorId
        self.postId = postId
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}


protocol Repository {
    associatedtype T
    
    func create(_ item: T) -> AnyPublisher<T, Error>
    func read(id: UUID) -> AnyPublisher<T?, Error>
    func update(_ item: T) -> AnyPublisher<T, Error>
    func delete(id: UUID) -> AnyPublisher<Bool, Error>
    func list() -> AnyPublisher<[T], Error>
}

class UserRepository: Repository {
    typealias T = User
    
    private let dataManager = DataManager.shared
    
    func create(_ item: User) -> AnyPublisher<User, Error> {
        dataManager.networkService.post(endpoint: "users", data: item)
            .decode(type: User.self, decoder: JSONDecoder())
            .eraseToAnyPublisher()
    }
    
    func read(id: UUID) -> AnyPublisher<User?, Error> {
        dataManager.fetchData(from: "users/\(id.uuidString)", type: User.self)
            .map { user in Optional(user) }
            .eraseToAnyPublisher()
    }
    
    func update(_ item: User) -> AnyPublisher<User, Error> {
        dataManager.networkService.post(endpoint: "users/\(item.id.uuidString)", data: item)
            .decode(type: User.self, decoder: JSONDecoder())
            .eraseToAnyPublisher()
    }
    
    func delete(id: UUID) -> AnyPublisher<Bool, Error> {
        dataManager.networkService.request(endpoint: "users/\(id.uuidString)/delete")
            .map { _ in true }
            .eraseToAnyPublisher()
    }
    
    func list() -> AnyPublisher<[User], Error> {
        dataManager.fetchData(from: "users", type: [User].self)
    }
}

class PostRepository: Repository {
    typealias T = Post
    
    private let dataManager = DataManager.shared
    
    func create(_ item: Post) -> AnyPublisher<Post, Error> {
        dataManager.networkService.post(endpoint: "posts", data: item)
            .decode(type: Post.self, decoder: JSONDecoder())
            .eraseToAnyPublisher()
    }
    
    func read(id: UUID) -> AnyPublisher<Post?, Error> {
        dataManager.fetchData(from: "posts/\(id.uuidString)", type: Post.self)
            .map { post in Optional(post) }
            .eraseToAnyPublisher()
    }
    
    func update(_ item: Post) -> AnyPublisher<Post, Error> {
        dataManager.networkService.post(endpoint: "posts/\(item.id.uuidString)", data: item)
            .decode(type: Post.self, decoder: JSONDecoder())
            .eraseToAnyPublisher()
    }
    
    func delete(id: UUID) -> AnyPublisher<Bool, Error> {
        dataManager.networkService.request(endpoint: "posts/\(id.uuidString)/delete")
            .map { _ in true }
            .eraseToAnyPublisher()
    }
    
    func list() -> AnyPublisher<[Post], Error> {
        dataManager.fetchData(from: "posts", type: [Post].self)
    }
    
    func listByAuthor(authorId: UUID) -> AnyPublisher<[Post], Error> {
        dataManager.fetchData(from: "posts?authorId=\(authorId.uuidString)", type: [Post].self)
    }
}


struct ValidationResult {
    let isValid: Bool
    let errors: [String]
    
    init(isValid: Bool, errors: [String] = []) {
        self.isValid = isValid
        self.errors = errors
    }
}

class Validator {
    static func validateEmail(_ email: String) -> ValidationResult {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        let isValid = emailPredicate.evaluate(with: email)
        
        return ValidationResult(
            isValid: isValid,
            errors: isValid ? [] : ["Invalid email format"]
        )
    }
    
    static func validateUser(_ user: User) -> ValidationResult {
        var errors: [String] = []
        
        if user.name.isEmpty {
            errors.append("Name cannot be empty")
        }
        
        if user.name.count < 2 {
            errors.append("Name must be at least 2 characters")
        }
        
        let emailValidation = validateEmail(user.email)
        if !emailValidation.isValid {
            errors.append(contentsOf: emailValidation.errors)
        }
        
        return ValidationResult(isValid: errors.isEmpty, errors: errors)
    }
    
    static func validatePost(_ post: Post) -> ValidationResult {
        var errors: [String] = []
        
        if post.title.isEmpty {
            errors.append("Title cannot be empty")
        }
        
        if post.title.count < 5 {
            errors.append("Title must be at least 5 characters")
        }
        
        if post.content.isEmpty {
            errors.append("Content cannot be empty")
        }
        
        if post.content.count < 10 {
            errors.append("Content must be at least 10 characters")
        }
        
        return ValidationResult(isValid: errors.isEmpty, errors: errors)
    }
}


extension Date {
    func timeAgo() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }
    
    func formatted(style: DateFormatter.Style) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = style
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }
}

extension String {
    func truncated(to length: Int) -> String {
        if self.count <= length {
            return self
        }
        return String(self.prefix(length)) + "..."
    }
    
    func slugified() -> String {
        return self.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9-]", with: "", options: .regularExpression)
    }
}

extension Array where Element == String {
    func joined() -> String {
        return self.joined(separator: ", ")
    }
}


class Logger {
    enum LogLevel: String, CaseIterable {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
    }
    
    static let shared = Logger()
    
    private init() {}
    
    func log(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        let filename = URL(fileURLWithPath: file).lastPathComponent
        let timestamp = DateFormatter.logFormatter.string(from: Date())
        print("[\(timestamp)] [\(level.rawValue)] [\(filename):\(line)] \(function) - \(message)")
    }
    
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, file: file, function: function, line: line)
    }
    
    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, file: file, function: function, line: line)
    }
    
    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, file: file, function: function, line: line)
    }
    
    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, file: file, function: function, line: line)
    }
}

extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
