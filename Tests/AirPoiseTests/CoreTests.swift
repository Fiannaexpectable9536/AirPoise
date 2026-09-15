import XCTest
@testable import AirPoiseCore

final class MathTests: XCTestCase {
    func testAngleWrap() {
        XCTAssertEqual(Angle.wrap(0), 0, accuracy: 1e-9)
        XCTAssertEqual(Angle.wrap(.pi), .pi, accuracy: 1e-9)
        XCTAssertEqual(Angle.wrap(3 * .pi), .pi, accuracy: 1e-6)
        XCTAssertEqual(Angle.wrap(-3 * .pi), -.pi, accuracy: 1e-6)
        XCTAssertEqual(Angle.delta(2.9, -2.9), Angle.wrap(-2.9 - 2.9), accuracy: 1e-9)
    }

    func testQuatRelativeIdentity() {
        let q = Quat(x: 0, y: 0.1, z: 0, w: 0.995).normalized
        let rel = q.relative(to: q)
        XCTAssertEqual(rel.x, 0, accuracy: 1e-6)
        XCTAssertEqual(rel.y, 0, accuracy: 1e-6)
        XCTAssertEqual(rel.z, 0, accuracy: 1e-6)
        XCTAssertEqual(abs(rel.w), 1, accuracy: 1e-6)
    }

    private func axisAngle(_ ax: Vec3, _ theta: Double) -> Quat {
        let s = sin(theta / 2), c = cos(theta / 2)
        return Quat(x: ax.x * s, y: ax.y * s, z: ax.z * s, w: c).normalized
    }

    func testHeadphoneEulerNodIsPitchUp() {
        // Rotation about +x (right ear) = nod: chin up is positive pitch.
        let q = axisAngle(Vec3(1, 0, 0), Angle.rad(20))
        let e = q.headphoneEuler
        XCTAssertEqual(e.pitch, Angle.rad(20), accuracy: 1e-6)
        XCTAssertEqual(e.yaw, 0, accuracy: 1e-6)
        XCTAssertEqual(e.roll, 0, accuracy: 1e-6)
    }

    func testHeadphoneEulerTurnIsYawLeft() {
        // Rotation about +z (crown): nose goes toward -x (left ear) ⇒ look left = positive yaw.
        let q = axisAngle(Vec3(0, 0, 1), Angle.rad(30))
        let e = q.headphoneEuler
        XCTAssertEqual(e.yaw, Angle.rad(30), accuracy: 1e-6)
        XCTAssertEqual(e.pitch, 0, accuracy: 1e-6)
        XCTAssertEqual(e.roll, 0, accuracy: 1e-6)
    }

    func testHeadphoneEulerTiltIsRollRightEarDown() {
        // Rotation about +y (nose): crown (+z) tips toward +x = right ear toward right shoulder.
        let q = axisAngle(Vec3(0, 1, 0), Angle.rad(25))
        let e = q.headphoneEuler
        XCTAssertEqual(e.roll, Angle.rad(25), accuracy: 1e-6)
        XCTAssertEqual(e.yaw, 0, accuracy: 1e-6)
        XCTAssertEqual(e.pitch, 0, accuracy: 1e-6)
    }

    func testGravityFrameFlexionChinDownIsPositive() {
        // AirPods upright: gravity ~ -z. Chin down tips nose toward world-down,
        // so gravity gains +y (nose) component ⇒ flexion > 0.
        let frame = GravityFrame.capture(gravity: Vec3(0, 0, -1))
        XCTAssertEqual(frame.flexion(gravity: Vec3(0, 0, -1)), 0, accuracy: 1e-9)
        let chinDown = frame.flexion(gravity: Vec3(0, 0.5, -0.866).normalized)
        XCTAssertGreaterThan(chinDown, Angle.rad(20))
        let chinUp = frame.flexion(gravity: Vec3(0, -0.5, -0.866).normalized)
        XCTAssertLessThan(chinUp, Angle.rad(-20))
    }

    func testGravityFrameLateralTiltRightIsPositive() {
        let frame = GravityFrame.capture(gravity: Vec3(0, 0, -1))
        let tiltRight = frame.lateral(gravity: Vec3(0.5, 0, -0.866).normalized)
        XCTAssertGreaterThan(tiltRight, Angle.rad(20))
        let tiltLeft = frame.lateral(gravity: Vec3(-0.5, 0, -0.866).normalized)
        XCTAssertLessThan(tiltLeft, Angle.rad(-20))
    }

    func testFlexionGrowsWhenGravityMovesForward() {
        let g0 = Vec3(0, -1, 0)
        let frame = GravityFrame.capture(gravity: g0, preferForward: Vec3(0, 0, -1))
        let gDown = Vec3(0, -0.87, -0.5).normalized
        let flex = frame.flexion(gravity: gDown)
        XCTAssertGreaterThan(abs(flex), Angle.rad(20))
    }

    func testOneEuroSettles() {
        let f = OneEuroFilter(minCutoff: 1.0, beta: 0.04)
        var y = 0.0
        for i in 0..<80 {
            y = f.filter(10, t: Double(i) * 0.04)
        }
        XCTAssertEqual(y, 10, accuracy: 0.15)
    }

    func testGravityFrameZeroAtCapture() {
        let g = Vec3(0.05, -0.98, -0.15)
        let frame = GravityFrame.capture(gravity: g)
        XCTAssertEqual(frame.flexion(gravity: g), 0, accuracy: 1e-9)
        XCTAssertEqual(frame.lateral(gravity: g), 0, accuracy: 1e-9)
        XCTAssertEqual(frame.totalTilt(gravity: g), 0, accuracy: 1e-9)
    }
}

final class PostureTests: XCTestCase {
    func testBands() {
        let coach = PostureCoach(day: "2099-01-01")
        var cfg = PostureConfig()
        cfg.slouchHold = 0.2
        cfg.nudgeCooldown = 0
        coach.config = cfg

        var nudges = 0
        coach.onEvent = { e in
            if case .nudge = e { nudges += 1 }
        }

        var t = 10.0
        let origin = Date()
        func feed(_ flex: Double, _ count: Int) {
            for _ in 0..<count {
                t += 0.04
                coach.process(makePose(flexionDeg: flex, t: t, calibrated: true, host: origin.addingTimeInterval(t)))
            }
        }
        feed(4, 12)
        XCTAssertEqual(coach.snapshot.band, .excellent)

        feed(15, 12)
        XCTAssertEqual(coach.snapshot.band, .leaning)

        feed(19.9, 3)   // boundary shimmer must not flip back
        feed(15, 12)
        XCTAssertEqual(coach.snapshot.band, .leaning)

        feed(28, 30)
        XCTAssertEqual(coach.snapshot.band, .slouch)
    }

    func testDailyScorePrefersUpright() {
        var s = DailyStats(day: "x")
        s.excellent = 50
        s.slouch = 50
        XCTAssertLessThan(s.score, 70)
        s.slouch = 0
        s.excellent = 100
        XCTAssertEqual(s.score, 100, accuracy: 0.1)
    }
}

final class GestureTests: XCTestCase {
    func testNodFiresOnDownAndReturn() {
        let eng = GestureEngine()
        var kinds: [GestureKind] = []
        eng.onGesture = { kinds.append($0.kind) }
        eng.config.sensitivity = 0.8
        eng.config.cooldown = 0.01

        var t = 0.0
        // settle rest
        for _ in 0..<20 {
            t += 0.04
            eng.process(makePose(pitchDeg: 0, t: t))
        }
        // chin down
        for p in stride(from: 0.0, through: -22, by: -3) {
            t += 0.04
            eng.process(makePose(pitchDeg: p, pitchRate: -2, t: t))
        }
        // return
        for p in stride(from: -22.0, through: 0, by: 4) {
            t += 0.04
            eng.process(makePose(pitchDeg: p, pitchRate: 2, t: t))
        }
        XCTAssertTrue(kinds.contains(.nod), "got \(kinds)")
    }

    func testLookRightFlick() {
        let eng = GestureEngine()
        var kinds: [GestureKind] = []
        eng.onGesture = { kinds.append($0.kind) }
        eng.config.sensitivity = 0.85
        eng.config.cooldown = 0.01

        var t = 0.0
        for _ in 0..<15 { t += 0.04; eng.process(makePose(t: t)) }
        for y in stride(from: 0.0, through: 28, by: 5) {
            t += 0.04
            eng.process(makePose(yawDeg: y, yawRate: 2.2, t: t))
        }
        for y in stride(from: 28.0, through: 0, by: -6) {
            t += 0.04
            eng.process(makePose(yawDeg: y, yawRate: -1.5, t: t))
        }
        XCTAssertTrue(kinds.contains(.lookRight) || kinds.contains(.lookLeft), "got \(kinds)")
    }

    func testRestDoesNotFireNod() {
        let eng = GestureEngine()
        var kinds: [GestureKind] = []
        eng.onGesture = { kinds.append($0.kind) }
        var t = 0.0
        for _ in 0..<80 {
            t += 0.04
            eng.process(makePose(pitchDeg: -16, t: t)) // held slouch
        }
        XCTAssertFalse(kinds.contains(.nod), "slouch should not be a nod, got \(kinds)")
    }
}

func makePose(
    yawDeg: Double = 0,
    pitchDeg: Double = 0,
    rollDeg: Double = 0,
    flexionDeg: Double = 0,
    lateralDeg: Double = 0,
    yawRate: Double = 0,
    pitchRate: Double = 0,
    rollRate: Double = 0,
    t: Double,
    calibrated: Bool = true,
    host: Date = Date(),
    quality: Double = 1,
    accel: Double = 0,
    gyro: Double? = nil
) -> HeadPose {
    HeadPose(
        time: t,
        hostTime: host,
        yaw: Angle.rad(yawDeg),
        pitch: Angle.rad(pitchDeg),
        roll: Angle.rad(rollDeg),
        yawRate: yawRate,
        pitchRate: pitchRate,
        rollRate: rollRate,
        flexion: Angle.rad(flexionDeg),
        lateral: Angle.rad(lateralDeg),
        accelMag: accel,
        gyroMag: gyro ?? hypot(yawRate, hypot(pitchRate, rollRate)),
        quality: quality,
        hz: 25,
        ear: .right,
        calibrated: calibrated
    )
}

