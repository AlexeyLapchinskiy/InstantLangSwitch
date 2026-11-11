import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct PreferencesView: View {
    @ObservedObject var preferences: Preferences
    let footer: String
    let changeStartup: (Bool) -> Void
    let setShortcut: (Shortcut?, ShortcutAction) -> Bool
    let setRecording: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                general.tabItem { Label("General", systemImage: "gearshape") }
                layouts.tabItem { Label("Layouts", systemImage: "keyboard") }
                appRules.tabItem { Label("App Rules", systemImage: "square.grid.2x2") }
                shortcuts.tabItem { Label("Shortcuts", systemImage: "command") }
            }
            Divider()
            Text(footer)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(12)
        }
    }

    private var general: some View {
        Form {
            Toggle("Open on startup", isOn: Binding(
                get: { preferences.startupStatus == .enabled || preferences.startupStatus == .requiresApproval },
                set: changeStartup
            ))
            if preferences.startupStatus == .requiresApproval {
                Button("Approve in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
            }
            Toggle("Show active layout in the menu bar", isOn: $preferences.configuration.showActiveLayout)
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
    }

    private var layouts: some View {
        Form {
            Section("Favorites") {
                ForEach(orderedSources) { source in
                    HStack {
                        Toggle(source.name, isOn: Binding(
                            get: { preferences.configuration.favorites.contains(source.id) },
                            set: { setFavorite(source.id, selected: $0) }
                        ))
                        .toggleStyle(.checkbox)
                        Spacer()
                        if let index = visibleFavorites.firstIndex(of: source.id) {
                            moveButton("Move \(source.name) up", symbol: "chevron.up", from: index, by: -1)
                            moveButton("Move \(source.name) down", symbol: "chevron.down", from: index, by: 1)
                        }
                    }
                }
                if preferences.sources.isEmpty {
                    Text("Add input sources in Keyboard settings.").foregroundStyle(.secondary)
                }
                Text("Fn follows the order above. With no available favorites, Fn cycles through all enabled layouts.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var appRules: some View {
        Form {
            Section("Default layouts") {
                ForEach($preferences.configuration.appRules) { $rule in
                    HStack {
                        sourcePicker(rule.name, selection: $rule.sourceID, none: "No default")
                        Button {
                            preferences.configuration.appRules.removeAll { $0.id == rule.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(rule.name) rule")
                    }
                }
                Button("Add App…", action: addApp)
                Text("The default applies when you enter an app. You can still switch layouts while using it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var shortcuts: some View {
        Form {
            Section("Global shortcuts") {
                shortcutRow("Switch layout", action: .switchLayout)
                shortcutRow("Correct selected text", action: .correctSelection)
            }
            Section("Text correction") {
                let layouts = preferences.sources.filter(\.supportsTextCorrection)
                sourcePicker(
                    "Typed with", selection: $preferences.configuration.correctionSourceID,
                    none: "Choose a layout", sources: layouts
                )
                sourcePicker(
                    "Convert to", selection: $preferences.configuration.correctionTargetID,
                    none: "Choose a layout", sources: layouts
                )
                Text("Select text in an editable field and run the correction shortcut. The first use asks for Accessibility access.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var visibleFavorites: [String] {
        let enabled = Set(preferences.sources.map(\.id))
        return preferences.configuration.favorites.filter { enabled.contains($0) }
    }

    private var orderedSources: [InputSource] {
        let sources = preferences.sources
        let byID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        let favorites = Set(visibleFavorites)
        return visibleFavorites.compactMap { byID[$0] } + sources.filter { !favorites.contains($0.id) }
    }

    private func setFavorite(_ id: String, selected: Bool) {
        preferences.configuration.favorites.removeAll { $0 == id }
        if selected { preferences.configuration.favorites.append(id) }
    }

    private func moveButton(_ label: String, symbol: String, from index: Int, by offset: Int) -> some View {
        let target = index + offset
        let favorites = visibleFavorites
        return Button {
            guard favorites.indices.contains(target),
                  let first = preferences.configuration.favorites.firstIndex(of: favorites[index]),
                  let second = preferences.configuration.favorites.firstIndex(of: favorites[target]) else { return }
            preferences.configuration.favorites.swapAt(first, second)
        } label: {
            Image(systemName: symbol)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
        .disabled(!favorites.indices.contains(target))
    }

    private func sourcePicker(
        _ label: String, selection: Binding<String?>, none: String, sources: [InputSource]? = nil
    ) -> some View {
        let available = sources ?? preferences.sources
        return Picker(label, selection: selection) {
            Text(none).tag(nil as String?)
            if let id = selection.wrappedValue, !available.contains(where: { $0.id == id }) {
                Text("Unavailable layout").tag(Optional(id))
            }
            ForEach(available) { source in
                Text(source.name).tag(Optional(source.id))
            }
        }
    }

    private func shortcutRow(_ label: String, action: ShortcutAction) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                ShortcutRecorderView(
                    label: label,
                    shortcut: preferences.shortcut(for: action),
                    onRecord: { setShortcut($0, action) },
                    onRecordingChanged: setRecording
                )
                .frame(width: 128)
                Button("Clear") { _ = setShortcut(nil, action) }
                    .disabled(preferences.shortcut(for: action) == nil)
                    .accessibilityLabel("Clear \(label) shortcut")
            }
            if let error = preferences.shortcutErrors[action] {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
              id != Bundle.main.bundleIdentifier,
              !preferences.configuration.appRules.contains(where: { $0.id == id }) else { return }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        preferences.configuration.appRules.append(AppLayoutRule(id: id, name: name))
    }
}

private struct ShortcutRecorderView: NSViewRepresentable {
    let label: String
    let shortcut: Shortcut?
    let onRecord: (Shortcut) -> Bool
    let onRecordingChanged: (Bool) -> Void

    func makeNSView(context: Context) -> ShortcutRecorder { ShortcutRecorder() }

    func updateNSView(_ view: ShortcutRecorder, context: Context) {
        view.setAccessibilityLabel("Record \(label) shortcut")
        view.shortcut = shortcut
        view.onRecord = onRecord
        view.onRecordingChanged = onRecordingChanged
    }
}
