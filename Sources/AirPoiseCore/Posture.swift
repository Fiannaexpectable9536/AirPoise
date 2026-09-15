import Foundation

public enum PostureBand: String, Codable, Sendable {
    case unknown
    case uncalibrated
    case excellent
    case good
    case leaning
    case slouch
    case tilted
}

public struct PostureSnapshot: Sendable {
    public var band: PostureBand
    public var flexionDeg: Double
    public var lateralDeg: Double
    public var totalDeg: Double
    public var score: Double
    public var dwell: TimeInterval
    public var calibrated: Bool
    public var hint: String

    public init(
        band: PostureBand,
        flexionDeg: Double,
        lateralDeg: Double,
        totalDeg: Double,
        score: Double,
        dwell: TimeInterval,
        calibrated: Bool,
        hint: String
    ) {
        self.band = band
        self.flexionDeg = flexionDeg
        self.lateralDeg = lateralDeg
        self.totalDeg = totalDeg
        self.score = score
        self.dwell = dwell
        self.calibrated = calibrated
        self.hint = hint
    }
}

public struct PostureConfig: Codable, Equatable, Sendable {
    public var enabled = true
    public var excellentMax: Double = 7
    public var goodMax: Double = 12
    public var leanMax: Double = 20
    public var lateralWarn: Double = 14
    public var slouchHold: Double = 8
    public var leanHold: Double = 12
    public var nudgeCooldown: Double = 90
    public var breakEveryMinutes: Double = 45
    public var breakHoldSeconds: Double = 20
    public var soundEnabled = true
    public var overlayEnabled = true
    public var notificationsEnabled = true
    public var speakEnabled = false
    public var hapticClick = true
    public var ignoreWhenWalking = true
    public var invertFlexion = false

    public init() {}
}

public struct DailyStats: Codable, Equatable, Sendable {
    public var day: String
    public var excellent: Double = 0
    public var good: Double = 0
    public var leaning: Double = 0
    public var slouch: Double = 0
    public var tilted: Double = 0
    public var worn: Double = 0
    public var nudges: Int = 0
    public var gestures: Int = 0
    public var calibrations: Int = 0
    public var breaksTaken: Int = 0

    public init(day: String) { self.day = day }

    public var totalTracked: Double { excellent + good + leaning + slouch + tilted }

    public var score: Double {
        let t = totalTracked
        guard t > 1 else { return 100 }
        return Angle.clamp((excellent * 100 + good * 82 + leaning * 55 + tilted * 60 + slouch * 20) / t, 0, 100)
    }
}

public enum CoachEvent: Sendable {
    case nudge(PostureBand, String)
    case recovered
    case takeBreak
    case calibrated
}

public final class PostureCoach: @unchecked Sendable {
    public var config = PostureConfig()
    public var onEvent: ((CoachEvent) -> Void)?
    public var onSnapshot: ((PostureSnapshot) -> Void)?

    public private(set) var snapshot = PostureSnapshot(
        band: .uncalibrated, flexionDeg: 0, lateralDeg: 0, totalDeg: 0,
        score: 100, dwell: 0, calibrated: false, hint: "Calibrate while sitting tall."
    )
    public private(set) var stats: DailyStats
    public private(set) var lastNudge: Date?

    private var bandSince = Date()
    private var lastBand: PostureBand = .unknown
    private var lastSample: Date?
    private var lastBreakPrompt = Date.distantPast
    private var sittingSince: Date?
    private var recoveredArmed = false
    /// Streak-based band stabilization: a different band must persist across this
    /// many samples (~0.4 s at 25 Hz) before it takes over. Kills boundary flicker.
    private let stabilityStreak = 10
    private var pendingBand: PostureBand = .unknown
    private var pendingCount = 0

    public init(day: String = DailyStats.todayKey()) {
        stats = DailyStats(day: day)
    }

    public func load(stats: DailyStats) { self.stats = stats }

    public func process(_ pose: HeadPose) {
        rotateDayIfNeeded()
        guard config.enabled else { return }

        let now = pose.hostTime
        if let last = lastSample {
            let dt = now.timeIntervalSince(last)
            if dt > 0, dt < 2.2 {
                accumulate(dt)
                stats.worn += dt
            }
        }
        lastSample = now
        if sittingSince == nil { sittingSince = now }

        guard pose.calibrated else {
            snapshot = PostureSnapshot(
                band: .uncalibrated, flexionDeg: 0, lateralDeg: 0, totalDeg: 0,
                score: stats.score, dwell: 0, calibrated: false,
                hint: "Sit the way you want to sit. Then calibrate."
            )
            onSnapshot?(snapshot)
            return
        }

        if config.ignoreWhenWalking, pose.accelMag > 0.7, pose.gyroMag > 2.5 {
            return
        }

        var flex = pose.flexionDeg
        if config.invertFlexion { flex = -flex }
        let lat = abs(pose.lateralDeg)
        let total = hypot(max(0, flex), lat)

        let candidate: PostureBand
        if lat > config.lateralWarn && lat >= max(8, abs(flex)) {
            candidate = .tilted
        } else if flex <= config.excellentMax && lat < config.lateralWarn * 0.75 {
            candidate = .excellent
        } else if flex <= config.goodMax && lat < config.lateralWarn {
            candidate = .good
        } else if flex <= config.leanMax {
            candidate = .leaning
        } else {
            candidate = .slouch
        }
        let band = stabilize(candidate: candidate, flex: flex, lat: lat, now: now)

        if band != lastBand {
            lastBand = band
            bandSince = now
            if (band == .excellent || band == .good), recoveredArmed {
                recoveredArmed = false
                onEvent?(.recovered)
            }
        }
        let dwell = now.timeIntervalSince(bandSince)

        let hint: String
        switch band {
        case .excellent: hint = "Spine stacked. Nice."
        case .good: hint = "Mostly upright."
        case .leaning: hint = "Chin is creeping forward."
        case .slouch: hint = "Lift through the crown. Bring the screen to you."
        case .tilted: hint = "Even out your ears — one shoulder is high."
        default: hint = ""
        }

        snapshot = PostureSnapshot(
            band: band,
            flexionDeg: flex,
            lateralDeg: pose.lateralDeg,
            totalDeg: total,
            score: stats.score,
            dwell: dwell,
            calibrated: true,
            hint: hint
        )
        onSnapshot?(snapshot)

        maybeNudge(band: band, dwell: dwell, now: now, hint: hint)
        maybeBreak(now: now)
    }

    public func noteCalibration() {
        rotateDayIfNeeded()
        stats.calibrations += 1
        lastBand = .excellent
        bandSince = Date()
        sittingSince = Date()
        onEvent?(.calibrated)
    }

    public func noteGesture() {
        rotateDayIfNeeded()
        stats.gestures += 1
    }

    public func noteBreakTaken() {
        rotateDayIfNeeded()
        stats.breaksTaken += 1
        sittingSince = Date()
        lastBreakPrompt = Date()
    }

    /// A candidate band must be seen for `stabilityStreak` consecutive samples
    /// before it replaces the last. Boundary oscillation never changes the band.
    private func stabilize(candidate: PostureBand, flex: Double, lat: Double, now: Date) -> PostureBand {
        _ = now; _ = flex; _ = lat
        if lastBand == .unknown || lastBand == .uncalibrated || candidate == lastBand {
            pendingBand = .unknown
            pendingCount = 0
            return candidate
        }
        if candidate == pendingBand {
            pendingCount += 1
        } else {
            pendingBand = candidate
            pendingCount = 1
        }
        if pendingCount >= stabilityStreak {
            pendingBand = .unknown
            pendingCount = 0
            return candidate
        }
        return lastBand
    }

    private func maybeNudge(band: PostureBand, dwell: TimeInterval, now: Date, hint: String) {
        let need: TimeInterval
        switch band {
        case .slouch: need = config.slouchHold
        case .leaning: need = config.leanHold
        case .tilted: need = max(10, config.leanHold)
        default: return
        }
        guard dwell >= need else { return }
        if let last = lastNudge, now.timeIntervalSince(last) < config.nudgeCooldown { return }
        lastNudge = now
        recoveredArmed = true
        stats.nudges += 1
        onEvent?(.nudge(band, hint))
    }

    private func maybeBreak(now: Date) {
        guard config.breakEveryMinutes > 0, let start = sittingSince else { return }
        let mins = now.timeIntervalSince(start) / 60
        guard mins >= config.breakEveryMinutes else { return }
        guard now.timeIntervalSince(lastBreakPrompt) > config.breakEveryMinutes * 45 else { return }
        lastBreakPrompt = now
        onEvent?(.takeBreak)
    }

    private func accumulate(_ dt: Double) {
        switch lastBand {
        case .excellent: stats.excellent += dt
        case .good: stats.good += dt
        case .leaning: stats.leaning += dt
        case .slouch: stats.slouch += dt
        case .tilted: stats.tilted += dt
        default: break
        }
    }

    private func rotateDayIfNeeded() {
        let key = DailyStats.todayKey()
        if stats.day != key { stats = DailyStats(day: key) }
    }
}

public extension DailyStats {
    static func todayKey(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
