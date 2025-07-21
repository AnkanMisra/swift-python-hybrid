import Foundation
import Combine
import os.log


class AnalyticsManager: ObservableObject {
    
    
    static let shared = AnalyticsManager()
    
    @Published var isEnabled = true
    @Published var isOnline = true
    @Published var trackingConsent = false
    @Published var debugMode = false
    
    private let eventQueue: DispatchQueue
    private let networkQueue: DispatchQueue
    private let storageQueue: DispatchQueue
    
    private var eventBuffer: [AnalyticsEvent] = []
    private var sessionData: SessionData
    private var userProperties: [String: Any] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    private let maxBufferSize = 1000
    private let batchSize = 50
    private let flushInterval: TimeInterval = 30.0
    private let sessionTimeout: TimeInterval = 1800.0 
    
    private var flushTimer: Timer?
    private var sessionTimer: Timer?
    
    
    private var providers: [AnalyticsProvider] = []
    
    
    private init() {
        self.eventQueue = DispatchQueue(label: "com.app.analytics.events", qos: .utility)
        self.networkQueue = DispatchQueue(label: "com.app.analytics.network", qos: .background)
        self.storageQueue = DispatchQueue(label: "com.app.analytics.storage", qos: .utility)
        
        self.sessionData = SessionData()
        
        setupAnalytics()
        setupProviders()
        setupNotifications()
        startFlushTimer()
        startSession()
    }
    
    private func setupAnalytics() {
        
        isEnabled = UserDefaults.standard.bool(forKey: "analytics_enabled")
        trackingConsent = UserDefaults.standard.bool(forKey: "tracking_consent")
        debugMode = UserDefaults.standard.bool(forKey: "analytics_debug_mode")
        
        
        if let savedProperties = UserDefaults.standard.dictionary(forKey: "analytics_user_properties") {
            userProperties = savedProperties
        }
        
        
        loadBufferedEvents()
    }
    
    private func setupProviders() {
        
        providers.append(FirebaseAnalyticsProvider())
        providers.append(MixpanelProvider())
        providers.append(AmplitudeProvider())
        providers.append(CustomAnalyticsProvider())
        
        
        providers.forEach { provider in
            provider.configure(
                enabled: isEnabled,
                debugMode: debugMode,
                trackingConsent: trackingConsent
            )
        }
    }
    
    private func setupNotifications() {
        
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
        
        NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)
            .sink { _ in
                self.handleAppWillTerminate()
            }
            .store(in: &cancellables)
        
        
        NotificationCenter.default.publisher(for: .networkConnectivityChanged)
            .sink { notification in
                if let isConnected = notification.object as? Bool {
                    self.isOnline = isConnected
                    if isConnected {
                        self.flushEvents()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    
    func enableAnalytics(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "analytics_enabled")
        
        providers.forEach { provider in
            provider.setEnabled(enabled)
        }
        
        if enabled {
            track(event: AnalyticsEvents.analyticsEnabled)
        }
    }
    
    func setTrackingConsent(_ consent: Bool) {
        trackingConsent = consent
        UserDefaults.standard.set(consent, forKey: "tracking_consent")
        
        providers.forEach { provider in
            provider.setTrackingConsent(consent)
        }
        
        if consent {
            track(event: AnalyticsEvents.trackingConsentGranted)
        }
    }
    
    func setDebugMode(_ debug: Bool) {
        debugMode = debug
        UserDefaults.standard.set(debug, forKey: "analytics_debug_mode")
        
        providers.forEach { provider in
            provider.setDebugMode(debug)
        }
    }
    
    
    func track(event: String, parameters: [String: Any]? = nil) {
        guard isEnabled && trackingConsent else { return }
        
        eventQueue.async {
            let analyticsEvent = AnalyticsEvent(
                name: event,
                parameters: parameters ?? [:],
                timestamp: Date(),
                sessionId: self.sessionData.id,
                userId: self.sessionData.userId
            )
            
            self.addEventToBuffer(analyticsEvent)
            
            if self.debugMode {
                self.logEvent(analyticsEvent)
            }
        }
    }
    
    func track(event: AnalyticsEvent) {
        guard isEnabled && trackingConsent else { return }
        
        eventQueue.async {
            var mutableEvent = event
            mutableEvent.sessionId = self.sessionData.id
            mutableEvent.userId = self.sessionData.userId
            mutableEvent.timestamp = Date()
            
            self.addEventToBuffer(mutableEvent)
            
            if self.debugMode {
                self.logEvent(mutableEvent)
            }
        }
    }
    
    func trackScreen(name: String, parameters: [String: Any]? = nil) {
        var params = parameters ?? [:]
        params["screen_name"] = name
        params["screen_class"] = name
        
        track(event: AnalyticsEvents.screenView, parameters: params)
    }
    
    func trackUserAction(action: String, target: String? = nil, parameters: [String: Any]? = nil) {
        var params = parameters ?? [:]
        params["action"] = action
        if let target = target {
            params["target"] = target
        }
        
        track(event: AnalyticsEvents.userAction, parameters: params)
    }
    
    func trackError(error: Error, context: String? = nil) {
        var params: [String: Any] = [
            "error_message": error.localizedDescription,
            "error_code": (error as NSError).code,
            "error_domain": (error as NSError).domain
        ]
        
        if let context = context {
            params["error_context"] = context
        }
        
        track(event: AnalyticsEvents.error, parameters: params)
    }
    
    func trackTiming(category: String, name: String, duration: TimeInterval, parameters: [String: Any]? = nil) {
        var params = parameters ?? [:]
        params["timing_category"] = category
        params["timing_name"] = name
        params["timing_duration"] = duration
        
        track(event: AnalyticsEvents.timing, parameters: params)
    }
    
    func trackCustomEvent(name: String, category: String, parameters: [String: Any]? = nil) {
        var params = parameters ?? [:]
        params["event_category"] = category
        
        track(event: name, parameters: params)
    }
    
    
    func setUserProperty(key: String, value: Any) {
        userProperties[key] = value
        saveUserProperties()
        
        providers.forEach { provider in
            provider.setUserProperty(key: key, value: value)
        }
    }
    
    func setUserProperties(_ properties: [String: Any]) {
        userProperties.merge(properties) { _, new in new }
        saveUserProperties()
        
        providers.forEach { provider in
            provider.setUserProperties(properties)
        }
    }
    
    func setUserId(_ userId: String) {
        sessionData.userId = userId
        setUserProperty(key: "user_id", value: userId)
        
        providers.forEach { provider in
            provider.setUserId(userId)
        }
    }
    
    func clearUserProperties() {
        userProperties.removeAll()
        saveUserProperties()
        
        providers.forEach { provider in
            provider.clearUserProperties()
        }
    }
    
    
    private func startSession() {
        sessionData = SessionData()
        track(event: AnalyticsEvents.sessionStart)
        
        sessionTimer = Timer.scheduledTimer(withTimeInterval: sessionTimeout, repeats: false) { _ in
            self.endSession()
        }
    }
    
    private func endSession() {
        track(event: AnalyticsEvents.sessionEnd, parameters: [
            "session_duration": sessionData.duration
        ])
        
        flushEvents()
        sessionTimer?.invalidate()
    }
    
    private func extendSession() {
        sessionTimer?.invalidate()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: sessionTimeout, repeats: false) { _ in
            self.endSession()
        }
    }
    
    
    private func addEventToBuffer(_ event: AnalyticsEvent) {
        eventBuffer.append(event)
        
        if eventBuffer.count >= maxBufferSize {
            
            eventBuffer.removeFirst(eventBuffer.count - maxBufferSize + 1)
        }
        
        if eventBuffer.count >= batchSize {
            flushEvents()
        }
        
        
        if eventBuffer.count % 10 == 0 {
            saveBufferedEvents()
        }
    }
    
    private func flushEvents() {
        guard !eventBuffer.isEmpty && isOnline else { return }
        
        networkQueue.async {
            let eventsToFlush = Array(self.eventBuffer.prefix(self.batchSize))
            
            self.providers.forEach { provider in
                provider.sendEvents(eventsToFlush) { [weak self] success in
                    if success {
                        DispatchQueue.main.async {
                            self?.eventBuffer.removeFirst(min(eventsToFlush.count, self?.eventBuffer.count ?? 0))
                            self?.saveBufferedEvents()
                        }
                    }
                }
            }
        }
    }
    
    private func startFlushTimer() {
        flushTimer = Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true) { _ in
            self.flushEvents()
        }
    }
    
    
    private func saveBufferedEvents() {
        storageQueue.async {
            do {
                let data = try JSONEncoder().encode(self.eventBuffer)
                UserDefaults.standard.set(data, forKey: "analytics_buffered_events")
            } catch {
                if self.debugMode {
                    print("Failed to save buffered events: \(error)")
                }
            }
        }
    }
    
    private func loadBufferedEvents() {
        storageQueue.async {
            guard let data = UserDefaults.standard.data(forKey: "analytics_buffered_events") else { return }
            
            do {
                let events = try JSONDecoder().decode([AnalyticsEvent].self, from: data)
                DispatchQueue.main.async {
                    self.eventBuffer = events
                }
            } catch {
                if self.debugMode {
                    print("Failed to load buffered events: \(error)")
                }
            }
        }
    }
    
    private func saveUserProperties() {
        UserDefaults.standard.set(userProperties, forKey: "analytics_user_properties")
    }
    
    
    func startTiming(for identifier: String) -> TimingTracker {
        return TimingTracker(identifier: identifier, analyticsManager: self)
    }
    
    func trackPerformance(operation: String, block: () throws -> Void) rethrows {
        let startTime = CFAbsoluteTimeGetCurrent()
        try block()
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        
        trackTiming(category: "performance", name: operation, duration: duration)
    }
    
    func trackMemoryUsage() {
        let memoryInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let result = withUnsafeMutablePointer(to: &memoryInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let memoryUsage = memoryInfo.resident_size
            track(event: AnalyticsEvents.memoryUsage, parameters: [
                "memory_usage_bytes": memoryUsage,
                "memory_usage_mb": Double(memoryUsage) / 1024.0 / 1024.0
            ])
        }
    }
    
    
    func trackExperiment(name: String, variant: String, parameters: [String: Any]? = nil) {
        var params = parameters ?? [:]
        params["experiment_name"] = name
        params["experiment_variant"] = variant
        
        track(event: AnalyticsEvents.experiment, parameters: params)
    }
    
    func trackConversion(experimentName: String, variant: String, conversionType: String) {
        track(event: AnalyticsEvents.conversion, parameters: [
            "experiment_name": experimentName,
            "experiment_variant": variant,
            "conversion_type": conversionType
        ])
    }
    
    
    func trackFunnelStep(funnel: String, step: String, stepIndex: Int, parameters: [String: Any]? = nil) {
        var params = parameters ?? [:]
        params["funnel_name"] = funnel
        params["funnel_step"] = step
        params["funnel_step_index"] = stepIndex
        
        track(event: AnalyticsEvents.funnelStep, parameters: params)
    }
    
    
    func trackCohortEvent(cohort: String, event: String, parameters: [String: Any]? = nil) {
        var params = parameters ?? [:]
        params["cohort"] = cohort
        params["cohort_event"] = event
        
        track(event: AnalyticsEvents.cohort, parameters: params)
    }
    
    
    func trackRevenue(amount: Double, currency: String, productId: String? = nil, parameters: [String: Any]? = nil) {
        var params = parameters ?? [:]
        params["revenue_amount"] = amount
        params["revenue_currency"] = currency
        
        if let productId = productId {
            params["product_id"] = productId
        }
        
        track(event: AnalyticsEvents.revenue, parameters: params)
    }
    
    
    func trackAttribution(source: String, medium: String, campaign: String? = nil) {
        var params: [String: Any] = [
            "attribution_source": source,
            "attribution_medium": medium
        ]
        
        if let campaign = campaign {
            params["attribution_campaign"] = campaign
        }
        
        track(event: AnalyticsEvents.attribution, parameters: params)
        setUserProperties(params)
    }
    
    
    private func handleAppDidEnterBackground() {
        track(event: AnalyticsEvents.appBackground)
        flushEvents()
    }
    
    private func handleAppWillEnterForeground() {
        track(event: AnalyticsEvents.appForeground)
        extendSession()
    }
    
    private func handleAppWillTerminate() {
        endSession()
    }
    
    
    private func logEvent(_ event: AnalyticsEvent) {
        if #available(iOS 14.0, *) {
            let logger = Logger(subsystem: "com.app.analytics", category: "events")
            logger.info("Analytics Event: \(event.name) - \(event.parameters)")
        } else {
            print("Analytics Event: \(event.name) - \(event.parameters)")
        }
    }
    
    func exportAnalyticsData() -> [String: Any] {
        return [
            "events": eventBuffer.map { $0.toDictionary() },
            "session": sessionData.toDictionary(),
            "user_properties": userProperties,
            "settings": [
                "enabled": isEnabled,
                "tracking_consent": trackingConsent,
                "debug_mode": debugMode
            ]
        ]
    }
    
    
    deinit {
        flushTimer?.invalidate()
        sessionTimer?.invalidate()
        flushEvents()
    }
}


struct AnalyticsEvent: Codable {
    let id: String
    let name: String
    let parameters: [String: AnyCodable]
    var timestamp: Date
    var sessionId: String
    var userId: String?
    
    init(name: String, parameters: [String: Any], timestamp: Date, sessionId: String, userId: String? = nil) {
        self.id = UUID().uuidString
        self.name = name
        self.parameters = parameters.mapValues { AnyCodable($0) }
        self.timestamp = timestamp
        self.sessionId = sessionId
        self.userId = userId
    }
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "name": name,
            "timestamp": timestamp.timeIntervalSince1970,
            "session_id": sessionId
        ]
        
        if let userId = userId {
            dict["user_id"] = userId
        }
        
        dict["parameters"] = parameters.mapValues { $0.value }
        
        return dict
    }
}

struct SessionData {
    let id: String
    let startTime: Date
    var userId: String?
    
    init() {
        self.id = UUID().uuidString
        self.startTime = Date()
    }
    
    var duration: TimeInterval {
        return Date().timeIntervalSince(startTime)
    }
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "start_time": startTime.timeIntervalSince1970,
            "duration": duration
        ]
        
        if let userId = userId {
            dict["user_id"] = userId
        }
        
        return dict
    }
}

struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else if let dictValue = try? container.decode([String: AnyCodable].self) {
            value = dictValue.mapValues { $0.value }
        } else {
            throw DecodingError.typeMismatch(AnyCodable.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let intValue as Int:
            try container.encode(intValue)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let stringValue as String:
            try container.encode(stringValue)
        case let boolValue as Bool:
            try container.encode(boolValue)
        case let arrayValue as [Any]:
            try container.encode(arrayValue.map { AnyCodable($0) })
        case let dictValue as [String: Any]:
            try container.encode(dictValue.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
}

class TimingTracker {
    private let identifier: String
    private let startTime: CFAbsoluteTime
    private weak var analyticsManager: AnalyticsManager?
    
    init(identifier: String, analyticsManager: AnalyticsManager) {
        self.identifier = identifier
        self.startTime = CFAbsoluteTimeGetCurrent()
        self.analyticsManager = analyticsManager
    }
    
    func stop(parameters: [String: Any]? = nil) {
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        analyticsManager?.trackTiming(category: "custom", name: identifier, duration: duration, parameters: parameters)
    }
}


protocol AnalyticsProvider {
    func configure(enabled: Bool, debugMode: Bool, trackingConsent: Bool)
    func setEnabled(_ enabled: Bool)
    func setDebugMode(_ debug: Bool)
    func setTrackingConsent(_ consent: Bool)
    func sendEvents(_ events: [AnalyticsEvent], completion: @escaping (Bool) -> Void)
    func setUserProperty(key: String, value: Any)
    func setUserProperties(_ properties: [String: Any])
    func setUserId(_ userId: String)
    func clearUserProperties()
}

class FirebaseAnalyticsProvider: AnalyticsProvider {
    private var isEnabled = false
    
    func configure(enabled: Bool, debugMode: Bool, trackingConsent: Bool) {
        self.isEnabled = enabled
        
    }
    
    func setEnabled(_ enabled: Bool) {
        self.isEnabled = enabled
    }
    
    func setDebugMode(_ debug: Bool) {
        
    }
    
    func setTrackingConsent(_ consent: Bool) {
        
    }
    
    func sendEvents(_ events: [AnalyticsEvent], completion: @escaping (Bool) -> Void) {
        guard isEnabled else {
            completion(false)
            return
        }
        
        
        completion(true)
    }
    
    func setUserProperty(key: String, value: Any) {
        
    }
    
    func setUserProperties(_ properties: [String: Any]) {
        
    }
    
    func setUserId(_ userId: String) {
        
    }
    
    func clearUserProperties() {
        
    }
}

class MixpanelProvider: AnalyticsProvider {
    private var isEnabled = false
    
    func configure(enabled: Bool, debugMode: Bool, trackingConsent: Bool) {
        self.isEnabled = enabled
        
    }
    
    func setEnabled(_ enabled: Bool) {
        self.isEnabled = enabled
    }
    
    func setDebugMode(_ debug: Bool) {
        
    }
    
    func setTrackingConsent(_ consent: Bool) {
        
    }
    
    func sendEvents(_ events: [AnalyticsEvent], completion: @escaping (Bool) -> Void) {
        guard isEnabled else {
            completion(false)
            return
        }
        
        
        completion(true)
    }
    
    func setUserProperty(key: String, value: Any) {
        
    }
    
    func setUserProperties(_ properties: [String: Any]) {
        
    }
    
    func setUserId(_ userId: String) {
        
    }
    
    func clearUserProperties() {
        
    }
}

class AmplitudeProvider: AnalyticsProvider {
    private var isEnabled = false
    
    func configure(enabled: Bool, debugMode: Bool, trackingConsent: Bool) {
        self.isEnabled = enabled
        
    }
    
    func setEnabled(_ enabled: Bool) {
        self.isEnabled = enabled
    }
    
    func setDebugMode(_ debug: Bool) {
        
    }
    
    func setTrackingConsent(_ consent: Bool) {
        
    }
    
    func sendEvents(_ events: [AnalyticsEvent], completion: @escaping (Bool) -> Void) {
        guard isEnabled else {
            completion(false)
            return
        }
        
        
        completion(true)
    }
    
    func setUserProperty(key: String, value: Any) {
        
    }
    
    func setUserProperties(_ properties: [String: Any]) {
        
    }
    
    func setUserId(_ userId: String) {
        
    }
    
    func clearUserProperties() {
        
    }
}

class CustomAnalyticsProvider: AnalyticsProvider {
    private var isEnabled = false
    
    func configure(enabled: Bool, debugMode: Bool, trackingConsent: Bool) {
        self.isEnabled = enabled
        
    }
    
    func setEnabled(_ enabled: Bool) {
        self.isEnabled = enabled
    }
    
    func setDebugMode(_ debug: Bool) {
        
    }
    
    func setTrackingConsent(_ consent: Bool) {
        
    }
    
    func sendEvents(_ events: [AnalyticsEvent], completion: @escaping (Bool) -> Void) {
        guard isEnabled else {
            completion(false)
            return
        }
        
        
        completion(true)
    }
    
    func setUserProperty(key: String, value: Any) {
        
    }
    
    func setUserProperties(_ properties: [String: Any]) {
        
    }
    
    func setUserId(_ userId: String) {
        
    }
    
    func clearUserProperties() {
        
    }
}


struct AnalyticsEvents {
    static let sessionStart = "session_start"
    static let sessionEnd = "session_end"
    static let screenView = "screen_view"
    static let userAction = "user_action"
    static let error = "error"
    static let timing = "timing"
    static let experiment = "experiment"
    static let conversion = "conversion"
    static let funnelStep = "funnel_step"
    static let cohort = "cohort"
    static let revenue = "revenue"
    static let attribution = "attribution"
    static let appBackground = "app_background"
    static let appForeground = "app_foreground"
    static let analyticsEnabled = "analytics_enabled"
    static let trackingConsentGranted = "tracking_consent_granted"
    static let memoryUsage = "memory_usage"
    
    
    static let userLogin = "user_login"
    static let userLogout = "user_logout"
    static let userRegistration = "user_registration"
    static let userProfileUpdate = "user_profile_update"
    
    
    static let productView = "product_view"
    static let addToCart = "add_to_cart"
    static let removeFromCart = "remove_from_cart"
    static let checkout = "checkout"
    static let purchase = "purchase"
    static let refund = "refund"
    
    
    static let contentView = "content_view"
    static let contentShare = "content_share"
    static let contentLike = "content_like"
    static let contentComment = "content_comment"
    
    
    static let search = "search"
    static let searchResult = "search_result"
    static let searchNoResult = "search_no_result"
}


extension Notification.Name {
    static let networkConnectivityChanged = Notification.Name("networkConnectivityChanged")
}
