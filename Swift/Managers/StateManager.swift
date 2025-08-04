import Foundation
import Combine
import SwiftUI

@MainActor
class StateManager: ObservableObject {
    static let shared = StateManager()

    @Published private(set) var appState: AppState = AppState()
    @Published private(set) var userSession: UserSession?
    @Published private(set) var networkState: NetworkState = .idle
    @Published private(set) var loadingStates: [String: Bool] = [:]
    @Published private(set) var errorStates: [String: AppError?] = [:]

    private var stateHistory: [StateSnapshot] = []
    private var cancellables = Set<AnyCancellable>()
    private let maxHistorySize = 50
    private let persistenceKey = "app_state_persistence"

    private init() {
        setupStateObservation()
        loadPersistedState()
    }

    private func setupStateObservation() {
        $appState
            .dropFirst()
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] state in
                self?.saveStateSnapshot(state)
                self?.persistState(state)
            }
            .store(in: &cancellables)
    }

    func updateAppState<T>(
        keyPath: WritableKeyPath<AppState, T>,
        value: T,
        animated: Bool = true
    ) {
        if animated {
            withAnimation(.easeInOut(duration: 0.3)) {
                appState[keyPath: keyPath] = value
            }
        } else {
            appState[keyPath: keyPath] = value
        }
    }

    func updateUserSession(_ session: UserSession?) {
        withAnimation {
            userSession = session
        }

        if let session = session {
            appState.isAuthenticated = true
            appState.currentUserId = session.userId
        } else {
            appState.isAuthenticated = false
            appState.currentUserId = nil
            clearUserSpecificState()
        }
    }

    func setNetworkState(_ state: NetworkState) {
        networkState = state
        appState.isOnline = state == .connected
    }

    func setLoading(_ isLoading: Bool, for key: String) {
        loadingStates[key] = isLoading
        appState.isLoading = loadingStates.values.contains(true)
    }

    func setError(_ error: AppError?, for key: String) {
        errorStates[key] = error
        appState.hasError = errorStates.values.compactMap { $0 }.count > 0
    }

    func clearError(for key: String) {
        errorStates[key] = nil
        appState.hasError = errorStates.values.compactMap { $0 }.count > 0
    }

    func clearAllErrors() {
        errorStates.removeAll()
        appState.hasError = false
    }

    func performStateTransaction<T>(
        _ transaction: (inout AppState) throws -> T
    ) rethrows -> T {
        var mutableState = appState
        let result = try transaction(&mutableState)
        appState = mutableState
        return result
    }

    func undoLastStateChange() {
        guard stateHistory.count > 1 else { return }

        stateHistory.removeLast()
        if let previousSnapshot = stateHistory.last {
            withAnimation {
                appState = previousSnapshot.state
            }
        }
    }

    func resetToInitialState() {
        withAnimation {
            appState = AppState()
            userSession = nil
            networkState = .idle
            loadingStates.removeAll()
            errorStates.removeAll()
        }

        stateHistory.removeAll()
        clearPersistedState()
    }

    private func saveStateSnapshot(_ state: AppState) {
        let snapshot = StateSnapshot(state: state, timestamp: Date())
        stateHistory.append(snapshot)

        if stateHistory.count > maxHistorySize {
            stateHistory.removeFirst()
        }
    }

    private func clearUserSpecificState() {
        appState.selectedItems.removeAll()
        appState.preferences = UserPreferences()
        appState.notifications.removeAll()
    }

    private func persistState(_ state: AppState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: persistenceKey)
    }

    private func loadPersistedState() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey),
              let persistedState = try? JSONDecoder().decode(AppState.self, from: data) else {
            return
        }

        appState = persistedState
    }

    private func clearPersistedState() {
        UserDefaults.standard.removeObject(forKey: persistenceKey)
    }
}

struct AppState: Codable, Equatable {
    var isAuthenticated: Bool = false
    var isOnline: Bool = true
    var isLoading: Bool = false
    var hasError: Bool = false
    var currentUserId: String?
    var selectedItems: Set<String> = []
    var preferences: UserPreferences = UserPreferences()
    var notifications: [AppNotification] = []
    var currentView: AppView = .home
    var searchQuery: String = ""
    var filters: [String: Any] = [:]

    private enum CodingKeys: String, CodingKey {
        case isAuthenticated, isOnline, isLoading, hasError
        case currentUserId, selectedItems, preferences, notifications
        case currentView, searchQuery
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isAuthenticated = try container.decode(Bool.self, forKey: .isAuthenticated)
        isOnline = try container.decode(Bool.self, forKey: .isOnline)
        isLoading = try container.decode(Bool.self, forKey: .isLoading)
        hasError = try container.decode(Bool.self, forKey: .hasError)
        currentUserId = try container.decodeIfPresent(String.self, forKey: .currentUserId)
        selectedItems = try container.decode(Set<String>.self, forKey: .selectedItems)
        preferences = try container.decode(UserPreferences.self, forKey: .preferences)
        notifications = try container.decode([AppNotification].self, forKey: .notifications)
        currentView = try container.decode(AppView.self, forKey: .currentView)
        searchQuery = try container.decode(String.self, forKey: .searchQuery)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isAuthenticated, forKey: .isAuthenticated)
        try container.encode(isOnline, forKey: .isOnline)
        try container.encode(isLoading, forKey: .isLoading)
        try container.encode(hasError, forKey: .hasError)
        try container.encodeIfPresent(currentUserId, forKey: .currentUserId)
        try container.encode(selectedItems, forKey: .selectedItems)
        try container.encode(preferences, forKey: .preferences)
        try container.encode(notifications, forKey: .notifications)
        try container.encode(currentView, forKey: .currentView)
        try container.encode(searchQuery, forKey: .searchQuery)
    }
}

struct UserSession: Codable, Equatable {
    let userId: String
    let token: String
    let refreshToken: String
    let expiresAt: Date
    let permissions: [String]
    let profile: UserProfile

    var isExpired: Bool {
        Date() > expiresAt
    }

    var isExpiringSoon: Bool {
        Date().addingTimeInterval(300) > expiresAt
    }
}

struct UserProfile: Codable, Equatable {
    let id: String
    let email: String
    let displayName: String
    let avatarURL: String?
    let role: UserRole
    let createdAt: Date
    let lastLoginAt: Date?
}

struct UserPreferences: Codable, Equatable {
    var theme: AppTheme = .system
    var language: String = "en"
    var notificationsEnabled: Bool = true
    var soundEnabled: Bool = true
    var autoSaveEnabled: Bool = true
    var dataUsageOptimized: Bool = false
    var privacySettings: PrivacySettings = PrivacySettings()
}

struct PrivacySettings: Codable, Equatable {
    var analyticsEnabled: Bool = true
    var crashReportingEnabled: Bool = true
    var locationSharingEnabled: Bool = false
    var dataSharingEnabled: Bool = false
}

struct AppNotification: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let message: String
    let type: NotificationType
    let timestamp: Date
    var isRead: Bool = false
    let actionURL: String?

    init(title: String, message: String, type: NotificationType, actionURL: String? = nil) {
        self.id = UUID().uuidString
        self.title = title
        self.message = message
        self.type = type
        self.timestamp = Date()
        self.actionURL = actionURL
    }
}

struct StateSnapshot {
    let state: AppState
    let timestamp: Date
}

enum NetworkState {
    case idle
    case connecting
    case connected
    case disconnected
    case error(Error)
}

enum AppView: String, Codable, CaseIterable {
    case home = "home"
    case profile = "profile"
    case settings = "settings"
    case search = "search"
    case notifications = "notifications"
    case favorites = "favorites"
}

enum AppTheme: String, Codable, CaseIterable {
    case light = "light"
    case dark = "dark"
    case system = "system"
}

enum UserRole: String, Codable {
    case admin = "admin"
    case moderator = "moderator"
    case user = "user"
    case guest = "guest"
}

enum NotificationType: String, Codable {
    case info = "info"
    case success = "success"
    case warning = "warning"
    case error = "error"
    case system = "system"
}

enum AppError: Error, Codable, Equatable {
    case networkError(String)
    case authenticationError(String)
    case validationError(String)
    case serverError(Int, String)
    case unknownError(String)

    var localizedDescription: String {
        switch self {
        case .networkError(let message):
            return "Network Error: \(message)"
        case .authenticationError(let message):
            return "Authentication Error: \(message)"
        case .validationError(let message):
            return "Validation Error: \(message)"
        case .serverError(let code, let message):
            return "Server Error (\(code)): \(message)"
        case .unknownError(let message):
            return "Unknown Error: \(message)"
        }
    }
}

extension StateManager {
    func binding<T>(
        for keyPath: WritableKeyPath<AppState, T>
    ) -> Binding<T> {
        Binding(
            get: { self.appState[keyPath: keyPath] },
            set: { self.updateAppState(keyPath: keyPath, value: $0) }
        )
    }

    func publisher<T>(
        for keyPath: KeyPath<AppState, T>
    ) -> AnyPublisher<T, Never> where T: Equatable {
        $appState
            .map { $0[keyPath: keyPath] }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    func isLoading(for key: String) -> Bool {
        loadingStates[key] ?? false
    }

    func error(for key: String) -> AppError? {
        errorStates[key] ?? nil
    }

    func addNotification(_ notification: AppNotification) {
        withAnimation {
            appState.notifications.insert(notification, at: 0)
        }
    }

    func markNotificationAsRead(_ id: String) {
        if let index = appState.notifications.firstIndex(where: { $0.id == id }) {
            appState.notifications[index].isRead = true
        }
    }

    func removeNotification(_ id: String) {
        appState.notifications.removeAll { $0.id == id }
    }

    func clearAllNotifications() {
        withAnimation {
            appState.notifications.removeAll()
        }
    }

    var unreadNotificationCount: Int {
        appState.notifications.filter { !$0.isRead }.count
    }
}
