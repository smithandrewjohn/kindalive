// FaceGeometry — the pure shape math of the LED dot-matrix face.
//
// Ports the scalar computations of drawMask() in
// kindalive/expression/web_assets/face3d.js (which remains the reference
// implementation). The renderer proper (mask rasterization, dot pass,
// autonomous blink/saccade/breath) lives in the app target; keeping the
// geometry here makes it testable against the face_geometry.json fixture.
//
// All coordinates are in grid space: 36 columns × 30 rows.

import Foundation

public enum FaceGrid {
    public static let cols = 36
    public static let rows = 30
    public static let eyeY = 10.5
    public static let eyeDx = 7.6
    public static let mouthY = 21.5
}

/// Derived shape parameters for one frame of the face, given the 12
/// muscle activations and the current blink amount [0, 1].
public struct FaceGeometry: Sendable, Equatable {
    /// lip_corner_pull − lip_corner_depress, in [-1, 1].
    public let smile: Double
    /// Eye openness factor (already scaled by 1 − blink).
    public let openK: Double
    /// Whether brow bars are drawn at all.
    public let showBrow: Bool
    /// Happy eyes render as upward arcs (^ ^) instead of ellipses.
    public let happyEyes: Bool
    /// Center of the right eye (left eye mirrors around cols/2).
    public let eyeCenterXRight: Double
    public let eyeCenterY: Double
    /// Per-eye rotation in radians (multiplied by ±1 per side).
    public let eyeRotation: Double
    /// Vertical half-height of the eye ellipse.
    public let eyeHalfHeight: Double
    /// Brow bar endpoint heights (inner end, outer end).
    public let browInnerY: Double
    public let browOuterY: Double
    public let mouthY: Double
    public let mouthHalfWidth: Double
    /// Open mouth renders as an ellipse; closed as a quadratic curve.
    public let mouthOpen: Bool
    public let mouthEllipseCenterY: Double
    public let mouthEllipseRy: Double
    public let mouthCurveEndY: Double
    public let mouthCurveControlY: Double

    public init(face: FaceState, blink: Double) {
        self.init(muscles: face.asDict(), blink: blink)
    }

    /// muscles: snake_case name → activation, as in FaceState.asDict().
    public init(muscles: [String: Double], blink: Double) {
        func m(_ name: String) -> Double { muscles[name] ?? 0.0 }

        let s = m("lip_corner_pull") - m("lip_corner_depress")
        smile = s
        openK = max(0.10, min(
            1.2, 0.52 + 0.55 * m("eyelid_upper_raise") - 0.55 * m("eyelid_lower_tighten")
        )) * (1 - blink)
        showBrow = m("brow_lower") > 0.18
            || m("brow_inner_raise") > 0.28
            || m("brow_outer_raise") > 0.4
        happyEyes = s > 0.34 && blink < 0.5
        eyeCenterXRight = Double(FaceGrid.cols) / 2 + FaceGrid.eyeDx
        eyeCenterY = FaceGrid.eyeY
        eyeRotation = m("brow_lower") * 0.45
        eyeHalfHeight = max(0.7, 1.0 + 3.6 * openK)
        browInnerY = FaceGrid.eyeY - 5.2 + 2.6 * m("brow_lower") - 1.6 * m("brow_inner_raise")
        browOuterY = FaceGrid.eyeY - 5.2 - 1.3 * m("brow_outer_raise")
        mouthY = FaceGrid.mouthY
        mouthHalfWidth = 7.0 * (1 - 0.3 * m("lip_pucker"))
        let jaw = m("jaw_open")
        mouthOpen = jaw > 0.10
        mouthEllipseCenterY = FaceGrid.mouthY + 1.6 * s
        mouthEllipseRy = 1.4 + 5.6 * jaw
        mouthCurveEndY = FaceGrid.mouthY - 1.6 * s
        mouthCurveControlY = FaceGrid.mouthY + 5.2 * s
    }
}
