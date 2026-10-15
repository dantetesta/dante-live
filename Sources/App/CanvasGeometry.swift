import Foundation
import CoreGraphics

/// The engine supplies the transformed unit box, including crop, bounds,
/// alignment, rotation and mirrored scale. Keep editing in canvas coordinates.
struct CanvasGeometry {
    let corners: [CGPoint]

    init?(corners: [[Double]]) {
        guard corners.count == 4,
              corners.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isFinite) }) else { return nil }
        self.corners = corners.map { CGPoint(x: $0[0], y: $0[1]) }
    }

    func contains(_ point: CGPoint) -> Bool {
        let origin = corners[0]
        let x = CGPoint(x: corners[1].x - origin.x, y: corners[1].y - origin.y)
        let y = CGPoint(x: corners[3].x - origin.x, y: corners[3].y - origin.y)
        let determinant = x.x * y.y - x.y * y.x
        guard abs(determinant) > 0.000001 else { return false }
        let dx = point.x - origin.x, dy = point.y - origin.y
        let u = (dx * y.y - dy * y.x) / determinant
        let v = (x.x * dy - x.y * dx) / determinant
        return u >= 0 && u <= 1 && v >= 0 && v <= 1
    }

    func resizeMultiplier(translation: CGSize) -> Double {
        let dx = corners[2].x - corners[0].x, dy = corners[2].y - corners[0].y
        let squaredLength = dx * dx + dy * dy
        guard squaredLength > 0.000001 else { return 1 }
        return max(0.01, 1 + (translation.width * dx + translation.height * dy) / squaredLength)
    }

    struct Resize {
        let multiplier: Double
        let position: CGPoint
    }
    /// Scale about the opposite corner; this also works for rotation, cropping
    /// and mirrored items, without assuming the item's position is its top left.
    func resize(corner: Int, translation: CGSize, position: CGPoint) -> Resize? {
        guard corners.indices.contains(corner) else { return nil }
        let fixed = corners[(corner + 2) % 4], moving = corners[corner]
        let dx = moving.x - fixed.x, dy = moving.y - fixed.y
        let length = dx * dx + dy * dy
        guard length > 0.000001 else { return nil }
        let ratio = max(0.01, 1 + (translation.width * dx + translation.height * dy) / length)
        return Resize(multiplier: ratio, position: CGPoint(x: fixed.x + (position.x - fixed.x) * ratio,
                                                           y: fixed.y + (position.y - fixed.y) * ratio))
    }
}
