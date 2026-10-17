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
        let noCrop = CanvasGeometry.Crop(left:0,top:0,right:0,bottom:0)
        // Portrait framing must reduce height independently of width, then allow
        // content to move vertically inside the fixed cropped frame.
        let top = box.crop(handle:1,translation:CGSize(width:0,height:12),sourceSize:CGSize(width:100,height:50),initial:noCrop,position:CGPoint(x:10,y:20),alignment:5)!
        precondition(top.crop == .init(left:0,top:12,right:0,bottom:0) && top.position == CGPoint(x:10,y:32))
        let bottom = box.crop(handle:5,translation:CGSize(width:0,height:-14),sourceSize:CGSize(width:100,height:50),initial:noCrop,position:CGPoint(x:10,y:20),alignment:5)!
        precondition(bottom.crop == .init(left:0,top:0,right:0,bottom:14) && bottom.position == CGPoint(x:10,y:20))
        let verticalFrame = CanvasGeometry(corners:[[10,32],[110,32],[110,58],[10,58]])!
        let verticalPan = verticalFrame.panCrop(translation:CGSize(width:0,height:-8),sourceSize:CGSize(width:100,height:50),initial:.init(left:0,top:12,right:0,bottom:12))!
        precondition(verticalPan == .init(left:0,top:20,right:0,bottom:4))
        let crop = box.crop(handle:0,translation:CGSize(width:20,height:10),sourceSize:CGSize(width:100,height:50),initial:noCrop,position:CGPoint(x:10,y:20),alignment:5)!
        precondition(crop.crop == .init(left:20,top:10,right:0,bottom:0) && crop.position == CGPoint(x:30,y:30))
        let rotatedCrop = rotated.crop(handle:0,translation:CGSize(width:-10,height:20),sourceSize:CGSize(width:100,height:50),initial:noCrop,position:CGPoint(x:10,y:20),alignment:5)!
        precondition(rotatedCrop.crop == crop.crop && rotatedCrop.position == CGPoint(x:0,y:40))
        let mirroredCrop = flipped.crop(handle:7,translation:CGSize(width:-20,height:0),sourceSize:CGSize(width:100,height:50),initial:noCrop,position:CGPoint(x:110,y:20),alignment:5)!
        precondition(mirroredCrop.crop.left == 20 && mirroredCrop.position.x == 90)
        let centeredCrop = box.crop(handle:7,translation:CGSize(width:20,height:0),sourceSize:CGSize(width:100,height:50),initial:noCrop,position:CGPoint(x:60,y:45),alignment:0)!
        precondition(centeredCrop.position == CGPoint(x:70,y:45))
        let clamped = box.crop(handle:4,translation:CGSize(width:-500,height:-500),sourceSize:CGSize(width:100,height:50),initial:noCrop,position:.zero,alignment:5)!
        precondition(clamped.crop.right == 99 && clamped.crop.bottom == 49)
        let restored = box.crop(handle:0,translation:CGSize(width:-500,height:-500),sourceSize:CGSize(width:100,height:50),initial:crop.crop,position:.zero,alignment:5)!
        precondition(restored.crop == noCrop)
        let pan = box.panCrop(translation:CGSize(width:500,height:-500),sourceSize:CGSize(width:140,height:70),initial:.init(left:20,top:10,right:20,bottom:10))!
        precondition(pan == .init(left:0,top:20,right:40,bottom:0))
        precondition(degenerate.crop(handle:0,translation:.zero,sourceSize:CGSize(width:100,height:50),initial:noCrop,position:.zero,alignment:5) == nil)
        print("PASS: crop edges/corners with rotation, mirror and centered anchor; nonempty clamp, uncrop and content pan preserving frame")
        let reflow = CanvasGeometry(corners:[[0,0],[480,0],[480,720],[0,720]])!
        let emptyCrop=CanvasGeometry.Crop(left:0,top:0,right:0,bottom:0)
        let right=reflow.resizeContent(handle:3,translation:CGSize(width:-180,height:100),sourceSize:CGSize(width:480,height:720),crop:emptyCrop,position:.zero,alignment:5,minimum:CGSize(width:240,height:140),maximum:CGSize(width:1920,height:2160))!
        precondition(right.size==CGSize(width:300,height:720) && right.position == .zero)
        let resizedTop=reflow.resizeContent(handle:1,translation:CGSize(width:120,height:100),sourceSize:CGSize(width:480,height:720),crop:emptyCrop,position:.zero,alignment:5,minimum:CGSize(width:240,height:140),maximum:CGSize(width:1920,height:2160))!
        precondition(resizedTop.size==CGSize(width:480,height:620) && resizedTop.position==CGPoint(x:0,y:100))
        let mirrored=CanvasGeometry(corners:[[0,0],[0,-480],[720,-480],[720,0]])!
        let resizedRotated=mirrored.resizeContent(handle:7,translation:CGSize(width:0,height:-80),sourceSize:CGSize(width:480,height:720),crop:emptyCrop,position:CGPoint(x:360,y:-240),alignment:0,minimum:CGSize(width:240,height:140),maximum:CGSize(width:1920,height:2160))!
        precondition(resizedRotated.size==CGSize(width:400,height:720) && resizedRotated.position==CGPoint(x:360,y:-280))
        print("PASS: responsive source width/height independently reflow, fixed opposite edge and rotated/mirrored centered anchor")
        print("PASS: canvas selection and proportional resize with rotation, mirroring, degenerate and invalid bounds")
    }
}
