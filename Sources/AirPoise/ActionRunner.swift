import Foundation
import AppKit
import AVFoundation
import ApplicationServices
import Carbon.HIToolbox
import UserNotifications
import AirPoiseCore

final class ActionRunner: @unchecked Sendable {
    private let speech = AVSpeechSynthesizer()
    var onResult: ((String) -> Void)?

    func run(_ action: BoundAction) {
        guard action.enabled else { onResult?("Action is disabled."); return }
        guard action.kind != .none else { onResult?("Nothing bound to this gesture yet — assign one in Settings → Actions."); return }
        DispatchQueue.main.async {
            self.onResult?(self.execute(action))
        }
    }

    func speak(_ text: String) {
        DispatchQueue.main.async {
            let u = AVSpeechUtterance(string: text)
            u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
            self.speech.stopSpeaking(at: .immediate)
            self.speech.speak(u)
        }
    }

    private func needAccessibility() -> Bool { !AXIsProcessTrusted() }

    /// Fires the action; returns "" on success or a short reason otherwise.
    private func execute(_ action: BoundAction) -> String {
        switch action.kind {
        case .none:
            return "Nothing bound."

        case .keystroke:
            guard let ks = action.keystroke else { return "No keystroke recorded — record one in Settings." }
            guard !needAccessibility() else { return "Needs Accessibility permission (Settings → General → Grant)." }
            postKeystroke(ks)
            return ""

        case .shortcutApp:
            guard let name = action.shortcutName, !name.isEmpty else { return "No Shortcuts name set." }
            launch("/usr/bin/shortcuts", ["run", name])
            return ""

        case .openURL:
            guard let s = action.url, let url = URL(string: s), url.scheme != nil else { return "Invalid URL." }
            NSWorkspace.shared.open(url)
            return ""

        case .openApp:
            guard let path = action.appPath, !path.isEmpty else { return "No app chosen." }
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            return ""

        case .shell:
            guard let cmd = action.shell, !cmd.isEmpty else { return "Empty shell command." }
            launch("/bin/zsh", ["-lc", cmd])
            return ""

        case .appleScript:
            guard let src = action.appleScript, !src.isEmpty else { return "Empty AppleScript." }
            var err: NSDictionary?
            NSAppleScript(source: src)?.executeAndReturnError(&err)
            if let err { return "AppleScript error: \(err[NSAppleScript.errorMessage] ?? "unknown")." }
            return ""

        case .notification:
            let content = UNMutableNotificationContent()
            content.title = action.label.isEmpty ? "AirPoise" : action.label
            content.body = action.text ?? ""
            content.sound = .default
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            )
            NSSound(named: "Tink")?.play()
            return ""

        case .speak:
            speak(action.text ?? action.label)
            return ""

        case .media:
            switch action.media ?? .playPause {
            case .playPause: postMediaKey(NX_KEYTYPE_PLAY)
            case .next: postMediaKey(NX_KEYTYPE_NEXT)
            case .previous: postMediaKey(NX_KEYTYPE_PREVIOUS)
            case .mute, .unmute: postMediaKey(NX_KEYTYPE_MUTE)
            }
            return ""

        case .volume:
            let step = Swift.max(1, Swift.min(50, action.amount))
            switch action.volume ?? .up {
            case .down: return runVolumeScript(delta: -step)
            case .muteToggle: return runVolumeMute()
            case .up: return runVolumeScript(delta: step)
            }

        case .brightness:
            let steps = Swift.max(1, Swift.min(16, action.amount))
            let key = action.brightness == .down ? NX_KEYTYPE_BRIGHTNESS_DOWN : NX_KEYTYPE_BRIGHTNESS_UP
            for _ in 0..<steps {
                postMediaKey(key)
                usleep(30_000)
            }
            return ""

        case .system:
            return runSystem(action.system ?? .missionControl)

        case .pasteText:
            guard let text = action.text, !text.isEmpty else { return "No paste text set." }
            guard !needAccessibility() else { return "Needs Accessibility permission (Settings → General → Grant)." }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            postKeystroke(Keystroke(keyCode: UInt16(kVK_ANSI_V), command: true, display: "⌘V"))
            return ""
        }
    }

    // MARK: - Keystrokes / system

    private func runSystem(_ verb: SystemVerb) -> String {
        func key(_ msg: String, _ code: Int, control: Bool = false, command: Bool = false, shift: Bool = false) -> String {
            guard !needAccessibility() else { return "Needs Accessibility permission (Settings → General → Grant)." }
            postKeystroke(Keystroke(
                keyCode: UInt16(code),
                shift: shift, control: control, command: command,
                display: msg
            ))
            return ""
        }

        switch verb {
        case .missionControl:
            return key("⌃↑", kVK_UpArrow, control: true)
        case .appExpose:
            return key("⌃↓", kVK_DownArrow, control: true)
        case .showDesktop:
            return key("F11", kVK_F11)
        case .notificationCenter:
            var err: NSDictionary?
            NSAppleScript(source: "tell application \"System Events\" to tell application process \"ControlCenter\" to click (menu bar item 1 of menu bar 1 whose description is \"Notification Center\")")?.executeAndReturnError(&err)
            if err != nil {
                // Fallback: just open DateTime settings sheet is silly; try keystroke off.
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/CoreServices/ControlCenter.app"))
            }
            return ""
        case .launchpad:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Launchpad.app"))
            return ""
        case .spotlight:
            return key("⌘Space", kVK_Space, command: true)
        case .screenshot:
            return key("⇧⌘3", kVK_ANSI_3, command: true, shift: true)
        case .screenshotSelection:
            return key("⇧⌘4", kVK_ANSI_4, command: true, shift: true)
        case .lockScreen:
            return key("⌃⌘Q", kVK_ANSI_Q, control: true, command: true)
        case .sleepDisplay:
            launch("/usr/bin/pmset", ["displaysleepnow"])
            return ""
        case .emptyTrash:
            var err: NSDictionary?
            NSAppleScript(source: "tell application \"Finder\" to empty the trash")?.executeAndReturnError(&err)
            return err.map { "Finder: \($0[NSAppleScript.errorMessage] ?? "error")" } ?? ""
        case .switchSpaceLeft:
            return key("⌃←", kVK_LeftArrow, control: true)
        case .switchSpaceRight:
            return key("⌃→", kVK_RightArrow, control: true)
        }
    }

    private func postKeystroke(_ ks: Keystroke) {
        var flags = CGEventFlags()
        if ks.shift { flags.insert(.maskShift) }
        if ks.control { flags.insert(.maskControl) }
        if ks.option { flags.insert(.maskAlternate) }
        if ks.command { flags.insert(.maskCommand) }
        if ks.fn { flags.insert(.maskSecondaryFn) }
        let src = CGEventSource(stateID: .hidSystemState)
        if let down = CGEvent(keyboardEventSource: src, virtualKey: ks.keyCode, keyDown: true) {
            down.flags = flags
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: ks.keyCode, keyDown: false) {
            up.flags = flags
            up.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Media/brightness keys

    private func postMediaKey(_ key: Int32) {
        // Post the system-defined event twice: at the annotated session tap (for
        // trusted listeners) and at the HID tap (for the system). This is the only
        // reliable way to make play/next/volume/etc work on modern macOS without
        // private APIs.
        func event(down: Bool) -> NSEvent? {
            let data1 = (Int(key) << 16) | (down ? 0x0A00 : 0x0B00)
            return NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(down ? 0x0A00 : 0x0B00)),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            )
        }
        for down in [true, false] {
            guard let ev = event(down: down), let cg = ev.cgEvent else { continue }
            cg.post(tap: .cgSessionEventTap)
        }
    }

    // MARK: - AppleScript helpers

    private func runVolumeScript(delta: Int) -> String {
        runAppleScript("""
            set s to get volume settings
            set v to output volume of s
            set output volume (max(0, min(100, v + (\(delta)))))
            if output muted of s then set volume without output muted
            """)
    }

    private func runVolumeMute() -> String {
        runAppleScript("""
            if output muted of (get volume settings) then
                set volume without output muted
            else
                set volume with output muted
            end if
            """)
    }

    @discardableResult
    private func runAppleScript(_ src: String) -> String {
        var err: NSDictionary?
        NSAppleScript(source: src)?.executeAndReturnError(&err)
        if let err { return "\(err[NSAppleScript.errorMessage] ?? "AppleScript error")." }
        return ""
    }

    private func launch(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }
}

// Media key usages (public NX constants via system-defined event subtype 8).
private let NX_KEYTYPE_SOUND_UP: Int32 = 0
private let NX_KEYTYPE_SOUND_DOWN: Int32 = 1
private let NX_KEYTYPE_BRIGHTNESS_UP: Int32 = 2
private let NX_KEYTYPE_BRIGHTNESS_DOWN: Int32 = 3
private let NX_KEYTYPE_MUTE: Int32 = 7
private let NX_KEYTYPE_PLAY: Int32 = 16
private let NX_KEYTYPE_NEXT: Int32 = 17
private let NX_KEYTYPE_PREVIOUS: Int32 = 18
