import Foundation
import UIKit


enum AnalyticsEventType: String, CaseIterable {
    case userLogin = "user_login"
    case userLogout = "user_logout"
    case screenView = "screen_view"
    case buttonTap = "button_tap"
    case purchase = "purchase"
    case search = "search"
    case share = "share"
    case error = "error"
    case performance = "performance"
    case customEvent = "custom_event"
}


protocol AnalyticsEvent {
    var eventType: AnalyticsEventType { get }
    var parameters: [String: Any] { get }
    var timestamp: Date { get }
    var sessionId: String { get }
}


struct StandardAnalyticsEvent: AnalyticsEvent {
    let eventType: AnalyticsEventType
    let parameters: [String: Any]
    let timestamp: Date
    let sessionId: String
    
    init(eventType: AnalyticsEventType, parameters: [String: Any] = [:], sessionId: String) {
        self.eventType = eventType
        self.parameters = parameters
        self.timestamp = Date()
        self.sessionId = sessionId
    }
}


struct UserAnalyticsEvent: AnalyticsEvent {
    let eventType: AnalyticsEventType
    let parameters: [String: Any]
    let timestamp: Date
    let sessionId: String
    let userId: String
    let userProperties: [String: Any]
    
    init(eventType: AnalyticsEventType, parameters: [String: Any] = [:], sessionId: String, userId: String, userProperties: [String: Any] = [:]) {
        self.eventType = eventType
        self.parameters = parameters
        self.timestamp = Date()
        self.sessionId = sessionId
        self.userId = userId
        self.userProperties = userProperties
    }
}


protocol AnalyticsProvider {
    func track(event: AnalyticsEvent)
    func setUserProperties(_ properties: [String: Any])
    func setUserId(_ userId: String)
    func flush()
}


class FirebaseAnalyticsProvider: AnalyticsProvider {
    private var isEnabled: Bool = true
    private var debugMode: Bool = false
    
    init(debugMode: Bool = false) {
        self.debugMode = debugMode
        setupFirebaseAnalytics()
    }
    
    private func setupFirebaseAnalytics() {
        
        if debugMode {
            print("Firebase Analytics initialized in debug mode")
        }
    }
    
    func track(event: AnalyticsEvent) {
        guard isEnabled else { return }
        
        var eventParameters = event.parameters
        eventParameters["timestamp"] = event.timestamp.timeIntervalSince1970
        eventParameters["session_id"] = event.sessionId
        
        
        if debugMode {
            print("Firebase: Tracking event \(event.eventType.rawValue) with parameters: \(eventParameters)")
        }
    }
    
    func setUserProperties(_ properties: [String: Any]) {
        guard isEnabled else { return }
        
        if debugMode {
            print("Firebase: Setting user properties: \(properties)")
        }
    }
    
    func setUserId(_ userId: String) {
        guard isEnabled else { return }
        
        if debugMode {
            print("Firebase: Setting user ID: \(userId)")
        }
    }
    
    func flush() {
        
        if debugMode {
            print("Firebase: Flushing analytics data")
        }
    }
}


class CustomAnalyticsProvider: AnalyticsProvider {
    private var isEnabled: Bool = true
    private var debugMode: Bool = false
    private var apiEndpoint: String
    private var apiKey: String
    
    init(apiEndpoint: String, apiKey: String, debugMode: Bool = false) {
        self.apiEndpoint = apiEndpoint
        self.apiKey = apiKey
        self.debugMode = debugMode
    }
    
    func track(event: AnalyticsEvent) {
        guard isEnabled else { return }
        
        let eventData = [
            "event_type": event.eventType.rawValue,
            "parameters": event.parameters,
            "timestamp": event.timestamp.timeIntervalSince1970,
            "session_id": event.sessionId
        ] as [String: Any]
        
        sendEventToAPI(eventData)
    }
    
    func setUserProperties(_ properties: [String: Any]) {
        guard isEnabled else { return }
        
        let userData = [
            "user_properties": properties,
            "timestamp": Date().timeIntervalSince1970
        ] as [String: Any]
        
        sendUserDataToAPI(userData)
    }
    
    func setUserId(_ userId: String) {
        guard isEnabled else { return }
        
        let userData = [
            "user_id": userId,
            "timestamp": Date().timeIntervalSince1970
        ] as [String: Any]
        
        sendUserDataToAPI(userData)
    }
    
    func flush() {
        
        if debugMode {
            print("Custom Analytics: Flushing analytics data")
        }
    }
    
    private func sendEventToAPI(_ eventData: [String: Any]) {
        guard let url = URL(string: "\(apiEndpoint)/events") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: eventData)
        } catch {
            if debugMode {
                print("Custom Analytics: Failed to serialize event data: \(error)")
            }
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                if self.debugMode {
                    print("Custom Analytics: API request failed: \(error)")
                }
            } else if self.debugMode {
                print("Custom Analytics: Event sent successfully")
            }
        }.resume()
    }
    
    private func sendUserDataToAPI(_ userData: [String: Any]) {
        guard let url = URL(string: "\(apiEndpoint)/user") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: userData)
        } catch {
            if debugMode {
                print("Custom Analytics: Failed to serialize user data: \(error)")
            }
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                if self.debugMode {
                    print("Custom Analytics: User data API request failed: \(error)")
                }
            } else if self.debugMode {
                print("Custom Analytics: User data sent successfully")
            }
        }.resume()
    }
}


class AnalyticsService {
    static let shared = AnalyticsService()
    
    private var providers: [AnalyticsProvider] = []
    private var sessionId: String
    private var userId: String?
    private var userProperties: [String: Any] = [:]
    private var isEnabled: Bool = true
    private var debugMode: Bool = false
    private var eventQueue: [AnalyticsEvent] = []
    private var maxQueueSize: Int = 100
    private var flushInterval: TimeInterval = 60.0
    private var flushTimer: Timer?
    
    private init() {
        self.sessionId = UUID().uuidString
        setupDefaultProviders()
        startFlushTimer()
    }
    
    private func setupDefaultProviders() {
        
        let firebaseProvider = FirebaseAnalyticsProvider(debugMode: debugMode)
        addProvider(firebaseProvider)
    }
    
    func configure(debugMode: Bool = false) {
        self.debugMode = debugMode
        if debugMode {
            print("Analytics Service configured in debug mode")
        }
    }
    
    func addProvider(_ provider: AnalyticsProvider) {
        providers.append(provider)
    }
    
    func removeAllProviders() {
        providers.removeAll()
    }
    
    func setUserId(_ userId: String) {
        self.userId = userId
        providers.forEach { $0.setUserId(userId) }
    }
    
    func setUserProperties(_ properties: [String: Any]) {
        userProperties.merge(properties) { _, new in new }
        providers.forEach { $0.setUserProperties(userProperties) }
    }
    
    func track(eventType: AnalyticsEventType, parameters: [String: Any] = [:]) {
        guard isEnabled else { return }
        
        let event = StandardAnalyticsEvent(
            eventType: eventType,
            parameters: parameters,
            sessionId: sessionId
        )
        
        trackEvent(event)
    }
    
    func trackUserEvent(eventType: AnalyticsEventType, parameters: [String: Any] = [:]) {
        guard isEnabled, let userId = userId else { return }
        
        let event = UserAnalyticsEvent(
            eventType: eventType,
            parameters: parameters,
            sessionId: sessionId,
            userId: userId,
            userProperties: userProperties
        )
        
        trackEvent(event)
    }
    
    func trackScreenView(screenName: String, screenClass: String? = nil) {
        var parameters: [String: Any] = ["screen_name": screenName]
        if let screenClass = screenClass {
            parameters["screen_class"] = screenClass
        }
        
        track(eventType: .screenView, parameters: parameters)
    }
    
    func trackButtonTap(buttonName: String, screenName: String? = nil) {
        var parameters: [String: Any] = ["button_name": buttonName]
        if let screenName = screenName {
            parameters["screen_name"] = screenName
        }
        
        track(eventType: .buttonTap, parameters: parameters)
    }
    
    func trackPurchase(productId: String, price: Double, currency: String = "USD") {
        let parameters: [String: Any] = [
            "product_id": productId,
            "price": price,
            "currency": currency
        ]
        
        track(eventType: .purchase, parameters: parameters)
    }
    
    func trackError(error: Error, context: String? = nil) {
        var parameters: [String: Any] = [
            "error_description": error.localizedDescription,
            "error_domain": (error as NSError).domain,
            "error_code": (error as NSError).code
        ]
        
        if let context = context {
            parameters["context"] = context
        }
        
        track(eventType: .error, parameters: parameters)
    }
    
    func trackPerformance(metric: String, value: Double, unit: String = "ms") {
        let parameters: [String: Any] = [
            "metric": metric,
            "value": value,
            "unit": unit
        ]
        
        track(eventType: .performance, parameters: parameters)
    }
    
    func trackSearch(query: String, category: String? = nil, results: Int? = nil) {
        var parameters: [String: Any] = ["query": query]
        if let category = category {
            parameters["category"] = category
        }
        if let results = results {
            parameters["results_count"] = results
        }
        
        track(eventType: .search, parameters: parameters)
    }
    
    func trackShare(contentType: String, contentId: String, method: String) {
        let parameters: [String: Any] = [
            "content_type": contentType,
            "content_id": contentId,
            "method": method
        ]
        
        track(eventType: .share, parameters: parameters)
    }
    
    private func trackEvent(_ event: AnalyticsEvent) {
        eventQueue.append(event)
        
        if eventQueue.count >= maxQueueSize {
            flushEvents()
        }
        
        if debugMode {
            print("Analytics: Queued event \(event.eventType.rawValue)")
        }
    }
    
    private func flushEvents() {
        guard !eventQueue.isEmpty else { return }
        
        let eventsToFlush = eventQueue
        eventQueue.removeAll()
        
        for event in eventsToFlush {
            providers.forEach { $0.track(event: event) }
        }
        
        providers.forEach { $0.flush() }
        
        if debugMode {
            print("Analytics: Flushed \(eventsToFlush.count) events")
        }
    }
    
    private func startFlushTimer() {
        flushTimer = Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true) { _ in
            self.flushEvents()
        }
    }
    
    func enable() {
        isEnabled = true
    }
    
    func disable() {
        isEnabled = false
        flushEvents()
    }
    
    func startNewSession() {
        sessionId = UUID().uuidString
        if debugMode {
            print("Analytics: Started new session: \(sessionId)")
        }
    }
    
    deinit {
        flushTimer?.invalidate()
        flushEvents()
    }
}


extension AnalyticsService {
    func trackAppLaunch() {
        track(eventType: .customEvent, parameters: ["event_name": "app_launch"])
    }
    
    func trackAppBackground() {
        track(eventType: .customEvent, parameters: ["event_name": "app_background"])
    }
    
    func trackAppForeground() {
        track(eventType: .customEvent, parameters: ["event_name": "app_foreground"])
    }
    
    func trackAppTerminate() {
        track(eventType: .customEvent, parameters: ["event_name": "app_terminate"])
    }
}


extension UIViewController {
    func trackScreenView() {
        let screenName = String(describing: type(of: self))
        AnalyticsService.shared.trackScreenView(screenName: screenName, screenClass: screenName)
    }
    
    func trackButtonTap(_ buttonName: String) {
        let screenName = String(describing: type(of: self))
        AnalyticsService.shared.trackButtonTap(buttonName: buttonName, screenName: screenName)
    }
}
