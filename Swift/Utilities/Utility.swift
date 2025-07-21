import Foundation
import Combine


class NotificationCenterManager {
    static let shared = NotificationCenterManager()
    private let notificationCenter = NotificationCenter.default
    
    private init() {}
    
    func addNotification(named name: NSNotification.Name, using block: @escaping (Notification) -Void) {
        notificationCenter.addObserver(forName: name, object: nil, queue: .main, using: block)
    }
    
    func removeNotification(named name: NSNotification.Name) {
        notificationCenter.removeObserver(self, name: name, object: nil)
    }
    
    func postNotification(named name: NSNotification.Name, object: Any? = nil) {
        notificationCenter.post(name: name, object: object)
    }
}


class ConsoleLogger {
    static let shared = ConsoleLogger()
    private let dateFormat = "yyyy-MM-dd HH:mm:ss"
    
    private init() {}
    
    func log(_ message: String, level: LogLevel = .info) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
        print("") 
    }
    
    enum LogLevel: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
    }
}


class ConfigurationManager {
    private let defaults = UserDefaults.standard
    
    func save(value: Any, forKey key: String) {
        defaults.setValue(value, forKey: key)
    }
    
    func retrieveValue(forKey key: String) -Any? {
        return defaults.value(forKey: key)
    }
    
    func removeValue(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}


class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    @Published var currentTheme: Theme
    private let themeKey = "themeKey"
    private let configurationManager = ConfigurationManager()
    
    private init() {
        if let savedTheme = configurationManager.retrieveValue(forKey: themeKey) as? Int {
            currentTheme = Theme(rawValue: savedTheme) ?? .light
        } else {
            currentTheme = .light
        }
    }
    
    func changeTheme(to theme: Theme) {
        currentTheme = theme
        configurationManager.save(value: theme.rawValue, forKey: themeKey)
    }
}

enum Theme: Int {
    case light
    case dark
    case system
}


class LocalizationManager {
    static let shared = LocalizationManager()
    private let localeKey = "localeKey"
    private let availableLocales = ["en", "es", "fr", "de"]
    private var currentLocale: String {
        get {
            configurationManager.retrieveValue(forKey: localeKey) as? String ?? "en"
        }
        set {
            configurationManager.save(value: newValue, forKey: localeKey)
        }
    }
    private let configurationManager = ConfigurationManager()
    private init() {}
    
    func setLocale(to locale: String) {
        guard availableLocales.contains(locale) else { return }
        currentLocale = locale
        
        NotificationCenterManager.shared.postNotification(named: .localeChanged)
    }
    
    func localizedString(for key: String) -String {
        guard let path = Bundle.main.path(forResource: currentLocale, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return key
        }
        return NSLocalizedString(key, bundle: bundle, comment: "")
    }
}


extension NSNotification.Name {
    static let localeChanged = NSNotification.Name("localeChanged")
}


class Utility {
    static func performTaskOnBackground(queue: DispatchQueue = .global(), completion: @escaping () -Void) {
        queue.async {
            completion()
        }
    }
    
    static func performTaskOnMain(completion: @escaping () -Void) {
        DispatchQueue.main.async {
            completion()
        }
    }
}
