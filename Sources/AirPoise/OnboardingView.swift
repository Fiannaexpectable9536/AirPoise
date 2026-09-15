import SwiftUI
import AppKit
import AirPoiseCore

struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    var onFinished: () -> Void

    @State private var page: Page = .cover

    enum Page: Int, CaseIterable {
        case cover, sit, slump, nod, permissions, calibrate, finale
    }

    var body: some View {
        VStack(spacing: 0) {
            mast
            pageBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(14)
            navBar
        }
        .background(Comic.paper)
        .frame(width: 760, height: 600)
        .onAppear {
            Comic.registerFonts()
        }
    }

    private var mast: some View {
        HStack {
            if let icon = Comic.art("comic-icon") {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 32, height: 32)
                    .clipped()
                    .overlay(Rectangle().stroke(Comic.ink, lineWidth: 2.5))
            }
            Text("AirPoise")
                .font(.comicSFX(26))
                .tracking(1)
                .foregroundStyle(Comic.ink)
            Spacer()
            Text("Vol. 1 No. 1  ·  Issue \(page.rawValue + 1) of \(Page.allCases.count)")
                .font(.system(size: 12, weight: .medium, design: .serif))
                .italic()
                .foregroundStyle(Comic.mute)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Comic.ink).frame(height: 4) }
    }

    @ViewBuilder
    private var pageBody: some View {
        switch page {
        case .cover: coverPage
        case .sit: storyPage(
            cap: "Meanwhile, at a desk somewhere…",
            sfx: "SIT!",
            art: "comic-upright",
            title: "Sit the way you mean to.",
            body: "Calibrate once. Gravity does the rest. Flexion is chin-forward. Side is ear-to-shoulder. The buds cannot see your spine, and we won’t pretend they can."
        )
        case .slump: storyPage(
            cap: "Panel 2 · 47 minutes later",
            sfx: "SLUMP!",
            art: "comic-slouch",
            title: "Then the chin creeps.",
            body: "Held too long, you get a nudge: a glass overlay, an optional ping. Not a lecture. A tap on the panel border."
        )
        case .nod: storyPage(
            cap: "Panel 3",
            sfx: "NOD!",
            art: "comic-nod",
            title: "A nod is not a slouch.",
            body: "A gesture is an excursion that returns. Sixteen of them. Bind any one to play/pause, Spaces, a Shortcut, a URL, a script — anything a Mac can do with its mouth shut."
        )
        case .permissions: permissionsPage
        case .calibrate: calibratePage
        case .finale: finalePage
        }
    }

    private var coverPage: some View {
        HStack(spacing: 14) {
            ComicPanel {
                ZStack(alignment: .topLeading) {
                    if let img = Comic.art("comic-upright") {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                            .blendMode(.multiply)
                    }
                    ComicCaption(text: "Meanwhile, at a desk somewhere…")
                        .padding(12)
                    Text("SIT!")
                        .font(.comicSFX(36))
                        .foregroundStyle(Comic.pop)
                        .shadow(color: Comic.ink, radius: 0, x: 2, y: 2)
                        .rotationEffect(.degrees(8))
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            ComicPanel(padding: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("A MENU-BAR UTILITY · ISSUE 1")
                        .font(.comicInk(11))
                        .tracking(1.6)
                        .foregroundStyle(Comic.pop)
                    Text("AIRPOISE")
                        .font(.comicSFX(72))
                        .foregroundStyle(Comic.pop)
                        .shadow(color: Comic.ink, radius: 0, x: 3, y: 3)
                        .rotationEffect(.degrees(-2))
                    Text("Wear your AirPods. Sit better.")
                        .font(.comicInk(22))
                        .foregroundStyle(Comic.ink)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Comic.ink, lineWidth: 3))
                    Text("That’s it. That’s the app. The buds already know how your head is sitting. AirPoise just draws the rest of the panel.")
                        .font(.system(size: 15, weight: .medium, design: .serif))
                        .italic()
                        .foregroundStyle(Comic.mute)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Text("macOS 14+  ·  AirPods with Spatial Audio  ·  on-device")
                        .font(.system(size: 12, design: .serif))
                        .italic()
                        .foregroundStyle(Comic.mute)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
    }

    private func storyPage(cap: String, sfx: String, art: String, title: String, body: String) -> some View {
        HStack(spacing: 14) {
            ComicPanel {
                ZStack(alignment: .topLeading) {
                    if let img = Comic.art(art) {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                            .blendMode(.multiply)
                    }
                    ComicCaption(text: cap)
                        .padding(12)
                    Text(sfx)
                        .font(.comicSFX(52))
                        .foregroundStyle(sfx == "NOD!" ? Comic.sky : Comic.pop)
                        .shadow(color: Comic.ink, radius: 0, x: 3, y: 3)
                        .rotationEffect(.degrees(-8))
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
            ComicPanel(padding: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(title)
                        .font(.comicInk(28))
                        .foregroundStyle(Comic.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(body)
                        .font(.system(size: 16, weight: .medium, design: .serif))
                        .foregroundStyle(Comic.mute)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
    }

    private var permissionsPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TWO BOXES. THAT’S THE WHOLE PERMISSIONS PAGE.")
                .font(.comicInk(13))
                .tracking(1.2)
                .foregroundStyle(Comic.pop)
            HStack(spacing: 12) {
                permissionCard(
                    stamp: "MOTION",
                    title: "Motion & Fitness",
                    body: "Lets AirPoise read the fused IMU Apple already runs for Spatial Audio. Asked automatically. If you denied it: System Settings → Privacy & Security → Motion & Fitness.",
                    ok: model.auth == .authorized,
                    okLabel: "Allowed",
                    waitLabel: model.auth == .denied ? "Denied — open Settings" : "Wear your buds"
                )
                permissionCard(
                    stamp: "KEYS",
                    title: "Accessibility",
                    body: "Only if you bind a gesture to a keystroke or a system action. Unused otherwise. Media keys don’t need it.",
                    ok: model.accessibilityTrusted,
                    okLabel: "Allowed",
                    waitLabel: "Grant…",
                    action: { model.requestAccessibility() }
                )
            }
            Text("Nothing leaves this Mac. No account. No network. Settings live in ~/Library/Application Support/AirPoise.")
                .font(.system(size: 13, design: .serif))
                .italic()
                .foregroundStyle(Comic.mute)
        }
    }

    private func permissionCard(stamp: String, title: String, body: String, ok: Bool, okLabel: String, waitLabel: String, action: (() -> Void)? = nil) -> some View {
        ComicPanel(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text(stamp)
                    .font(.comicSFX(22))
                    .foregroundStyle(ok ? Comic.ink : Comic.pop)
                Text(title)
                    .font(.comicInk(20))
                Text(body)
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(Comic.mute)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if let action, !ok {
                    ComicBurstButton(title: waitLabel, action: action)
                } else {
                    Text(ok ? "✓  \(okLabel)" : waitLabel)
                        .font(.comicInk(13))
                        .foregroundStyle(ok ? Color(red: 0.12, green: 0.54, blue: 0.24) : Comic.mute)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var calibratePage: some View {
        HStack(spacing: 14) {
            ComicPanel {
                ZStack(alignment: .topLeading) {
                    if let img = Comic.art("comic-upright") {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                            .blendMode(.multiply)
                    }
                    ComicCaption(text: "Hold still. Look at the screen.")
                        .padding(12)
                }
            }
            ComicPanel(padding: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Calibrate upright.")
                        .font(.comicInk(28))
                    Text("Sit the way you actually want to sit. Wear the buds. Press the stamp. AirPoise stores that gravity vector. Posture survives taking them out. Gestures are flicks that come home.")
                        .font(.system(size: 15, design: .serif))
                        .foregroundStyle(Comic.mute)
                        .fixedSize(horizontal: false, vertical: true)
                    if model.calibrating {
                        Text("Hold still…")
                            .font(.comicInk(16))
                            .foregroundStyle(Comic.pop)
                    } else if model.pose.isCalibrated {
                        Text("✓  Calibrated. That’s your upright.")
                            .font(.comicInk(14))
                            .foregroundStyle(Color(red: 0.12, green: 0.54, blue: 0.24))
                    }
                    Spacer()
                    ComicBurstButton(title: model.calibrating ? "HOLD…" : "CALIBRATE", large: true) {
                        model.beginCalibration()
                    }
                    Text(model.lastActionNote)
                        .font(.system(size: 12, design: .serif))
                        .italic()
                        .foregroundStyle(Comic.mute)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
    }

    private var finalePage: some View {
        ComicPanel(padding: 28) {
            VStack(spacing: 14) {
                Text("THE LAST PANEL")
                    .font(.comicInk(12))
                    .tracking(2)
                    .foregroundStyle(Comic.pop)
                Text("It’s in the menu bar.")
                    .font(.comicSFX(52))
                    .foregroundStyle(Comic.pop)
                    .shadow(color: Comic.ink, radius: 0, x: 3, y: 3)
                Text("No Dock icon. Left-click the HUD. Right-click Pause / Calibrate / Settings / Quit. Double-nod is play/pause. Look left or right to switch Space. Change all of it.")
                    .font(.system(size: 16, design: .serif))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Comic.mute)
                    .frame(maxWidth: 520)
                Text("Sit better today.")
                    .font(.comicInk(18))
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var navBar: some View {
        HStack {
            if page != .cover {
                Button("Back") { go(-1) }
                    .font(.comicInk(13))
                    .foregroundStyle(Comic.ink)
                    .buttonStyle(.plain)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(Page.allCases, id: \.rawValue) { p in
                    Rectangle()
                        .fill(p == page ? Comic.pop : Comic.ink.opacity(0.18))
                        .frame(width: p == page ? 18 : 8, height: 8)
                        .overlay(Rectangle().stroke(Comic.ink, lineWidth: 1.5))
                }
            }
            Spacer()
            ComicBurstButton(title: page == .finale ? "DONE" : "NEXT") {
                if page == .finale { finish() } else { go(1) }
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
        .padding(.top, 8)
        .onReceive(Timer.publish(every: 1.2, on: .main, in: .common).autoconnect()) { _ in
            if page == .permissions { model.refreshPermissions() }
        }
    }

    private func go(_ delta: Int) {
        let next = page.rawValue + delta
        guard let p = Page(rawValue: next) else { return }
        withAnimation(.easeInOut(duration: 0.18)) { page = p }
    }

    private func finish() {
        model.settings.onboardingComplete = true
        model.onboarding = false
        model.save()
        onFinished()
    }
}
