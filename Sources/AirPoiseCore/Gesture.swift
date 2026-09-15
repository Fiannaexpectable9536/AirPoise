import Foundation

public enum GestureKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case nod
    case doubleNod
    case shake
    case doubleShake
    case lookLeft
    case lookRight
    case lookUp
    case lookDown
    case tiltLeft
    case tiltRight
    case tiltLeftHold
    case tiltRightHold
    case leanForward
    case leanBack
    case rollLeft
    case rollRight

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .nod: return "Nod"
        case .doubleNod: return "Double nod"
        case .shake: return "Shake"
        case .doubleShake: return "Double shake"
        case .lookLeft: return "Look left"
        case .lookRight: return "Look right"
        case .lookUp: return "Look up"
        case .lookDown: return "Look down"
        case .tiltLeft: return "Tilt left"
        case .tiltRight: return "Tilt right"
        case .tiltLeftHold: return "Hold tilt left"
        case .tiltRightHold: return "Hold tilt right"
        case .leanForward: return "Lean forward"
        case .leanBack: return "Lean back"
        case .rollLeft: return "Roll left"
        case .rollRight: return "Roll right"
        }
    }

    public var hint: String {
        switch self {
        case .nod: return "Dip your chin once, then return."
        case .doubleNod: return "Two quick nods."
        case .shake: return "Shake your head no."
        case .doubleShake: return "Two quick shakes."
        case .lookLeft: return "Glance left and return."
        case .lookRight: return "Glance right and return."
        case .lookUp: return "Glance up and return."
        case .lookDown: return "Glance down and return."
        case .tiltLeft: return "Ear toward left shoulder, then return."
        case .tiltRight: return "Ear toward right shoulder, then return."
        case .tiltLeftHold: return "Hold left ear tilt ~0.5s."
        case .tiltRightHold: return "Hold right ear tilt ~0.5s."
        case .leanForward: return "Lean your head forward, then sit up."
        case .leanBack: return "Tip your head back, then return."
        case .rollLeft: return "Roll your head left."
        case .rollRight: return "Roll your head right."
        }
    }
}

public struct GestureEvent: Sendable, Identifiable {
    public var id = UUID()
    public var kind: GestureKind
    public var time: TimeInterval
    public var hostTime: Date
    public var confidence: Double
    public var magnitudeDeg: Double
    /// True when emitted repeatedly during an ongoing hold gesture.
    public var repeated: Bool = false

    public init(kind: GestureKind, time: TimeInterval, hostTime: Date, confidence: Double, magnitudeDeg: Double, repeated: Bool = false) {
        self.kind = kind
        self.time = time
        self.hostTime = hostTime
        self.confidence = confidence
        self.magnitudeDeg = magnitudeDeg
        self.repeated = repeated
    }
}

public struct GestureConfig: Codable, Equatable, Sendable {
    public var enabled = true
    public var cooldown: Double = 0.60
    public var minQuality: Double = 0.32
    /// 0...1 — higher fires on smaller motions.
    public var sensitivity: Double = 0.62
    public var holdDuration: Double = 0.55
    /// While a hold gesture is maintained, re-emit it at this interval (seconds).
    /// Stepping actions (volume/brightness) respond to repeats; one-shots ignore them.
    public var holdRepeatInterval: Double = 0.35
    public var rejectWalkAccel: Double = 0.58
    public var restCutoff: Double = 0.22

    public enum CodingKeys: String, CodingKey {
        case enabled, cooldown, minQuality, sensitivity, holdDuration
        case holdRepeatInterval, rejectWalkAccel, restCutoff
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        cooldown = try c.decodeIfPresent(Double.self, forKey: .cooldown) ?? 0.60
        minQuality = try c.decodeIfPresent(Double.self, forKey: .minQuality) ?? 0.32
        sensitivity = try c.decodeIfPresent(Double.self, forKey: .sensitivity) ?? 0.62
        holdDuration = try c.decodeIfPresent(Double.self, forKey: .holdDuration) ?? 0.55
        holdRepeatInterval = try c.decodeIfPresent(Double.self, forKey: .holdRepeatInterval) ?? 0.35
        rejectWalkAccel = try c.decodeIfPresent(Double.self, forKey: .rejectWalkAccel) ?? 0.58
        restCutoff = try c.decodeIfPresent(Double.self, forKey: .restCutoff) ?? 0.22
    }
}

/// Detects discrete head gestures from a calibrated `HeadPose` stream.
///
/// Absolute pose is *not* used as the rest position. A slow rest tracker
/// follows the user, so a slouch doesn't look like a permanent nod. Gestures
/// are excursions that return (flicks) or held offsets (holds).
public final class GestureEngine: @unchecked Sendable {
    public var config = GestureConfig()
    public var onGesture: ((GestureEvent) -> Void)?

    private struct Flick {
        var dir = 0
        var extremum = 0.0
        var started = 0.0
        var lastCross = 0.0
    }

    private var restYaw = 0.0
    private var restPitch = 0.0
    private var restRoll = 0.0
    private var restFlex = 0.0
    private var restLat = 0.0
    private var restSeeded = false

    private var yawF = Flick()
    private var pitchF = Flick()
    private var rollF = Flick()
    private var flexF = Flick()

    private var holdRollDir = 0
    private var holdRollSince: TimeInterval?
    private var holdRollFired = false
    private var holdRepeatAt: TimeInterval = 0

    private var nodTimes: [TimeInterval] = []
    private var shakeTimes: [TimeInterval] = []
    private var lastFire: [GestureKind: TimeInterval] = [:]
    private var lastAny: TimeInterval = -1e9
    private var lastT: TimeInterval?
    private var yawSignChanges: [(TimeInterval, Int)] = []
    private var nodDown = false
    private var nodExt = 0.0
    private var nodT0: TimeInterval = 0

    public init() {}

    public func reset() {
        restSeeded = false
        yawF = Flick(); pitchF = Flick(); rollF = Flick(); flexF = Flick()
        holdRollDir = 0; holdRollSince = nil; holdRollFired = false
        nodTimes.removeAll(); shakeTimes.removeAll()
        lastFire.removeAll(); lastAny = -1e9
        lastT = nil
        yawSignChanges.removeAll()
        nodDown = false; nodExt = 0; nodT0 = 0
    }

    public func process(_ pose: HeadPose) {
        guard config.enabled, pose.calibrated else { return }
        guard pose.quality >= config.minQuality else { return }
        if pose.accelMag > config.rejectWalkAccel, pose.gyroMag > 3.2 { return }

        let t = pose.time
        let dt = max(1e-3, t - (lastT ?? (t - 0.04)))
        lastT = t

        // Rest pose: very slow when the head is quiet, slightly faster when it isn't,
        // so a new sitting position is adopted without counting as a gesture.
        let quiet = pose.gyroMag < 0.55
        let restAlpha = 1 - exp(-dt * (quiet ? config.restCutoff : config.restCutoff * 0.35))
        if !restSeeded {
            restYaw = pose.yaw; restPitch = pose.pitch; restRoll = pose.roll
            restFlex = pose.flexion; restLat = pose.lateral
            restSeeded = true
        } else {
            restYaw += Angle.delta(restYaw, pose.yaw) * restAlpha
            restPitch += Angle.delta(restPitch, pose.pitch) * restAlpha
            restRoll += Angle.delta(restRoll, pose.roll) * restAlpha
            restFlex += Angle.delta(restFlex, pose.flexion) * restAlpha
            restLat += Angle.delta(restLat, pose.lateral) * restAlpha
        }

        let dYaw = Angle.delta(restYaw, pose.yaw)
        let dPitch = Angle.delta(restPitch, pose.pitch)
        let dRoll = Angle.delta(restRoll, pose.roll)
        let dFlex = Angle.delta(restFlex, pose.flexion)

        let s = Angle.clamp(config.sensitivity, 0, 1)
        let flickAmp = lerp(Angle.rad(24), Angle.rad(10), s)
        let nodAmp = lerp(Angle.rad(18), Angle.rad(8), s)
        let tiltAmp = lerp(Angle.rad(22), Angle.rad(11), s)
        let returnBand = lerp(Angle.rad(9), Angle.rad(5), s)
        let maxFlick = 0.85
        let minRate = lerp(1.35, 0.70, s)

        detectNod(t: t, pose: pose, dPitch: dPitch, dYaw: dYaw, amp: nodAmp, ret: returnBand)
        detectShake(t: t, pose: pose, dYaw: dYaw, dPitch: dPitch, amp: nodAmp)
        detectHold(t: t, pose: pose, dRoll: dRoll, amp: tiltAmp)

        detectFlick(
            t: t, pose: pose, value: dPitch, rate: pose.pitchRate,
            flick: &pitchF, amp: flickAmp, ret: returnBand, maxDur: maxFlick, minRate: minRate,
            pos: .lookUp, neg: .lookDown,
            isolation: abs(dYaw) < flickAmp * 0.85 && abs(dRoll) < tiltAmp * 0.9
        )
        detectFlick(
            t: t, pose: pose, value: dYaw, rate: pose.yawRate,
            flick: &yawF, amp: flickAmp, ret: returnBand, maxDur: maxFlick, minRate: minRate,
            pos: .lookLeft, neg: .lookRight,
            isolation: abs(dPitch) < flickAmp * 0.75
        )
        detectFlick(
            t: t, pose: pose, value: dRoll, rate: pose.rollRate,
            flick: &rollF, amp: tiltAmp, ret: returnBand, maxDur: maxFlick, minRate: minRate * 0.8,
            pos: .tiltRight, neg: .tiltLeft,
            isolation: abs(dYaw) < flickAmp
        )
        detectFlick(
            t: t, pose: pose, value: dFlex, rate: pose.pitchRate,
            flick: &flexF, amp: nodAmp * 1.15, ret: returnBand, maxDur: 1.1, minRate: minRate * 0.5,
            pos: .leanForward, neg: .leanBack,
            isolation: abs(dYaw) < flickAmp * 0.7 && abs(dRoll) < tiltAmp * 0.8
        )
        detectRoll(t: t, pose: pose, dRoll: dRoll, dYaw: dYaw, amp: tiltAmp)
    }

    private func detectFlick(
        t: TimeInterval,
        pose: HeadPose,
        value: Double,
        rate: Double,
        flick: inout Flick,
        amp: Double,
        ret: Double,
        maxDur: Double,
        minRate: Double,
        pos: GestureKind,
        neg: GestureKind,
        isolation: Bool
    ) {
        if !isolation {
            flick.dir = 0
            return
        }
        if flick.dir == 0 {
            if value > amp, abs(rate) > minRate * 0.25 {
                flick.dir = 1; flick.extremum = value; flick.started = t
            } else if value < -amp, abs(rate) > minRate * 0.25 {
                flick.dir = -1; flick.extremum = value; flick.started = t
            }
            return
        }
        if flick.dir == 1 { flick.extremum = max(flick.extremum, value) }
        else { flick.extremum = min(flick.extremum, value) }

        if t - flick.started > maxDur {
            flick.dir = 0
            return
        }
        let returned = flick.dir == 1 ? value < ret : value > -ret
        if returned, abs(flick.extremum) >= amp {
            let kind = flick.dir == 1 ? pos : neg
            fire(kind, t: t, pose: pose, mag: Angle.deg(abs(flick.extremum)),
                 conf: conf(mag: Angle.deg(abs(flick.extremum)), q: pose.quality))
            flick.dir = 0
        }
    }

    private func detectNod(t: TimeInterval, pose: HeadPose, dPitch: Double, dYaw: Double, amp: Double, ret: Double) {
        guard abs(dYaw) < amp * 0.7 else { return }
        if !nodDown, dPitch < -amp {
            nodDown = true; nodExt = dPitch; nodT0 = t
        }
        guard nodDown else { return }
        nodExt = min(nodExt, dPitch)
        if t - nodT0 > 0.7 {
            nodDown = false
        } else if dPitch > -ret * 0.9 {
            let mag = Angle.deg(abs(nodExt))
            fire(.nod, t: t, pose: pose, mag: mag, conf: conf(mag: mag, q: pose.quality))
            nodTimes.append(t)
            nodTimes = nodTimes.filter { t - $0 < 0.85 }
            if nodTimes.count >= 2 {
                fire(.doubleNod, t: t, pose: pose, mag: mag, conf: 0.9)
                nodTimes.removeAll()
            }
            nodDown = false
        }
    }

    private func detectShake(t: TimeInterval, pose: HeadPose, dYaw: Double, dPitch: Double, amp: Double) {
        guard abs(dPitch) < amp * 0.85 else { return }
        let sign = dYaw > amp * 0.55 ? 1 : (dYaw < -amp * 0.55 ? -1 : 0)
        if sign != 0 {
            if let last = yawSignChanges.last, last.1 != sign, t - last.0 < 0.55 {
                yawSignChanges.append((t, sign))
            } else if yawSignChanges.isEmpty || t - (yawSignChanges.last?.0 ?? t) > 0.18 {
                if yawSignChanges.last?.1 != sign { yawSignChanges.append((t, sign)) }
            }
        }
        yawSignChanges = yawSignChanges.filter { t - $0.0 < 0.9 }
        if yawSignChanges.count >= 3 {
            let mag = Angle.deg(abs(dYaw))
            fire(.shake, t: t, pose: pose, mag: max(18, mag), conf: 0.82)
            shakeTimes.append(t)
            shakeTimes = shakeTimes.filter { t - $0 < 1.1 }
            if shakeTimes.count >= 2 {
                fire(.doubleShake, t: t, pose: pose, mag: mag, conf: 0.9)
                shakeTimes.removeAll()
            }
            yawSignChanges.removeAll()
        }
    }

    private func detectHold(t: TimeInterval, pose: HeadPose, dRoll: Double, amp: Double) {
        let still = pose.gyroMag < 1.35
        let dir = still && dRoll > amp * 1.05 ? 1 : (still && dRoll < -amp * 1.05 ? -1 : 0)
        if dir == 0 {
            holdRollDir = 0
            holdRollSince = nil
            holdRollFired = false
            return
        }
        if dir != holdRollDir {
            holdRollDir = dir
            holdRollSince = t
            holdRollFired = false
        }
        if !holdRollFired {
            if t - (holdRollSince ?? t) >= config.holdDuration {
                holdRollFired = true
                holdRepeatAt = t
                fire(dir > 0 ? .tiltRightHold : .tiltLeftHold,
                     t: t, pose: pose, mag: Angle.deg(abs(dRoll)), conf: 0.84)
            }
            return
        }
        // Held past the first fire: repeat at holdRepeatInterval for stepping actions.
        if t - holdRepeatAt >= config.holdRepeatInterval {
            holdRepeatAt = t
            fireRepeat(dir > 0 ? .tiltRightHold : .tiltLeftHold,
                       t: t, pose: pose, mag: Angle.deg(abs(dRoll)))
        }
    }

    private func fireRepeat(_ kind: GestureKind, t: TimeInterval, pose: HeadPose, mag: Double) {
        onGesture?(GestureEvent(kind: kind, time: t, hostTime: pose.hostTime,
                                confidence: 0.7, magnitudeDeg: mag, repeated: true))
    }

    private func detectRoll(t: TimeInterval, pose: HeadPose, dRoll: Double, dYaw: Double, amp: Double) {
        guard abs(pose.rollRate) > 1.25, abs(pose.yawRate) > 0.6, abs(pose.pitch) < Angle.rad(24) else { return }
        if dRoll > amp, pose.rollRate > 0 {
            fire(.rollRight, t: t, pose: pose, mag: Angle.deg(dRoll), conf: 0.68)
        } else if dRoll < -amp, pose.rollRate < 0 {
            fire(.rollLeft, t: t, pose: pose, mag: Angle.deg(abs(dRoll)), conf: 0.68)
        }
    }

    private func fire(_ kind: GestureKind, t: TimeInterval, pose: HeadPose, mag: Double, conf: Double) {
        let companion = kind == .doubleNod || kind == .doubleShake
        if !companion, t - lastAny < config.cooldown * 0.42 { return }
        if let prev = lastFire[kind], t - prev < config.cooldown { return }
        lastFire[kind] = t
        if !companion { lastAny = t }
        onGesture?(GestureEvent(kind: kind, time: t, hostTime: pose.hostTime, confidence: conf, magnitudeDeg: mag))
    }

    private func conf(mag: Double, q: Double) -> Double {
        Angle.clamp(q * (0.42 + 0.58 * Angle.clamp(mag / 28, 0, 1)), 0.2, 1)
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
}
