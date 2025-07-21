import SwiftUI
import Combine


class SettingsViewModel: ObservableObject {
    @Published var notificationEnabled: Bool
    @Published var selectedTheme: Theme
    @Published var selectedLanguage: String
    private let configurationManager: ConfigurationManager
    private let themes: [Theme]
    private let languages: [String]
    private var cancellables = Set<AnyCancellable>()
    
    init(configurationManager: ConfigurationManager = ConfigurationManager()) {
        self.configurationManager = configurationManager
        self.notificationEnabled = configurationManager.retrieveValue(forKey: "notificationsEnabled") as? Bool ?? true
        self.selectedTheme = Theme(rawValue: configurationManager.retrieveValue(forKey: "selectedTheme") as? Int ?? 0) ?? .light
        self.selectedLanguage = configurationManager.retrieveValue(forKey: "selectedLanguage") as? String ?? "en"
        self.themes = [.light, .dark, .system]
        self.languages = ["en", "es", "fr", "de"]
        setupSubscribers()
    }
    
    private func setupSubscribers() {
        $notificationEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                self?.configurationManager.save(value: enabled, forKey: "notificationsEnabled")
            }
            .store(in: &cancellables)
        
        $selectedTheme
            .dropFirst()
            .sink { [weak self] theme in
                self?.configurationManager.save(value: theme.rawValue, forKey: "selectedTheme")
                self?.applyTheme(theme)
            }
            .store(in: &cancellables)
        
        $selectedLanguage
            .dropFirst()
            .sink { [weak self] language in
                self?.configurationManager.save(value: language, forKey: "selectedLanguage")
                NotificationCenterManager.shared.postNotification(named: .localeChanged)
            }
            .store(in: &cancellables)
    }
    
    func applyTheme(_ theme: Theme) {
        
    }
}


struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    
    init(viewModel: SettingsViewModel = SettingsViewModel()) {
        self.viewModel = viewModel
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Notifications")) {
                    Toggle("Enable Notifications", isOn: $viewModel.notificationEnabled)
                }
                
                Section(header: Text("Appearance")) {
                    Picker("Theme", selection: $viewModel.selectedTheme) {
                        ForEach(viewModel.themes, id: \Theme.rawValue) 
                            Text($0.description)
                        }
                    }.pickerStyle(SegmentedPickerStyle())
                }
                
                Section(header: Text("Language")) {
                    Picker("Language", selection: $viewModel.selectedLanguage) {
                        ForEach(viewModel.languages, id: \String.self) {
                            Text($0.uppercased())
                        }
                    }
                }
            }
            .navigationBarTitle("Settings")
        }
    }
}


struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}


extension Theme: CustomStringConvertible {
    var description: String {
        switch self {
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        case .system:
            return "System"
        }
    }
}

extension NSNotification.Name {
    static let settingsChanged = NSNotification.Name("settingsChanged")
}
