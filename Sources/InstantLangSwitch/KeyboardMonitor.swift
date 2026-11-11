import CoreGraphics
import Foundation
import IOKit.hid
import IOKit.hidsystem

final class KeyboardMonitor {
    static var hasInputMonitoringAccess: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    static func requestInputMonitoringAccessIfUndetermined() {
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeUnknown {
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
    }

    private static let chordModifiers: CGEventFlags = [
        .maskCommand, .maskControl, .maskAlternate, .maskShift
    ]
    // Apple keyboards use vendor-defined Fn usages. External Globe keys can use AC Keyboard Layout Select.
    private static let appleTopCasePage: UInt32 = 0x00FF
    private static let appleKeyboardPage: UInt32 = 0xFF01
    private static let appleFnUsage: UInt32 = 0x03
    private static let globeUsage: UInt32 = 0x029D

    private var manager: IOHIDManager?
    private var fnTap = FnTap()
    private var activeFn: IOHIDElement?

    func start() -> Bool {
        if manager != nil { return true }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let devices = [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keypad],
            [kIOHIDDeviceUsagePageKey: kHIDPage_Consumer, kIOHIDDeviceUsageKey: kHIDUsage_Csmr_ConsumerControl]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, devices as CFArray)
        let inputPages = [
            UInt32(kHIDPage_KeyboardOrKeypad), UInt32(kHIDPage_Consumer),
            Self.appleTopCasePage, Self.appleKeyboardPage
        ]
        let elements = inputPages.map { [kIOHIDElementUsagePageKey: $0] }
        IOHIDManagerSetInputValueMatchingMultiple(manager, elements as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, { context, result, _, value in
            guard result == kIOReturnSuccess, let context else { return }
            Unmanaged<KeyboardMonitor>.fromOpaque(context).takeUnretainedValue().handle(value)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<KeyboardMonitor>.fromOpaque(context).takeUnretainedValue().deviceRemoved(device)
        }, context)

        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            return false
        }
        self.manager = manager
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        return true
    }

    func stop() {
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            self.manager = nil
        }
        activeFn = nil
        fnTap.reset()
    }

    private func handle(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let page = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let isFn = ((page == Self.appleTopCasePage || page == Self.appleKeyboardPage) && usage == Self.appleFnUsage)
            || (page == kHIDPage_Consumer && usage == Self.globeUsage)
        if !isFn {
            if activeFn != nil, IOHIDValueGetIntegerValue(value) != 0 {
                fnTap.otherKeyPressed()
            }
            return
        }

        let isDown = IOHIDValueGetIntegerValue(value) != 0
        if let activeFn, !CFEqual(activeFn, element) {
            if isDown { fnTap.otherKeyPressed() }
            return
        }

        activeFn = isDown ? element : nil
        let modifiers = CGEventSource.flagsState(.combinedSessionState)
        if fnTap.fnChanged(isDown: isDown, hasOtherModifiers: !modifiers.intersection(Self.chordModifiers).isEmpty) {
            DispatchQueue.main.async { InputSources.selectNext() }
        }
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        guard let activeFn, CFEqual(IOHIDElementGetDevice(activeFn), device) else { return }
        self.activeFn = nil
        fnTap.reset()
    }
}
