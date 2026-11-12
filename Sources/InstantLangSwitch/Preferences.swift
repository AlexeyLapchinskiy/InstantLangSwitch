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

    @Published var configuration: PreferencesConfiguration {
        didSet {
            if let data = try? PropertyListEncoder().encode(configuration) {
                defaults.set(data, forKey: Self.key)
            }
        }
    }
    @Published var sources: [InputSource] = []
    @Published var startupStatus: SMAppService.Status = .notRegistered
    @Published var shortcutErrors: [ShortcutAction: String] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let saved = try? PropertyListDecoder().decode(PreferencesConfiguration.self, from: data) {
            configuration = saved
        } else {
            configuration = PreferencesConfiguration()
        }
    }

    func shortcut(for action: ShortcutAction) -> Shortcut? {
        configuration.shortcuts[String(action.rawValue)]
    }

    func saveShortcut(_ shortcut: Shortcut?, for action: ShortcutAction) {
        configuration.shortcuts[String(action.rawValue)] = shortcut
    }

    func refreshSources() {
        let available = InputSources.available()
        if sources != available {
            sources = available
        }
    }

    var correctionPair: (first: InputSource, second: InputSource)? {
        SelectionCorrection.layoutPair(in: sources, favorites: configuration.favorites)
    }
}
