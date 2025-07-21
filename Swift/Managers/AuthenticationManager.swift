import Foundation
import Security
import CryptoKit
import Combine
import LocalAuthentication


class AuthenticationManager: ObservableObject {
    
    
    static let shared = AuthenticationManager()
    
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var authenticationState: AuthenticationState = .unauthenticated
    @Published var biometricAuthenticationEnabled = false
    @Published var twoFactorEnabled = false
    @Published var sessionTimeout: TimeInterval = 1800 
    
    private let keychain = KeychainHelper()
    private let networkManager = NetworkManager.shared
    private let sessionManager = SessionManager()
    private let biometricManager = BiometricManager()
    private let tokenManager = TokenManager()
    
    private var cancellables = Set<AnyCancellable>()
    private var sessionTimer: Timer?
    private var refreshTokenTimer: Timer?
    
    
    private struct AuthKeys {
        static let accessToken = "access_token"
        static let refreshToken = "refresh_token"
        static let userCredentials = "user_credentials"
        static let biometricEnabled = "biometric_enabled"
        static let lastAuthenticationDate = "last_auth_date"
        static let failedAttempts = "failed_attempts"
        static let lockoutTime = "lockout_time"
    }
    
    
    private init() {
        setupAuthenticationState()
        setupSessionTimeout()
        setupTokenRefresh()
        loadStoredCredentials()
    }
    
    private func setupAuthenticationState() {
        
        if let token = keychain.get(AuthKeys.accessToken),
           tokenManager.isValidToken(token) {
            isAuthenticated = true
            authenticationState = .authenticated
            loadCurrentUser()
        }
        
        
        biometricAuthenticationEnabled = UserDefaults.standard.bool(forKey: AuthKeys.biometricEnabled)
        
        
        twoFactorEnabled = UserDefaults.standard.bool(forKey: "two_factor_enabled")
    }
    
    private func setupSessionTimeout() {
        sessionTimer = Timer.scheduledTimer(withTimeInterval: sessionTimeout, repeats: false) { _ in
            self.logout(reason: .sessionTimeout)
        }
    }
    
    private func setupTokenRefresh() {
        refreshTokenTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in
            self.refreshTokenIfNeeded()
        }
    }
    
    private func loadStoredCredentials() {
        if let userData = keychain.get("current_user"),
           let user = try? JSONDecoder().decode(User.self, from: userData) {
            currentUser = user
        }
    }
    
    
    func login(username: String, password: String) -> AnyPublisher<User, AuthenticationError> {
        return Future { [weak self] promise in
            guard let self = self else {
                promise(.failure(.unknownError))
                return
            }
            
            
            if self.isAccountLocked() {
                promise(.failure(.accountLocked))
                return
            }
            
            
            guard self.validateCredentials(username: username, password: password) else {
                promise(.failure(.invalidCredentials))
                return
            }
            
            
            self.performLogin(username: username, password: password)
                .sink(
                    receiveCompletion: { completion in
                        switch completion {
                        case .finished:
                            break
                        case .failure(let error):
                            self.handleFailedLogin()
                            promise(.failure(error))
                        }
                    },
                    receiveValue: { user in
                        self.handleSuccessfulLogin(user: user)
                        promise(.success(user))
                    }
                )
                .store(in: &self.cancellables)
        }
        .eraseToAnyPublisher()
    }
    
    private func performLogin(username: String, password: String) -> AnyPublisher<User, AuthenticationError> {
        let hashedPassword = hashPassword(password)
        let loginRequest = LoginRequest(username: username, password: hashedPassword)
        
        return networkManager.performRequest(
            endpoint: "/auth/login",
            method: .POST,
            parameters: loginRequest.toDictionary(),
            responseType: LoginResponse.self
        )
        .map { response in
            
            self.keychain.set(response.accessToken, forKey: AuthKeys.accessToken)
            self.keychain.set(response.refreshToken, forKey: AuthKeys.refreshToken)
            
            
            if let userData = try? JSONEncoder().encode(response.user) {
                self.keychain.set(userData, forKey: "current_user")
            }
            
            return response.user
        }
        .mapError { error in
            return AuthenticationError.loginFailed(error.localizedDescription)
        }
        .eraseToAnyPublisher()
    }
    
    func loginWithBiometric() -> AnyPublisher<User, AuthenticationError> {
        return biometricManager.authenticate()
            .flatMap { _ in
                return self.validateStoredCredentials()
            }
            .eraseToAnyPublisher()
    }
    
    func loginWithTwoFactor(username: String, password: String, code: String) -> AnyPublisher<User, AuthenticationError> {
        return Future { [weak self] promise in
            guard let self = self else {
                promise(.failure(.unknownError))
                return
            }
            
            let twoFactorRequest = TwoFactorRequest(
                username: username,
                password: self.hashPassword(password),
                code: code
            )
            
            self.networkManager.performRequest(
                endpoint: "/auth/two-factor",
                method: .POST,
                parameters: twoFactorRequest.toDictionary(),
                responseType: LoginResponse.self
            )
            .sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        break
                    case .failure(let error):
                        promise(.failure(.twoFactorFailed(error.localizedDescription)))
                    }
                },
                receiveValue: { response in
                    self.handleSuccessfulLogin(user: response.user)
                    promise(.success(response.user))
                }
            )
            .store(in: &self.cancellables)
        }
        .eraseToAnyPublisher()
    }
    
    func logout(reason: LogoutReason = .userInitiated) {
        
        keychain.delete(AuthKeys.accessToken)
        keychain.delete(AuthKeys.refreshToken)
        keychain.delete("current_user")
        
        
        isAuthenticated = false
        currentUser = nil
        authenticationState = .unauthenticated
        
        
        sessionTimer?.invalidate()
        refreshTokenTimer?.invalidate()
        
        
        NotificationCenter.default.post(name: .userDidLogout, object: reason)
        
        
        clearSensitiveData()
    }
    
    
    func register(username: String, email: String, password: String) -> AnyPublisher<User, AuthenticationError> {
        return Future { [weak self] promise in
            guard let self = self else {
                promise(.failure(.unknownError))
                return
            }
            
            
            guard self.validateRegistrationData(username: username, email: email, password: password) else {
                promise(.failure(.invalidRegistrationData))
                return
            }
            
            let registrationRequest = RegistrationRequest(
                username: username,
                email: email,
                password: self.hashPassword(password)
            )
            
            self.networkManager.performRequest(
                endpoint: "/auth/register",
                method: .POST,
                parameters: registrationRequest.toDictionary(),
                responseType: RegistrationResponse.self
            )
            .sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        break
                    case .failure(let error):
                        promise(.failure(.registrationFailed(error.localizedDescription)))
                    }
                },
                receiveValue: { response in
                    promise(.success(response.user))
                }
            )
            .store(in: &self.cancellables)
        }
        .eraseToAnyPublisher()
    }
    
    
    func changePassword(currentPassword: String, newPassword: String) -> AnyPublisher<Void, AuthenticationError> {
        return Future { [weak self] promise in
            guard let self = self else {
                promise(.failure(.unknownError))
                return
            }
            
            guard self.validatePassword(newPassword) else {
                promise(.failure(.weakPassword))
                return
            }
            
            let changePasswordRequest = ChangePasswordRequest(
                currentPassword: self.hashPassword(currentPassword),
                newPassword: self.hashPassword(newPassword)
            )
            
            self.networkManager.performRequest(
                endpoint: "/auth/change-password",
                method: .POST,
                parameters: changePasswordRequest.toDictionary(),
                responseType: SuccessResponse.self
            )
            .sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        break
                    case .failure(let error):
                        promise(.failure(.passwordChangeFailed(error.localizedDescription)))
                    }
                },
                receiveValue: { _ in
                    promise(.success(()))
                }
            )
            .store(in: &self.cancellables)
        }
        .eraseToAnyPublisher()
    }
    
    func resetPassword(email: String) -> AnyPublisher<Void, AuthenticationError> {
        return Future { [weak self] promise in
            guard let self = self else {
                promise(.failure(.unknownError))
                return
            }
            
            let resetRequest = PasswordResetRequest(email: email)
            
            self.networkManager.performRequest(
                endpoint: "/auth/reset-password",
                method: .POST,
                parameters: resetRequest.toDictionary(),
                responseType: SuccessResponse.self
            )
            .sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        break
                    case .failure(let error):
                        promise(.failure(.passwordResetFailed(error.localizedDescription)))
                    }
                },
                receiveValue: { _ in
                    promise(.success(()))
                }
            )
            .store(in: &self.cancellables)
        }
        .eraseToAnyPublisher()
    }
    
    
    func refreshTokenIfNeeded() {
        guard let refreshToken = keychain.get(AuthKeys.refreshToken) else {
            logout(reason: .tokenExpired)
            return
        }
        
        guard let accessToken = keychain.get(AuthKeys.accessToken),
              tokenManager.isTokenExpiringSoon(accessToken) else {
            return
        }
        
        refreshAccessToken(refreshToken: refreshToken)
            .sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        break
                    case .failure:
                        self.logout(reason: .tokenExpired)
                    }
                },
                receiveValue: { newToken in
                    self.keychain.set(newToken, forKey: AuthKeys.accessToken)
                }
            )
            .store(in: &cancellables)
    }
    
    private func refreshAccessToken(refreshToken: String) -> AnyPublisher<String, AuthenticationError> {
        return networkManager.performRequest(
            endpoint: "/auth/refresh",
            method: .POST,
            parameters: ["refresh_token": refreshToken],
            responseType: TokenResponse.self
        )
        .map { response in
            return response.accessToken
        }
        .mapError { error in
            return AuthenticationError.tokenRefreshFailed(error.localizedDescription)
        }
        .eraseToAnyPublisher()
    }
    
    
    func enableBiometricAuthentication() -> AnyPublisher<Void, AuthenticationError> {
        return biometricManager.authenticate()
            .map { _ in
                UserDefaults.standard.set(true, forKey: AuthKeys.biometricEnabled)
                self.biometricAuthenticationEnabled = true
            }
            .mapError { error in
                return AuthenticationError.biometricAuthenticationFailed(error.localizedDescription)
            }
            .eraseToAnyPublisher()
    }
    
    func disableBiometricAuthentication() {
        UserDefaults.standard.set(false, forKey: AuthKeys.biometricEnabled)
        biometricAuthenticationEnabled = false
    }
    
    
    func enableTwoFactor() -> AnyPublisher<String, AuthenticationError> {
        return networkManager.performRequest(
            endpoint: "/auth/two-factor/enable",
            method: .POST,
            responseType: TwoFactorSetupResponse.self
        )
        .map { response in
            UserDefaults.standard.set(true, forKey: "two_factor_enabled")
            self.twoFactorEnabled = true
            return response.qrCode
        }
        .mapError { error in
            return AuthenticationError.twoFactorSetupFailed(error.localizedDescription)
        }
        .eraseToAnyPublisher()
    }
    
    func disableTwoFactor(code: String) -> AnyPublisher<Void, AuthenticationError> {
        return networkManager.performRequest(
            endpoint: "/auth/two-factor/disable",
            method: .POST,
            parameters: ["code": code],
            responseType: SuccessResponse.self
        )
        .map { _ in
            UserDefaults.standard.set(false, forKey: "two_factor_enabled")
            self.twoFactorEnabled = false
        }
        .mapError { error in
            return AuthenticationError.twoFactorDisableFailed(error.localizedDescription)
        }
        .eraseToAnyPublisher()
    }
    
    
    func extendSession() {
        sessionTimer?.invalidate()
        setupSessionTimeout()
    }
    
    func getSessionTimeRemaining() -> TimeInterval {
        return sessionTimer?.fireDate.timeIntervalSinceNow ?? 0
    }
    
    
    private func isAccountLocked() -> Bool {
        let failedAttempts = UserDefaults.standard.integer(forKey: AuthKeys.failedAttempts)
        let lockoutTime = UserDefaults.standard.double(forKey: AuthKeys.lockoutTime)
        
        if failedAttempts >= 5 {
            let lockoutDuration: TimeInterval = 900 
            return Date().timeIntervalSince1970 < lockoutTime + lockoutDuration
        }
        
        return false
    }
    
    private func handleFailedLogin() {
        let failedAttempts = UserDefaults.standard.integer(forKey: AuthKeys.failedAttempts) + 1
        UserDefaults.standard.set(failedAttempts, forKey: AuthKeys.failedAttempts)
        
        if failedAttempts >= 5 {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: AuthKeys.lockoutTime)
        }
    }
    
    private func handleSuccessfulLogin(user: User) {
        
        UserDefaults.standard.removeObject(forKey: AuthKeys.failedAttempts)
        UserDefaults.standard.removeObject(forKey: AuthKeys.lockoutTime)
        
        
        isAuthenticated = true
        currentUser = user
        authenticationState = .authenticated
        
        
        UserDefaults.standard.set(Date(), forKey: AuthKeys.lastAuthenticationDate)
        
        
        setupSessionTimeout()
        
        
        NotificationCenter.default.post(name: .userDidLogin, object: user)
    }
    
    
    private func validateCredentials(username: String, password: String) -> Bool {
        return !username.isEmpty && !password.isEmpty && password.count >= 8
    }
    
    private func validateRegistrationData(username: String, email: String, password: String) -> Bool {
        return validateCredentials(username: username, password: password) &&
               isValidEmail(email) &&
               validatePassword(password)
    }
    
    private func validatePassword(_ password: String) -> Bool {
        
        let hasUppercase = password.rangeOfCharacter(from: .uppercaseLetters) != nil
        let hasLowercase = password.rangeOfCharacter(from: .lowercaseLetters) != nil
        let hasNumbers = password.rangeOfCharacter(from: .decimalDigits) != nil
        let hasSpecialChars = password.rangeOfCharacter(from: CharacterSet(charactersIn: "!@#$%^&*()_+-=[]{}|;':\",./<>?")) != nil
        
        return password.count >= 8 && hasUppercase && hasLowercase && hasNumbers && hasSpecialChars
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        return NSPredicate(format: "SELF MATCHES %@", emailRegex).evaluate(with: email)
    }
    
    private func validateStoredCredentials() -> AnyPublisher<User, AuthenticationError> {
        guard let userData = keychain.get("current_user"),
              let user = try? JSONDecoder().decode(User.self, from: userData) else {
            return Fail(error: AuthenticationError.invalidStoredCredentials)
                .eraseToAnyPublisher()
        }
        
        return Just(user)
            .setFailureType(to: AuthenticationError.self)
            .eraseToAnyPublisher()
    }
    
    
    private func hashPassword(_ password: String) -> String {
        let inputData = Data(password.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private func clearSensitiveData() {
        
        currentUser = nil
        
        
        keychain.delete(AuthKeys.userCredentials)
        
        
        clearTemporaryFiles()
    }
    
    private func clearTemporaryFiles() {
        let tempDirectory = NSTemporaryDirectory()
        let fileManager = FileManager.default
        
        do {
            let tempFiles = try fileManager.contentsOfDirectory(atPath: tempDirectory)
            for file in tempFiles {
                if file.contains("auth_temp") {
                    try fileManager.removeItem(atPath: tempDirectory + file)
                }
            }
        } catch {
            print("Error clearing temporary files: \(error)")
        }
    }
    
    deinit {
        sessionTimer?.invalidate()
        refreshTokenTimer?.invalidate()
    }
}


enum AuthenticationState {
    case unauthenticated
    case authenticating
    case authenticated
    case locked
}

enum LogoutReason {
    case userInitiated
    case sessionTimeout
    case tokenExpired
    case securityViolation
}

enum AuthenticationError: Error, LocalizedError {
    case invalidCredentials
    case accountLocked
    case loginFailed(String)
    case registrationFailed(String)
    case invalidRegistrationData
    case passwordChangeFailed(String)
    case passwordResetFailed(String)
    case tokenRefreshFailed(String)
    case biometricAuthenticationFailed(String)
    case twoFactorFailed(String)
    case twoFactorSetupFailed(String)
    case twoFactorDisableFailed(String)
    case invalidStoredCredentials
    case weakPassword
    case unknownError
    
    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid username or password"
        case .accountLocked:
            return "Account is temporarily locked due to multiple failed attempts"
        case .loginFailed(let message):
            return "Login failed: \(message)"
        case .registrationFailed(let message):
            return "Registration failed: \(message)"
        case .invalidRegistrationData:
            return "Invalid registration data provided"
        case .passwordChangeFailed(let message):
            return "Password change failed: \(message)"
        case .passwordResetFailed(let message):
            return "Password reset failed: \(message)"
        case .tokenRefreshFailed(let message):
            return "Token refresh failed: \(message)"
        case .biometricAuthenticationFailed(let message):
            return "Biometric authentication failed: \(message)"
        case .twoFactorFailed(let message):
            return "Two-factor authentication failed: \(message)"
        case .twoFactorSetupFailed(let message):
            return "Two-factor setup failed: \(message)"
        case .twoFactorDisableFailed(let message):
            return "Two-factor disable failed: \(message)"
        case .invalidStoredCredentials:
            return "Invalid stored credentials"
        case .weakPassword:
            return "Password does not meet security requirements"
        case .unknownError:
            return "An unknown error occurred"
        }
    }
}


struct LoginRequest {
    let username: String
    let password: String
    
    func toDictionary() -> [String: Any] {
        return [
            "username": username,
            "password": password
        ]
    }
}

struct LoginResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let user: User
    let expiresIn: TimeInterval
}

struct RegistrationRequest {
    let username: String
    let email: String
    let password: String
    
    func toDictionary() -> [String: Any] {
        return [
            "username": username,
            "email": email,
            "password": password
        ]
    }
}

struct RegistrationResponse: Codable {
    let user: User
    let message: String
}

struct TwoFactorRequest {
    let username: String
    let password: String
    let code: String
    
    func toDictionary() -> [String: Any] {
        return [
            "username": username,
            "password": password,
            "code": code
        ]
    }
}

struct ChangePasswordRequest {
    let currentPassword: String
    let newPassword: String
    
    func toDictionary() -> [String: Any] {
        return [
            "current_password": currentPassword,
            "new_password": newPassword
        ]
    }
}

struct PasswordResetRequest {
    let email: String
    
    func toDictionary() -> [String: Any] {
        return [
            "email": email
        ]
    }
}

struct TokenResponse: Codable {
    let accessToken: String
    let expiresIn: TimeInterval
}

struct TwoFactorSetupResponse: Codable {
    let qrCode: String
    let backupCodes: [String]
}

struct SuccessResponse: Codable {
    let success: Bool
    let message: String
}


extension Notification.Name {
    static let userDidLogin = Notification.Name("userDidLogin")
    static let userDidLogout = Notification.Name("userDidLogout")
    static let sessionWillExpire = Notification.Name("sessionWillExpire")
    static let authenticationStateChanged = Notification.Name("authenticationStateChanged")
}


class KeychainHelper {
    func set(_ data: Data, forKey key: String) {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecValueData: data
        ] as CFDictionary
        
        SecItemDelete(query)
        SecItemAdd(query, nil)
    }
    
    func set(_ string: String, forKey key: String) {
        if let data = string.data(using: .utf8) {
            set(data, forKey: key)
        }
    }
    
    func get(_ key: String) -> Data? {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true
        ] as CFDictionary
        
        var result: AnyObject?
        SecItemCopyMatching(query, &result)
        return result as? Data
    }
    
    func get(_ key: String) -> String? {
        if let data = get(key) as Data? {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
    
    func delete(_ key: String) {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key
        ] as CFDictionary
        
        SecItemDelete(query)
    }
}

class SessionManager {
    private var sessionStartTime: Date?
    private var lastActivityTime: Date?
    
    func startSession() {
        sessionStartTime = Date()
        lastActivityTime = Date()
    }
    
    func updateActivity() {
        lastActivityTime = Date()
    }
    
    func getSessionDuration() -> TimeInterval {
        guard let startTime = sessionStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }
    
    func getTimeSinceLastActivity() -> TimeInterval {
        guard let lastActivity = lastActivityTime else { return 0 }
        return Date().timeIntervalSince(lastActivity)
    }
    
    func endSession() {
        sessionStartTime = nil
        lastActivityTime = nil
    }
}

class BiometricManager {
    private let context = LAContext()
    
    func authenticate() -> AnyPublisher<Void, AuthenticationError> {
        return Future { promise in
            var error: NSError?
            
            guard self.context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
                promise(.failure(.biometricAuthenticationFailed("Biometric authentication not available")))
                return
            }
            
            self.context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Authenticate to access your account"
            ) { success, error in
                if success {
                    promise(.success(()))
                } else {
                    let errorMessage = error?.localizedDescription ?? "Authentication failed"
                    promise(.failure(.biometricAuthenticationFailed(errorMessage)))
                }
            }
        }
        .eraseToAnyPublisher()
    }
}

class TokenManager {
    func isValidToken(_ token: String) -> Bool {
        
        return !token.isEmpty && token.count > 10
    }
    
    func isTokenExpiringSoon(_ token: String) -> Bool {
        
        
        return false
    }
    
    func getTokenExpirationDate(_ token: String) -> Date? {
        
        return nil
    }
}

struct User: Codable {
    let id: String
    let username: String
    let email: String
    let firstName: String
    let lastName: String
    let profileImageURL: String?
    let isEmailVerified: Bool
    let createdAt: Date
    let updatedAt: Date
    let roles: [String]
    let preferences: UserPreferences
}

struct UserPreferences: Codable {
    let language: String
    let timezone: String
    let notifications: NotificationPreferences
    let privacy: PrivacyPreferences
}

struct NotificationPreferences: Codable {
    let push: Bool
    let email: Bool
    let sms: Bool
}

struct PrivacyPreferences: Codable {
    let profileVisibility: String
    let dataSharing: Bool
    let analytics: Bool
}
