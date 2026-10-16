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
    func resize(handle: Int, translation: CGSize, position: CGPoint) -> Resize? {
        guard (0..<8).contains(handle) else { return nil }
        if handle%2 == 0 { return resize(corner: handle/2, translation: translation, position: position) }
        let index = handle/2
        let moving = CGPoint(x: (corners[index].x+corners[(index+1)%4].x)/2, y: (corners[index].y+corners[(index+1)%4].y)/2)
        let fixed = CGPoint(x: (corners[(index+2)%4].x+corners[(index+3)%4].x)/2, y: (corners[(index+2)%4].y+corners[(index+3)%4].y)/2)
        let dx = moving.x-fixed.x, dy = moving.y-fixed.y, length = dx*dx+dy*dy
        guard length > 0.000001 else { return nil }
        let ratio = max(0.01,1+(translation.width*dx+translation.height*dy)/length)
        return Resize(multiplier: ratio, position: CGPoint(x: fixed.x+(position.x-fixed.x)*ratio,y: fixed.y+(position.y-fixed.y)*ratio))
    }

    struct Crop: Equatable {
        var left: Double; var top: Double; var right: Double; var bottom: Double
    }
    struct CropEdit { let crop: Crop; let position: CGPoint }
    /// Handles run clockwise: top-left, top, top-right, right, bottom-right,
    /// bottom, bottom-left, left. Work in source pixels even when rotated/mirrored.
    func crop(handle: Int, translation: CGSize, sourceSize: CGSize, initial: Crop, position: CGPoint, alignment: Int) -> CropEdit? {
        let width = sourceSize.width - initial.left - initial.right
        let height = sourceSize.height - initial.top - initial.bottom
        guard (0..<8).contains(handle), width > 0, height > 0 else { return nil }
        let x = CGPoint(x: (corners[1].x-corners[0].x)/width, y: (corners[1].y-corners[0].y)/width)
        let y = CGPoint(x: (corners[3].x-corners[0].x)/height, y: (corners[3].y-corners[0].y)/height)
        let determinant = x.x*y.y-x.y*y.x
        guard abs(determinant) > 0.000001 else { return nil }
        let dx = (translation.width*y.y-translation.height*y.x)/determinant
        let dy = (x.x*translation.height-x.y*translation.width)/determinant
        var crop = initial
        if [0,6,7].contains(handle) { crop.left = min(max(0, (initial.left+dx).rounded()), sourceSize.width-initial.right-1) }
        if [2,3,4].contains(handle) { crop.right = min(max(0, (initial.right-dx).rounded()), sourceSize.width-initial.left-1) }
        if [0,1,2].contains(handle) { crop.top = min(max(0, (initial.top+dy).rounded()), sourceSize.height-initial.bottom-1) }
        if [4,5,6].contains(handle) { crop.bottom = min(max(0, (initial.bottom-dy).rounded()), sourceSize.height-initial.top-1) }
        let left = crop.left-initial.left, right = crop.right-initial.right
        let top = crop.top-initial.top, bottom = crop.bottom-initial.bottom
        let anchorX = alignment & 1 != 0 ? 0.0 : alignment & 2 != 0 ? 1.0 : 0.5
        let anchorY = alignment & 4 != 0 ? 0.0 : alignment & 8 != 0 ? 1.0 : 0.5
        let shiftX = left-anchorX*(left+right), shiftY = top-anchorY*(top+bottom)
        return CropEdit(crop: crop, position: CGPoint(x: position.x+x.x*shiftX+y.x*shiftY, y: position.y+x.y*shiftX+y.y*shiftY))
    }

    /// Option-drag inside a cropped frame moves the content while keeping its box fixed.
    func panCrop(translation: CGSize, sourceSize: CGSize, initial: Crop) -> Crop? {
        let width = sourceSize.width-initial.left-initial.right, height = sourceSize.height-initial.top-initial.bottom
        guard width > 0, height > 0 else { return nil }
        let x = CGPoint(x: (corners[1].x-corners[0].x)/width, y: (corners[1].y-corners[0].y)/width)
        let y = CGPoint(x: (corners[3].x-corners[0].x)/height, y: (corners[3].y-corners[0].y)/height)
        let determinant = x.x*y.y-x.y*y.x
        guard abs(determinant) > 0.000001 else { return nil }
        let dx = (translation.width*y.y-translation.height*y.x)/determinant
        let dy = (x.x*translation.height-x.y*translation.width)/determinant
        let horizontal = initial.left+initial.right, vertical = initial.top+initial.bottom
        let left = min(max(0,(initial.left-dx).rounded()),horizontal), top = min(max(0,(initial.top-dy).rounded()),vertical)
        return Crop(left: left, top: top, right: horizontal-left, bottom: vertical-top)
    }
}
