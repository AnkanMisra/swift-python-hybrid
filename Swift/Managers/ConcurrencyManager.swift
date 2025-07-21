import Foundation


actor TaskManager {
    private var runningTasks: [String: Task<Void, Never>] = [:]
    
    
    func cancelTask(_ id: String) {
        runningTasks[id]?.cancel()
        runningTasks.removeValue(forKey: id)
    }
    
    func cancelAllTasks() {
        runningTasks.values.forEach { $0.cancel() }
        runningTasks.removeAll()
    }
    
    func getTaskCount() -> Int {
        return runningTasks.count
    }
}


actor FileManager {
    private let baseURL: URL
    
    init(baseURL: URL = FileManager.default.temporaryDirectory) {
        self.baseURL = baseURL
    }
    
    func writeFile(name: String, content: Data) async throws {
        let fileURL = baseURL.appendingPathComponent(name)
        try content.write(to: fileURL)
    }
    
    func readFile(name: String) async throws -> Data {
        let fileURL = baseURL.appendingPathComponent(name)
        return try Data(contentsOf: fileURL)
    }
    
    func deleteFile(name: String) async throws {
        let fileURL = baseURL.appendingPathComponent(name)
        try Foundation.FileManager.default.removeItem(at: fileURL)
    }
    
    func listFiles() async throws -> [String] {
        let contents = try Foundation.FileManager.default.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil)
        return contents.map { $0.lastPathComponent }
    }
}


class DataProcessor {
    
    struct ProcessResult {
        let processedItems: Int
        let totalTime: TimeInterval
        let errors: [Error]
    }
    
    func processDataConcurrently<T>(_ items: [T], batchSize: Int = 10, processor: @escaping (T) async throws -> Void) async -> ProcessResult {
        let startTime = Date()
        var errors: [Error] = []
        var processedCount = 0
        
        
        for batch in items.chunked(into: batchSize) {
            await withTaskGroup(of: Void.self) { group in
                for item in batch {
                    group.addTask {
                        do {
                            try await processor(item)
                            await MainActor.run {
                                processedCount += 1
                            }
                        } catch {
                            await MainActor.run {
                                errors.append(error)
                            }
                        }
                    }
                }
                
                
                await group.waitForAll()
            }
        }
        
        let totalTime = Date().timeIntervalSince(startTime)
        return ProcessResult(processedItems: processedCount, totalTime: totalTime, errors: errors)
    }
    
    func downloadFiles(urls: [URL]) async -> [URL: Result<Data, Error>] {
        var results: [URL: Result<Data, Error>] = [:]
        
        await withTaskGroup(of: (URL, Result<Data, Error>).self) { group in
            for url in urls {
                group.addTask {
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        return (url, .success(data))
                    } catch {
                        return (url, .failure(error))
                    }
                }
            }
            
            for await (url, result) in group {
                results[url] = result
            }
        }
        
        return results
    }
}


actor CacheManager<Key: Hashable, Value> {
    private var cache: [Key: Value] = [:]
    private var accessTimes: [Key: Date] = [:]
    private let maxSize: Int
    private let ttl: TimeInterval
    
    init(maxSize: Int = 100, ttl: TimeInterval = 300) {
        self.maxSize = maxSize
        self.ttl = ttl
    }
    
    func set(_ key: Key, value: Value) {
        cleanupExpiredItems()
        
        if cache.count >= maxSize && cache[key] == nil {
            removeOldestItem()
        }
        
        cache[key] = value
        accessTimes[key] = Date()
    }
    
    func get(_ key: Key) -> Value? {
        cleanupExpiredItems()
        
        guard let value = cache[key] else { return nil }
        accessTimes[key] = Date()
        return value
    }
    
    func remove(_ key: Key) {
        cache.removeValue(forKey: key)
        accessTimes.removeValue(forKey: key)
    }
    
    func clear() {
        cache.removeAll()
        accessTimes.removeAll()
    }
    
    private func cleanupExpiredItems() {
        let now = Date()
        let expiredKeys = accessTimes.compactMap { key, time in
            now.timeIntervalSince(time) > ttl ? key : nil
        }
        
        for key in expiredKeys {
            cache.removeValue(forKey: key)
            accessTimes.removeValue(forKey: key)
        }
    }
    
    private func removeOldestItem() {
        guard let oldestKey = accessTimes.min(by: { $0.value < $1.value })?.key else { return }
        cache.removeValue(forKey: oldestKey)
        accessTimes.removeValue(forKey: oldestKey)
    }
}


class APIClient {
    private let session: URLSession
    private let baseURL: URL
    
    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }
    
    func request<T: Codable>(
        endpoint: String,
        method: HTTPMethod = .GET,
        body: Data? = nil,
        headers: [String: String] = [:],
        responseType: T.Type
    ) async throws -> T {
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.httpBody = body
        
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw APIError.invalidResponse
        }
        
        do {
            return try JSONDecoder().decode(responseType, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }
    
    enum HTTPMethod: String {
        case GET, POST, PUT, DELETE, PATCH
    }
    
    enum APIError: Error {
        case invalidResponse
        case decodingError(Error)
    }
}


extension AsyncSequence {
    func collect() async rethrows -> [Element] {
        var result: [Element] = []
        for try await element in self {
            result.append(element)
        }
        return result
    }
    
    func first(where predicate: @escaping (Element) async throws -> Bool) async rethrows -> Element? {
        for try await element in self {
            if try await predicate(element) {
                return element
            }
        }
        return nil
    }
}


extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}


class ConcurrencyExamples {
    
    func demonstrateUsage() async {
        let taskManager = TaskManager()
        let fileManager = FileManager()
        let dataProcessor = DataProcessor()
        let cacheManager = CacheManager<String, Data>(maxSize: 50, ttl: 600)
        
        
        do {
            let data = "Hello, World!".data(using: .utf8)!
            try await fileManager.writeFile(name: "test.txt", content: data)
            let readData = try await fileManager.readFile(name: "test.txt")
            print("File content: \(String(data: readData, encoding: .utf8) ?? "")")
            
            let files = try await fileManager.listFiles()
            print("Files: \(files)")
        } catch {
            print("File operation error: \(error)")
        }
        
        
        let numbers = Array(1...100)
        let result = await dataProcessor.processDataConcurrently(numbers, batchSize: 10) { number in
            
            try await Task.sleep(nanoseconds: 10_000_000) 
            print("Processed: \(number)")
        }
        
        print("Processed \(result.processedItems) items in \(result.totalTime) seconds")
        
        
        await cacheManager.set("key1", value: "Hello".data(using: .utf8)!)
        let cachedValue = await cacheManager.get("key1")
        print("Cached value: \(String(data: cachedValue ?? Data(), encoding: .utf8) ?? "")")
        
        
        let task = Task {
            for i in 1...10 {
                print("Task running: \(i)")
                try await Task.sleep(nanoseconds: 1_000_000_000) 
            }
        }
        
        await taskManager.addTask("example-task", task: task)
        
        
        Task {
            try await Task.sleep(nanoseconds: 3_000_000_000)
            await taskManager.cancelTask("example-task")
            print("Task cancelled")
        }
    }
}
