// FaceRenderModel — per-frame state of the LED dot-matrix face.
//
// Direct port of the state machine in
// kindalive/expression/web_assets/face3d.js: muscles lerp toward driven
// targets, and the face layers its own life on top — blinking, eye
// saccades, a breathing glow, and a syllable-rate mouth flap while the
// robot speaks. The shape math itself lives in KindaliveKit.FaceGeometry
// (fixture-locked); this class supplies the animated inputs and the
// 36×30 coverage mask.

import CoreGraphics
import Foundation
import KindaliveKit

struct MoodColor {
    var red: Double
    var green: Double
    var blue: Double

    init(hex: String) {
        let cleaned = hex.replacingOccurrences(of: "#", with: "")
        let value = UInt32(cleaned, radix: 16) ?? 0x46E0D8
        red = Double((value >> 16) & 255)
        green = Double((value >> 8) & 255)
        blue = Double(value & 255)
    }
}

final class FaceRenderModel {
    // Driven state (targets pushed at ~10 Hz by the view model).
    private var target: [String: Double]
    private(set) var current: [String: Double]
    private var moodTarget = MoodColor(hex: "#46E0D8")
    private(set) var moodCurrent = MoodColor(hex: "#46E0D8")
    private(set) var moodIntensity = 0.3

    // Speech flap.
    private var speaking = false
    private var speechJaw = 0.0
    private var speechPulse = 0.0

    // Autonomous life.
    private var elapsed = 0.0
    private var blinkAt = 1.5
    private var blinkPhase = -1.0
    private var saccadeAt = 2.0
    private(set) var saccade = 0.0
    private var saccadeTarget = 0.0
    private(set) var blink = 0.0
    private(set) var breath = 1.0

    private var lastTime: Double?

    // Reusable 36×30 8-bit grayscale mask context — one byte per LED
    // cell. Shapes are drawn in white on the cleared (black) background;
    // each cell's gray value is its coverage, the same semantics as the
    // JS renderer sampling the mask canvas's alpha channel.
    private let maskContext: CGContext = {
        let ctx = CGContext(
            data: nil,
            width: FaceGrid.cols,
            height: FaceGrid.rows,
            bitsPerComponent: 8,
            bytesPerRow: FaceGrid.cols,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        ctx.setShouldAntialias(true)
        return ctx
    }()

    init() {
        target = Dictionary(uniqueKeysWithValues: FaceState.muscleNames.map { ($0, 0.0) })
        current = target
    }

    // MARK: - Driven inputs (the JS setTargets / setSpeaking / mouthPulse API)

    func setTargets(face: FaceState, moodColorHex: String, moodIntensity: Double) {
        for (name, value) in face.orderedValues {
            target[name] = max(0.0, min(1.0, value))
        }
        moodTarget = MoodColor(hex: moodColorHex)
        self.moodIntensity = max(0.0, min(1.0, moodIntensity))
    }

    func setSpeaking(_ on: Bool) {
        speaking = on
        if !on { speechPulse = 0 }
    }

    func mouthPulse() {
        speechPulse = 1.0
    }

    // MARK: - Per-frame update

    /// Advance animation state to `time` (seconds) and return the current
    /// geometry. Mirrors the frame() function in face3d.js.
    func update(time: Double) -> FaceGeometry {
        let dt = min(max(time - (lastTime ?? time), 0), 0.1)
        lastTime = time
        elapsed += dt

        let k = 1 - exp(-dt / 0.11)
        for name in FaceState.muscleNames {
            current[name]! += (target[name]! - current[name]!) * k
        }
        moodCurrent.red += (moodTarget.red - moodCurrent.red) * k
        moodCurrent.green += (moodTarget.green - moodCurrent.green) * k
        moodCurrent.blue += (moodTarget.blue - moodCurrent.blue) * k

        // Blink: 0.16 s triangle, every 2.4-6 s.
        if blinkPhase >= 0 {
            blinkPhase += dt / 0.16
            if blinkPhase > 1 { blinkPhase = -1 }
        } else if elapsed > blinkAt {
            blinkPhase = 0
            blinkAt = elapsed + 2.4 + Double.random(in: 0..<3.6)
        }
        blink = blinkPhase >= 0 ? 1 - abs(blinkPhase - 0.5) * 2 : 0

        // Saccade: occasional glance, ±1.1 cells.
        if elapsed > saccadeAt {
            saccadeTarget = Double.random(in: -1.1...1.1)
            saccadeAt = elapsed + 1.8 + Double.random(in: 0..<3.2)
        }
        saccade += (saccadeTarget - saccade) * (1 - exp(-dt / 0.06))

        // Speaking flap feeds the mouth's jaw_open.
        var flapTarget = 0.0
        if speaking {
            let osc = abs(0.6 * sin(elapsed * 27.0) + 0.4 * sin(elapsed * 17.3 + 1.7))
            flapTarget = 0.10 + 0.55 * osc + 0.30 * speechPulse
        }
        speechPulse *= exp(-dt / 0.10)
        speechJaw += (flapTarget - speechJaw) * (1 - exp(-dt / 0.05))

        breath = 0.92 + 0.08 * sin(elapsed * 1.6)

        var muscles = current
        if speechJaw > 0.001 {
            muscles["jaw_open"] = min(1.0, muscles["jaw_open"]! + speechJaw)
        }
        return FaceGeometry(muscles: muscles, blink: blink)
    }

    // MARK: - Mask rasterization

    /// Draw the face shapes into the low-res mask and return per-cell
    /// coverage in [0, 1], row-major with row 0 at the TOP (same as the
    /// JS getImageData sampling). Canvas anti-aliasing gives edge dots a
    /// fractional coverage → the smooth LED falloff.
    func coverage(for geometry: FaceGeometry) -> [Double] {
        let cols = FaceGrid.cols
        let rows = FaceGrid.rows
        let ctx = maskContext

        ctx.clear(CGRect(x: 0, y: 0, width: cols, height: rows))
        ctx.saveGState()
        // CG's origin is bottom-left; the JS grid is top-down. Flip once
        // so all the geometry below uses grid coordinates directly.
        ctx.translateBy(x: 0, y: CGFloat(rows))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.setStrokeColor(gray: 1, alpha: 1)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        let cx = Double(cols) / 2
        let eyeY = geometry.eyeCenterY

        for sx in [-1.0, 1.0] {
            let ex = cx + sx * FaceGrid.eyeDx + saccade

            if geometry.happyEyes {
                // Happy: upward arc (^), stroked.
                ctx.saveGState()
                ctx.translateBy(x: ex, y: eyeY)
                ctx.setLineWidth(2.2)
                let path = CGMutablePath()
                path.addArc(
                    center: CGPoint(x: 0, y: 1.8), radius: 4.0,
                    startAngle: .pi * 1.18, endAngle: .pi * 1.82,
                    clockwise: false
                )
                ctx.addPath(path)
                ctx.strokePath()
                ctx.restoreGState()
            } else {
                ctx.saveGState()
                ctx.translateBy(x: ex, y: eyeY)
                ctx.rotate(by: sx * geometry.eyeRotation)
                let hh = geometry.eyeHalfHeight
                ctx.fillEllipse(in: CGRect(x: -3.3, y: -hh, width: 6.6, height: 2 * hh))
                ctx.restoreGState()
            }

            if geometry.showBrow {
                ctx.setLineWidth(1.7)
                ctx.move(to: CGPoint(x: ex - sx * 4, y: geometry.browOuterY))
                ctx.addLine(to: CGPoint(x: ex + sx * 3, y: geometry.browInnerY))
                ctx.strokePath()
            }
        }

        // Mouth.
        let halfW = geometry.mouthHalfWidth
        if geometry.mouthOpen {
            let ry = geometry.mouthEllipseRy
            ctx.fillEllipse(in: CGRect(
                x: cx - halfW,
                y: geometry.mouthEllipseCenterY - ry,
                width: 2 * halfW,
                height: 2 * ry
            ))
        } else {
            ctx.setLineWidth(2.1)
            ctx.move(to: CGPoint(x: cx - halfW, y: geometry.mouthCurveEndY))
            ctx.addQuadCurve(
                to: CGPoint(x: cx + halfW, y: geometry.mouthCurveEndY),
                control: CGPoint(x: cx, y: geometry.mouthCurveControlY)
            )
            ctx.strokePath()
        }
        ctx.restoreGState()

        guard let data = ctx.data else {
            return Array(repeating: 0, count: cols * rows)
        }
        let buffer = data.bindMemory(to: UInt8.self, capacity: cols * rows)
        var coverage = [Double](repeating: 0, count: cols * rows)
        for y in 0..<rows {
            // The flip transform only affects drawing; the backing store
            // still has row 0 at the bottom, so mirror rows at readback.
            let sourceRow = rows - 1 - y
            for x in 0..<cols {
                coverage[y * cols + x] = Double(buffer[sourceRow * cols + x]) / 255.0
            }
        }
        return coverage
    }
}
