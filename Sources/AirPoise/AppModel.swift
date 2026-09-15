import Foundation
import AppKit
import ApplicationServices
import CoreMotion
import Combine
import UserNotifications
import SwiftUI
import AirPoiseCore

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let motion = HeadMotionService()
    let pose = PoseEstimator()
    let gestures = GestureEngine()
    let coach = PostureCoach()
    let runner = ActionRunner()

    @Published var settings: AppSettings {
        didSet { persistSettings() }
    }
    @Published var connected = false
    @Published var available = false
    @Published var auth: CMAuthorizationStatus = .notDetermined
    @Published var live: HeadPose?
    @Published var snapshot: PostureSnapshot
    @Published var lastGesture: GestureEvent?
    @Published var lastActionNote: String = ""
    @Published var calibrating = false
    @Published var paused = false
    @Published var hudOpen = false
    @Published var onboarding = false
    @Published var accessibilityTrusted = false
    @Published var today: DailyStats
    @Published var hz: Double = 0
    @Published var ear: SensorEar = .unknown
    @Published var samples: Int = 0

    private var statsMap: [String: DailyStats]
    private var calibBuffer: [HeadSample] = []
    private var persistTimer: Timer?
    private var lastSampleHost: Date?
    private var settingsWindow: NSWindow?
    private var previewWindow: NSWindow?
    private let overlays = OverlayController()

    private init() {
        let loaded = Store.loadSettings()
        settings = loaded
        statsMap = Store.loadStats()
        let key = DailyStats.todayKey()
        let todayStats = statsMap[key] ?? DailyStats(day: key)
        today = todayStats
        snapshot = PostureSnapshot(
            band: .uncalibrated, flexionDeg: 0, lateralDeg: 0, totalDeg: 0,
            score: todayStats.score, dwell: 0, calibrated: false, hint: "Calibrate while sitting tall."
        )
        paused = loaded.globalPause
        coach.load(stats: todayStats)
        if let frame = loaded.gravityFrame {
            pose.restore(frame: frame)
        }

        motion.onSample = { [weak self] sample in
            Task { @MainActor in self?.handle(sample) }
        }
        motion.onConnection = { [weak self] ok in
            Task { @MainActor in
                self?.connected = ok
                if !ok { self?.live = nil }
            }
        }
        motion.onAvailability = { [weak self] ok in
            Task { @MainActor in self?.available = ok }
        }
        motion.onAuthorization = { [weak self] status in
            Task { @MainActor in self?.auth = status }
        }
        gestures.onGesture = { [weak self] event in
            Task { @MainActor in self?.handleGesture(event) }
        }
        coach.onSnapshot = { [weak self] snap in
            Task { @MainActor in self?.snapshot = snap }
        }
        coach.onEvent = { [weak self] event in
            Task { @MainActor in self?.handleCoach(event) }
        }

        persistTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.flushStats() }
        }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        refreshPermissions()
        onboarding = !loaded.onboardingComplete
        applySettings()
    }

    func start() {
        motion.start()
        overlays.prepare()
        refreshPermissions()
        runner.onResult = { [weak self] note in
            Task { @MainActor in
                if !note.isEmpty { self?.lastActionNote = note }
            }
        }
    }

    func stop() {
        motion.stop()
        flushStats(force: true)
        Store.saveSettings(settings)
    }

    func applySettings() {
        pose.config.invertPitch = settings.invertPitch
        pose.config.invertYaw = settings.invertYaw
        pose.config.invertRoll = settings.invertRoll
        pose.config.invertFlexion = settings.invertFlexion
        pose.config.invertLateral = settings.invertLateral
        pose.config.yawDriftCorrection = settings.yawDriftCorrection
        gestures.config = settings.gesture
        coach.config = settings.posture
        coach.config.invertFlexion = settings.invertFlexion
        paused = settings.globalPause
    }

    func rerunOnboarding() {
        settings.onboardingComplete = false
        onboarding = true
        save()
        NotificationCenter.default.post(name: .airPoiseShowOnboarding, object: nil)
    }

    func save() {
        applySettings()
        Store.saveSettings(settings)
    }

    func refreshPermissions() {
        accessibilityTrusted = AXIsProcessTrusted()
        auth = motion.authorizationStatus
        available = motion.isAvailable
    }

    func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        accessibilityTrusted = AXIsProcessTrustedWithOptions(opts)
    }

    func handle(_ sample: HeadSample) {
        samples += 1
        ear = sample.ear
        if calibrating {
            calibBuffer.append(sample)
        }
        // Stream restarts (idle, wake, resubscribe) reset Apple's relative
        // quaternion origin. Keep gravity posture; re-zero attitude.
        if pose.reference == nil {
            pose.recaptureAttitude(from: sample)
        } else if let last = lastSampleHost, sample.hostTime.timeIntervalSince(last) > 2.2 {
            pose.recaptureAttitude(from: sample)
            gestures.reset()
        }
        lastSampleHost = sample.hostTime
        let p = pose.process(sample)
        live = p
        hz = p.hz

        if !paused {
            coach.process(p)
            if settings.gesture.enabled {
                gestures.process(p)
            }
        }
        today = coach.stats
        overlays.sync(pose: p, snapshot: snapshot)
    }

    func beginCalibration() {
        if !available, live == nil {
            lastActionNote = "Wear AirPods Pro / 3 / 4 / Max first."
            return
        }
        calibrating = true
        calibBuffer.removeAll()
        overlays.showCalibration()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            self?.finishCalibration()
        }
    }

    func finishCalibration() {
        defer {
            calibrating = false
            overlays.hideCalibration()
        }
        let sample: HeadSample?
        if !calibBuffer.isEmpty {
            sample = average(calibBuffer.suffix(18))
        } else {
            sample = nil
        }
        guard let sample else {
            lastActionNote = "No motion data — wear compatible AirPods."
            return
        }
        pose.calibrate(from: sample)
        gestures.reset()
        coach.noteCalibration()
        settings.gravityFrame = pose.frame
        save()
        lastActionNote = "Calibrated upright posture."
        NSSound(named: "Tink")?.play()
    }

    func clearCalibration() {
        pose.clearCalibration()
        gestures.reset()
        settings.gravityFrame = nil
        lastActionNote = "Calibration cleared."
        save()
    }

    func togglePause() {
        settings.globalPause.toggle()
        paused = settings.globalPause
        save()
    }

    func testNudge() {
        overlays.showNudge(title: "Sit up a little", detail: "This is how a posture nudge looks.", tint: .posture)
        notify(title: "AirPoise", body: "Test nudge — your real ones will look like this.")
        if settings.posture.soundEnabled { NSSound(named: "Submarine")?.play() }
    }

    func binding(for kind: GestureKind) -> GestureBinding? {
        settings.bindings.first(where: { $0.gesture == kind })
    }

    func updateBinding(_ binding: GestureBinding) {
        if let i = settings.bindings.firstIndex(where: { $0.id == binding.id }) {
            settings.bindings[i] = binding
        } else if let i = settings.bindings.firstIndex(where: { $0.gesture == binding.gesture }) {
            settings.bindings[i] = binding
        } else {
            settings.bindings.append(binding)
        }
        save()
    }

    func openSettings() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView().environmentObject(self))
            let win = NSWindow(contentViewController: host)
            win.title = "AirPoise Settings"
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            win.setContentSize(NSSize(width: 660, height: 480))
            win.toolbarStyle = .unified
            win.center()
            win.isReleasedWhenClosed = false
            win.identifier = NSUserInterfaceItemIdentifier("airpoise.settings")
            settingsWindow = win
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: win,
                queue: .main
            ) { _ in
                NSApp.setActivationPolicy(.accessory)
            }
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func openPreview3D() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if previewWindow == nil {
            let host = NSHostingController(rootView: Preview3DView().environmentObject(self))
            let win = NSWindow(contentViewController: host)
            win.title = "AirPoise 3D Preview"
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            win.setContentSize(NSSize(width: 520, height: 520))
            win.center()
            win.isReleasedWhenClosed = false
            win.identifier = NSUserInterfaceItemIdentifier("airpoise.preview3d")
            previewWindow = win
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: win,
                queue: .main
            ) { _ in
                NSApp.setActivationPolicy(.accessory)
            }
        }
        previewWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - private

    private func handleGesture(_ event: GestureEvent) {
        // Repeat events keep stats/UI quiet and only fire for stepping actions.
        if event.repeated {
            guard !paused,
                  let bind = settings.bindings.first(where: { $0.gesture == event.kind && $0.enabled }),
                  bind.action.enabled,
                  bind.action.kind != .none else { return }
            switch bind.action.kind {
            case .volume, .brightness:
                runner.run(bind.action)
            default:
                break
            }
            return
        }
        lastGesture = event
        coach.noteGesture()
        today = coach.stats
        guard !paused else { return }
        guard let bind = settings.bindings.first(where: { $0.gesture == event.kind && $0.enabled }) else { return }
        guard bind.action.kind != .none, bind.action.enabled else { return }
        overlays.flashGesture(event.kind.title)
        lastActionNote = "\(event.kind.title) → \(bind.action.summary)"
        runner.run(bind.action)
    }

    private func handleCoach(_ event: CoachEvent) {
        switch event {
        case .nudge(let band, let hint):
            today = coach.stats
            let title: String
            switch band {
            case .slouch: title = "You're slouching"
            case .leaning: title = "Chin creeping forward"
            case .tilted: title = "Head is tilting"
            default: title = "Check your posture"
            }
            if settings.posture.overlayEnabled { overlays.showNudge(title: title, detail: hint, tint: .posture) }
            if settings.posture.notificationsEnabled { notify(title: title, body: hint) }
            if settings.posture.soundEnabled { NSSound(named: "Purr")?.play() }
            if settings.posture.speakEnabled {
                runner.speak(hint)
            }
        case .recovered:
            overlays.hideNudge()
        case .takeBreak:
            let body = "You've been still a while. Stand, roll the shoulders, look far away."
            if settings.posture.overlayEnabled { overlays.showNudge(title: "Time to move", detail: body, tint: .breakTime) }
            if settings.posture.notificationsEnabled { notify(title: "Time to move", body: body) }
            if settings.posture.soundEnabled { NSSound(named: "Glass")?.play() }
        case .calibrated:
            break
        }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = settings.posture.soundEnabled ? .default : nil
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    private func persistSettings() {
        Store.saveSettings(settings)
        applySettings()
    }

    private func flushStats(force: Bool = false) {
        today = coach.stats
        statsMap[today.day] = today
        Store.saveStats(statsMap)
    }

    private func average(_ samples: ArraySlice<HeadSample>) -> HeadSample? {
        guard let first = samples.first else { return nil }
        var g = Vec3.zero
        var a = Vec3.zero
        var r = Vec3.zero
        var q = first.attitude
        for s in samples {
            g = g + s.gravity
            a = a + s.userAcceleration
            r = r + s.rotationRate
            q = s.attitude
        }
        let n = Double(samples.count)
        return HeadSample(
            time: samples.last!.time,
            hostTime: Date(),
            attitude: q,
            gravity: Vec3(g.x / n, g.y / n, g.z / n),
            userAcceleration: Vec3(a.x / n, a.y / n, a.z / n),
            rotationRate: Vec3(r.x / n, r.y / n, r.z / n),
            heading: first.heading,
            ear: samples.last!.ear
        )
    }
}

extension Notification.Name {
    static let airPoiseShowOnboarding = Notification.Name("AirPoiseShowOnboarding")
}

extension CMAuthorizationStatus {
    var label: String {
        switch self {
        case .authorized: return "Motion allowed"
        case .denied: return "Motion denied"
        case .restricted: return "Motion restricted"
        case .notDetermined: return "Motion not asked"
        @unknown default: return "Motion unknown"
        }
    }
}
