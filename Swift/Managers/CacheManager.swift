import Foundation
import UIKit
import Combine


class CacheManager: ObservableObject {
    
    
    static let shared = CacheManager()
    
    @Published var memoryUsage: Int64 = 0
    @Published var diskUsage: Int64 = 0
    @Published var cacheHitRate: Double = 0.0
    @Published var isMemoryWarning = false
    
    private let memoryCache = NSCache<NSString, AnyObject>()
    private let diskCacheQueue = DispatchQueue(label: "com.app.cache.disk", qos: .utility)
    private let cleanupQueue = DispatchQueue(label: "com.app.cache.cleanup", qos: .background)
    
    private var cacheDirectory: URL
    private var imagesCacheDirectory: URL
    private var dataCacheDirectory: URL
    private var tempCacheDirectory: URL
    
    private var cancellables = Set<AnyCancellable>()
    private var cleanupTimer: Timer?
    
    
    private var cacheHits: Int = 0
    private var cacheMisses: Int = 0
    private var totalRequests: Int = 0
    
    
    private let maxMemoryCacheSize: Int = 100 * 1024 * 1024 
    private let maxDiskCacheSize: Int64 = 500 * 1024 * 1024 
    private let defaultExpirationTime: TimeInterval = 86400 * 7 
    private let cleanupInterval: TimeInterval = 3600 
    
    
    private init() {
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        cacheDirectory = documentsPath.appendingPathComponent("Cache")
        imagesCacheDirectory = cacheDirectory.appendingPathComponent("Images")
        dataCacheDirectory = cacheDirectory.appendingPathComponent("Data")
        tempCacheDirectory = cacheDirectory.appendingPathComponent("Temp")
        
        setupCacheDirectories()
        setupMemoryCache()
        setupNotifications()
        startCleanupTimer()
        calculateInitialCacheSize()
    }
    
    private func setupCacheDirectories() {
        let directories = [cacheDirectory, imagesCacheDirectory, dataCacheDirectory, tempCacheDirectory]
        
        for directory in directories {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Error creating cache directory: \(error)")
            }
        }
    }
    
    private func setupMemoryCache() {
        memoryCache.countLimit = 200 
        memoryCache.totalCostLimit = maxMemoryCacheSize
        memoryCache.name = "AppMemoryCache"
        
        
        memoryCache.delegate = self
    }
    
    private func setupNotifications() {
        
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { _ in
                self.handleMemoryWarning()
            }
            .store(in: &cancellables)
        
        
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { _ in
                self.handleAppDidEnterBackground()
            }
            .store(in: &cancellables)
        
        
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { _ in
                self.handleAppWillEnterForeground()
            }
            .store(in: &cancellables)
    }
    
    private func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: cleanupInterval, repeats: true) { _ in
            self.performCleanup()
        }
    }
    
    private func calculateInitialCacheSize() {
        calculateDiskUsage()
        calculateMemoryUsage()
    }
    
    
    func setObject<T: AnyObject>(_ object: T, forKey key: String, cost: Int = 0) {
        let nsKey = NSString(string: key)
        memoryCache.setObject(object, forKey: nsKey, cost: cost)
        updateMemoryUsage()
    }
    
    func object<T: AnyObject>(ofType type: T.Type, forKey key: String) -> T? {
        totalRequests += 1
        let nsKey = NSString(string: key)
        
        if let object = memoryCache.object(forKey: nsKey) as? T {
            cacheHits += 1
            updateCacheHitRate()
            return object
        }
        
        cacheMisses += 1
        updateCacheHitRate()
        return nil
    }
    
    func removeObject(forKey key: String) {
        let nsKey = NSString(string: key)
        memoryCache.removeObject(forKey: nsKey)
        updateMemoryUsage()
    }
    
    func clearMemoryCache() {
        memoryCache.removeAllObjects()
        memoryUsage = 0
    }
    
    
    func setData(_ data: Data, forKey key: String, expiration: TimeInterval? = nil) {
        diskCacheQueue.async {
            let cacheItem = CacheItem(
                data: data,
                key: key,
                timestamp: Date(),
                expiration: expiration ?? self.defaultExpirationTime
            )
            
            self.saveCacheItem(cacheItem, to: self.dataCacheDirectory)
        }
    }
    
    func data(forKey key: String) -> Data? {
        totalRequests += 1
        
        let filePath = dataCacheDirectory.appendingPathComponent(sanitizedKey(key))
        
        guard let cacheItem = loadCacheItem(from: filePath) else {
            cacheMisses += 1
            updateCacheHitRate()
            return nil
        }
        
        
        if cacheItem.isExpired {
            removeCacheItem(at: filePath)
            cacheMisses += 1
            updateCacheHitRate()
            return nil
        }
        
        cacheHits += 1
        updateCacheHitRate()
        return cacheItem.data
    }
    
    func removeData(forKey key: String) {
        diskCacheQueue.async {
            let filePath = self.dataCacheDirectory.appendingPathComponent(self.sanitizedKey(key))
            self.removeCacheItem(at: filePath)
        }
    }
    
    
    func setImage(_ image: UIImage, forKey key: String, expiration: TimeInterval? = nil) {
        
        let cost = Int(image.size.width * image.size.height * 4) 
        setObject(image, forKey: key, cost: cost)
        
        
        diskCacheQueue.async {
            guard let imageData = image.jpegData(compressionQuality: 0.8) else { return }
            
            let cacheItem = CacheItem(
                data: imageData,
                key: key,
                timestamp: Date(),
                expiration: expiration ?? self.defaultExpirationTime
            )
            
            self.saveCacheItem(cacheItem, to: self.imagesCacheDirectory)
        }
    }
    
    func image(forKey key: String) -> UIImage? {
        
        if let image = object(ofType: UIImage.self, forKey: key) {
            return image
        }
        
        
        totalRequests += 1
        let filePath = imagesCacheDirectory.appendingPathComponent(sanitizedKey(key))
        
        guard let cacheItem = loadCacheItem(from: filePath) else {
            cacheMisses += 1
            updateCacheHitRate()
            return nil
        }
        
        
        if cacheItem.isExpired {
            removeCacheItem(at: filePath)
            cacheMisses += 1
            updateCacheHitRate()
            return nil
        }
        
        
        guard let image = UIImage(data: cacheItem.data) else {
            cacheMisses += 1
            updateCacheHitRate()
            return nil
        }
        
        let cost = Int(image.size.width * image.size.height * 4)
        setObject(image, forKey: key, cost: cost)
        
        cacheHits += 1
        updateCacheHitRate()
        return image
    }
    
    func removeImage(forKey key: String) {
        removeObject(forKey: key)
        
        diskCacheQueue.async {
            let filePath = self.imagesCacheDirectory.appendingPathComponent(self.sanitizedKey(key))
            self.removeCacheItem(at: filePath)
        }
    }
    
    
    func setDataAsync(_ data: Data, forKey key: String, expiration: TimeInterval? = nil) -> AnyPublisher<Void, Error> {
        return Future { promise in
            self.diskCacheQueue.async {
                let cacheItem = CacheItem(
                    data: data,
                    key: key,
                    timestamp: Date(),
                    expiration: expiration ?? self.defaultExpirationTime
                )
                
                do {
                    try self.saveCacheItemSync(cacheItem, to: self.dataCacheDirectory)
                    promise(.success(()))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    func dataAsync(forKey key: String) -> AnyPublisher<Data?, Never> {
        return Future { promise in
            self.diskCacheQueue.async {
                let data = self.data(forKey: key)
                promise(.success(data))
            }
        }
        .eraseToAnyPublisher()
    }
    
    func imageAsync(forKey key: String) -> AnyPublisher<UIImage?, Never> {
        return Future { promise in
            DispatchQueue.main.async {
                let image = self.image(forKey: key)
                promise(.success(image))
            }
        }
        .eraseToAnyPublisher()
    }
    
    
    func setObject<T: Codable>(_ object: T, forKey key: String, expiration: TimeInterval? = nil) {
        do {
            let data = try JSONEncoder().encode(object)
            setData(data, forKey: key, expiration: expiration)
        } catch {
            print("Error encoding object for cache: \(error)")
        }
    }
    
    func object<T: Codable>(ofType type: T.Type, forKey key: String) -> T? {
        guard let data = data(forKey: key) else { return nil }
        
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            print("Error decoding object from cache: \(error)")
            return nil
        }
    }
    
    
    func setTemporaryData(_ data: Data, forKey key: String) {
        diskCacheQueue.async {
            let cacheItem = CacheItem(
                data: data,
                key: key,
                timestamp: Date(),
                expiration: 3600 
            )
            
            self.saveCacheItem(cacheItem, to: self.tempCacheDirectory)
        }
    }
    
    func temporaryData(forKey key: String) -> Data? {
        let filePath = tempCacheDirectory.appendingPathComponent(sanitizedKey(key))
        
        guard let cacheItem = loadCacheItem(from: filePath) else {
            return nil
        }
        
        if cacheItem.isExpired {
            removeCacheItem(at: filePath)
            return nil
        }
        
        return cacheItem.data
    }
    
    func clearTemporaryCache() {
        diskCacheQueue.async {
            self.clearDirectory(self.tempCacheDirectory)
        }
    }
    
    
    func clearAllCaches() {
        clearMemoryCache()
        
        diskCacheQueue.async {
            self.clearDirectory(self.imagesCacheDirectory)
            self.clearDirectory(self.dataCacheDirectory)
            self.clearDirectory(self.tempCacheDirectory)
            
            DispatchQueue.main.async {
                self.diskUsage = 0
                self.memoryUsage = 0
            }
        }
    }
    
    func clearExpiredItems() {
        diskCacheQueue.async {
            self.clearExpiredItems(in: self.imagesCacheDirectory)
            self.clearExpiredItems(in: self.dataCacheDirectory)
            self.clearExpiredItems(in: self.tempCacheDirectory)
            
            DispatchQueue.main.async {
                self.calculateDiskUsage()
            }
        }
    }
    
    func evictLeastRecentlyUsed() {
        diskCacheQueue.async {
            self.evictLRU(in: self.imagesCacheDirectory)
            self.evictLRU(in: self.dataCacheDirectory)
            
            DispatchQueue.main.async {
                self.calculateDiskUsage()
            }
        }
    }
    
    
    func getCacheInfo() -> CacheInfo {
        return CacheInfo(
            memoryUsage: memoryUsage,
            diskUsage: diskUsage,
            cacheHitRate: cacheHitRate,
            totalRequests: totalRequests,
            cacheHits: cacheHits,
            cacheMisses: cacheMisses,
            memoryObjectCount: memoryCache.count,
            diskFileCount: getDiskFileCount()
        )
    }
    
    func resetStatistics() {
        cacheHits = 0
        cacheMisses = 0
        totalRequests = 0
        cacheHitRate = 0.0
    }
    
    
    private func saveCacheItem(_ item: CacheItem, to directory: URL) {
        let filePath = directory.appendingPathComponent(sanitizedKey(item.key))
        
        do {
            let data = try JSONEncoder().encode(item)
            try data.write(to: filePath)
            
            DispatchQueue.main.async {
                self.calculateDiskUsage()
            }
        } catch {
            print("Error saving cache item: \(error)")
        }
    }
    
    private func saveCacheItemSync(_ item: CacheItem, to directory: URL) throws {
        let filePath = directory.appendingPathComponent(sanitizedKey(item.key))
        let data = try JSONEncoder().encode(item)
        try data.write(to: filePath)
    }
    
    private func loadCacheItem(from filePath: URL) -> CacheItem? {
        do {
            let data = try Data(contentsOf: filePath)
            return try JSONDecoder().decode(CacheItem.self, from: data)
        } catch {
            return nil
        }
    }
    
    private func removeCacheItem(at filePath: URL) {
        do {
            try FileManager.default.removeItem(at: filePath)
            
            DispatchQueue.main.async {
                self.calculateDiskUsage()
            }
        } catch {
            print("Error removing cache item: \(error)")
        }
    }
    
    private func sanitizedKey(_ key: String) -> String {
        return key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
    }
    
    private func clearDirectory(_ directory: URL) {
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            for file in contents {
                try FileManager.default.removeItem(at: file)
            }
        } catch {
            print("Error clearing directory: \(error)")
        }
    }
    
    private func clearExpiredItems(in directory: URL) {
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            
            for file in contents {
                if let cacheItem = loadCacheItem(from: file), cacheItem.isExpired {
                    try FileManager.default.removeItem(at: file)
                }
            }
        } catch {
            print("Error clearing expired items: \(error)")
        }
    }
    
    private func evictLRU(in directory: URL) {
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
            
            
            let sortedFiles = contents.sorted { file1, file2 in
                let date1 = try? file1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? Date.distantPast
                let date2 = try? file2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? Date.distantPast
                return date1! < date2!
            }
            
            
            let filesToRemove = Int(Double(sortedFiles.count) * 0.2)
            for i in 0..<filesToRemove {
                try FileManager.default.removeItem(at: sortedFiles[i])
            }
        } catch {
            print("Error evicting LRU items: \(error)")
        }
    }
    
    private func calculateDiskUsage() {
        diskCacheQueue.async {
            let directories = [self.imagesCacheDirectory, self.dataCacheDirectory, self.tempCacheDirectory]
            var totalSize: Int64 = 0
            
            for directory in directories {
                totalSize += self.directorySize(directory)
            }
            
            DispatchQueue.main.async {
                self.diskUsage = totalSize
            }
        }
    }
    
    private func directorySize(_ directory: URL) -> Int64 {
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
            
            return contents.reduce(0) { totalSize, file in
                do {
                    let resourceValues = try file.resourceValues(forKeys: [.fileSizeKey])
                    return totalSize + Int64(resourceValues.fileSize ?? 0)
                } catch {
                    return totalSize
                }
            }
        } catch {
            return 0
        }
    }
    
    private func calculateMemoryUsage() {
        
        memoryUsage = Int64(memoryCache.totalCostLimit)
    }
    
    private func updateMemoryUsage() {
        
        calculateMemoryUsage()
    }
    
    private func updateCacheHitRate() {
        guard totalRequests > 0 else {
            cacheHitRate = 0.0
            return
        }
        
        cacheHitRate = Double(cacheHits) / Double(totalRequests)
    }
    
    private func getDiskFileCount() -> Int {
        let directories = [imagesCacheDirectory, dataCacheDirectory, tempCacheDirectory]
        
        return directories.reduce(0) { totalCount, directory in
            do {
                let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                return totalCount + contents.count
            } catch {
                return totalCount
            }
        }
    }
    
    private func performCleanup() {
        cleanupQueue.async {
            
            self.clearExpiredItems()
            
            
            if self.diskUsage > self.maxDiskCacheSize {
                self.evictLeastRecentlyUsed()
            }
            
            
            let tempCacheCreationDate = self.tempCacheDirectory.creationDate ?? Date.distantPast
            if Date().timeIntervalSince(tempCacheCreationDate) > 86400 { 
                self.clearTemporaryCache()
            }
        }
    }
    
    
    private func handleMemoryWarning() {
        isMemoryWarning = true
        
        
        clearMemoryCache()
        
        
        clearTemporaryCache()
        
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.isMemoryWarning = false
        }
    }
    
    private func handleAppDidEnterBackground() {
        
        performCleanup()
        
        
        clearMemoryCache()
    }
    
    private func handleAppWillEnterForeground() {
        
        calculateDiskUsage()
        calculateMemoryUsage()
    }
    
    deinit {
        cleanupTimer?.invalidate()
    }
}


extension CacheManager: NSCacheDelegate {
    func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: AnyObject) {
        
        updateMemoryUsage()
    }
}


struct CacheItem: Codable {
    let data: Data
    let key: String
    let timestamp: Date
    let expiration: TimeInterval
    
    var isExpired: Bool {
        return Date().timeIntervalSince(timestamp) > expiration
    }
}

struct CacheInfo {
    let memoryUsage: Int64
    let diskUsage: Int64
    let cacheHitRate: Double
    let totalRequests: Int
    let cacheHits: Int
    let cacheMisses: Int
    let memoryObjectCount: Int
    let diskFileCount: Int
    
    var formattedMemoryUsage: String {
        return ByteCountFormatter.string(fromByteCount: memoryUsage, countStyle: .file)
    }
    
    var formattedDiskUsage: String {
        return ByteCountFormatter.string(fromByteCount: diskUsage, countStyle: .file)
    }
    
    var hitRatePercentage: String {
        return String(format: "%.1f%%", cacheHitRate * 100)
    }
}


enum CachePolicy {
    case noCache
    case memoryOnly
    case diskOnly
    case memoryAndDisk
    case automatic
}

enum EvictionPolicy {
    case lru 
    case lfu 
    case fifo 
    case size 
}


class AdvancedCacheManager: CacheManager {
    
    private var accessCounts: [String: Int] = [:]
    private var accessTimes: [String: Date] = [:]
    
    override func object<T: AnyObject>(ofType type: T.Type, forKey key: String) -> T? {
        
        accessCounts[key, default: 0] += 1
        accessTimes[key] = Date()
        
        return super.object(ofType: type, forKey: key)
    }
    
    override func data(forKey key: String) -> Data? {
        
        accessCounts[key, default: 0] += 1
        accessTimes[key] = Date()
        
        return super.data(forKey: key)
    }
    
    func evict(using policy: EvictionPolicy, count: Int = 10) {
        switch policy {
        case .lru:
            evictLRU(count: count)
        case .lfu:
            evictLFU(count: count)
        case .fifo:
            evictFIFO(count: count)
        case .size:
            evictLargestItems(count: count)
        }
    }
    
    private func evictLRU(count: Int) {
        let sortedByTime = accessTimes.sorted { $0.value < $1.value }
        let keysToEvict = Array(sortedByTime.prefix(count)).map { $0.key }
        
        for key in keysToEvict {
            removeObject(forKey: key)
            removeData(forKey: key)
            accessCounts.removeValue(forKey: key)
            accessTimes.removeValue(forKey: key)
        }
    }
    
    private func evictLFU(count: Int) {
        let sortedByCount = accessCounts.sorted { $0.value < $1.value }
        let keysToEvict = Array(sortedByCount.prefix(count)).map { $0.key }
        
        for key in keysToEvict {
            removeObject(forKey: key)
            removeData(forKey: key)
            accessCounts.removeValue(forKey: key)
            accessTimes.removeValue(forKey: key)
        }
    }
    
    private func evictFIFO(count: Int) {
        
        evictLRU(count: count) 
    }
    
    private func evictLargestItems(count: Int) {
        
        evictLRU(count: count) 
    }
}


extension URL {
    var creationDate: Date? {
        return try? resourceValues(forKeys: [.creationDateKey]).creationDate
    }
    
    var modificationDate: Date? {
        return try? resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
    
    var fileSize: Int64 {
        return Int64(try? resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
    }
}


extension CacheManager {
    func preloadImages(urls: [URL], completion: @escaping (Int, Int) -> Void) {
        let group = DispatchGroup()
        var successCount = 0
        var failureCount = 0
        
        for url in urls {
            group.enter()
            
            URLSession.shared.dataTask(with: url) { data, response, error in
                defer { group.leave() }
                
                if let data = data, let image = UIImage(data: data) {
                    let key = url.absoluteString
                    self.setImage(image, forKey: key)
                    successCount += 1
                } else {
                    failureCount += 1
                }
            }.resume()
        }
        
        group.notify(queue: .main) {
            completion(successCount, failureCount)
        }
    }
    
    func downloadAndCacheImage(from url: URL, key: String? = nil) -> AnyPublisher<UIImage?, Error> {
        let cacheKey = key ?? url.absoluteString
        
        
        if let cachedImage = image(forKey: cacheKey) {
            return Just(cachedImage)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }
        
        
        return URLSession.shared.dataTaskPublisher(for: url)
            .map(\.data)
            .compactMap { UIImage(data: $0) }
            .handleEvents(receiveOutput: { [weak self] image in
                self?.setImage(image, forKey: cacheKey)
            })
            .eraseToAnyPublisher()
    }
}
