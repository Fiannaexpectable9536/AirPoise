import Foundation

public enum ActionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case keystroke
    case shortcutApp
    case openURL
    case openApp
    case shell
    case appleScript
    case notification
    case speak
    case media
    case volume
    case brightness
    case system
    case pasteText

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: return "Do nothing"
        case .keystroke: return "Keyboard shortcut"
        case .shortcutApp: return "Run Shortcuts action"
        case .openURL: return "Open URL"
        case .openApp: return "Open app"
        case .shell: return "Run shell command"
        case .appleScript: return "Run AppleScript"
        case .notification: return "Notification"
        case .speak: return "Speak"
        case .media: return "Media"
        case .volume: return "Volume"
        case .brightness: return "Brightness"
        case .system: return "System"
        case .pasteText: return "Paste text"
        }
    }
}

public enum MediaVerb: String, Codable, CaseIterable, Sendable {
    case playPause, next, previous, mute, unmute
}

public enum VolumeVerb: String, Codable, CaseIterable, Sendable {
    case up, down, muteToggle
}

public enum BrightnessVerb: String, Codable, CaseIterable, Sendable {
    case up, down
}

public enum SystemVerb: String, Codable, CaseIterable, Sendable {
    case missionControl, appExpose, showDesktop, notificationCenter
    case launchpad, spotlight, screenshot, screenshotSelection
    case lockScreen, sleepDisplay, emptyTrash
    case switchSpaceLeft, switchSpaceRight
}

public struct Keystroke: Codable, Equatable, Sendable {
    public var keyCode: UInt16
    public var shift: Bool
    public var control: Bool
    public var option: Bool
    public var command: Bool
    public var fn: Bool
    public var display: String

    public init(keyCode: UInt16, shift: Bool = false, control: Bool = false, option: Bool = false, command: Bool = false, fn: Bool = false, display: String) {
        self.keyCode = keyCode
        self.shift = shift; self.control = control; self.option = option
        self.command = command; self.fn = fn; self.display = display
    }

    public static let playPause = Keystroke(keyCode: 16, display: "Play/Pause") // NX dummy; media uses HID
}

public struct BoundAction: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: ActionKind
    public var label: String
    public var enabled: Bool
    public var keystroke: Keystroke?
    public var shortcutName: String?
    public var url: String?
    public var appPath: String?
    public var shell: String?
    public var appleScript: String?
    public var text: String?
    public var media: MediaVerb?
    public var volume: VolumeVerb?
    public var brightness: BrightnessVerb?
    public var system: SystemVerb?
    /// Volume: percent change per fire. Brightness: steps per fire.
    public var amount: Int = 5

    public enum CodingKeys: String, CodingKey {
        case id, kind, label, enabled, keystroke, shortcutName, url, appPath
        case shell, appleScript, text, media, volume, brightness, system, amount
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(ActionKind.self, forKey: .kind)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        keystroke = try c.decodeIfPresent(Keystroke.self, forKey: .keystroke)
        shortcutName = try c.decodeIfPresent(String.self, forKey: .shortcutName)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        appPath = try c.decodeIfPresent(String.self, forKey: .appPath)
        shell = try c.decodeIfPresent(String.self, forKey: .shell)
        appleScript = try c.decodeIfPresent(String.self, forKey: .appleScript)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        media = try c.decodeIfPresent(MediaVerb.self, forKey: .media)
        volume = try c.decodeIfPresent(VolumeVerb.self, forKey: .volume)
        brightness = try c.decodeIfPresent(BrightnessVerb.self, forKey: .brightness)
        system = try c.decodeIfPresent(SystemVerb.self, forKey: .system)
        amount = try c.decodeIfPresent(Int.self, forKey: .amount) ?? 5
    }

    public init(
        id: UUID = UUID(),
        kind: ActionKind = .none,
        label: String = "",
        enabled: Bool = true,
        keystroke: Keystroke? = nil,
        shortcutName: String? = nil,
        url: String? = nil,
        appPath: String? = nil,
        shell: String? = nil,
        appleScript: String? = nil,
        text: String? = nil,
        media: MediaVerb? = nil,
        volume: VolumeVerb? = nil,
        brightness: BrightnessVerb? = nil,
        system: SystemVerb? = nil,
        amount: Int = 5
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.enabled = enabled
        self.keystroke = keystroke
        self.shortcutName = shortcutName
        self.url = url
        self.appPath = appPath
        self.shell = shell
        self.appleScript = appleScript
        self.text = text
        self.media = media
        self.volume = volume
        self.brightness = brightness
        self.system = system
        self.amount = amount
    }

    public var summary: String {
        if !label.isEmpty { return label }
        switch kind {
        case .none: return "Unassigned"
        case .keystroke: return keystroke?.display ?? "Shortcut"
        case .shortcutApp: return shortcutName ?? "Shortcuts"
        case .openURL: return url ?? "URL"
        case .openApp: return appPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "App"
        case .shell: return shell ?? "Shell"
        case .appleScript: return "AppleScript"
        case .notification: return text ?? "Notify"
        case .speak: return text ?? "Speak"
        case .media: return media?.rawValue ?? "Media"
        case .volume: return volume?.rawValue ?? "Volume"
        case .brightness: return brightness?.rawValue ?? "Brightness"
        case .system: return system?.rawValue ?? "System"
        case .pasteText: return text ?? "Paste"
        }
    }

    public static func keystroke(_ ks: Keystroke, label: String) -> BoundAction {
        BoundAction(kind: .keystroke, label: label, keystroke: ks)
    }
    public static func media(_ v: MediaVerb, label: String) -> BoundAction {
        BoundAction(kind: .media, label: label, media: v)
    }
    public static func system(_ v: SystemVerb, label: String) -> BoundAction {
        BoundAction(kind: .system, label: label, system: v)
    }
}

public struct GestureBinding: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var gesture: GestureKind
    public var action: BoundAction
    public var enabled: Bool
    public var requireIdleHands: Bool

    public init(id: UUID = UUID(), gesture: GestureKind, action: BoundAction, enabled: Bool = true, requireIdleHands: Bool = false) {
        self.id = id
        self.gesture = gesture
        self.action = action
        self.enabled = enabled
        self.requireIdleHands = requireIdleHands
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var posture = PostureConfig()
    public var gesture = GestureConfig()
    public var invertPitch = false
    public var invertYaw = false
    public var invertRoll = false
    public var invertFlexion = false
    public var invertLateral = false
    public var launchAtLogin = false
    public var showDegreesInMenu = true
    public var pauseGesturesWhenSlouchNudge = false
    public var globalPause = false
    public var menuBarStyle: String = "iconAndTilt"
    public var bindings: [GestureBinding] = AppSettings.defaultBindings()
    public var calibrationFlexSign: Double = 1
    public var onboardingComplete = false
    public var gravityFrame: GravityFrame?
    public var yawDriftCorrection = true

    public init() {}

    public static func defaultBindings() -> [GestureBinding] {
        [
            GestureBinding(gesture: .doubleNod, action: .media(.playPause, label: "Play / Pause")),
            GestureBinding(gesture: .lookLeft, action: .system(.switchSpaceLeft, label: "Space left")),
            GestureBinding(gesture: .lookRight, action: .system(.switchSpaceRight, label: "Space right")),
            GestureBinding(gesture: .doubleShake, action: BoundAction(kind: .notification, label: "Ping", text: "AirPoise is listening.")),
            GestureBinding(gesture: .tiltLeftHold, action: .system(.missionControl, label: "Mission Control")),
            GestureBinding(gesture: .nod, action: BoundAction(kind: .none, label: "Unassigned")),
            GestureBinding(gesture: .shake, action: BoundAction(kind: .none, label: "Unassigned")),
            GestureBinding(gesture: .lookUp, action: BoundAction(kind: .none, label: "Unassigned")),
            GestureBinding(gesture: .lookDown, action: BoundAction(kind: .none, label: "Unassigned")),
            GestureBinding(gesture: .tiltLeft, action: BoundAction(kind: .none, label: "Unassigned")),
            GestureBinding(gesture: .tiltRight, action: BoundAction(kind: .none, label: "Unassigned")),
            GestureBinding(gesture: .tiltRightHold, action: BoundAction(kind: .none, label: "Unassigned")),
            GestureBinding(gesture: .leanForward, action: BoundAction(kind: .none, label: "Unassigned")),
            GestureBinding(gesture: .leanBack, action: BoundAction(kind: .none, label: "Unassigned")),
            GestureBinding(gesture: .rollLeft, action: BoundAction(kind: .none, label: "Unassigned")),
            GestureBinding(gesture: .rollRight, action: BoundAction(kind: .none, label: "Unassigned"))
        ]
    }
}

public enum Store {
    public static var appSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("AirPoise", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static var settingsURL: URL { appSupport.appendingPathComponent("settings.json") }
    public static var statsURL: URL { appSupport.appendingPathComponent("stats.json") }
    public static var logURL: URL { appSupport.appendingPathComponent("events.log") }

    public static func loadSettings() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsURL) else { return AppSettings() }
        var settings = (try? JSONDecoder().decode(AppSettings.self, from: data)) ?? AppSettings()
        mergeDefaultBindings(&settings)
        return settings
    }

    private static func mergeDefaultBindings(_ settings: inout AppSettings) {
        let existing = Set(settings.bindings.map(\.gesture))
        for extra in AppSettings.defaultBindings() where !existing.contains(extra.gesture) {
            settings.bindings.append(extra)
        }
    }

    public static func saveSettings(_ s: AppSettings) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(s) {
            try? data.write(to: settingsURL, options: .atomic)
        }
    }

    public static func loadStats() -> [String: DailyStats] {
        guard let data = try? Data(contentsOf: statsURL),
              let decoded = try? JSONDecoder().decode([String: DailyStats].self, from: data)
        else { return [:] }
        return decoded
    }

    public static func saveStats(_ map: [String: DailyStats]) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(map) {
            try? data.write(to: statsURL, options: .atomic)
        }
    }
}
