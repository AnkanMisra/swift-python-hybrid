import Foundation
import os.log
import Combine
import CryptoKit

protocol LogEntry {
    var id: UUID { get }
    var timestamp: Date { get }
    var level: LogLevel { get }
    var message: String { get }
    var category: String { get }
    var metadata: [String: Any] { get }
}

struct StandardLogEntry: LogEntry, Codable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let message: String
    let category: String
    let metadata: [String: Any]
    let file: String
    let function: String
    let line: Int
    let thread: String
    
    init(
        level: LogLevel,
        message: String,
        category: String,
        metadata: [String: Any] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.level = level
        self.message = message
        self.category = category
        self.metadata = metadata
        self.file = URL(fileURLWithPath: file).lastPathComponent
        self.function = function
        self.line = line
        self.thread = Thread.current.isMainThread ? "main" : Thread.current.name ?? "unknown"
    }
    
    enum CodingKeys: String, CodingKey {
        case id, timestamp, level, message, category, file, function, line, thread
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(level, forKey: .level)
        try container.encode(message, forKey: .message)
        try container.encode(category, forKey: .category)
        try container.encode(file, forKey: .file)
        try container.encode(function, forKey: .function)
        try container.encode(line, forKey: .line)
        try container.encode(thread, forKey: .thread)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        level = try container.decode(LogLevel.self, forKey: .level)
        message = try container.decode(String.self, forKey: .message)
        category = try container.decode(String.self, forKey: .category)
        file = try container.decode(String.self, forKey: .file)
        function = try container.decode(String.self, forKey: .function)
        line = try container.decode(Int.self, forKey: .line)
        thread = try container.decode(String.self, forKey: .thread)
        metadata = [:]
    }
}

enum LogLevel: String, CaseIterable, Codable, Comparable {
    case trace = "TRACE"
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    case critical = "CRITICAL"
    
    var priority: Int {
        switch self {
        case .trace: return 0
        case .debug: return 1
        case .info: return 2
        case .warning: return 3
        case .error: return 4
        case .critical: return 5
        }
    }
    
    var osLogType: OSLogType {
        switch self {
        case .trace, .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        case .critical: return .fault
        }
    }
    
    var emoji: String {
        switch self {
        case .trace: return "🔍"
        case .debug: return "🐛"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .critical: return "🚨"
        }
    }
    
    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        return lhs.priority < rhs.priority
    }
}

protocol LogDestination {
    var name: String { get }
    var isEnabled: Bool { get set }
    var minimumLevel: LogLevel { get set }
    var formatter: LogFormatter { get set }
    
    func write(_ entry: LogEntry)
    func flush()
    func close()
}

protocol LogFormatter {
    func format(_ entry: LogEntry) -> String
}

struct StandardLogFormatter: LogFormatter {
    let dateFormatter: DateFormatter
    let includeMetadata: Bool
    let colorEnabled: Bool
    
    init(includeMetadata: Bool = true, colorEnabled: Bool = false) {
        self.includeMetadata = includeMetadata
        self.colorEnabled = colorEnabled
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    }
    
    func format(_ entry: LogEntry) -> String {
        let timestamp = dateFormatter.string(from: entry.timestamp)
        let level = colorEnabled ? coloredLevel(entry.level) : entry.level.rawValue
        let category = entry.category.isEmpty ? "" : "[\(entry.category)]"
        
        var formatted = "\(timestamp) \(level) \(category) \(entry.message)"
        
        if let standardEntry = entry as? StandardLogEntry {
            formatted += " (\(standardEntry.file):\(standardEntry.line))"
        }
        
        if includeMetadata && !entry.metadata.isEmpty {
            let metadataString = entry.metadata.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            formatted += " {\(metadataString)}"
        }
        
        return formatted
    }
    
    private func coloredLevel(_ level: LogLevel) -> String {
        switch level {
        case .trace: return "\u{001B}[37mTRACE\u{001B}[0m"
        case .debug: return "\u{001B}[36mDEBUG\u{001B}[0m"
        case .info: return "\u{001B}[32mINFO\u{001B}[0m"
        case .warning: return "\u{001B}[33mWARNING\u{001B}[0m"
        case .error: return "\u{001B}[31mERROR\u{001B}[0m"
        case .critical: return "\u{001B}[35mCRITICAL\u{001B}[0m"
        }
    }
}

struct JSONLogFormatter: LogFormatter {
    private let encoder: JSONEncoder
    
    init() {
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }
    
    func format(_ entry: LogEntry) -> String {
        guard let standardEntry = entry as? StandardLogEntry else {
            return "{\"error\": \"unsupported log entry type\"}"
        }
        
        do {
            let data = try encoder.encode(standardEntry)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{\"error\": \"encoding failed: \(error.localizedDescription)\"}"
        }
    }
}

class ConsoleDestination: LogDestination {
    let name = "console"
    var isEnabled = true
    var minimumLevel: LogLevel = .debug
    var formatter: LogFormatter = StandardLogFormatter(colorEnabled: true)
    
    func write(_ entry: LogEntry) {
        guard isEnabled && entry.level >= minimumLevel else { return }
        print(formatter.format(entry))
    }
    
    func flush() {}
    func close() {}
}

class FileDestination: LogDestination {
    let name = "file"
    var isEnabled = true
    var minimumLevel: LogLevel = .info
    var formatter: LogFormatter = StandardLogFormatter()
    
    private let fileURL: URL
    private let fileHandle: FileHandle?
    private let queue = DispatchQueue(label: "file-logger", qos: .utility)
    private let maxFileSize: Int
    private let maxBackupFiles: Int
    
    init(fileURL: URL, maxFileSize: Int = 10 * 1024 * 1024, maxBackupFiles: Int = 5) {
        self.fileURL = fileURL
        self.maxFileSize = maxFileSize
        self.maxBackupFiles = maxBackupFiles
        
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        
        self.fileHandle = try? FileHandle(forWritingTo: fileURL)
        self.fileHandle?.seekToEndOfFile()
    }
    
    func write(_ entry: LogEntry) {
        guard isEnabled && entry.level >= minimumLevel else { return }
        
        queue.async {
            let formatted = self.formatter.format(entry) + "\n"
            if let data = formatted.data(using: .utf8) {
                self.fileHandle?.write(data)
                self.checkFileRotation()
            }
        }
    }
    
    func flush() {
        queue.sync {
            fileHandle?.synchronizeFile()
        }
    }
    
    func close() {
        queue.sync {
            fileHandle?.closeFile()
        }
    }
    
    private func checkFileRotation() {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let fileSize = attributes[.size] as? Int,
              fileSize > maxFileSize else { return }
        
        rotateFiles()
    }
    
    private func rotateFiles() {
        fileHandle?.closeFile()
        
        for i in (1..<maxBackupFiles).reversed() {
            let currentBackup = fileURL.appendingPathExtension("\(i)")
            let nextBackup = fileURL.appendingPathExtension("\(i + 1)")
            
            if FileManager.default.fileExists(atPath: currentBackup.path) {
                try? FileManager.default.moveItem(at: currentBackup, to: nextBackup)
            }
        }
        
        let firstBackup = fileURL.appendingPathExtension("1")
        try? FileManager.default.moveItem(at: fileURL, to: firstBackup)
        
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
    }
}

class OSLogDestination: LogDestination {
    let name = "oslog"
    var isEnabled = true
    var minimumLevel: LogLevel = .info
    var formatter: LogFormatter = StandardLogFormatter(includeMetadata: false)
    
    private let osLog: OSLog
    
    init(subsystem: String, category: String) {
        self.osLog = OSLog(subsystem: subsystem, category: category)
    }
    
    func write(_ entry: LogEntry) {
        guard isEnabled && entry.level >= minimumLevel else { return }
        
        let message = formatter.format(entry)
        os_log("%{public}@", log: osLog, type: entry.level.osLogType, message)
    }
    
    func flush() {}
    func close() {}
}

class RemoteDestination: LogDestination {
    let name = "remote"
    var isEnabled = true
    var minimumLevel: LogLevel = .warning
    var formatter: LogFormatter = JSONLogFormatter()
    
    private let endpoint: URL
    private let session: URLSession
    private let queue = DispatchQueue(label: "remote-logger", qos: .utility)
    private var buffer: [LogEntry] = []
    private let bufferSize: Int
    private let flushInterval: TimeInterval
    private var flushTimer: Timer?
    
    init(endpoint: URL, bufferSize: Int = 100, flushInterval: TimeInterval = 30) {
        self.endpoint = endpoint
        self.bufferSize = bufferSize
        self.flushInterval = flushInterval
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config)
        
        startFlushTimer()
    }
    
    func write(_ entry: LogEntry) {
        guard isEnabled && entry.level >= minimumLevel else { return }
        
        queue.async {
            self.buffer.append(entry)
            if self.buffer.count >= self.bufferSize {
                self.flushBuffer()
            }
        }
    }
    
    func flush() {
        queue.sync {
            flushBuffer()
        }
    }
    
    func close() {
        flushTimer?.invalidate()
        flush()
    }
    
    private func startFlushTimer() {
        flushTimer = Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true) { _ in
            self.flush()
        }
    }
    
    private func flushBuffer() {
        guard !buffer.isEmpty else { return }
        
        let entries = buffer
        buffer.removeAll()
        
        let logData = entries.map { formatter.format($0) }.joined(separator: "\n")
        
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = logData.data(using: .utf8)
        
        session.dataTask(with: request) { _, _, error in
            if let error = error {
                print("Failed to send logs: \(error.localizedDescription)")
            }
        }.resume()
    }
}

struct LoggingConfiguration {
    let minimumLevel: LogLevel
    let destinations: [LogDestination]
    let categories: Set<String>
    let enableMetrics: Bool
    let bufferSize: Int
    let asyncLogging: Bool
    
    init(
        minimumLevel: LogLevel = .info,
        destinations: [LogDestination] = [ConsoleDestination()],
        categories: Set<String> = [],
        enableMetrics: Bool = true,
        bufferSize: Int = 1000,
        asyncLogging: Bool = true
    ) {
        self.minimumLevel = minimumLevel
        self.destinations = destinations
        self.categories = categories
        self.enableMetrics = enableMetrics
        self.bufferSize = bufferSize
        self.asyncLogging = asyncLogging
    }
}

struct LoggingMetrics {
    var totalLogs: Int = 0
    var logsByLevel: [LogLevel: Int] = [:]
    var logsByCategory: [String: Int] = [:]
    var averageLogSize: Double = 0
    var droppedLogs: Int = 0
    var lastLogTime: Date?
    var startTime: Date = Date()
    
    mutating func recordLog(_ entry: LogEntry) {
        totalLogs += 1
        logsByLevel[entry.level, default: 0] += 1
        logsByCategory[entry.category, default: 0] += 1
        lastLogTime = entry.timestamp
        
        let logSize = Double(entry.message.count)
        averageLogSize = (averageLogSize * Double(totalLogs - 1) + logSize) / Double(totalLogs)
    }
    
    var uptime: TimeInterval {
        Date().timeIntervalSince(startTime)
    }
    
    var logsPerSecond: Double {
        uptime > 0 ? Double(totalLogs) / uptime : 0
    }
}

actor LoggingSystem {
    static let shared = LoggingSystem()
    
    private var configuration: LoggingConfiguration
    private var destinations: [LogDestination]
    private var metrics: LoggingMetrics
    private var logBuffer: [LogEntry]
    private var isProcessing: Bool = false
    private var processingTask: Task<Void, Never>?
    
    private init() {
        self.configuration = LoggingConfiguration()
        self.destinations = configuration.destinations
        self.metrics = LoggingMetrics()
        self.logBuffer = []
        startProcessing()
    }
    
    func configure(_ configuration: LoggingConfiguration) {
        self.configuration = configuration
        self.destinations = configuration.destinations
    }
    
    func log(
        level: LogLevel,
        message: String,
        category: String = "",
        metadata: [String: Any] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard level >= configuration.minimumLevel else { return }
        
        if !configuration.categories.isEmpty && !configuration.categories.contains(category) {
            return
        }
        
        let entry = StandardLogEntry(
            level: level,
            message: message,
            category: category,
            metadata: metadata,
            file: file,
            function: function,
            line: line
        )
        
        if configuration.asyncLogging {
            addToBuffer(entry)
        } else {
            processEntry(entry)
        }
    }
    
    func trace(_ message: String, category: String = "", metadata: [String: Any] = [:], file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .trace, message: message, category: category, metadata: metadata, file: file, function: function, line: line)
    }
    
    func debug(_ message: String, category: String = "", metadata: [String: Any] = [:], file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .debug, message: message, category: category, metadata: metadata, file: file, function: function, line: line)
    }
    
    func info(_ message: String, category: String = "", metadata: [String: Any] = [:], file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .info, message: message, category: category, metadata: metadata, file: file, function: function, line: line)
    }
    
    func warning(_ message: String, category: String = "", metadata: [String: Any] = [:], file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .warning, message: message, category: category, metadata: metadata, file: file, function: function, line: line)
    }
    
    func error(_ message: String, category: String = "", metadata: [String: Any] = [:], file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .error, message: message, category: category, metadata: metadata, file: file, function: function, line: line)
    }
    
    func critical(_ message: String, category: String = "", metadata: [String: Any] = [:], file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .critical, message: message, category: category, metadata: metadata, file: file, function: function, line: line)
    }
    
    func getMetrics() -> LoggingMetrics {
        return metrics
    }
    
    func flush() {
        for destination in destinations {
            destination.flush()
        }
    }
    
    func shutdown() {
        processingTask?.cancel()
        processBuffer()
        
        for destination in destinations {
            destination.close()
        }
    }
    
    private func addToBuffer(_ entry: LogEntry) {
        if logBuffer.count >= configuration.bufferSize {
            logBuffer.removeFirst()
            metrics.droppedLogs += 1
        }
        
        logBuffer.append(entry)
    }
    
    private func startProcessing() {
        processingTask = Task {
            while !Task.isCancelled {
                await processBuffer()
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }
    }
    
    private func processBuffer() {
        guard !isProcessing && !logBuffer.isEmpty else { return }
        
        isProcessing = true
        let entries = logBuffer
        logBuffer.removeAll()
        
        for entry in entries {
            processEntry(entry)
        }
        
        isProcessing = false
    }
    
    private func processEntry(_ entry: LogEntry) {
        if configuration.enableMetrics {
            metrics.recordLog(entry)
        }
        
        for destination in destinations {
            destination.write(entry)
        }
    }
}

class Logger {
    private let category: String
    private let loggingSystem: LoggingSystem
    
    init(category: String) {
        self.category = category
        self.loggingSystem = LoggingSystem.shared
    }
    
    func trace(_ message: String, metadata: [String: Any] = [:], file: String = #file, function: String = #function, line: Int = #line) {
        Task {
            await loggingSystem.trace(message, category: category, metadata: metadata, file: file, function: function, line: line)
        }
    }
    
    func debug(_ message: String, metadata: [String: Any] = [:], file: String = #file, function: String = #function, line: Int = #line) {
        Task {
            await loggingSystem.debug(message, category: category, metadata: metadata, file: file, function: function, line: line)
        }
    }
    
    func info(_ message: String, metadata: [String: Any] = [:], file: String = #file, function: String = #function, line: Int = #line) {
        Task {
            await loggingSystem.info(message, category: category, metadata: metadata, file: file, function: function, line: line)
        }
    }
    
    func warning(_ message: String, metadata: [String: Any] = [:], file: String = #file, function: String = #function, line: Int = #line) {
        Task {
            await loggingSystem.warning(message, category: category, metadata: metadata, file: file, function: function, line: line)
        }
    }
    
    func error(_ message: String, metadata: [String: Any] = [:], file: String = #file, function: String = #function, line: Int = #line) {
        Task {
            await loggingSystem.error(message, category: category, metadata: metadata, file: file, function: function, line: line)
        }
    }
    
    func critical(_ message: String, metadata: [String: Any] = [:], file: String = #file, function: String = #function, line: Int = #line) {
        Task {
            await loggingSystem.critical(message, category: category, metadata: metadata, file: file, function: function, line: line)
        }
    }
}

func logPerformance<T>(
    operation: String,
    category: String = "performance",
    level: LogLevel = .info,
    _ block: () throws -> T
) rethrows -> T {
    let startTime = CFAbsoluteTimeGetCurrent()
    let result = try block()
    let duration = CFAbsoluteTimeGetCurrent() - startTime
    
    Task {
        await LoggingSystem.shared.log(
            level: level,
            message: "\(operation) completed in \(String(format: "%.3f", duration * 1000))ms",
            category: category,
            metadata: ["duration_ms": duration * 1000, "operation": operation]
        )
    }
    
    return result
}

func logPerformanceAsync<T>(
    operation: String,
    category: String = "performance",
    level: LogLevel = .info,
    _ block: () async throws -> T
) async rethrows -> T {
    let startTime = CFAbsoluteTimeGetCurrent()
    let result = try await block()
    let duration = CFAbsoluteTimeGetCurrent() - startTime
    
    await LoggingSystem.shared.log(
        level: level,
        message: "\(operation) completed in \(String(format: "%.3f", duration * 1000))ms",
        category: category,
        metadata: ["duration_ms": duration * 1000, "operation": operation]
    )
    
    return result
}

extension LoggingSystem {
    func logError(_ error: Error, context: String = "", category: String = "error") {
        let metadata: [String: Any] = [
            "error_type": String(describing: type(of: error)),
            "error_description": error.localizedDescription,
            "context": context
        ]
        
        Task {
            await self.error("Error occurred: \(error.localizedDescription)", category: category, metadata: metadata)
        }
    }
    
    func logNetworkRequest(
        url: URL,
        method: String,
        statusCode: Int? = nil,
        duration: TimeInterval? = nil,
        error: Error? = nil
    ) {
        var metadata: [String: Any] = [
            "url": url.absoluteString,
            "method": method
        ]
        
        if let statusCode = statusCode {
            metadata["status_code"] = statusCode
        }
        
        if let duration = duration {
            metadata["duration_ms"] = duration * 1000
        }
        
        let level: LogLevel
        let message: String
        
        if let error = error {
            level = .error
            message = "Network request failed: \(method) \(url.absoluteString) - \(error.localizedDescription)"
            metadata["error"] = error.localizedDescription
        } else if let statusCode = statusCode {
            level = statusCode >= 400 ? .warning : .info
            message = "Network request: \(method) \(url.absoluteString) - \(statusCode)"
        } else {
            level = .info
            message = "Network request: \(method) \(url.absoluteString)"
        }
        
        Task {
            await self.log(level: level, message: message, category: "network", metadata: metadata)
        }
    }
}

class LoggingObservable: ObservableObject {
    @Published var metrics: LoggingMetrics = LoggingMetrics()
    @Published var recentLogs: [LogEntry] = []
    
    private let loggingSystem = LoggingSystem.shared
    private var updateTimer: Timer?
    
    init() {
        startMonitoring()
    }
    
    private func startMonitoring() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task {
                await self.updateMetrics()
            }
        }
    }
    
    private func updateMetrics() async {
        let currentMetrics = await loggingSystem.getMetrics()
        
        DispatchQueue.main.async {
            self.metrics = currentMetrics
        }
    }
    
    deinit {
        updateTimer?.invalidate()
    }
}