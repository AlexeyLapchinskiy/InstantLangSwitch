import Combine
import Foundation
import ServiceManagement

struct AppLayoutRule: Codable, Identifiable {
    let id: String
    let name: String
    var sourceID: String?
}

struct PreferencesConfiguration: Codable {
    var favorites: [String] = []
    var showActiveLayout = false
    var appRules: [AppLayoutRule] = []
    var shortcuts: [String: Shortcut] = [:]
}

final class Preferences: ObservableObject {
    private let defaults: UserDefaults
    private static let key = "switchingPreferences"
    private static let layoutShortcutKey = "0"

    @Published var configuration: PreferencesConfiguration {
        didSet { persistConfiguration() }
    }
    @Published var sources: [InputSource] = []
    @Published var startupStatus: SMAppService.Status = .notRegistered
    @Published var layoutShortcutError: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           var saved = try? PropertyListDecoder().decode(PreferencesConfiguration.self, from: data) {
            // Earlier versions stored the second shortcut under key "1".
            let removedShortcut = saved.shortcuts.removeValue(forKey: "1")
            configuration = saved
            if removedShortcut != nil { persistConfiguration() }
        } else {
            configuration = PreferencesConfiguration()
        }
    }

    var layoutShortcut: Shortcut? {
        get { configuration.shortcuts[Self.layoutShortcutKey] }
        set { configuration.shortcuts[Self.layoutShortcutKey] = newValue }
    }

    private func persistConfiguration() {
        if let data = try? PropertyListEncoder().encode(configuration) {
            defaults.set(data, forKey: Self.key)
        }
    }

    func refreshSources() {
        let available = InputSources.available()
        if sources != available {
            sources = available
        }
    }
}
