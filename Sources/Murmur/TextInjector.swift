import Foundation
import AppKit
import CoreGraphics

/// Inserts text into whatever app currently has focus, using the proven
/// pasteboard + synthetic Cmd+V approach: save the clipboard, put our text on
/// it, post Cmd+V, then restore the original clipboard.
///
/// Even when synthetic paste is blocked (some apps, secure input fields), the
/// text remains on the clipboard until the restore fires, so the user can paste
/// manually.
enum TextInjector {
    static func insert(_ text: String) async {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        let savedString = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Give the pasteboard server a beat before the paste keystroke.
        try? await Task.sleep(for: .milliseconds(60))
        postCmdV()

        // Restore the user's clipboard after the target app has read ours.
        try? await Task.sleep(for: .milliseconds(500))
        pasteboard.clearContents()
        if let savedString {
            pasteboard.setString(savedString, forType: .string)
        }
    }

    private static func postCmdV() {
        let vKeycode: CGKeyCode = 9
        let source = CGEventSource(stateID: .combinedSessionState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeycode, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeycode, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
