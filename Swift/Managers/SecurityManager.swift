import Foundation
import CommonCrypto
import Security
import LocalAuthentication
import CryptoKit


enum SecurityError: Error, LocalizedError {
    case encryptionFailed
    case decryptionFailed
    case keyGenerationFailed
    case keychainStoreFailed
    case keychainRetrieveFailed
    case biometricAuthenticationFailed
    case invalidData
    case invalidPassword
    case biometricNotAvailable
    case authenticationCancelled
    case authenticationFailure
    case certificateValidationFailed
    case networkSecurityFailed
    
    var errorDescription: String? {
        switch self {
        case .encryptionFailed:
            return "Encryption operation failed"
        case .decryptionFailed:
            return "Decryption operation failed"
        case .keyGenerationFailed:
            return "Key generation failed"
        case .keychainStoreFailed:
            return "Failed to store data in keychain"
        case .keychainRetrieveFailed:
            return "Failed to retrieve data from keychain"
        case .biometricAuthenticationFailed:
            return "Biometric authentication failed"
        case .invalidData:
            return "Invalid data provided"
        case .invalidPassword:
            return "Invalid password"
        case .biometricNotAvailable:
            return "Biometric authentication not available"
        case .authenticationCancelled:
            return "Authentication was cancelled"
        case .authenticationFailure:
            return "Authentication failed"
        case .certificateValidationFailed:
            return "Certificate validation failed"
        case .networkSecurityFailed:
            return "Network security validation failed"
        }
    }
}


enum EncryptionType {
    case aes256
    case aes128
    case chacha20
    case rsa
}


enum AuthenticationMethod {
    case biometric
    case passcode
    case combined
}


protocol EncryptionProvider {
    func encrypt(data: Data, key: Data) throws -> Data
    func decrypt(data: Data, key: Data) throws -> Data
    func generateKey() throws -> Data
}


class AESEncryptionProvider: EncryptionProvider {
    private let keySize: Int
    private let blockSize: Int
    
    init(keySize: Int = kCCKeySizeAES256) {
        self.keySize = keySize
        self.blockSize = kCCBlockSizeAES128
    }
    
    func encrypt(data: Data, key: Data) throws -> Data {
        guard key.count == keySize else {
            throw SecurityError.encryptionFailed
        }
        
        let ivSize = blockSize
        let iv = Data((0..<ivSize).map { _ in UInt8.random(in: 0...255) })
        
        let cryptLength = data.count + kCCBlockSizeAES128
        var cryptData = Data(count: cryptLength)
        var numBytesEncrypted = 0
        
        let cryptStatus = cryptData.withUnsafeMutableBytes { cryptBytes in
            data.withUnsafeBytes { dataBytes in
                iv.withUnsafeBytes { ivBytes in
                    key.withUnsafeBytes { keyBytes in
                        CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES128),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.bindMemory(to: UInt8.self).baseAddress,
                            keySize,
                            ivBytes.bindMemory(to: UInt8.self).baseAddress,
                            dataBytes.bindMemory(to: UInt8.self).baseAddress,
                            data.count,
                            cryptBytes.bindMemory(to: UInt8.self).baseAddress,
                            cryptLength,
                            &numBytesEncrypted
                        )
                    }
                }
            }
        }
        
        guard cryptStatus == kCCSuccess else {
            throw SecurityError.encryptionFailed
        }
        
        cryptData.count = numBytesEncrypted
        return iv + cryptData
    }
    
    func decrypt(data: Data, key: Data) throws -> Data {
        guard key.count == keySize else {
            throw SecurityError.decryptionFailed
        }
        
        let ivSize = blockSize
        guard data.count > ivSize else {
            throw SecurityError.decryptionFailed
        }
        
        let iv = data.subdata(in: 0..<ivSize)
        let encryptedData = data.subdata(in: ivSize..<data.count)
        
        let cryptLength = encryptedData.count + kCCBlockSizeAES128
        var cryptData = Data(count: cryptLength)
        var numBytesDecrypted = 0
        
        let cryptStatus = cryptData.withUnsafeMutableBytes { cryptBytes in
            encryptedData.withUnsafeBytes { dataBytes in
                iv.withUnsafeBytes { ivBytes in
                    key.withUnsafeBytes { keyBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES128),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.bindMemory(to: UInt8.self).baseAddress,
                            keySize,
                            ivBytes.bindMemory(to: UInt8.self).baseAddress,
                            dataBytes.bindMemory(to: UInt8.self).baseAddress,
                            encryptedData.count,
                            cryptBytes.bindMemory(to: UInt8.self).baseAddress,
                            cryptLength,
                            &numBytesDecrypted
                        )
                    }
                }
            }
        }
        
        guard cryptStatus == kCCSuccess else {
            throw SecurityError.decryptionFailed
        }
        
        cryptData.count = numBytesDecrypted
        return cryptData
    }
    
    func generateKey() throws -> Data {
        var keyData = Data(count: keySize)
        let result = keyData.withUnsafeMutableBytes { keyBytes in
            SecRandomCopyBytes(kSecRandomDefault, keySize, keyBytes.bindMemory(to: UInt8.self).baseAddress!)
        }
        
        guard result == errSecSuccess else {
            throw SecurityError.keyGenerationFailed
        }
        
        return keyData
    }
}


@available(iOS 13.0, *)
class ChaCha20EncryptionProvider: EncryptionProvider {
    func encrypt(data: Data, key: Data) throws -> Data {
        guard key.count == 32 else {
            throw SecurityError.encryptionFailed
        }
        
        let symmetricKey = SymmetricKey(data: key)
        let nonce = try ChaCha20Poly1305.Nonce()
        
        do {
            let sealedBox = try ChaCha20Poly1305.seal(data, using: symmetricKey, nonce: nonce)
            return Data(nonce) + sealedBox.ciphertext + sealedBox.tag
        } catch {
            throw SecurityError.encryptionFailed
        }
    }
    
    func decrypt(data: Data, key: Data) throws -> Data {
        guard key.count == 32, data.count >= 28 else {
            throw SecurityError.decryptionFailed
        }
        
        let symmetricKey = SymmetricKey(data: key)
        let nonce = data.subdata(in: 0..<12)
        let ciphertext = data.subdata(in: 12..<data.count-16)
        let tag = data.subdata(in: data.count-16..<data.count)
        
        do {
            let sealedBox = try ChaCha20Poly1305.SealedBox(nonce: ChaCha20Poly1305.Nonce(data: nonce), ciphertext: ciphertext, tag: tag)
            return try ChaCha20Poly1305.open(sealedBox, using: symmetricKey)
        } catch {
            throw SecurityError.decryptionFailed
        }
    }
    
    func generateKey() throws -> Data {
        let symmetricKey = SymmetricKey(size: .bits256)
        return symmetricKey.withUnsafeBytes { Data($0) }
    }
}


class KeychainManager {
    private let service: String
    private let accessGroup: String?
    
    init(service: String, accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }
    
    func store(data: Data, forKey key: String, requiresBiometric: Bool = false) throws {
        let query = baseQuery(forKey: key)
        
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        var attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        
        if requiresBiometric {
            attributes[kSecAttrAccessControl as String] = SecAccessControlCreateWithFlags(
                kCFAllocatorDefault,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                .biometryAny,
                nil
            )
        }
        
        if status == errSecSuccess {
            
            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw SecurityError.keychainStoreFailed
            }
        } else {
            
            var newQuery = query
            newQuery.merge(attributes) { _, new in new }
            
            let addStatus = SecItemAdd(newQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw SecurityError.keychainStoreFailed
            }
        }
    }
    
    func retrieve(forKey key: String, context: LAContext? = nil) throws -> Data {
        var query = baseQuery(forKey: key)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        
        if let context = context {
            query[kSecUseAuthenticationContext as String] = context
        }
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess, let data = result as? Data else {
            throw SecurityError.keychainRetrieveFailed
        }
        
        return data
    }
    
    func delete(forKey key: String) throws {
        let query = baseQuery(forKey: key)
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecurityError.keychainStoreFailed
        }
    }
    
    func deleteAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecurityError.keychainStoreFailed
        }
    }
    
    private func baseQuery(forKey key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        return query
    }
}


class BiometricAuthManager {
    private let context = LAContext()
    private let policy = LAPolicy.deviceOwnerAuthenticationWithBiometrics
    
    func isBiometricAvailable() -> Bool {
        var error: NSError?
        return context.canEvaluatePolicy(policy, error: &error)
    }
    
    func getBiometricType() -> LABiometryType {
        guard isBiometricAvailable() else { return .none }
        return context.biometryType
    }
    
    func authenticate(reason: String, fallbackTitle: String? = nil) async throws -> Bool {
        let context = LAContext()
        
        if let fallbackTitle = fallbackTitle {
            context.localizedFallbackTitle = fallbackTitle
        }
        
        do {
            let success = try await context.evaluatePolicy(policy, localizedReason: reason)
            return success
        } catch {
            if let laError = error as? LAError {
                switch laError.code {
                case .userCancel:
                    throw SecurityError.authenticationCancelled
                case .biometryNotAvailable:
                    throw SecurityError.biometricNotAvailable
                case .authenticationFailed:
                    throw SecurityError.authenticationFailure
                default:
                    throw SecurityError.biometricAuthenticationFailed
                }
            }
            throw SecurityError.biometricAuthenticationFailed
        }
    }
}


class PasswordManager {
    private let saltLength = 16
    private let keyLength = 32
    private let iterations = 100000
    
    func hashPassword(_ password: String, salt: Data? = nil) throws -> (hash: Data, salt: Data) {
        let saltData = salt ?? generateSalt()
        let passwordData = password.data(using: .utf8)!
        
        var derivedKey = Data(count: keyLength)
        let result = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
            passwordData.withUnsafeBytes { passwordBytes in
                saltData.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress,
                        passwordData.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        saltData.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedKeyBytes.bindMemory(to: UInt8.self).baseAddress,
                        keyLength
                    )
                }
            }
        }
        
        guard result == kCCSuccess else {
            throw SecurityError.keyGenerationFailed
        }
        
        return (hash: derivedKey, salt: saltData)
    }
    
    func verifyPassword(_ password: String, hash: Data, salt: Data) throws -> Bool {
        let hashedInput = try hashPassword(password, salt: salt)
        return hashedInput.hash == hash
    }
    
    func generateSalt() -> Data {
        var salt = Data(count: saltLength)
        _ = salt.withUnsafeMutableBytes { saltBytes in
            SecRandomCopyBytes(kSecRandomDefault, saltLength, saltBytes.bindMemory(to: UInt8.self).baseAddress!)
        }
        return salt
    }
    
    func generateSecurePassword(length: Int = 16, includeSymbols: Bool = true) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let symbols = "!@#$%^&*()_+-=[]{}|;:,.<>?"
        let characters = includeSymbols ? letters + symbols : letters
        
        return String((0..<length).map { _ in characters.randomElement()! })
    }
}


class CertificateManager {
    func validateCertificate(data: Data) throws -> Bool {
        guard let certificate = SecCertificateCreateWithData(nil, data) else {
            throw SecurityError.certificateValidationFailed
        }
        
        let policy = SecPolicyCreateSSL(true, nil)
        var trust: SecTrust?
        
        let status = SecTrustCreateWithCertificates(certificate, policy, &trust)
        guard status == errSecSuccess, let trust = trust else {
            throw SecurityError.certificateValidationFailed
        }
        
        var result: SecTrustResultType = .invalid
        let evaluateStatus = SecTrustEvaluate(trust, &result)
        
        guard evaluateStatus == errSecSuccess else {
            throw SecurityError.certificateValidationFailed
        }
        
        return result == .unspecified || result == .proceed
    }
    
    func pinCertificate(data: Data, host: String) throws {
        
        let certificate = SecCertificateCreateWithData(nil, data)
        guard certificate != nil else {
            throw SecurityError.certificateValidationFailed
        }
        
        
        let key = "pinned_cert_\(host)"
        let keychain = KeychainManager(service: "com.app.certificates")
        try keychain.store(data: data, forKey: key)
    }
    
    func verifyPinnedCertificate(host: String, serverCertificates: [Data]) throws -> Bool {
        let key = "pinned_cert_\(host)"
        let keychain = KeychainManager(service: "com.app.certificates")
        
        do {
            let pinnedCertData = try keychain.retrieve(forKey: key)
            return serverCertificates.contains(pinnedCertData)
        } catch {
            return false
        }
    }
}


class SecurityManager {
    static let shared = SecurityManager()
    
    private let aesProvider = AESEncryptionProvider()
    private var chaCha20Provider: ChaCha20EncryptionProvider?
    private let keychainManager = KeychainManager(service: "com.app.security")
    private let biometricManager = BiometricAuthManager()
    private let passwordManager = PasswordManager()
    private let certificateManager = CertificateManager()
    
    private init() {
        if #available(iOS 13.0, *) {
            chaCha20Provider = ChaCha20EncryptionProvider()
        }
    }
    
    
    func encryptData(_ data: Data, using type: EncryptionType = .aes256) throws -> (encryptedData: Data, key: Data) {
        switch type {
        case .aes256, .aes128:
            let key = try aesProvider.generateKey()
            let encryptedData = try aesProvider.encrypt(data: data, key: key)
            return (encryptedData, key)
        case .chacha20:
            if #available(iOS 13.0, *), let provider = chaCha20Provider {
                let key = try provider.generateKey()
                let encryptedData = try provider.encrypt(data: data, key: key)
                return (encryptedData, key)
            } else {
                throw SecurityError.encryptionFailed
            }
        case .rsa:
            
            throw SecurityError.encryptionFailed
        }
    }
    
    func decryptData(_ encryptedData: Data, key: Data, using type: EncryptionType = .aes256) throws -> Data {
        switch type {
        case .aes256, .aes128:
            return try aesProvider.decrypt(data: encryptedData, key: key)
        case .chacha20:
            if #available(iOS 13.0, *), let provider = chaCha20Provider {
                return try provider.decrypt(data: encryptedData, key: key)
            } else {
                throw SecurityError.decryptionFailed
            }
        case .rsa:
            
            throw SecurityError.decryptionFailed
        }
    }
    
    
    func storeSecurely(_ data: Data, forKey key: String, requiresBiometric: Bool = false) throws {
        try keychainManager.store(data: data, forKey: key, requiresBiometric: requiresBiometric)
    }
    
    func retrieveSecurely(forKey key: String, withBiometric: Bool = false) async throws -> Data {
        if withBiometric {
            _ = try await biometricManager.authenticate(reason: "Access secure data")
        }
        return try keychainManager.retrieve(forKey: key)
    }
    
    func deleteSecurely(forKey key: String) throws {
        try keychainManager.delete(forKey: key)
    }
    
    
    func authenticateUser(method: AuthenticationMethod, reason: String) async throws -> Bool {
        switch method {
        case .biometric:
            return try await biometricManager.authenticate(reason: reason)
        case .passcode:
            let context = LAContext()
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        case .combined:
            do {
                return try await biometricManager.authenticate(reason: reason)
            } catch {
                let context = LAContext()
                return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            }
        }
    }
    
    func isBiometricAvailable() -> Bool {
        return biometricManager.isBiometricAvailable()
    }
    
    func getBiometricType() -> LABiometryType {
        return biometricManager.getBiometricType()
    }
    
    
    func hashPassword(_ password: String) throws -> (hash: Data, salt: Data) {
        return try passwordManager.hashPassword(password)
    }
    
    func verifyPassword(_ password: String, hash: Data, salt: Data) throws -> Bool {
        return try passwordManager.verifyPassword(password, hash: hash, salt: salt)
    }
    
    func generateSecurePassword(length: Int = 16, includeSymbols: Bool = true) -> String {
        return passwordManager.generateSecurePassword(length: length, includeSymbols: includeSymbols)
    }
    
    
    func validateCertificate(data: Data) throws -> Bool {
        return try certificateManager.validateCertificate(data: data)
    }
    
    func pinCertificate(data: Data, host: String) throws {
        try certificateManager.pinCertificate(data: data, host: host)
    }
    
    func verifyPinnedCertificate(host: String, serverCertificates: [Data]) throws -> Bool {
        return try certificateManager.verifyPinnedCertificate(host: host, serverCertificates: serverCertificates)
    }
    
    
    func generateRandomBytes(count: Int) -> Data {
        var bytes = Data(count: count)
        _ = bytes.withUnsafeMutableBytes { bytesPointer in
            SecRandomCopyBytes(kSecRandomDefault, count, bytesPointer.bindMemory(to: UInt8.self).baseAddress!)
        }
        return bytes
    }
    
    func generateUUID() -> String {
        return UUID().uuidString
    }
    
    func hashData(_ data: Data, algorithm: String = "SHA256") -> Data {
        switch algorithm {
        case "SHA256":
            var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
            data.withUnsafeBytes {
                _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
            }
            return Data(hash)
        default:
            return Data()
        }
    }
    
    func clearSensitiveData() {
        
        try? keychainManager.deleteAll()
    }
}


extension SecurityManager {
    func createSecureSession() -> String {
        let sessionId = generateUUID()
        let timestamp = Date().timeIntervalSince1970
        let sessionData = "\(sessionId)_\(timestamp)".data(using: .utf8)!
        let hashedSession = hashData(sessionData)
        return hashedSession.base64EncodedString()
    }
    
    func validateSecureSession(_ sessionToken: String) -> Bool {
        
        return !sessionToken.isEmpty && sessionToken.count > 32
    }
    
    func secureCompare(_ string1: String, _ string2: String) -> Bool {
        guard string1.count == string2.count else { return false }
        
        var result = 0
        for (char1, char2) in zip(string1, string2) {
            result |= Int(char1.asciiValue ?? 0) ^ Int(char2.asciiValue ?? 0)
        }
        
        return result == 0
    }
}


extension Data {
    func securelyErase() {
        withUnsafeMutableBytes { bytes in
            memset(bytes.baseAddress, 0, count)
        }
    }
    
    var hexString: String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}


extension String {
    func securelyErase() {
        
        
    }
    
    var isStrongPassword: Bool {
        let minLength = 8
        let hasUpperCase = rangeOfCharacter(from: .uppercaseLetters) != nil
        let hasLowerCase = rangeOfCharacter(from: .lowercaseLetters) != nil
        let hasNumbers = rangeOfCharacter(from: .decimalDigits) != nil
        let hasSymbols = rangeOfCharacter(from: .symbols) != nil
        
        return count >= minLength && hasUpperCase && hasLowerCase && hasNumbers && hasSymbols
    }
}
