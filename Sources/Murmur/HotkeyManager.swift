import Foundation
import CoreGraphics
import AppKit

/// Global push-to-talk hotkey: hold Right Option (⌥) to record, release to process.
///
/// Uses a CGEvent tap rather than Carbon's RegisterEventHotKey — the Carbon API
/// only fires when the frontmost app declines the key, so it silently fails inside
/// self-drawn apps (Zed, VS Code's terminal, etc.). A session-level event tap sees
/// every keystroke regardless of who is frontmost. Requires Accessibility permission.
final class HotkeyManager {
    /// Right Option key. (Left Option is 58; Fn is 63 — see README for remapping notes.)
    private static let rightOptionKeycode: Int64 = 61

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isDown = false

    /// Install the event tap. Returns false if creation failed (almost always
    /// because Accessibility permission has not been granted).
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
            manager.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        runLoopSource = nil
        tap = nil
    }

    private func handle(type: CGEventType, event: CGEvent) {
        // The system disables taps that stall or when secure input kicks in; re-enable.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard type == .flagsChanged else { return }
        guard event.getIntegerValueField(.keyboardEventKeycode) == Self.rightOptionKeycode else { return }

        let pressed = event.flags.contains(.maskAlternate)
        if pressed && !isDown {
            isDown = true
            DispatchQueue.main.async { [weak self] in self?.onPress?() }
        } else if !pressed && isDown {
            isDown = false
            DispatchQueue.main.async { [weak self] in self?.onRelease?() }
        }
    }
}
