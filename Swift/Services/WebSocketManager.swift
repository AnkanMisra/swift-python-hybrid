import Foundation
import Network
import Combine
import CryptoKit

protocol WebSocketMessage: Codable {
    var id: UUID { get }
    var timestamp: Date { get }
    var type: String { get }
}

struct TextMessage: WebSocketMessage {
    let id: UUID
    let timestamp: Date
    let type: String
    let content: String
    let sender: String
    let metadata: [String: String]
    
    init(content: String, sender: String, metadata: [String: String] = [:]) {
        self.id = UUID()
        self.timestamp = Date()
        self.type = "text"
        self.content = content
        self.sender = sender
        self.metadata = metadata
    }
}

struct BinaryMessage: WebSocketMessage {
    let id: UUID
    let timestamp: Date
    let type: String
    let data: Data
    let encoding: String
    let checksum: String
    
    init(data: Data, encoding: String = "base64") {
        self.id = UUID()
        self.timestamp = Date()
        self.type = "binary"
        self.data = data
        self.encoding = encoding
        self.checksum = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }
}

struct ControlMessage: WebSocketMessage {
    let id: UUID
    let timestamp: Date
    let type: String
    let command: ControlCommand
    let parameters: [String: Any]
    
    init(command: ControlCommand, parameters: [String: Any] = [:]) {
        self.id = UUID()
        self.timestamp = Date()
        self.type = "control"
        self.command = command
        self.parameters = parameters
    }
}

enum ControlCommand: String, CaseIterable {
    case ping = "ping"
    case pong = "pong"
    case subscribe = "subscribe"
    case unsubscribe = "unsubscribe"
    case authenticate = "authenticate"
    case heartbeat = "heartbeat"
    case close = "close"
}

enum WebSocketState: String, CaseIterable {
    case disconnected = "disconnected"
    case connecting = "connecting"
    case connected = "connected"
    case reconnecting = "reconnecting"
    case error = "error"
    case closing = "closing"
}

enum WebSocketError: Error, LocalizedError {
    case invalidURL
    case connectionFailed(Error)
    case authenticationFailed
    case messageEncodingFailed
    case messageDecodingFailed
    case connectionTimeout
    case rateLimitExceeded
    case serverError(Int, String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid WebSocket URL"
        case .connectionFailed(let error):
            return "Connection failed: \(error.localizedDescription)"
        case .authenticationFailed:
            return "Authentication failed"
        case .messageEncodingFailed:
            return "Failed to encode message"
        case .messageDecodingFailed:
            return "Failed to decode message"
        case .connectionTimeout:
            return "Connection timeout"
        case .rateLimitExceeded:
            return "Rate limit exceeded"
        case .serverError(let code, let message):
            return "Server error \(code): \(message)"
        }
    }
}

struct WebSocketConfiguration {
    let url: URL
    let protocols: [String]
    let headers: [String: String]
    let timeoutInterval: TimeInterval
    let heartbeatInterval: TimeInterval
    let maxReconnectAttempts: Int
    let reconnectDelay: TimeInterval
    let maxMessageSize: Int
    let compressionEnabled: Bool
    let authenticationToken: String?
    
    init(
        url: URL,
        protocols: [String] = [],
        headers: [String: String] = [:],
        timeoutInterval: TimeInterval = 30,
        heartbeatInterval: TimeInterval = 30,
        maxReconnectAttempts: Int = 5,
        reconnectDelay: TimeInterval = 2,
        maxMessageSize: Int = 1024 * 1024,
        compressionEnabled: Bool = true,
        authenticationToken: String? = nil
    ) {
        self.url = url
        self.protocols = protocols
        self.headers = headers
        self.timeoutInterval = timeoutInterval
        self.heartbeatInterval = heartbeatInterval
        self.maxReconnectAttempts = maxReconnectAttempts
        self.reconnectDelay = reconnectDelay
        self.maxMessageSize = maxMessageSize
        self.compressionEnabled = compressionEnabled
        self.authenticationToken = authenticationToken
    }
}

struct WebSocketMetrics {
    var connectionCount: Int = 0
    var messagesSent: Int = 0
    var messagesReceived: Int = 0
    var bytesTransferred: Int = 0
    var reconnectAttempts: Int = 0
    var lastConnectionTime: Date?
    var averageLatency: TimeInterval = 0
    var errorCount: Int = 0
}

actor WebSocketManager: ObservableObject {
    static let shared = WebSocketManager()
    
    @Published private(set) var state: WebSocketState = .disconnected
    @Published private(set) var isConnected: Bool = false
    @Published private(set) var metrics: WebSocketMetrics = WebSocketMetrics()
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession
    private var configuration: WebSocketConfiguration?
    private var messageQueue: [(WebSocketMessage, TaskPriority)] = []
    private var subscriptions: [String: [(WebSocketMessage) async -> Void]] = [:]
    private var heartbeatTimer: Timer?
    private var reconnectTimer: Timer?
    private var reconnectAttempts: Int = 0
    private var pendingMessages: [UUID: (Date, CheckedContinuation<Void, Error>)] = [:]
    private var rateLimiter: RateLimiter
    private var messageBuffer: [WebSocketMessage] = []
    private var compressionEnabled: Bool = false
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.urlSession = URLSession(configuration: config)
        self.rateLimiter = RateLimiter(maxRequests: 100, timeWindow: 60)
    }
    
    func configure(_ configuration: WebSocketConfiguration) {
        self.configuration = configuration
        self.compressionEnabled = configuration.compressionEnabled
    }
    
    func connect() async throws {
        guard let config = configuration else {
            throw WebSocketError.invalidURL
        }
        
        await updateState(.connecting)
        
        var request = URLRequest(url: config.url)
        request.timeoutInterval = config.timeoutInterval
        
        for (key, value) in config.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        if let token = config.authenticationToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()
        
        do {
            try await waitForConnection()
            await updateState(.connected)
            await updateConnectionMetrics()
            startHeartbeat()
            startListening()
            await processMessageQueue()
        } catch {
            await updateState(.error)
            throw WebSocketError.connectionFailed(error)
        }
    }
    
    func disconnect() async {
        await updateState(.closing)
        
        stopHeartbeat()
        stopReconnectTimer()
        
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        
        await updateState(.disconnected)
    }
    
    func send<T: WebSocketMessage>(_ message: T, priority: TaskPriority = .medium) async throws {
        guard await rateLimiter.allowRequest() else {
            throw WebSocketError.rateLimitExceeded
        }
        
        if state != .connected {
            messageQueue.append((message, priority))
            messageQueue.sort { $0.1.rawValue > $1.1.rawValue }
            return
        }
        
        try await sendMessage(message)
    }
    
    func sendAndWait<T: WebSocketMessage>(_ message: T) async throws {
        try await withCheckedThrowingContinuation { continuation in
            pendingMessages[message.id] = (Date(), continuation)
            
            Task {
                do {
                    try await send(message)
                } catch {
                    pendingMessages.removeValue(forKey: message.id)
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func subscribe<T: WebSocketMessage>(
        to messageType: T.Type,
        handler: @escaping (T) async -> Void
    ) -> UUID {
        let subscriptionId = UUID()
        let typeName = String(describing: messageType)
        
        let wrappedHandler: (WebSocketMessage) async -> Void = { message in
            if let typedMessage = message as? T {
                await handler(typedMessage)
            }
        }
        
        if subscriptions[typeName] == nil {
            subscriptions[typeName] = []
        }
        
        subscriptions[typeName]?.append(wrappedHandler)
        
        return subscriptionId
    }
    
    func unsubscribe(from messageType: String, subscriptionId: UUID) {
        
    }
    
    func broadcast<T: WebSocketMessage>(_ message: T, to subscribers: [String] = []) async {
        for subscription in subscribers {
            if let handlers = subscriptions[subscription] {
                for handler in handlers {
                    await handler(message)
                }
            }
        }
    }
    
    func getConnectionInfo() -> [String: Any] {
        return [
            "state": state.rawValue,
            "isConnected": isConnected,
            "reconnectAttempts": reconnectAttempts,
            "messageQueueSize": messageQueue.count,
            "activeSubscriptions": subscriptions.count,
            "url": configuration?.url.absoluteString ?? "N/A"
        ]
    }
    
    private func waitForConnection() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: UInt64((configuration?.timeoutInterval ?? 30) * 1_000_000_000))
                continuation.resume(throwing: WebSocketError.connectionTimeout)
            }
            
            Task {
                do {
                    let message = try await webSocketTask?.receive()
                    timeoutTask.cancel()
                    continuation.resume()
                } catch {
                    timeoutTask.cancel()
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func sendMessage<T: WebSocketMessage>(_ message: T) async throws {
        guard let webSocketTask = webSocketTask else {
            throw WebSocketError.connectionFailed(NSError(domain: "WebSocket", code: -1))
        }
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        do {
            let data = try encoder.encode(message)
            
            if data.count > configuration?.maxMessageSize ?? 1024 * 1024 {
                throw WebSocketError.messageEncodingFailed
            }
            
            let compressedData = compressionEnabled ? try compress(data) : data
            let urlMessage = URLSessionWebSocketTask.Message.data(compressedData)
            
            try await webSocketTask.send(urlMessage)
            
            await updateSentMetrics(data.count)
            
        } catch {
            throw WebSocketError.messageEncodingFailed
        }
    }
    
    private func startListening() {
        Task {
            while state == .connected {
                do {
                    guard let webSocketTask = webSocketTask else { break }
                    
                    let message = try await webSocketTask.receive()
                    await handleReceivedMessage(message)
                    
                } catch {
                    if state == .connected {
                        await handleConnectionError(error)
                    }
                    break
                }
            }
        }
    }
    
    private func handleReceivedMessage(_ message: URLSessionWebSocketTask.Message) async {
        do {
            let data: Data
            
            switch message {
            case .data(let messageData):
                data = compressionEnabled ? try decompress(messageData) : messageData
            case .string(let messageString):
                data = messageString.data(using: .utf8) ?? Data()
            @unknown default:
                return
            }
            
            await updateReceivedMetrics(data.count)
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            if let textMessage = try? decoder.decode(TextMessage.self, from: data) {
                await notifySubscribers(textMessage)
            } else if let binaryMessage = try? decoder.decode(BinaryMessage.self, from: data) {
                await notifySubscribers(binaryMessage)
            } else if let controlMessage = try? decoder.decode(ControlMessage.self, from: data) {
                await handleControlMessage(controlMessage)
            }
            
        } catch {
            await updateErrorMetrics()
        }
    }
    
    private func handleControlMessage(_ message: ControlMessage) async {
        switch message.command {
        case .ping:
            let pong = ControlMessage(command: .pong)
            try? await send(pong)
        case .pong:
            await updateLatencyMetrics(message)
        case .heartbeat:
            break
        case .close:
            await disconnect()
        default:
            await notifySubscribers(message)
        }
    }
    
    private func notifySubscribers<T: WebSocketMessage>(_ message: T) async {
        let typeName = String(describing: type(of: message))
        
        if let handlers = subscriptions[typeName] {
            for handler in handlers {
                await handler(message)
            }
        }
        
        if let continuation = pendingMessages.removeValue(forKey: message.id) {
            continuation.1.resume()
        }
    }
    
    private func startHeartbeat() {
        guard let interval = configuration?.heartbeatInterval else { return }
        
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task {
                let heartbeat = ControlMessage(command: .heartbeat)
                try? await self.send(heartbeat)
            }
        }
    }
    
    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }
    
    private func handleConnectionError(_ error: Error) async {
        await updateState(.error)
        await updateErrorMetrics()
        
        if reconnectAttempts < (configuration?.maxReconnectAttempts ?? 5) {
            await scheduleReconnect()
        }
    }
    
    private func scheduleReconnect() async {
        await updateState(.reconnecting)
        reconnectAttempts += 1
        
        let delay = configuration?.reconnectDelay ?? 2.0
        
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            Task {
                try? await self.connect()
            }
        }
    }
    
    private func stopReconnectTimer() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }
    
    private func processMessageQueue() async {
        while !messageQueue.isEmpty && state == .connected {
            let (message, _) = messageQueue.removeFirst()
            try? await sendMessage(message)
        }
    }
    
    private func compress(_ data: Data) throws -> Data {
        return try (data as NSData).compressed(using: .lzfse) as Data
    }
    
    private func decompress(_ data: Data) throws -> Data {
        return try (data as NSData).decompressed(using: .lzfse) as Data
    }
    
    private func updateState(_ newState: WebSocketState) async {
        await MainActor.run {
            state = newState
            isConnected = newState == .connected
        }
    }
    
    private func updateConnectionMetrics() async {
        await MainActor.run {
            metrics.connectionCount += 1
            metrics.lastConnectionTime = Date()
            reconnectAttempts = 0
        }
    }
    
    private func updateSentMetrics(_ bytes: Int) async {
        await MainActor.run {
            metrics.messagesSent += 1
            metrics.bytesTransferred += bytes
        }
    }
    
    private func updateReceivedMetrics(_ bytes: Int) async {
        await MainActor.run {
            metrics.messagesReceived += 1
            metrics.bytesTransferred += bytes
        }
    }
    
    private func updateErrorMetrics() async {
        await MainActor.run {
            metrics.errorCount += 1
        }
    }
    
    private func updateLatencyMetrics(_ message: ControlMessage) async {
        let latency = Date().timeIntervalSince(message.timestamp)
        
        await MainActor.run {
            let totalMessages = metrics.messagesSent + metrics.messagesReceived
            if totalMessages > 0 {
                metrics.averageLatency = (
                    (metrics.averageLatency * Double(totalMessages - 1)) + latency
                ) / Double(totalMessages)
            }
        }
    }
}

class RateLimiter {
    private let maxRequests: Int
    private let timeWindow: TimeInterval
    private var requestTimes: [Date] = []
    private let lock = NSLock()
    
    init(maxRequests: Int, timeWindow: TimeInterval) {
        self.maxRequests = maxRequests
        self.timeWindow = timeWindow
    }
    
    func allowRequest() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        let now = Date()
        let cutoff = now.addingTimeInterval(-timeWindow)
        
        requestTimes = requestTimes.filter { $0 > cutoff }
        
        if requestTimes.count < maxRequests {
            requestTimes.append(now)
            return true
        }
        
        return false
    }
}

extension WebSocketManager {
    func sendText(_ content: String, sender: String, metadata: [String: String] = [:]) async throws {
        let message = TextMessage(content: content, sender: sender, metadata: metadata)
        try await send(message)
    }
    
    func sendBinary(_ data: Data, encoding: String = "base64") async throws {
        let message = BinaryMessage(data: data, encoding: encoding)
        try await send(message)
    }
    
    func sendControl(_ command: ControlCommand, parameters: [String: Any] = [:]) async throws {
        let message = ControlMessage(command: command, parameters: parameters)
        try await send(message)
    }
    
    func subscribeToTextMessages(handler: @escaping (TextMessage) async -> Void) -> UUID {
        return subscribe(to: TextMessage.self, handler: handler)
    }
    
    func subscribeToBinaryMessages(handler: @escaping (BinaryMessage) async -> Void) -> UUID {
        return subscribe(to: BinaryMessage.self, handler: handler)
    }
    
    func subscribeToControlMessages(handler: @escaping (ControlMessage) async -> Void) -> UUID {
        return subscribe(to: ControlMessage.self, handler: handler)
    }
}

class WebSocketPool {
    private var connections: [String: WebSocketManager] = [:]
    private let lock = NSLock()
    
    func getConnection(for identifier: String, configuration: WebSocketConfiguration) -> WebSocketManager {
        lock.lock()
        defer { lock.unlock() }
        
        if let existing = connections[identifier] {
            return existing
        }
        
        let manager = WebSocketManager()
        manager.configure(configuration)
        connections[identifier] = manager
        
        return manager
    }
    
    func removeConnection(for identifier: String) {
        lock.lock()
        defer { lock.unlock() }
        
        if let manager = connections.removeValue(forKey: identifier) {
            Task {
                await manager.disconnect()
            }
        }
    }
    
    func disconnectAll() {
        lock.lock()
        let allConnections = connections
        connections.removeAll()
        lock.unlock()
        
        for (_, manager) in allConnections {
            Task {
                await manager.disconnect()
            }
        }
    }
}