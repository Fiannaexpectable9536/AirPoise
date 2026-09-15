import SwiftUI
import AppKit
import AirPoiseCore

struct MenuBarView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            bandPill
                .padding(.top, 10)
            metrics
                .padding(.top, 10)
            PostureGauges(snapshot: model.snapshot, live: model.live)
                .padding(.top, 10)
            controls
                .padding(.top, 12)
            if !model.lastActionNote.isEmpty {
                Text(model.lastActionNote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, 8)
            }
            footer
                .padding(.top, 10)
        }
        .padding(14)
        .frame(width: 316)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(bandColor.opacity(0.15))
                    .frame(width: 34, height: 34)
                Image(systemName: statusSymbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(bandColor)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(statusTitle)
                    .font(.system(size: 13, weight: .semibold))
                Text(statusSubtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ScoreRing(score: model.today.score)
        }
    }

    private var bandPill: some View {
        HStack(spacing: 6) {
            Image(systemName: bandSymbol)
                .font(.system(size: 10, weight: .bold))
            Text(bandTitle)
                .font(.system(size: 11, weight: .semibold))
            Spacer()
            if model.pose.isCalibrated {
                Text(String(format: "%+.0f°", model.snapshot.flexionDeg))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(bandColor)
        .background(bandColor.opacity(0.12), in: Capsule())
    }

    // MARK: Metrics

    private var metrics: some View {
        HStack(spacing: 6) {
            Metric(label: "Flex", value: deg(model.snapshot.flexionDeg), tint: bandColor)
            Metric(label: "Side", value: deg(model.snapshot.lateralDeg))
            Metric(label: "Yaw", value: deg(model.live?.yawDeg ?? 0))
            Metric(label: "Worn", value: minutes(model.today.worn))
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button(model.calibrating ? "Hold still…" : "Calibrate upright") {
                    model.beginCalibration()
                }
                .keyboardShortcut("c")
                .disabled(model.calibrating)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Menu {
                    Button("Settings…") { model.openSettings() }
                    Button("3D Preview") { model.openPreview3D() }
                    Divider()
                    Button("Test nudge") { model.testNudge() }
                    Divider()
                    Button(model.paused ? "Resume tracking" : "Pause tracking") { model.togglePause() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 14) {
            Toggle(isOn: gestureBinding) {
                Label("Gestures", systemImage: "move.3d")
            }
            Toggle(isOn: coachBinding) {
                Label("Coach", systemImage: "figure.stand")
            }
            Spacer()
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Quit AirPoise")
            .keyboardShortcut("q")
        }
        .font(.caption)
        .toggleStyle(.switch)
        .controlSize(.mini)
        .foregroundStyle(.primary)
    }

    // MARK: Derived

    private var statusTitle: String {
        if model.paused { return "Paused" }
        if !model.available { return "No head-tracking buds" }
        if model.auth == .denied { return "Motion permission needed" }
        if !model.connected && model.live == nil { return "Waiting for AirPods" }
        if !model.pose.isCalibrated { return "Not calibrated" }
        return bandTitle
    }

    private var statusSubtitle: String {
        if let g = model.lastGesture, Date().timeIntervalSince(g.hostTime) < 8 {
            return "Last gesture: \(g.kind.title)"
        }
        if model.live != nil {
            let ear = model.ear == .left ? "left" : model.ear == .right ? "right" : "auto"
            return String(format: "%@ bud · %.0f Hz", ear, model.hz)
        }
        return "AirPods Pro / 3 / 4 / Max · Beats Fit Pro"
    }

    private var statusSymbol: String {
        if model.paused { return "pause.fill" }
        if model.live == nil { return "airpods.pro" }
        return bandSymbol
    }

    private var bandTitle: String {
        switch model.snapshot.band {
        case .excellent: return "Excellent"
        case .good: return "Good posture"
        case .leaning: return "Leaning forward"
        case .slouch: return "Slouching"
        case .tilted: return "Head tilted"
        case .uncalibrated: return "Uncalibrated"
        case .unknown: return "No data"
        }
    }

    private var bandSymbol: String {
        switch model.snapshot.band {
        case .excellent, .good: return "checkmark"
        case .leaning: return "exclamationmark"
        case .slouch: return "exclamationmark.triangle.fill"
        case .tilted: return "arrow.left.arrow.right"
        default: return "minus"
        }
    }

    private var bandColor: Color {
        if model.paused || model.live == nil { return .secondary }
        if !model.pose.isCalibrated { return .orange }
        switch model.snapshot.band {
        case .excellent: return .green
        case .good: return .mint
        case .leaning: return .orange
        case .slouch: return .red
        case .tilted: return .yellow
        default: return .secondary
        }
    }

    private var gestureBinding: Binding<Bool> {
        Binding(
            get: { model.settings.gesture.enabled },
            set: { model.settings.gesture.enabled = $0; model.save() }
        )
    }

    private var coachBinding: Binding<Bool> {
        Binding(
            get: { model.settings.posture.enabled },
            set: { model.settings.posture.enabled = $0; model.save() }
        )
    }

    private func deg(_ v: Double) -> String { String(format: "%+.0f°", v) }
    private func minutes(_ s: Double) -> String {
        let m = Int(s / 60)
        if m < 60 { return "\(m)m" }
        return String(format: "%dh%02d", m / 60, m % 60)
    }
}

// MARK: - Components

struct ScoreRing: View {
    var score: Double
    private var tint: Color {
        if score >= 85 { return .green }
        if score >= 70 { return .orange }
        return .red
    }
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.10), lineWidth: 4)
            Circle()
                .trim(from: 0, to: score / 100)
                .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: score)
            Text(String(format: "%.0f", score))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .frame(width: 34, height: 34)
        .help("Today's posture score")
    }
}

struct Metric: View {
    let label: String
    let value: String
    var tint: Color = .secondary
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(tint == .secondary ? AnyShapeStyle(.primary) : AnyShapeStyle(tint))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Two stacked gauges: how far forward the head has drifted, how far it lists
/// to the side. Center-anchored — zero in the middle, positive grows right,
/// negative grows left.
struct PostureGauges: View {
    var snapshot: PostureSnapshot
    var live: HeadPose?
    var thresholds: (excellent: Double, good: Double, lean: Double) = (7, 12, 20)

    var body: some View {
        VStack(spacing: 8) {
            PostureBar(
                label: "Forward",
                value: snapshot.flexionDeg,
                range: -15...25,
                zones: [thresholds.excellent, thresholds.good, thresholds.lean],
                tint: forwardTint
            )
            PostureBar(
                label: "Side",
                value: snapshot.lateralDeg,
                range: -25...25,
                zones: [7, 14, 20],
                tint: sideTint
            )
        }
        .padding(10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var forwardTint: Color {
        let f = snapshot.flexionDeg
        if f > thresholds.lean { return .red }
        if f > thresholds.good { return .orange }
        return .green
    }

    private var sideTint: Color {
        abs(snapshot.lateralDeg) > 14 ? .yellow : .green
    }
}

struct PostureBar: View {
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    let zones: [Double]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%+.0f°", value))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
            }
            GeometryReader { geo in
                let w = geo.size.width
                let center = frac(0) * w
                let px = frac(clamped(value)) * w
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    // zone ticks, mirrored around zero
                    ForEach(Array(Set(zones.flatMap { [abs($0), -abs($0)] })).sorted(), id: \.self) { z in
                        Rectangle()
                            .fill(Color.primary.opacity(0.18))
                            .frame(width: 1, height: 6)
                            .offset(x: frac(z) * w - 0.5)
                    }
                    // center tick (slightly darker = "zero")
                    Rectangle()
                        .fill(Color.primary.opacity(0.35))
                        .frame(width: 1.5, height: 8)
                        .offset(x: center - 0.75)
                    // value fill from center
                    Capsule()
                        .fill(tint.opacity(0.85).gradient)
                        .frame(width: max(2, abs(px - center)))
                        .offset(x: min(px, center))
                        .animation(.easeOut(duration: 0.15), value: value)
                    // marker dot at the tip
                    Circle()
                        .fill(tint)
                        .frame(width: 7, height: 7)
                        .offset(x: px - 3.5, y: -0.5)
                        .animation(.easeOut(duration: 0.15), value: value)
                }
            }
            .frame(height: 6)
        }
    }

    private func frac(_ x: Double) -> CGFloat {
        CGFloat((x - range.lowerBound) / (range.upperBound - range.lowerBound))
    }
    private func clamped(_ v: Double) -> Double {
        min(max(v, range.lowerBound), range.upperBound)
    }
}
