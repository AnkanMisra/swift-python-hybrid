import Foundation
import Combine

protocol Event {
    var id: UUID { get }
    var timestamp: Date { get }
    var eventType: String { get }
}

protocol EventHandler {
    associatedtype EventType: Event
    func handle(_ event: EventType) async
}

struct BaseEvent: Event {
    let id: UUID
    let timestamp: Date
    let eventType: String
    let payload: [String: Any]
    
    init(eventType: String, payload: [String: Any] = [:]) {
        self.id = UUID()
        self.timestamp = Date()
        self.eventType = eventType
        self.payload = payload
    }
}

struct UserEvent: Event {
    let id: UUID
    let timestamp: Date
    let eventType: String
    let userId: String
    let action: UserAction
    let metadata: [String: Any]
    
    init(userId: String, action: UserAction, metadata: [String: Any] = [:]) {
        self.id = UUID()
        self.timestamp = Date()
        self.eventType = "user_event"
        self.userId = userId
        self.action = action
        self.metadata = metadata
    }
}

struct SystemEvent: Event {
    let id: UUID
    let timestamp: Date
    let eventType: String
    let level: SystemLevel
    let message: String
    let source: String
    
    init(level: SystemLevel, message: String, source: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.eventType = "system_event"
        self.level = level
        self.message = message
        self.source = source
    }
}

enum UserAction: String, CaseIterable {
    case login = "login"
    case logout = "logout"
    case profileUpdate = "profile_update"
    case passwordChange = "password_change"
    case dataExport = "data_export"
    case accountDeletion = "account_deletion"
}

enum SystemLevel: String, CaseIterable {
    case debug = "debug"
    case info = "info"
    case warning = "warning"
    case error = "error"
    case critical = "critical"
}

enum EventPriority: Int, CaseIterable {
    case low = 1
    case normal = 2
    case high = 3
    case critical = 4
}

struct EventSubscription {
    let id: UUID
    let eventType: String
    let priority: EventPriority
    let handler: (Event) async -> Void
    let filter: ((Event) -> Bool)?
    let isOneTime: Bool
    let createdAt: Date
    
    init(
        eventType: String,
        priority: EventPriority = .normal,
        handler: @escaping (Event) async -> Void,
        filter: ((Event) -> Bool)? = nil,
        isOneTime: Bool = false
    ) {
        self.id = UUID()
        self.eventType = eventType
        self.priority = priority
        self.handler = handler
        self.filter = filter
        self.isOneTime = isOneTime
        self.createdAt = Date()
    }
}

struct EventMetrics {
    var totalEvents: Int = 0
    var eventsByType: [String: Int] = [:]
    var averageProcessingTime: TimeInterval = 0
    var failedEvents: Int = 0
    var activeSubscriptions: Int = 0
    var lastEventTime: Date?
}

actor EventBus {
    static let shared = EventBus()
    
    private var subscriptions: [String: [EventSubscription]] = [:]
    private var eventHistory: [Event] = []
    private var metrics: EventMetrics = EventMetrics()
    private var isProcessing: Bool = false
    private var eventQueue: [(Event, EventPriority)] = []
    private var maxHistorySize: Int = 1000
    private var processingTask: Task<Void, Never>?
    
    private init() {
        startProcessing()
    }
    
    func subscribe<T: Event>(
        to eventType: T.Type,
        priority: EventPriority = .normal,
        filter: ((T) -> Bool)? = nil,
        isOneTime: Bool = false,
        handler: @escaping (T) async -> Void
    ) -> UUID {
        let eventTypeName = String(describing: eventType)
        
        let subscription = EventSubscription(
            eventType: eventTypeName,
            priority: priority,
            handler: { event in
                if let typedEvent = event as? T {
                    if let filter = filter {
                        if filter(typedEvent) {
                            await handler(typedEvent)
                        }
                    } else {
                        await handler(typedEvent)
                    }
                }
            },
            filter: filter != nil ? { event in
                if let typedEvent = event as? T {
                    return filter!(typedEvent)
                }
                return false
            } : nil,
            isOneTime: isOneTime
        )
        
        if subscriptions[eventTypeName] == nil {
            subscriptions[eventTypeName] = []
        }
        
        subscriptions[eventTypeName]?.append(subscription)
        subscriptions[eventTypeName]?.sort { $0.priority.rawValue > $1.priority.rawValue }
        
        metrics.activeSubscriptions += 1
        
        return subscription.id
    }
    
    func unsubscribe(_ subscriptionId: UUID) {
        for (eventType, subs) in subscriptions {
            if let index = subs.firstIndex(where: { $0.id == subscriptionId }) {
                subscriptions[eventType]?.remove(at: index)
                metrics.activeSubscriptions -= 1
                
                if subscriptions[eventType]?.isEmpty == true {
                    subscriptions.removeValue(forKey: eventType)
                }
                break
            }
        }
    }
    
    func publish<T: Event>(_ event: T, priority: EventPriority = .normal) {
        eventQueue.append((event, priority))
        eventQueue.sort { $0.1.rawValue > $1.1.rawValue }
        
        metrics.totalEvents += 1
        metrics.eventsByType[event.eventType, default: 0] += 1
        metrics.lastEventTime = event.timestamp
        
        addToHistory(event)
    }
    
    func publishAndWait<T: Event>(_ event: T, priority: EventPriority = .normal) async {
        await processEvent(event)
    }
    
    func getSubscriptionCount(for eventType: String) -> Int {
        return subscriptions[eventType]?.count ?? 0
    }
    
    func getMetrics() -> EventMetrics {
        return metrics
    }
    
    func getEventHistory(limit: Int = 100) -> [Event] {
        return Array(eventHistory.suffix(limit))
    }
    
    func clearHistory() {
        eventHistory.removeAll()
    }
    
    func clearSubscriptions() {
        subscriptions.removeAll()
        metrics.activeSubscriptions = 0
    }
    
    private func startProcessing() {
        processingTask = Task {
            while !Task.isCancelled {
                await processNextEvent()
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }
    }
    
    private func processNextEvent() async {
        guard !eventQueue.isEmpty else { return }
        
        let (event, _) = eventQueue.removeFirst()
        await processEvent(event)
    }
    
    private func processEvent(_ event: Event) async {
        let startTime = Date()
        let eventTypeName = String(describing: type(of: event))
        
        guard let eventSubscriptions = subscriptions[eventTypeName] else {
            return
        }
        
        var subscriptionsToRemove: [UUID] = []
        
        for subscription in eventSubscriptions {
            do {
                if let filter = subscription.filter {
                    if filter(event) {
                        await subscription.handler(event)
                    }
                } else {
                    await subscription.handler(event)
                }
                
                if subscription.isOneTime {
                    subscriptionsToRemove.append(subscription.id)
                }
            } catch {
                metrics.failedEvents += 1
            }
        }
        
        for subscriptionId in subscriptionsToRemove {
            unsubscribe(subscriptionId)
        }
        
        let processingTime = Date().timeIntervalSince(startTime)
        updateAverageProcessingTime(processingTime)
    }
    
    private func addToHistory(_ event: Event) {
        eventHistory.append(event)
        
        if eventHistory.count > maxHistorySize {
            eventHistory.removeFirst(eventHistory.count - maxHistorySize)
        }
    }
    
    private func updateAverageProcessingTime(_ newTime: TimeInterval) {
        let totalProcessed = metrics.totalEvents - metrics.failedEvents
        if totalProcessed > 0 {
            metrics.averageProcessingTime = (
                (metrics.averageProcessingTime * Double(totalProcessed - 1)) + newTime
            ) / Double(totalProcessed)
        }
    }
    
    deinit {
        processingTask?.cancel()
    }
}

class EventBusObservable: ObservableObject {
    @Published var metrics: EventMetrics = EventMetrics()
    @Published var recentEvents: [Event] = []
    
    private let eventBus = EventBus.shared
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
        let currentMetrics = await eventBus.getMetrics()
        let currentHistory = await eventBus.getEventHistory(limit: 10)
        
        DispatchQueue.main.async {
            self.metrics = currentMetrics
            self.recentEvents = currentHistory
        }
    }
    
    deinit {
        updateTimer?.invalidate()
    }
}

extension EventBus {
    func subscribeToUserEvents(
        userId: String? = nil,
        actions: [UserAction]? = nil,
        handler: @escaping (UserEvent) async -> Void
    ) -> UUID {
        return subscribe(
            to: UserEvent.self,
            filter: { event in
                if let userId = userId, event.userId != userId {
                    return false
                }
                if let actions = actions, !actions.contains(event.action) {
                    return false
                }
                return true
            },
            handler: handler
        )
    }
    
    func subscribeToSystemEvents(
        level: SystemLevel? = nil,
        source: String? = nil,
        handler: @escaping (SystemEvent) async -> Void
    ) -> UUID {
        return subscribe(
            to: SystemEvent.self,
            filter: { event in
                if let level = level, event.level != level {
                    return false
                }
                if let source = source, event.source != source {
                    return false
                }
                return true
            },
            handler: handler
        )
    }
    
    func publishUserEvent(
        userId: String,
        action: UserAction,
        metadata: [String: Any] = [:]
    ) {
        let event = UserEvent(userId: userId, action: action, metadata: metadata)
        publish(event)
    }
    
    func publishSystemEvent(
        level: SystemLevel,
        message: String,
        source: String
    ) {
        let event = SystemEvent(level: level, message: message, source: source)
        publish(event, priority: level == .critical ? .critical : .normal)
    }
}

struct EventBusMiddleware {
    static func loggingMiddleware() -> (Event) async -> Void {
        return { event in
            print("[EventBus] \(event.timestamp): \(event.eventType) - \(event.id)")
        }
    }
    
    static func analyticsMiddleware() -> (Event) async -> Void {
        return { event in
            
        }
    }
    
    static func persistenceMiddleware() -> (Event) async -> Void {
        return { event in
            
        }
    }
}

struct EventPattern {
    static func createSequencePattern(
        events: [String],
        timeWindow: TimeInterval,
        handler: @escaping ([Event]) -> Void
    ) -> UUID {
        var collectedEvents: [Event] = []
        var startTime: Date?
        
        return EventBus.shared.subscribe(
            to: BaseEvent.self,
            handler: { event in
                if events.contains(event.eventType) {
                    if startTime == nil {
                        startTime = event.timestamp
                        collectedEvents = [event]
                    } else if event.timestamp.timeIntervalSince(startTime!) <= timeWindow {
                        collectedEvents.append(event)
                        
                        if collectedEvents.count == events.count {
                            handler(collectedEvents)
                            collectedEvents.removeAll()
                            startTime = nil
                        }
                    } else {
                        collectedEvents = [event]
                        startTime = event.timestamp
                    }
                }
            }
        )
    }
}