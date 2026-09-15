import AppKit
import SwiftUI
import AirPoiseCore

@MainActor
final class OverlayController {
    private var nudge: OverlayWindow?
    private var calib: OverlayWindow?
    private var toast: OverlayWindow?
    private var hideNudgeWork: DispatchWorkItem?
    private var hideToastWork: DispatchWorkItem?

    func prepare() {}

    func showNudge(title: String, detail: String, tint: NudgeTint = .posture) {
        let view = NudgeCard(title: title, detail: detail, tint: tint)
        nudge = present(view, existing: nudge, size: NSSize(width: 340, height: 96), yOffset: 96)
        hideNudgeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hideNudge() }
        hideNudgeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: work)
    }

    func hideNudge() {
        nudge?.orderOut(nil)
        nudge = nil
    }

    func showCalibration() {
        calib = present(CalibrationCard(), existing: calib, size: NSSize(width: 316, height: 148), yOffset: 160)
    }

    func hideCalibration() {
        calib?.orderOut(nil)
        calib = nil
    }

    func flashGesture(_ name: String) {
        toast = present(GestureToast(name: name), existing: toast, size: NSSize(width: 200, height: 42), yOffset: 52)
        hideToastWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.toast?.orderOut(nil)
            self?.toast = nil
        }
        hideToastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    func sync(pose: HeadPose, snapshot: PostureSnapshot) {
        _ = pose
        _ = snapshot
    }

    private func present<V: View>(_ view: V, existing: OverlayWindow?, size: NSSize, yOffset: CGFloat) -> OverlayWindow {
        let win = existing ?? OverlayWindow(size: size)
        win.setContent(view, size: size)
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            let x = f.midX - size.width / 2
            let y = f.minY + yOffset
            win.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        }
        win.orderFrontRegardless()
        return win
    }
}

enum NudgeTint {
    case posture, breakTime, generic

    var color: Color {
        switch self {
        case .posture: return .orange
        case .breakTime: return .teal
        case .generic: return .blue
        }
    }

    var symbol: String {
        switch self {
        case .posture: return "figure.stand"
        case .breakTime: return "figure.walk"
        case .generic: return "waveform.path.ecg"
        }
    }
}

final class OverlayWindow: NSPanel {
    private var host: NSHostingView<AnyView>?

    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = true
        animationBehavior = .utilityWindow
    }

    func setContent<V: View>(_ view: V, size: NSSize) {
        let wrapped = AnyView(view.frame(width: size.width, height: size.height))
        if let host {
            host.rootView = wrapped
        } else {
            let h = NSHostingView(rootView: wrapped)
            h.frame = NSRect(origin: .zero, size: size)
            contentView = h
            host = h
        }
        setContentSize(size)
    }
}

// MARK: - Nudge

struct NudgeCard: View {
    let title: String
    let detail: String
    let tint: NudgeTint

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: tint.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(
                    LinearGradient(colors: [tint.color.opacity(0.95), tint.color.opacity(0.7)],
                                   startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .apGlass(cornerRadius: 18)
        .shadow(color: .black.opacity(0.18), radius: 20, y: 6)
        .padding(6)
    }
}

// MARK: - Calibration

struct CalibrationCard: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "airpods.pro")
                .font(.system(size: 22, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
            Text("Hold still")
                .font(.system(size: 14, weight: .semibold))
            Text("Sit how you want to sit and look at the screen.\nThis becomes your 0°.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .apGlass(cornerRadius: 18)
        .shadow(color: .black.opacity(0.18), radius: 20, y: 6)
        .padding(6)
    }
}

// MARK: - Gesture toast

struct GestureToast: View {
    let name: String

    var body: some View {
        Label(name, systemImage: "bolt.fill")
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .apGlassCapsule()
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }
}
