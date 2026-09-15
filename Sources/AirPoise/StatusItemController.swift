import AppKit
import SwiftUI
import AirPoiseCore

@MainActor
final class StatusItemController: NSObject {
    private var item: NSStatusItem?
    private let model: AppModel
    private var popover = NSPopover()

    init(model: AppModel) {
        self.model = model
        super.init()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.baseImage(band: .unknown)
        item.button?.imagePosition = .imageLeading
        item.button?.target = self
        item.button?.action = #selector(toggle)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        self.item = item

        popover.behavior = .transient
        popover.animates = true
        let view = MenuBarView().environmentObject(model)
        popover.contentViewController = NSHostingController(rootView: view)

        Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    @objc func toggle(_ sender: Any?) {
        guard let button = item?.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
            return
        }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.refreshPermissions()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc func refresh() {
        guard let button = item?.button else { return }
        let band = model.paused ? PostureBand.unknown : model.snapshot.band
        button.image = Self.baseImage(band: band, flexion: model.snapshot.flexionDeg)
        switch model.settings.menuBarStyle {
        case "score":
            button.title = model.pose.isCalibrated ? String(format: " %.0f", model.today.score) : " —"
        case "iconAndTilt":
            if model.settings.showDegreesInMenu, model.pose.isCalibrated, model.live != nil {
                button.title = String(format: " %+.0f°", model.snapshot.flexionDeg)
            } else {
                button.title = ""
            }
        default:
            button.title = ""
        }
        button.toolTip = tooltip()
        button.appearsDisabled = model.paused
    }

    private func tooltip() -> String {
        if model.paused { return "AirPoise — paused" }
        if !model.available { return "AirPoise — no motion-capable headphones" }
        if !model.pose.isCalibrated { return "AirPoise — calibrate to start" }
        return String(
            format: "AirPoise — %@ · flex %+.0f° · score %.0f",
            model.snapshot.band.rawValue,
            model.snapshot.flexionDeg,
            model.today.score
        )
    }

    private func showMenu() {
        let m = NSMenu()
        m.addItem(withTitle: model.paused ? "Resume" : "Pause", action: #selector(pause), keyEquivalent: "p")
        m.addItem(withTitle: "Calibrate", action: #selector(calibrate), keyEquivalent: "c")
        m.addItem(withTitle: "3D Preview", action: #selector(preview), keyEquivalent: "3")
        m.addItem(withTitle: "Settings…", action: #selector(settings), keyEquivalent: ",")
        m.addItem(.separator())
        m.addItem(withTitle: "Quit AirPoise", action: #selector(quit), keyEquivalent: "q")
        m.items.forEach { $0.target = self }
        item?.menu = m
        item?.button?.performClick(nil)
        item?.menu = nil
    }

    @objc func pause() { model.togglePause() }
    @objc func calibrate() { model.beginCalibration() }
    @objc func preview() { model.openPreview3D() }
    @objc func settings() { model.openSettings() }
    @objc func quit() { NSApp.terminate(nil) }

    static func baseImage(band: PostureBand, flexion: Double = 0) -> NSImage {
        let point = NSSize(width: 18, height: 18)
        let img = NSImage(size: point, flipped: false) { rect in
            let color: NSColor
            switch band {
            case .excellent, .good: color = NSColor.systemGreen
            case .leaning: color = NSColor.systemOrange
            case .slouch: color = NSColor.systemRed
            case .tilted: color = NSColor.systemYellow
            default: color = NSColor.labelColor
            }
            color.setStroke()
            let head = NSBezierPath(ovalIn: NSRect(x: 5.5, y: 8.2, width: 7, height: 7))
            head.lineWidth = 1.4
            head.stroke()
            let spine = NSBezierPath()
            let lean = CGFloat(max(-0.7, min(0.9, flexion / 28)))
            spine.move(to: NSPoint(x: 9, y: 8.2))
            spine.curve(
                to: NSPoint(x: 9 + lean * 4, y: 1.6),
                controlPoint1: NSPoint(x: 9 + lean * 1.2, y: 6),
                controlPoint2: NSPoint(x: 9 + lean * 3.2, y: 3.4)
            )
            spine.lineWidth = 1.5
            spine.lineCapStyle = .round
            spine.stroke()
            return true
        }
        img.isTemplate = (band == .unknown || band == .uncalibrated)
        return img
    }
}
