import Carbon
import Foundation
import OSLog

struct InputSource: Identifiable, Equatable {
    let id: String
    let name: String
    let shortLabel: String
}

enum InputSourceCycle {
    static func nextIndex(in sources: [String], current: String?) -> Int? {
        guard sources.count > 1 else { return nil }
        guard let current, let index = sources.firstIndex(of: current) else { return 0 }
        return (index + 1) % sources.count
    }

    static func nextID(in available: [String], favorites: [String], current: String?) -> String? {
        let enabled = Set(available)
        var seen = Set<String>()
        let selected = favorites.filter { enabled.contains($0) && seen.insert($0).inserted }
        let cycle = selected.isEmpty ? available : selected
        if selected.count == 1 { return selected.first == current ? nil : selected.first }
        return nextIndex(in: cycle, current: current).map { cycle[$0] }
    }
}

enum InputSources {
    static let selectedChanged = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
    static let enabledChanged = Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String)
    private static let logger = Logger(subsystem: "com.alexeylapchinskiy.InstantLangSwitch", category: "InputSources")

    static func available() -> [InputSource] {
        selectable().map(\.info)
    }

    static func current() -> InputSource? {
        TISCopyCurrentKeyboardInputSource()?.takeRetainedValue().sourceInfo
    }

    static func selectNext(favorites: [String]) -> (previousID: String?, selectedID: String)? {
        let sources = selectable()
        let previous = current()?.id
        guard let id = InputSourceCycle.nextID(in: sources.map(\.info.id), favorites: favorites, current: previous),
              let source = sources.first(where: { $0.info.id == id }),
              select(source.raw) else { return nil }
        return (previous, id)
    }

    @discardableResult
    static func select(id: String) -> Bool {
        guard let source = selectable().first(where: { $0.info.id == id }) else { return false }
        return current()?.id == id || select(source.raw)
    }

    private static func select(_ source: TISInputSource) -> Bool {
        let status = TISSelectInputSource(source)
        if status != noErr {
            logger.error("Input source selection failed with OSStatus \(status).")
        }
        return status == noErr
    }

    private static func selectable() -> [(info: InputSource, raw: TISInputSource)] {
        let filters = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as Any,
            kTISPropertyInputSourceIsSelectCapable as String: kCFBooleanTrue as Any
        ] as CFDictionary
        guard let list = TISCreateInputSourceList(filters, false)?.takeRetainedValue(),
              let sources = list as NSArray as? [TISInputSource] else { return [] }
        var seen = Set<String>()
        return sources.compactMap { source in
            guard let info = source.sourceInfo, seen.insert(info.id).inserted else { return nil }
            return (info, source)
        }
    }
}

private extension TISInputSource {
    var sourceInfo: InputSource? {
        guard let idProperty = TISGetInputSourceProperty(self, kTISPropertyInputSourceID) else { return nil }
        let id = Unmanaged<CFString>.fromOpaque(idProperty).takeUnretainedValue() as String
        let name = TISGetInputSourceProperty(self, kTISPropertyLocalizedName).map {
            Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String
        } ?? id
        let languages = TISGetInputSourceProperty(self, kTISPropertyInputSourceLanguages).map {
            Unmanaged<CFArray>.fromOpaque($0).takeUnretainedValue() as NSArray
        } as? [String]
        let code = languages?.first?.split(separator: "-").first
        let label = code.map { String($0).uppercased() } ?? String(name.prefix(3))
        return InputSource(id: id, name: name, shortLabel: label)
    }
}
