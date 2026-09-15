import Foundation

public struct Vec3: Equatable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x; self.y = y; self.z = z
    }

    public init(x: Double, y: Double, z: Double) {
        self.x = x; self.y = y; self.z = z
    }

    public static let zero = Vec3(0, 0, 0)
    public static let up = Vec3(0, 1, 0)

    public var length: Double { (x * x + y * y + z * z).squareRoot() }

    public var normalized: Vec3 {
        let n = length
        return n > 1e-12 ? Vec3(x / n, y / n, z / n) : .zero
    }

    public func dot(_ o: Vec3) -> Double { x * o.x + y * o.y + z * o.z }
    public func cross(_ o: Vec3) -> Vec3 {
        Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x)
    }

    public static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x + b.x, a.y + b.y, a.z + b.z) }
    public static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x - b.x, a.y - b.y, a.z - b.z) }
    public static func * (a: Vec3, s: Double) -> Vec3 { Vec3(a.x * s, a.y * s, a.z * s) }
}

public struct Quat: Equatable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    public var w: Double

    public init(x: Double, y: Double, z: Double, w: Double) {
        self.x = x; self.y = y; self.z = z; self.w = w
    }

    public static let identity = Quat(x: 0, y: 0, z: 0, w: 1)

    public var inverse: Quat {
        let n = x * x + y * y + z * z + w * w
        guard n > 1e-18 else { return .identity }
        return Quat(x: -x / n, y: -y / n, z: -z / n, w: w / n)
    }

    public var normalized: Quat {
        let n = (x * x + y * y + z * z + w * w).squareRoot()
        guard n > 1e-18 else { return .identity }
        return Quat(x: x / n, y: y / n, z: z / n, w: w / n)
    }

    /// Hamilton product `self * r`.
    public func multiplied(by r: Quat) -> Quat {
        Quat(
            x: w * r.x + x * r.w + y * r.z - z * r.y,
            y: w * r.y - x * r.z + y * r.w + z * r.x,
            z: w * r.z + x * r.y - y * r.x + z * r.w,
            w: w * r.w - x * r.x - y * r.y - z * r.z
        )
    }

    /// `current * reference⁻¹` — same convention as `CMAttitude.multiply(byInverseOf:)`.
    public func relative(to reference: Quat) -> Quat {
        multiplied(by: reference.inverse).normalized
    }

    /// Orientation relative to `reference` expressed in the *reference body* frame:
    /// `reference⁻¹ * self`. This is the recentering used by head trackers.
    public func bodyRelative(to reference: Quat) -> Quat {
        reference.inverse.multiplied(by: self).normalized
    }

    /// Euler decomposition for Apple's headphone body frame:
    /// **x = right ear, y = nose, z = crown**.
    ///
    /// Intrinsic Z–X′–Y″ order (R = Rz(yaw)·Rx(pitch)·Ry(roll)), anatomical signs:
    /// - `yaw +`  = look left        (rotation about +z / up)
    /// - `pitch +` = chin up         (rotation about +x / right ear)
    /// - `roll +` = top of head toward the right shoulder (rotation about +y / nose)
    public var headphoneEuler: (yaw: Double, pitch: Double, roll: Double) {
        let sinp = 2 * (y * z + w * x)
        let pitch: Double
        if sinp >= 1 { pitch = .pi / 2 }
        else if sinp <= -1 { pitch = -.pi / 2 }
        else { pitch = asin(sinp) }
        let yaw = atan2(2 * (w * z - x * y), 1 - 2 * (x * x + z * z))
        let roll = atan2(2 * (w * y - x * z), 1 - 2 * (x * x + y * y))
        return (yaw, pitch, roll)
    }

    public func rotate(_ v: Vec3) -> Vec3 {
        let qv = Vec3(x, y, z)
        let t = qv.cross(v) * 2
        return v + t * w + qv.cross(t)
    }
}

public enum Angle {
    public static func deg(_ rad: Double) -> Double { rad * 180 / .pi }
    public static func rad(_ deg: Double) -> Double { deg * .pi / 180 }

    public static func wrap(_ r: Double) -> Double {
        var a = r.truncatingRemainder(dividingBy: 2 * .pi)
        if a > .pi { a -= 2 * .pi }
        if a < -.pi { a += 2 * .pi }
        return a
    }

    public static func wrapDeg(_ d: Double) -> Double {
        var a = d.truncatingRemainder(dividingBy: 360)
        if a > 180 { a -= 360 }
        if a < -180 { a += 360 }
        return a
    }

    public static func delta(_ from: Double, _ to: Double) -> Double {
        wrap(to - from)
    }

    public static func clamp(_ x: Double, _ a: Double, _ b: Double) -> Double {
        min(max(x, a), b)
    }
}

/// Casiez 1€ filter — low lag at rest, damps jitter when still.
public final class OneEuroFilter: @unchecked Sendable {
    public var minCutoff: Double
    public var beta: Double
    public var dCutoff: Double

    private var xHat: Double?
    private var dxHat: Double = 0
    private var lastT: Double?

    public init(minCutoff: Double = 1.0, beta: Double = 0.04, dCutoff: Double = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    public func reset() {
        xHat = nil
        dxHat = 0
        lastT = nil
    }

    public func filter(_ x: Double, t: Double, wrapAngles: Bool = false) -> Double {
        defer { lastT = t }
        guard let lastT, let xHat else {
            self.xHat = x
            return x
        }
        let dt = max(1e-3, t - lastT)
        let dx: Double
        if wrapAngles {
            dx = Angle.delta(xHat, x) / dt
        } else {
            dx = (x - xHat) / dt
        }
        let ad = alpha(dCutoff, dt: dt)
        dxHat += (dx - dxHat) * ad
        let cutoff = minCutoff + beta * abs(dxHat)
        let a = alpha(cutoff, dt: dt)
        let next: Double
        if wrapAngles {
            next = xHat + Angle.delta(xHat, x) * a
        } else {
            next = xHat + (x - xHat) * a
        }
        self.xHat = next
        return next
    }

    private func alpha(_ cutoff: Double, dt: Double) -> Double {
        let tau = 1 / (2 * .pi * max(1e-6, cutoff))
        return 1 / (1 + tau / dt)
    }
}

public struct LowPass: Sendable {
    public var alpha: Double
    public var y: Double?

    public init(alpha: Double) { self.alpha = alpha }

    public mutating func apply(_ x: Double) -> Double {
        if let y {
            let n = y + (x - y) * alpha
            self.y = n
            return n
        }
        y = x
        return x
    }

    public mutating func reset() { y = nil }
}

public final class RingBuffer<T>: @unchecked Sendable {
    private var storage: [T]
    private var index = 0
    public private(set) var count = 0
    public let capacity: Int

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
        storage = []
        storage.reserveCapacity(self.capacity)
    }

    public func push(_ value: T) {
        if storage.count < capacity {
            storage.append(value)
            count = storage.count
            index = count % capacity
        } else {
            storage[index] = value
            index = (index + 1) % capacity
            count = capacity
        }
    }

    public var values: [T] {
        if storage.count < capacity { return storage }
        return Array(storage[index...]) + Array(storage[..<index])
    }

    public func last(_ n: Int) -> [T] {
        let v = values
        if v.count <= n { return v }
        return Array(v.suffix(n))
    }

    public func clear() {
        storage.removeAll(keepingCapacity: true)
        index = 0
        count = 0
    }
}
