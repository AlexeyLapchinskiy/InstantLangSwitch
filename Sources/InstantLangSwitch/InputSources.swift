import Carbon
import Foundation
import OSLog

enum InputSourceCycle {
    static func nextIndex(in sources: [String], current: String?) -> Int? {
        guard sources.count > 1 else { return nil }
        guard let current, let index = sources.firstIndex(of: current) else { return 0 }
        return (index + 1) % sources.count
    }
}

enum InputSources {
    private static let logger = Logger(subsystem: "com.alexeylapchinskiy.InstantLangSwitch", category: "InputSources")

    static func selectNext() {
        let filters = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as Any,
            kTISPropertyInputSourceIsSelectCapable as String: kCFBooleanTrue as Any
        ] as CFDictionary
        guard let list = TISCreateInputSourceList(filters, false)?.takeRetainedValue(),
              let sources = list as NSArray as? [TISInputSource] else { return }

        let selectable = sources.compactMap { source in
            identifier(of: source).map { (id: $0, source: source) }
        }
        let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        guard let index = InputSourceCycle.nextIndex(
            in: selectable.map(\.id),
            current: current.flatMap(identifier(of:))
        ) else { return }

        let status = TISSelectInputSource(selectable[index].source)
        if status != noErr {
            logger.error("Input source selection failed with OSStatus \(status).")
        }
    }

    private static func identifier(of source: TISInputSource) -> String? {
        guard let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
    }
}
