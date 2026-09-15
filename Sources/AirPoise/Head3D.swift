import SwiftUI
import AppKit
import SceneKit
import AirPoiseCore

// MARK: - Scene

final class HeadScene {
    let scene = SCNScene()
    private(set) var yawPivot = SCNNode()
    private(set) var pitchPivot = SCNNode()
    private(set) var rollPivot = SCNNode()
    private var headMaterial = SCNMaterial()
    private var budMaterial = SCNMaterial()
    private var ringYaw = SCNNode()
    private var ringPitch = SCNNode()

    init() {
        build()
    }

    private func build() {
        scene.background.contents = NSColor.windowBackgroundColor.withAlphaComponent(0)

        // Lights
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 350
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .omni
        key.light?.intensity = 900
        key.position = SCNVector3(4, 5, 6)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .omni
        fill.light?.intensity = 350
        fill.position = SCNVector3(-5, 2, 4)
        scene.rootNode.addChildNode(fill)

        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .omni
        rim.light?.intensity = 500
        rim.position = SCNVector3(0, 3, -6)
        scene.rootNode.addChildNode(rim)

        // Camera — looking at the head's crown line
        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera?.zFar = 50
        cam.position = SCNVector3(0, 0.5, 5.4)
        scene.rootNode.addChildNode(cam)
        let camConstraint = SCNLookAtConstraint(target: rollPivot)
        cam.constraints = [camConstraint]

        // Reference rings (stay fixed; show motion relative to them)
        ringYaw = torus(majorRadius: 1.55, tube: 0.012, color: NSColor.labelColor.withAlphaComponent(0.30))
        ringYaw.eulerAngles = SCNVector3(0, 0, 0)
        ringPitch = torus(majorRadius: 1.55, tube: 0.012, color: NSColor.labelColor.withAlphaComponent(0.30))
        ringPitch.eulerAngles = SCNVector3(0, CGFloat.pi / 2, 0)
        scene.rootNode.addChildNode(ringYaw)
        scene.rootNode.addChildNode(ringPitch)

        // Pivot chain: yaw (about Y) -> pitch (about X) -> roll (about Z) -> geometry
        scene.rootNode.addChildNode(yawPivot)
        yawPivot.addChildNode(pitchPivot)
        pitchPivot.addChildNode(rollPivot)

        // Materials
        headMaterial.diffuse.contents = NSColor(calibratedRed: 0.82, green: 0.85, blue: 0.88, alpha: 1)
        headMaterial.specular.contents = NSColor.white
        headMaterial.shininess = 0.35
        let faceMaterial = SCNMaterial()
        faceMaterial.diffuse.contents = NSColor(calibratedRed: 0.28, green: 0.63, blue: 0.99, alpha: 1)
        faceMaterial.emission.contents = NSColor(calibratedRed: 0.05, green: 0.22, blue: 0.45, alpha: 1)
        budMaterial.diffuse.contents = NSColor(white: 0.97, alpha: 1)
        budMaterial.specular.contents = NSColor.white
        budMaterial.shininess = 0.8

        // Head — slightly elongated sphere
        let head = SCNSphere(radius: 1.0)
        head.segmentCount = 48
        head.materials = [headMaterial]
        let headNode = SCNNode(geometry: head)
        headNode.scale = SCNVector3(0.92, 1.06, 0.98)
        headNode.position = SCNVector3(0, 0.42, 0)
        rollPivot.addChildNode(headNode)

        // Face panel (front = +Z, toward camera at neutral)
        let face = SCNSphere(radius: 0.62)
        face.materials = [faceMaterial]
        let faceNode = SCNNode(geometry: face)
        faceNode.scale = SCNVector3(0.72, 1.0, 0.45)
        faceNode.position = SCNVector3(0, 0.34, 0.55)
        rollPivot.addChildNode(faceNode)

        // Eyes
        for sx in [-0.32, 0.32] as [Double] {
            let eye = SCNSphere(radius: 0.085)
            eye.materials = [solid(NSColor(white: 0.12, alpha: 1))]
            let e = SCNNode(geometry: eye)
            e.position = SCNVector3(sx, 0.52, 0.82)
            rollPivot.addChildNode(e)
        }

        // Nose cone — the clearest "which way am I facing" cue
        let nose = SCNCone(topRadius: 0.0, bottomRadius: 0.13, height: 0.42)
        nose.materials = [headMaterial]
        let noseNode = SCNNode(geometry: nose)
        noseNode.position = SCNVector3(0, 0.32, 1.0)
        noseNode.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
        rollPivot.addChildNode(noseNode)

        // Ears
        for sx in [-1.0, 1.0] as [Double] {
            let ear = SCNSphere(radius: 0.16)
            ear.materials = [headMaterial]
            let e = SCNNode(geometry: ear)
            e.position = SCNVector3(sx * 0.94, 0.42, 0)
            e.scale = SCNVector3(0.5, 1.0, 0.8)
            rollPivot.addChildNode(e)
        }

        // AirPods: bud + stem hanging down, at each side
        for sx in [-1.0, 1.0] as [Double] {
            let bud = SCNSphere(radius: 0.13)
            bud.materials = [budMaterial]
            let budNode = SCNNode(geometry: bud)
            budNode.position = SCNVector3(sx * 1.02, 0.30, 0.1)
            rollPivot.addChildNode(budNode)

            let stem = SCNCapsule(capRadius: 0.05, height: 0.42)
            stem.materials = [budMaterial]
            let stemNode = SCNNode(geometry: stem)
            stemNode.position = SCNVector3(sx * 1.03, 0.02, 0.1)
            stemNode.eulerAngles = SCNVector3(0.2, 0, sx * 0.12)
            rollPivot.addChildNode(stemNode)

            let dot = SCNSphere(radius: 0.035)
            dot.materials = [solid(NSColor.systemGreen)]
            let dotNode = SCNNode(geometry: dot)
            dotNode.position = SCNVector3(sx * 1.04, -0.2, 0.12)
            rollPivot.addChildNode(dotNode)
        }

        // Neck + shoulders
        let neck = SCNCylinder(radius: 0.34, height: 0.55)
        neck.materials = [headMaterial]
        let neckNode = SCNNode(geometry: neck)
        neckNode.position = SCNVector3(0, -0.82, 0)
        rollPivot.addChildNode(neckNode)

        let body = SCNSphere(radius: 1.05)
        body.materials = [solid(NSColor(calibratedRed: 0.32, green: 0.35, blue: 0.40, alpha: 1))]
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, -1.62, 0)
        bodyNode.scale = SCNVector3(1.35, 0.65, 0.75)
        rollPivot.addChildNode(bodyNode)

        // Floor
        let floor = SCNFloor()
        floor.reflectivity = 0.08
        floor.firstMaterial?.diffuse.contents = NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.13, alpha: 1)
        floor.firstMaterial?.lightingModel = SCNMaterial.LightingModel.physicallyBased
        let floorNode = SCNNode(geometry: floor)
        floorNode.position = SCNVector3(0, -2.45, 0)
        scene.rootNode.addChildNode(floorNode)
    }

    private func torus(majorRadius: CGFloat, tube: CGFloat, color: NSColor) -> SCNNode {
        let t = SCNTorus(ringRadius: majorRadius, pipeRadius: tube)
        t.materials = [solid(color)]
        return SCNNode(geometry: t)
    }

    private func solid(_ c: NSColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = c
        return m
    }

    /// Drive the head. Mirror view: the avatar faces the user like a mirror.
    /// Inputs are the headphone-frame angles (yaw+ = look left, pitch+ = chin up,
    /// roll+ = top of head toward right shoulder).
    func apply(yaw: Double, pitch: Double, roll: Double, band: PostureBand, animated: Bool = true) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.05 : 0
        // Look left ⇒ avatar's nose moves toward screen-left.
        yawPivot.rotation = SCNVector4(0, 1, 0, yaw)
        // Chin up ⇒ avatar's nose moves up on screen.
        pitchPivot.rotation = SCNVector4(1, 0, 0, -pitch)
        // Head tilted right ⇒ mirrored avatar's crown moves screen-right.
        rollPivot.rotation = SCNVector4(0, 0, 1, -roll)

        let tint: NSColor
        switch band {
        case .excellent, .good: tint = NSColor.systemGreen
        case .leaning: tint = NSColor.systemOrange
        case .slouch: tint = NSColor.systemRed
        case .tilted: tint = NSColor.systemYellow
        default: tint = NSColor.labelColor
        }
        headMaterial.emission.contents = tint.withAlphaComponent(0.16)
        SCNTransaction.commit()
    }
}

// MARK: - SwiftUI wrapper

struct Head3DView: NSViewRepresentable {
    var yaw: Double
    var pitch: Double
    var roll: Double
    var band: PostureBand

    func makeNSView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = context.coordinator.sceneModel.scene
        v.allowsCameraControl = false
        v.backgroundColor = .clear
        v.antialiasingMode = .multisampling4X
        v.isPlaying = true
        return v
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        context.coordinator.sceneModel.apply(yaw: yaw, pitch: pitch, roll: roll, band: band)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator {
        let sceneModel = HeadScene()
    }
}

/// Live-driven 3D head (from the motion stream).
struct LiveHead3DView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let p = model.live
        Head3DView(
            yaw: p?.yaw ?? 0,
            pitch: p?.pitch ?? 0,
            roll: p?.roll ?? 0,
            band: model.snapshot.band
        )
    }
}

// MARK: - Preview window

struct Preview3DView: View {
    @EnvironmentObject var model: AppModel
    @State private var demo = false
    @State private var t0 = Date()

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if demo {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                        let t = ctx.date.timeIntervalSince(t0)
                        Head3DView(
                            yaw: sin(t * 0.7) * 0.5,
                            pitch: sin(t * 0.45) * 0.3,
                            roll: sin(t * 0.55) * 0.4,
                            band: demoBand(t)
                        )
                    }
                } else {
                    LiveHead3DView()
                }
            }

            // Overlay HUD
            VStack(alignment: .leading, spacing: 6) {
                Label(demo ? "Demo" : (model.live != nil ? "Live" : "Idle"),
                      systemImage: demo ? "play.circle" : model.live != nil ? "circle.fill" : "circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(demo ? .blue : model.live != nil ? .green : .secondary)
                if !demo {
                    Text(String(format: "yaw %+.0f°   pitch %+.0f°   roll %+.0f°",
                                model.live?.yawDeg ?? 0,
                                model.live?.pitchDeg ?? 0,
                                model.live?.rollDeg ?? 0))
                        .monospacedDigit()
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(14)

            Spacer()
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            Toggle("Demo motion", isOn: $demo)
                .toggleStyle(.switch)
                .help("Animate with synthetic motion — no AirPods needed")
        }
    }

    private func demoBand(_ t: Double) -> PostureBand {
        let v = sin(t * 0.2)
        if v > 0.5 { return .excellent }
        if v > 0 { return .good }
        if v > -0.5 { return .leaning }
        return .slouch
    }
}
