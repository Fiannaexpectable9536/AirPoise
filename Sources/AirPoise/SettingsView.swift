import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers
import AirPoiseCore

enum SettingsPage: String, CaseIterable, Identifiable, Hashable {
    case general = "General"
    case posture = "Posture"
    case gestures = "Gestures"
    case actions = "Actions"
    case today = "Today"
    case about = "About"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .posture: return "figure.stand"
        case .gestures: return "move.3d"
        case .actions: return "bolt.fill"
        case .today: return "chart.bar.xaxis"
        case .about: return "info.circle"
        }
    }

    var color: Color {
        switch self {
        case .general: return Color(.systemGray)
        case .posture: return .green
        case .gestures: return .purple
        case .actions: return .orange
        case .today: return .blue
        case .about: return .teal
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var selection: SettingsPage = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $selection) { page in
                Label {
                    Text(page.rawValue)
                } icon: {
                    SettingsIcon(symbol: page.symbol, color: page.color)
                }
                .tag(page)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 148, ideal: 168, max: 200)
        } detail: {
            Group {
                switch selection {
                case .general: GeneralSettings()
                case .posture: PostureSettings()
                case .gestures: GestureSettings()
                case .actions: BindingsSettings()
                case .today: StatsSettings()
                case .about: AboutSettings()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(selection.rawValue)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 620, idealWidth: 660, minHeight: 460)
    }
}

// MARK: - General

struct GeneralSettings: View {
    @EnvironmentObject var model: AppModel
    @State private var login = SMAppService.mainApp.status == .enabled

    private var yawDriftBinding: Binding<Bool> {
        Binding(
            get: { model.settings.yawDriftCorrection },
            set: { model.settings.yawDriftCorrection = $0; model.save() }
        )
    }

    var body: some View {
        Form {
            Section("Headphones") {
                LabeledContent("Motion sensor") {
                    HStack(spacing: 5) {
                        Circle().fill(model.available ? Color.green : Color.secondary.opacity(0.4)).frame(width: 7, height: 7)
                        Text(model.available ? "Ready" : "Not available")
                    }
                }
                LabeledContent("Stream") {
                    HStack(spacing: 5) {
                        Circle().fill(model.live != nil ? Color.green : Color.secondary.opacity(0.4)).frame(width: 7, height: 7)
                        Text(model.live != nil ? String(format: "%.0f Hz · %@ bud", model.hz, model.ear == .left ? "left" : model.ear == .right ? "right" : "auto") : "Idle")
                    }
                }
                LabeledContent("Supported", value: "AirPods Pro · AirPods 3 / 4 · AirPods Max · Beats Fit Pro")
                LabeledContent("Authorization", value: model.auth.label)
            }

            Section("Permissions") {
                HStack {
                    Label(model.accessibilityTrusted ? "Accessibility allowed" : "Accessibility needed for custom shortcuts",
                          systemImage: model.accessibilityTrusted ? "checkmark.shield.fill" : "shield.lefthalf.filled.trianglebadge.exclamationmark")
                    .foregroundStyle(model.accessibilityTrusted ? .green : .orange)
                    Spacer()
                    if !model.accessibilityTrusted {
                        Button("Grant…") { model.requestAccessibility() }
                            .controlSize(.small)
                    }
                }
                Text("Motion & Fitness is requested automatically. If denied: System Settings → Privacy & Security → Motion & Fitness.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Startup & menu bar") {
                Toggle("Launch at login", isOn: $login)
                    .onChange(of: login) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch {
                            login = SMAppService.mainApp.status == .enabled
                        }
                    }
                Toggle("Show degrees in menu bar", isOn: $model.settings.showDegreesInMenu)
                Picker("Menu bar style", selection: $model.settings.menuBarStyle) {
                    Text("Icon").tag("icon")
                    Text("Icon + tilt").tag("iconAndTilt")
                    Text("Score").tag("score")
                }
            }

            Section("Accuracy") {
                Toggle("Yaw drift correction", isOn: yawDriftBinding)
                Text("Headphone yaw drifts slowly (no magnetometer in the buds). While your head is still, AirPoise bleeds yaw back to center; deliberate turns are untouched.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Axis fix") {
                Text("AirPoise uses Apple's headphone frame (x = right ear, y = nose, z = crown). If one direction reads backwards on your buds, flip it here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Invert pitch (nod)", isOn: $model.settings.invertPitch)
                Toggle("Invert yaw (look left / right)", isOn: $model.settings.invertYaw)
                Toggle("Invert roll (ear tilt)", isOn: $model.settings.invertRoll)
                Toggle("Invert head-forward", isOn: $model.settings.invertFlexion)
                Toggle("Invert head-side", isOn: $model.settings.invertLateral)
            }

            Section {
                Button("Re-run onboarding") { model.rerunOnboarding() }
                Button("Clear calibration", role: .destructive, action: model.clearCalibration)
            }
        }
        .formStyle(.grouped)
        .onAppear { model.refreshPermissions(); login = SMAppService.mainApp.status == .enabled }
        .onChange(of: model.settings) { _, _ in model.save() }
    }
}

// MARK: - Posture

struct PostureSettings: View {
    @EnvironmentObject var model: AppModel
    var p: Binding<PostureConfig> { $model.settings.posture }

    var body: some View {
        Form {
            Section {
                Toggle("Posture coach", isOn: p.enabled)
                Text("Measures how far your chin drifts forward (flexion) and how far your head lists sideways, relative to your calibrated upright.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Thresholds") {
                SliderRow(title: "Excellent ≤", value: p.excellentMax, range: 3...15, unit: "°")
                SliderRow(title: "Good ≤", value: p.goodMax, range: 8...22, unit: "°")
                SliderRow(title: "Nudge after", value: p.leanMax, range: 14...35, unit: "°")
                SliderRow(title: "Side-tilt warn", value: p.lateralWarn, range: 8...30, unit: "°")
            }

            Section("Timing") {
                SliderRow(title: "Hold before nudge", value: p.slouchHold, range: 3...30, unit: "s")
                SliderRow(title: "Cooldown between nudges", value: p.nudgeCooldown, range: 20...300, unit: "s")
                SliderRow(title: "Break reminder every", value: p.breakEveryMinutes, range: 0...120, unit: " min")
                Text("Hysteresis on thresholds plus these holds keep the coach from nagging over noise.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Nudge style") {
                Toggle("Overlay card", isOn: p.overlayEnabled)
                Toggle("Notification", isOn: p.notificationsEnabled)
                Toggle("Sound", isOn: p.soundEnabled)
                Toggle("Speak the cue", isOn: p.speakEnabled)
                Toggle("Ignore while walking", isOn: p.ignoreWhenWalking)
            }

            Section {
                Button("Send test nudge") { model.testNudge() }
            }
        }
        .formStyle(.grouped)
        .onChange(of: model.settings) { _, _ in model.save() }
    }
}

// MARK: - Gestures

struct GestureSettings: View {
    @EnvironmentObject var model: AppModel
    var g: Binding<GestureConfig> { $model.settings.gesture }

    var body: some View {
        Form {
            Section {
                Toggle("Head-gesture shortcuts", isOn: g.enabled)
                Text("Gestures fire on excursions that return to center, relative to a slow rest pose — sitting still in a slouch never counts as a nod.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Feel") {
                SliderRow(title: "Sensitivity", value: g.sensitivity, range: 0...1, unit: "", percent: true)
                SliderRow(title: "Cooldown", value: g.cooldown, range: 0.2...2.0, unit: "s", decimals: 2)
                SliderRow(title: "Hold duration", value: g.holdDuration, range: 0.25...1.5, unit: "s", decimals: 2)
                SliderRow(title: "Hold repeat every", value: g.holdRepeatInterval, range: 0.1...1.0, unit: "s", decimals: 2)
            }
            Section {
                Text("Hold-to-repeat only fires for stepping actions (volume, brightness). Other bound actions ignore holds after their first fire.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("The gestures") {
                ForEach(GestureKind.allCases) { kind in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(kind.title)
                            .frame(width: 128, alignment: .leading)
                        Text(kind.hint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: model.settings) { _, _ in model.save() }
    }
}

// MARK: - Actions

struct BindingsSettings: View {
    @EnvironmentObject var model: AppModel
    @State private var selected: GestureKind = .doubleNod

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(GestureKind.allCases) { kind in
                        GestureChip(
                            kind: kind,
                            summary: model.binding(for: kind)?.action.summary ?? "—",
                            isSelected: selected == kind
                        )
                        .onTapGesture { selected = kind }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            Divider()

            if let idx = model.settings.bindings.firstIndex(where: { $0.gesture == selected }) {
                ActionEditor(binding: $model.settings.bindings[idx])
            } else {
                ContentUnavailableView(
                    "No binding for \(selected.title)",
                    systemImage: "bolt.slash",
                    description: Text("Add one to make this gesture do something.")
                )
                .frame(maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    Button("Add binding") {
                        model.settings.bindings.append(GestureBinding(gesture: selected, action: BoundAction()))
                    }
                    .padding(.bottom, 16)
                }
            }
        }
        .onChange(of: model.settings) { _, _ in model.save() }
    }
}

struct GestureChip: View {
    let kind: GestureKind
    let summary: String
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(kind.title)
                .font(.system(size: 11.5, weight: .semibold))
            Text(summary)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(
            isSelected ? AnyShapeStyle(.tint.opacity(0.9)) : AnyShapeStyle(Color.primary.opacity(0.06)),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .foregroundStyle(isSelected ? .white : .primary)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Action editor

struct ActionEditor: View {
    @Binding var binding: GestureBinding

    var body: some View {
        Form {
            Section {
                Toggle("Enabled", isOn: $binding.enabled)
                Picker("Action type", selection: $binding.action.kind) {
                    ForEach(ActionKind.allCases) { k in
                        Text(k.title).tag(k)
                    }
                }
                TextField("Label", text: $binding.action.label, prompt: Text("Shown next to the gesture"))
            }

            switch binding.action.kind {
            case .none:
                ContentUnavailableView(
                    "Unassigned",
                    systemImage: "circle.slash",
                    description: Text("Pick an action type above.")
                )
                .frame(minHeight: 120)
            case .keystroke:
                Section("Keyboard shortcut") {
                    HStack {
                        Text(binding.action.keystroke?.display ?? "Awaiting keys…")
                            .font(.headline.monospaced())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                        KeyCaptureButton { ks in
                            binding.action.keystroke = ks
                            if binding.action.label.isEmpty { binding.action.label = ks.display }
                        }
                        .controlSize(.small)
                    }
                    Text("Requires Accessibility permission.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .shortcutApp:
                Section("Shortcuts") {
                    TextField("Shortcut name", text: string($binding.action.shortcutName), prompt: Text("Exact name from the Shortcuts app"))
                }
            case .openURL:
                Section("URL") {
                    TextField("https://…", text: string($binding.action.url))
                        .autocorrectionDisabled()
                }
            case .openApp:
                Section("Application") {
                    HStack {
                        TextField("Path", text: string($binding.action.appPath))
                        Button("Choose…") { pickApp() }.controlSize(.small)
                    }
                }
            case .shell:
                Section("Shell command") {
                    TextField("zsh -lc …", text: string($binding.action.shell), axis: .vertical)
                        .lineLimit(2, reservesSpace: true)
                        .font(.body.monospaced())
                }
            case .appleScript:
                Section("AppleScript") {
                    TextField("tell application …", text: string($binding.action.appleScript), axis: .vertical)
                        .lineLimit(4, reservesSpace: true)
                        .font(.body.monospaced())
                }
            case .notification:
                Section("Notification") {
                    TextField("Body", text: string($binding.action.text))
                }
            case .speak:
                Section("Speak") {
                    TextField("Text to say", text: string($binding.action.text))
                }
            case .pasteText:
                Section("Paste text") {
                    TextField("Text to paste", text: string($binding.action.text), axis: .vertical)
                        .lineLimit(2, reservesSpace: true)
                    Text("Copies the text and sends ⌘V. Requires Accessibility.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .media:
                Section("Media key") {
                    Picker("Key", selection: opt($binding.action.media)) {
                        ForEach(MediaVerb.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }
            case .volume:
                Section("Volume") {
                    Picker("Direction", selection: opt($binding.action.volume)) {
                        ForEach(VolumeVerb.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Stepper(value: amount($binding.action, min: 1, max: 50), in: 1...50) {
                        HStack {
                            Text("Change per fire")
                            Spacer()
                            Text("\(binding.action.amount)%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("Hold keeps repeating every 0.35s (see Gestures).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .brightness:
                Section("Brightness") {
                    Picker("Direction", selection: opt($binding.action.brightness)) {
                        ForEach(BrightnessVerb.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Stepper(value: amount($binding.action, min: 1, max: 16), in: 1...16) {
                        HStack {
                            Text("Steps per fire")
                            Spacer()
                            Text("\(binding.action.amount)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("Hold keeps repeating every 0.35s (see Gestures).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .system:
                Section("System action") {
                    Picker("Action", selection: opt($binding.action.system)) {
                        ForEach(SystemVerb.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }
            }

            Section {
                Button {
                    AppModel.shared.runner.run(binding.action)
                } label: {
                    Label("Fire now (test)", systemImage: "play.fill")
                }
                .disabled(binding.action.kind == .none)
            }
        }
        .formStyle(.grouped)
    }

    private func string(_ b: Binding<String?>) -> Binding<String> {
        Binding(get: { b.wrappedValue ?? "" }, set: { b.wrappedValue = $0 })
    }

    private func opt<T: Hashable & CaseIterable>(_ b: Binding<T?>) -> Binding<T> {
        Binding(
            get: { b.wrappedValue ?? T.allCases.first! },
            set: { b.wrappedValue = $0 }
        )
    }

    private func amount(_ action: Binding<BoundAction>, min lo: Int, max hi: Int) -> Binding<Int> {
        Binding(
            get: { Swift.max(lo, Swift.min(hi, action.wrappedValue.amount)) },
            set: { newValue in
                action.wrappedValue.amount = Swift.max(lo, Swift.min(hi, newValue))
            }
        )
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url {
            binding.action.appPath = url.path
        }
    }
}

// MARK: - Today

struct StatsSettings: View {
    @EnvironmentObject var model: AppModel
    var s: DailyStats { model.today }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today's posture")
                        .font(.title2.weight(.semibold))
                    Text(Date(), format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 16) {
                    ScoreRing(score: s.score)
                        .scaleEffect(1.8)
                        .frame(width: 90, height: 90)
                    VStack(alignment: .leading, spacing: 6) {
                        StatRow(label: "Worn", value: hm(s.worn))
                        StatRow(label: "Nudges", value: "\(s.nudges)")
                        StatRow(label: "Gestures fired", value: "\(s.gestures)")
                        StatRow(label: "Breaks taken", value: "\(s.breaksTaken)")
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 10) {
                    Bar(label: "Excellent", seconds: s.excellent, color: .green, total: max(1, s.totalTracked))
                    Bar(label: "Good", seconds: s.good, color: .mint, total: max(1, s.totalTracked))
                    Bar(label: "Leaning", seconds: s.leaning, color: .orange, total: max(1, s.totalTracked))
                    Bar(label: "Slouch", seconds: s.slouch, color: .red, total: max(1, s.totalTracked))
                    Bar(label: "Tilted", seconds: s.tilted, color: .yellow, total: max(1, s.totalTracked))
                }

                Text("All processing is on-device. Motion data never leaves this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .frame(minWidth: 420)
    }

    private func hm(_ sec: Double) -> String {
        let m = Int(sec / 60)
        return String(format: "%d:%02d", m / 60, m % 60)
    }
}

struct StatRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit().fontWeight(.semibold)
        }
        .font(.callout)
    }
}

struct Bar: View {
    let label: String
    let seconds: Double
    let color: Color
    let total: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: "%.0f min", seconds / 60)).foregroundStyle(.secondary)
            }
            .font(.callout)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.07))
                    Capsule().fill(color.gradient)
                        .frame(width: max(3, g.size.width * seconds / total))
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - About

struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "airpods.pro")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(.tint)
            Text("AirPoise")
                .font(.title.bold())
            Text("Posture coaching and head-gesture shortcuts,\npowered by Apple's fused AirPods motion pipeline.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("Version 1.0 · macOS 14+")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Shared rows

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var unit: String
    var decimals: Int = 0
    var percent: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
            Slider(value: $value, in: range)
                .frame(maxWidth: 200)
            Text(percent ? String(format: "%.0f%%", value * 100) : String(format: "%.\(decimals)F%@", value, unit))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
    }
}

// MARK: - Key capture

struct KeyCaptureButton: View {
    var onCapture: (Keystroke) -> Void
    @State private var listening = false

    var body: some View {
        Button(listening ? "Press keys…" : "Record") { listening = true }
            .background(KeyMonitor(active: $listening, onCapture: onCapture))
    }
}

struct KeyMonitor: NSViewRepresentable {
    @Binding var active: Bool
    var onCapture: (Keystroke) -> Void

    func makeNSView(context: Context) -> KeyMonitorView {
        let v = KeyMonitorView()
        v.onCapture = { ks in
            onCapture(ks)
            active = false
        }
        return v
    }

    func updateNSView(_ nsView: KeyMonitorView, context: Context) {
        nsView.listening = active
        if active { nsView.window?.makeFirstResponder(nsView) }
    }
}

final class KeyMonitorView: NSView {
    var listening = false
    var onCapture: ((Keystroke) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        guard listening else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        onCapture?(Keystroke(
            keyCode: event.keyCode,
            shift: flags.contains(.shift),
            control: flags.contains(.control),
            option: flags.contains(.option),
            command: flags.contains(.command),
            fn: flags.contains(.function),
            display: describe(event)
        ))
    }

    private func describe(_ event: NSEvent) -> String {
        var parts: [String] = []
        let f = event.modifierFlags
        if f.contains(.control) { parts.append("⌃") }
        if f.contains(.option) { parts.append("⌥") }
        if f.contains(.shift) { parts.append("⇧") }
        if f.contains(.command) { parts.append("⌘") }
        parts.append(event.charactersIgnoringModifiers?.uppercased() ?? "key \(event.keyCode)")
        return parts.joined()
    }
}
