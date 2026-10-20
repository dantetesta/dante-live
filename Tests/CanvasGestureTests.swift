import AppKit
import SwiftUI

@MainActor func runCanvasGestureTests(model: StudioModel) async throws {
    let name="Crop gesture QA", scene=model.sceneName
    precondition(model.command("source.add",["scene":scene,"type":"color_source_v3","name":name,"settings":["width":640,"height":360]]))
    let id=model.items.first { $0.string("name")==name }!.sceneItemID
    precondition(model.command("item.transform",["scene":scene,"id":id,"x":100,"y":60,"scaleX":0.5,"scaleY":0.5]))
    model.selectedItem=id
    let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:640,height:360),styleMask:[.borderless],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false
    // Inject only the modifier state: native AppKit mouse events still exercise
    // SwiftUI hit testing and DragGesture without changing the user's keyboard.
    let host=NSHostingView(rootView:CanvasView(model:model,cropModifier:{true}))
    window.contentView=host;window.orderBack(nil)
    defer { window.orderOut(nil);window.contentView=nil;window.close();_ = model.command("source.remove",["scene":scene,"id":id]) }
    try await Task.sleep(for:.milliseconds(350));host.layoutSubtreeIfNeeded()
    var modifiers: NSEvent.ModifierFlags = .option
    func send(_ type:NSEvent.EventType,_ point:CGPoint) {
        let event=NSEvent.mouseEvent(with:type,location:CGPoint(x:point.x,y:360-point.y),modifierFlags:modifiers,timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
        window.sendEvent(event)
    }
    func drag(from:CGPoint,to:CGPoint) async throws {
        send(.leftMouseDown,from)
        for step in 1...8 {
            send(.leftMouseDragged,CGPoint(x:from.x+(to.x-from.x)*Double(step)/8,y:from.y+(to.y-from.y)*Double(step)/8))
            try await Task.sleep(for:.milliseconds(30))
        }
        send(.leftMouseUp,to);try await Task.sleep(for:.milliseconds(150));model.refresh()
    }
    try await drag(from:CGPoint(x:260,y:60),to:CGPoint(x:260,y:90))
    guard let item=model.selected else { fatalError("Lost crop selection") }
    precondition(abs(item.number("cropTop")-60)<=2 && item.number("cropBottom")==0,"Top handle must crop vertically: \(item)")
    precondition(abs(item.number("y")-90)<=1 && item.number("scaleY")==0.5)
    try await drag(from:CGPoint(x:260,y:240),to:CGPoint(x:260,y:215))
    precondition(abs(model.selected!.number("cropBottom")-50)<=2)
    host.rootView=CanvasView(model:model,cropModifier:{false})
    modifiers=[]
    model.framingItem=id
    try await Task.sleep(for:.milliseconds(150))
    let previous=model.selected!,oldBox=previous["boxCorners"] as! [[Double]],undoCount=model.undoCount
    try await drag(from:CGPoint(x:260,y:150),to:CGPoint(x:260,y:160))
    let framed=model.selected!
    precondition(abs(framed.number("cropTop")-(previous.number("cropTop")-20))<=2)
    precondition(framed["boxCorners"] as! [[Double]] == oldBox,"Framing must pan content, not move the box")
    precondition(model.undoCount==undoCount+1,"One framing drag must produce one undo step")
    model.selectedItem=nil
    precondition(model.framingItem==nil,"Changing selection exits framing")
    for (type, label) in [("dante_youtube_chat", "Chat width QA"),
                          ("dante_superchat", "Highlight width QA"),
                          ("dante_youtube_alert", "Likes width QA")] {
        precondition(model.command("source.add", ["scene":scene,"type":type,"name":label,
                                                 "settings":["layoutWidth":320,"layoutHeight":180,"componentScale":1.5]]))
        let sourceID=model.items.first { $0.string("name")==label }!.sceneItemID
        precondition(model.command("item.transform",["scene":scene,"id":sourceID,"x":100,"y":90]))
        model.selectedItem=sourceID
        host.rootView=CanvasView(model:model,cropModifier:{false})
        try await Task.sleep(for:.milliseconds(180));host.layoutSubtreeIfNeeded()
        let before=model.selected!
        let corners=before["boxCorners"] as! [[Double]]
        let right=CGPoint(x:(corners[1][0]+corners[2][0])/2,y:(corners[1][1]+corners[2][1])/2)
        try await drag(from:right,to:CGPoint(x:right.x+70,y:right.y))
        let after=model.selected!
        precondition(after.number("width") >= before.number("width")+60,
                     "\(type) must grow horizontally with the right handle: \(after)")
        precondition(abs(after.number("height")-before.number("height"))<=3,"\(type) height must not stretch beyond pixel rounding")
        let resizedSettings=model.properties(name:label).object("settings")
        precondition(abs(resizedSettings.number("componentScale")-1.5)<0.001,"\(type) scale must remain unchanged")
        model.selectedItem=nil
        precondition(model.command("source.remove",["scene":scene,"id":sourceID]))
    }
    print("PASS: explicit framing pans without Alt, keeps the visible box fixed, one undo and selection cleanup")
    print("PASS: actual SwiftUI top/bottom handle drag crops vertically in fixed canvas coordinates; no global input injection")
    print("PASS: scaled chat, featured comment and likes resize horizontally without changing height or scale")
}
