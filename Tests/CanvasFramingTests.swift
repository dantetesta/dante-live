import AppKit
import SwiftUI
var appVersion: String { "framing-qa" }
@main enum FramingQA {
 @MainActor static func main() async throws {
  NSApplication.shared.setActivationPolicy(.accessory)
  let dir=URL(fileURLWithPath:CommandLine.arguments[2]);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
  let fixture=dir.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:fixture,withIntermediateDirectories:true)
  defer { try? FileManager.default.removeItem(at:fixture) }
  let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:640,pixelsHigh:360,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
  let pixels=bitmap.bitmapData!
  for y in 0..<360 { for x in 0..<640 {
   let i=y*bitmap.bytesPerRow+x*4
   let color:[UInt8] = x<160 ? [255,0,0] : x>480 ? [0,0,255] : y<100 ? [255,255,0] : [0,255,0]
   pixels[i]=color[0];pixels[i+1]=color[1];pixels[i+2]=color[2];pixels[i+3]=255
  } }

  let png=fixture.appendingPathComponent("pattern.png");try bitmap.representation(using:.png,properties:[:])!.write(to:png);try bitmap.representation(using:.png,properties:[:])!.write(to:dir.appendingPathComponent("pattern.png"))
  let model=StudioModel(projectDirectory:fixture)
  model.engine=dante_engine_create_with_config(CommandLine.arguments[1],640,360,30,fixture.path)!;model.refresh()
  precondition(model.command("source.add",["scene":model.sceneName,"type":"image_source","name":"Framing test pattern","settings":["file":png.path]]));model.refresh()
  let id=model.items.first!.sceneItemID
  precondition(model.command("item.transform",["scene":model.sceneName,"id":id,"x":220,"y":110,"scaleX":0.6,"scaleY":0.6,"cropLeft":160,"cropRight":160,"cropTop":80,"cropBottom":80]))
  model.selectedItem=id
  let window=NSWindow(contentRect:NSRect(x:100,y:100,width:640,height:360),styleMask:[.titled],backing:.buffered,defer:false);window.isReleasedWhenClosed=false;window.title="Dante Live — isolated framing QA"
  let host=NSHostingView(rootView:CanvasView(model:model,cropModifier:{false}));window.contentView=host;window.orderFront(nil)
  func snapshot(_ name:String) async throws -> NSBitmapImageRep {
   try await Task.sleep(for:.milliseconds(700));host.layoutSubtreeIfNeeded()
   guard let cg=CGWindowListCreateImage(.null,.optionIncludingWindow,CGWindowID(window.windowNumber),[.boundsIgnoreFraming,.bestResolution]) else { fatalError("Own-window capture unavailable") }
   let rep=NSBitmapImageRep(cgImage:cg);try rep.representation(using:.png,properties:[:])!.write(to:dir.appendingPathComponent(name+".png"));return rep
  }
  func color(_ rep:NSBitmapImageRep,_ x:Double,_ y:Double)->NSColor {
   let scale=Double(rep.pixelsWide)/640,caption=Double(rep.pixelsHigh)-360*scale
   return rep.colorAt(x:Int(x*scale),y:Int(caption+y*scale))!.usingColorSpace(.deviceRGB)!
  }
  let off=try await snapshot("framing-off")
  let alt=NSEvent.keyEvent(with:.flagsChanged,location:.zero,modifierFlags:.option,timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:58)!
  NSApplication.shared.sendEvent(alt)
  let held=try await snapshot("framing-alt")
  let orange=color(held,220,110)
  precondition(orange.redComponent>0.8 && orange.greenComponent<0.8 && orange.blueComponent<0.4,"Alt alone must immediately color handles orange")
  let panel=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:100,height:100),styleMask:[.titled],backing:.buffered,defer:false)
  panel.isReleasedWhenClosed=false
  let released=NSEvent.keyEvent(with:.flagsChanged,location:.zero,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:panel.windowNumber,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:58)!
  NSApplication.shared.sendEvent(released)
  let releaseImage=try await snapshot("framing-alt-released")
  precondition(color(releaseImage,150,180).redComponent<0.02,"Alt released in another panel must clear the guide")
  panel.close()
  model.framingItem=id;let on=try await snapshot("framing-on")
  let escape=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53)!
  NSApplication.shared.sendEvent(escape)
  precondition(model.framingItem==nil,"Escape must end framing")
  let ended=try await snapshot("framing-ended")
  precondition(color(off,150,180).redComponent<0.02 && color(ended,150,180).redComponent<0.02)
  let ghost=color(on,150,180)
  precondition(ghost.redComponent>0.15 && ghost.redComponent<0.5 && ghost.redComponent>ghost.greenComponent*2,"Cropped-away red pixels must appear translucent only while framing")
  precondition(abs(color(on,300,180).greenComponent-color(off,300,180).greenComponent)<0.02,"Guide must not darken the visible crop")
  print("PASS Alt event immediately colors handles; translucent native source pixels match crop; visible content unchanged; ending removes guide")
  func detach(_ v:NSView) { (v as? EngineDisplayOwner)?.detach();for child in v.subviews { detach(child) } };detach(host);window.orderOut(nil);window.contentView=nil;window.close();try await Task.sleep(for:.milliseconds(100));model.shutdown()
  print("PASS own-window framing screenshots, guide lifecycle, no capture devices or public outputs")
 }
}
