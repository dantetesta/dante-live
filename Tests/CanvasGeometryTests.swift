import Foundation
import CoreGraphics

@main enum CanvasGeometryTests {
    static func main() {
        let box = CanvasGeometry(corners: [[10,20],[110,20],[110,70],[10,70]])!
        precondition(box.contains(CGPoint(x: 60, y: 45)))
        precondition(!box.contains(CGPoint(x: 120, y: 45)))
        precondition(abs(box.resizeMultiplier(translation: CGSize(width: 100, height: 50)) - 2) < 0.000001)
        let rotated = CanvasGeometry(corners: [[10,20],[10,120],[-40,120],[-40,20]])!
        precondition(rotated.contains(CGPoint(x: -15, y: 70)))
        precondition(!rotated.contains(CGPoint(x: 15, y: 70)))
        precondition(abs(rotated.resizeMultiplier(translation: CGSize(width: -50, height: 100)) - 2) < 0.000001)
        let flipped = CanvasGeometry(corners: [[110,20],[10,20],[10,70],[110,70]])!
        precondition(flipped.contains(CGPoint(x: 60, y: 45)))
        precondition(abs(flipped.resizeMultiplier(translation: CGSize(width: -100, height: 50)) - 2) < 0.000001)
        let degenerate = CanvasGeometry(corners: [[0,0],[0,0],[0,0],[0,0]])!
        precondition(!degenerate.contains(.zero))
        precondition(degenerate.resizeMultiplier(translation: CGSize(width: 30, height: 50)) == 1)
        precondition(CanvasGeometry(corners: [[.nan,0],[0,0],[0,0],[0,0]]) == nil)
        precondition(CanvasGeometry(corners: [[0,0]]) == nil)
        for geometry in [box, rotated, flipped] {
            for corner in 0..<4 {
                let fixed = geometry.corners[(corner + 2) % 4]
                let moving = geometry.corners[corner]
                let delta = CGSize(width: moving.x - fixed.x, height: moving.y - fixed.y)
                let resized = geometry.resize(corner: corner, translation: delta, position: geometry.corners[0])!
                precondition(abs(resized.multiplier - 2) < 0.000001)
                precondition(abs(resized.position.x - (fixed.x + (geometry.corners[0].x - fixed.x) * 2)) < 0.000001)
                precondition(abs(resized.position.y - (fixed.y + (geometry.corners[0].y - fixed.y) * 2)) < 0.000001)
            }
        }
        precondition(degenerate.resize(corner: 0, translation: .zero, position: .zero) == nil)
        print("PASS: canvas selection and proportional resize with rotation, mirroring, degenerate and invalid bounds")
    }
}
