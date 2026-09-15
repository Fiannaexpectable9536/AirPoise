import Foundation
import CoreMotion
import os.log

private let log = Logger(subsystem: "app.airpoise.AirPoise", category: "motion")

public enum SensorEar: String, Codable, Sendable {
    case unknown, left, right
}

public struct HeadSample: Sendable {
    public var time: TimeInterval
    public var hostTime: Date
    public var attitude: Quat
    public var gravity: Vec3
    public var userAcceleration: Vec3
    public var rotationRate: Vec3
    public var heading: Double
    public var ear: SensorEar

    public init(
        time: TimeInterval,
        hostTime: Date,
        attitude: Quat,
        gravity: Vec3,
        userAcceleration: Vec3,
        rotationRate: Vec3,
        heading: Double,
        ear: SensorEar
    ) {
        self.time = time
        self.hostTime = hostTime
        self.attitude = attitude
        self.gravity = gravity
        self.userAcceleration = userAcceleration
        self.rotationRate = rotationRate
        self.heading = heading
        self.ear = ear
    }
}

public struct HeadPose: Sendable {
    public var time: TimeInterval
    public var hostTime: Date
    public var yaw: Double
    public var pitch: Double
    public var roll: Double
    public var yawDeg: Double { Angle.deg(yaw) }
    public var pitchDeg: Double { Angle.deg(pitch) }
    public var rollDeg: Double { Angle.deg(roll) }
    public var yawRate: Double
    public var pitchRate: Double
    public var rollRate: Double
    public var flexion: Double
    public var lateral: Double
    public var flexionDeg: Double { Angle.deg(flexion) }
    public var lateralDeg: Double { Angle.deg(lateral) }
    public var accelMag: Double
    public var gyroMag: Double
    public var quality: Double
    public var hz: Double
    public var ear: SensorEar
    public var calibrated: Bool

    public init(
        time: TimeInterval,
        hostTime: Date,
        yaw: Double,
        pitch: Double,
        roll: Double,
        yawRate: Double,
        pitchRate: Double,
        rollRate: Double,
        flexion: Double,
        lateral: Double,
        accelMag: Double,
        gyroMag: Double,
        quality: Double,
        hz: Double,
        ear: SensorEar,
        calibrated: Bool
    ) {
        self.time = time
        self.hostTime = hostTime
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
        self.yawRate = yawRate
        self.pitchRate = pitchRate
        self.rollRate = rollRate
        self.flexion = flexion
        self.lateral = lateral
        self.accelMag = accelMag
        self.gyroMag = gyroMag
        self.quality = quality
        self.hz = hz
        self.ear = ear
        self.calibrated = calibrated
    }
}

public struct GravityFrame: Equatable, Codable, Sendable {
    public var g0: Vec3
    public var up: Vec3
    public var forward: Vec3
    public var right: Vec3

    public init(g0: Vec3, up: Vec3, forward: Vec3, right: Vec3) {
        self.g0 = g0
        self.up = up
        self.forward = forward
        self.right = right
    }

    /// `preferForward` is the anatomical nose direction in the (headphone) body frame.
    /// For AirPods that is +y.
    public static func capture(gravity g: Vec3, preferForward: Vec3 = Vec3(0, 1, 0)) -> GravityFrame {
        let g0 = g.normalized
        var up = (g0 * -1).normalized
        if up.length < 0.5 { up = Vec3(0, 0, 1) }

        func project(_ guess: Vec3) -> Vec3 {
            let p = guess - up * guess.dot(up)
            return p.length < 0.15 ? .zero : p.normalized
        }

        var forward = project(preferForward)
        if forward.length < 0.5 {
            // Gravity nearly along the nose (lying down): pick any horizontal axis.
            let alt = abs(up.z) < 0.85 ? Vec3(0, 0, 1) : Vec3(1, 0, 0)
            forward = project(alt)
        }
        if forward.length < 0.5 { forward = Vec3(0, 1, 0) }

        // x = right ear, y = nose, z = crown  ⇒  right = forward × up
        var right = forward.cross(up)
        if right.length < 1e-6 { right = Vec3(1, 0, 0) }
        right = right.normalized
        up = right.cross(forward).normalized
        return GravityFrame(g0: g0, up: up, forward: forward, right: right)
    }

    /// Signed deflection of the gravity (down) vector into `forward` (nose).
    /// Measured against the down axis so it is wrap-free and symmetric.
    /// Positive = gravity tips toward the nose = chin moves down.
    public func flexion(gravity g: Vec3) -> Double {
        let gn = g.normalized
        let down = up * -1
        return atan2(gn.dot(forward), gn.dot(down)) - atan2(g0.dot(forward), g0.dot(down))
    }

    /// Signed deflection of the gravity vector into `right` (right ear).
    /// Positive = right ear toward right shoulder.
    public func lateral(gravity g: Vec3) -> Double {
        let gn = g.normalized
        let down = up * -1
        return atan2(gn.dot(right), gn.dot(down)) - atan2(g0.dot(right), g0.dot(down))
    }

    public func totalTilt(gravity g: Vec3) -> Double {
        let c = Angle.clamp(g.normalized.dot(g0.normalized), -1, 1)
        return acos(c)
    }
}

public struct PoseConfig: Sendable {
    public var invertPitch = false
    public var invertYaw = false
    public var invertRoll = false
    public var invertFlexion = false
    public var invertLateral = false
    /// Display/gesture smoothing (1€). Head motion at ~25 Hz:
    /// lower minCutoff = steadier at rest, higher beta = snappier while moving.
    public var angleMinCutoff = 1.0
    public var angleBeta = 0.03
    /// Posture smoothing — slower, rejects nod noise.
    public var postureMinCutoff = 0.55
    public var postureBeta = 0.02
    public var yawDriftCorrection = true
    /// °/s the yaw-zero chases raw yaw while the head is still.
    public var yawDriftRate = Angle.rad(0.9)
    /// Gyro magnitude below which the head counts as still (rad/s).
    public var yawDriftStillGyro = 0.28
    /// Ear-switch / long-gap arrivals re-seed attitude so pose doesn't jump.
    public var recenterOnEarSwitch = true

    public init() {}
}

public final class PoseEstimator: @unchecked Sendable {
    public var config = PoseConfig()
    public private(set) var reference: Quat?
    public private(set) var frame: GravityFrame?
    public private(set) var lastPose: HeadPose?
    public private(set) var hz: Double = 0
    public private(set) var earSwitchCount = 0

    private let yawF = OneEuroFilter()
    private let pitchF = OneEuroFilter()
    private let rollF = OneEuroFilter()
    private let flexF = OneEuroFilter()
    private let latF = OneEuroFilter()

    private var lastT: TimeInterval?
    private var emaDt: Double = 1 / 25
    private var lastEar: SensorEar?
    private var yawDrift = 0.0

    public init() {}

    public var isCalibrated: Bool { frame != nil && reference != nil }

    public func calibrate(from sample: HeadSample) {
        reference = sample.attitude.normalized
        frame = GravityFrame.capture(gravity: sample.gravity)
        yawDrift = 0
        yawF.reset(); pitchF.reset(); rollF.reset(); flexF.reset(); latF.reset()
    }

    public func restore(frame: GravityFrame) {
        self.frame = frame
    }

    public func clearCalibration() {
        reference = nil
        frame = nil
        lastPose = nil
        yawF.reset(); pitchF.reset(); rollF.reset(); flexF.reset(); latF.reset()
    }

    /// After a stream reset, keep gravity posture but re-zero yaw/pitch/roll relative pose.
    public func recaptureAttitude(from sample: HeadSample) {
        reference = sample.attitude.normalized
        yawDrift = 0
        yawF.reset(); pitchF.reset(); rollF.reset()
    }

    public func process(_ sample: HeadSample) -> HeadPose {
        let dt = max(1e-3, lastT.map { sample.time - $0 } ?? 0.04)
        emaDt = emaDt * 0.9 + dt * 0.1
        lastT = sample.time
        hz = 1 / emaDt

        // Bud handoff (left → right or vice versa) can jump the attitude solution.
        // Gravity is continuous across buds; re-seed only the attitude reference.
        if config.recenterOnEarSwitch, sample.ear != .unknown,
           let last = lastEar, last != sample.ear, last != .unknown {
            recaptureAttitude(from: sample)
            earSwitchCount += 1
        }
        lastEar = sample.ear

        yawF.minCutoff = config.angleMinCutoff; yawF.beta = config.angleBeta
        pitchF.minCutoff = config.angleMinCutoff; pitchF.beta = config.angleBeta
        rollF.minCutoff = config.angleMinCutoff; rollF.beta = config.angleBeta
        flexF.minCutoff = config.postureMinCutoff; flexF.beta = config.postureBeta
        latF.minCutoff = config.postureMinCutoff; latF.beta = config.postureBeta

        let rel: Quat
        if let reference {
            rel = sample.attitude.bodyRelative(to: reference)
        } else {
            rel = .identity
        }
        var euler = rel.headphoneEuler

        // Yaw has no absolute anchor for headphones and drifts slowly over minutes.
        // While the head is measurably still, bleed the apparent yaw back toward
        // center at a capped rate; deliberate turns (fast) pass through untouched.
        if config.yawDriftCorrection {
            let still = sample.rotationRate.length < config.yawDriftStillGyro
            if still {
                let maxStep = config.yawDriftRate * dt
                yawDrift += min(maxStep, max(-maxStep, Angle.wrap(euler.yaw - yawDrift)))
            }
            euler.yaw = Angle.wrap(euler.yaw - yawDrift)
        }
        if config.invertRoll { euler.roll = -euler.roll }
        if config.invertPitch { euler.pitch = -euler.pitch }
        if config.invertYaw { euler.yaw = -euler.yaw }

        let yaw = yawF.filter(euler.yaw, t: sample.time, wrapAngles: true)
        let pitch = pitchF.filter(euler.pitch, t: sample.time, wrapAngles: true)
        let roll = rollF.filter(euler.roll, t: sample.time, wrapAngles: true)

        var flexRaw = frame.map { $0.flexion(gravity: sample.gravity) } ?? 0
        var latRaw = frame.map { $0.lateral(gravity: sample.gravity) } ?? 0
        if config.invertFlexion { flexRaw = -flexRaw }
        if config.invertLateral { latRaw = -latRaw }
        let flexion = flexF.filter(flexRaw, t: sample.time, wrapAngles: true)
        let lateral = latF.filter(latRaw, t: sample.time, wrapAngles: true)

        // Gyro is in the headphone body frame (x right ear, y nose, z crown):
        // turn = about z, nod = about x, ear tilt = about y.
        let rr = sample.rotationRate
        var yawRate = rr.z
        var pitchRate = rr.x
        var rollRate = rr.y
        if config.invertYaw { yawRate = -yawRate }
        if config.invertPitch { pitchRate = -pitchRate }
        if config.invertRoll { rollRate = -rollRate }

        let accel = sample.userAcceleration.length
        let gyro = rr.length

        // Quality drops when samples are stale, buds are being handled, or walking.
        var quality = 1.0
        if hz < 8 { quality *= 0.4 }
        if gyro > 6 { quality *= 0.3 }
        if accel > 0.45 { quality *= 0.4 }
        if frame == nil { quality *= 0.7 }

        let pose = HeadPose(
            time: sample.time,
            hostTime: sample.hostTime,
            yaw: yaw, pitch: pitch, roll: roll,
            yawRate: yawRate, pitchRate: pitchRate, rollRate: rollRate,
            flexion: flexion, lateral: lateral,
            accelMag: accel, gyroMag: gyro,
            quality: Angle.clamp(quality, 0, 1),
            hz: hz,
            ear: sample.ear,
            calibrated: isCalibrated
        )
        lastPose = pose
        return pose
    }
}

public final class HeadMotionService: NSObject, CMHeadphoneMotionManagerDelegate, @unchecked Sendable {
    public var onSample: ((HeadSample) -> Void)?
    public var onConnection: ((Bool) -> Void)?
    public var onAvailability: ((Bool) -> Void)?
    public var onAuthorization: ((CMAuthorizationStatus) -> Void)?

    private var manager = CMHeadphoneMotionManager()
    private let queue = OperationQueue()
    private var started = false
    private var connected = false
    private var lastSampleAt: Date?
    private var lastResub = Date.distantPast
    private var watchdog: DispatchSourceTimer?
    private let lock = NSLock()

    public override init() {
        super.init()
        queue.name = "app.airpoise.motion"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
    }

    public var isAvailable: Bool { manager.isDeviceMotionAvailable }
    public var isActive: Bool { manager.isDeviceMotionActive }
    public var isConnected: Bool { connected }
    public var authorizationStatus: CMAuthorizationStatus { CMHeadphoneMotionManager.authorizationStatus() }
    public var lastSampleDate: Date? { lastSampleAt }

    public func start() {
        manager.delegate = self
        onAuthorization?(authorizationStatus)
        onAvailability?(manager.isDeviceMotionAvailable)
        manager.startConnectionStatusUpdates()
        startUpdates()
        startWatchdog()
    }

    public func stop() {
        watchdog?.cancel(); watchdog = nil
        manager.stopDeviceMotionUpdates()
        manager.stopConnectionStatusUpdates()
        started = false
        connected = false
    }

    public func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        connected = true
        log.info("headphones connected")
        DispatchQueue.main.async { self.onConnection?(true) }
        startUpdates()
    }

    public func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        connected = false
        started = false
        log.info("headphones disconnected")
        DispatchQueue.main.async { self.onConnection?(false) }
    }

    private func startUpdates() {
        lock.lock()
        defer { lock.unlock() }
        onAvailability?(manager.isDeviceMotionAvailable)
        onAuthorization?(authorizationStatus)
        guard manager.isDeviceMotionAvailable else { return }
        guard !started else { return }
        started = true
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, error in
            guard let self else { return }
            if let error {
                log.error("motion error: \(error.localizedDescription, privacy: .public)")
                return
            }
            guard let motion else { return }
            self.lastSampleAt = Date()
            self.connected = true
            let sample = Self.convert(motion)
            DispatchQueue.main.async { self.onSample?(sample) }
        }
    }

    public func resubscribe() {
        lock.lock()
        manager.stopDeviceMotionUpdates()
        manager.delegate = nil
        manager = CMHeadphoneMotionManager()
        manager.delegate = self
        started = false
        lastSampleAt = nil
        lastResub = Date()
        lock.unlock()
        manager.startConnectionStatusUpdates()
        startUpdates()
        log.info("resubscribed motion manager")
    }

    private func startWatchdog() {
        watchdog?.cancel()
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        t.schedule(deadline: .now() + 4, repeating: 4)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.onAvailability?(self.manager.isDeviceMotionAvailable)
            self.onAuthorization?(self.authorizationStatus)
            guard self.manager.isDeviceMotionAvailable else { return }
            let stale: Bool
            if let last = self.lastSampleAt {
                stale = Date().timeIntervalSince(last) > 8
            } else {
                stale = self.started
            }
            if stale, Date().timeIntervalSince(self.lastResub) > 12 {
                self.resubscribe()
            } else if !self.started {
                self.startUpdates()
            }
        }
        t.resume()
        watchdog = t
    }

    private static func convert(_ m: CMDeviceMotion) -> HeadSample {
        let q = m.attitude.quaternion
        let ear: SensorEar
        switch m.sensorLocation {
        case .headphoneLeft: ear = .left
        case .headphoneRight: ear = .right
        default: ear = .unknown
        }
        return HeadSample(
            time: m.timestamp,
            hostTime: Date(),
            attitude: Quat(x: q.x, y: q.y, z: q.z, w: q.w).normalized,
            gravity: Vec3(m.gravity.x, m.gravity.y, m.gravity.z),
            userAcceleration: Vec3(m.userAcceleration.x, m.userAcceleration.y, m.userAcceleration.z),
            rotationRate: Vec3(m.rotationRate.x, m.rotationRate.y, m.rotationRate.z),
            heading: m.heading,
            ear: ear
        )
    }
}
