import AppKit
import SwiftUI

/// Editor-only samples: never passed to dante_chat_frame or the program texture.
/// This structural separation keeps placeholders out of streams, recordings and guest return.
struct ChatCanvasExamples: View {
    @ObservedObject var studio:StudioModel
    @ObservedObject var countdown:LiveCountdown
    var factor:Double
    static func allowed(active:Bool,preparing:Bool,countdown:Int?,session:Bool)->Bool {
        !active && !preparing && countdown == nil && !session
    }
    var body:some View {
        if Self.allowed(active:studio.active,preparing:studio.preparingLive,countdown:countdown.remaining,session:studio.youtube.chat.sessionActive) {
            ForEach(studio.items.filter{$0.flag("visible",true) && ["dante_youtube_chat","dante_superchat","dante_youtube_alert"].contains($0.string("type"))},id:\.sceneItemID) { item in
                ChatExampleItem(item:item,settings:studio.properties(name:item.string("name")).object("settings"),factor:factor)
            }
        }
    }
}

private struct ChatExampleItem:View {
    let item:[String:Any]
    let settings:[String:Any]
    let factor:Double
    @MainActor private static let cache:NSCache<NSString,NSImage> = {
        let cache=NSCache<NSString,NSImage>();cache.totalCostLimit=32*1024*1024;cache.countLimit=8;return cache
    }()
    @MainActor private var example:NSImage? {
        let key=item.string("type")+":"+jsonString(settings)
        if let image=Self.cache.object(forKey:key as NSString){return image}
        guard let image=Self.image(type:item.string("type"),settings:settings) else{return nil}
        Self.cache.setObject(image,forKey:key as NSString,cost:Int(image.size.width*image.size.height)*4);return image
    }
    var body:some View {
        let image=example
        Canvas { context,_ in
            guard let image,let points=item["boxCorners"] as? [[Double]],let box=CanvasGeometry(corners:points) else{return}
            let left=item.number("cropLeft"),top=item.number("cropTop")
            let width=item.number("width")-left-item.number("cropRight"),height=item.number("height")-top-item.number("cropBottom")
            guard width>0,height>0 else{return}
            let a=box.corners[0],b=box.corners[1],d=box.corners[3]
            context.transform=CGAffineTransform(a:(b.x-a.x)*factor/width,b:(b.y-a.y)*factor/width,c:(d.x-a.x)*factor/height,d:(d.y-a.y)*factor/height,tx:a.x*factor,ty:a.y*factor)
            context.clip(to:Path(CGRect(x:0,y:0,width:width,height:height)))
            context.draw(Image(nsImage:image),in:CGRect(x:-left,y:-top,width:item.number("width"),height:item.number("height")))
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
    @MainActor static func image(type:String,settings:[String:Any])->NSImage? {
        func message(_ id:String,_ name:String,_ text:String,paid:Bool=false)->ChatMessage {
            ChatMessage(["id":id,"authorDetails":["displayName":name],"snippet":["type":paid ? "superChatEvent":"textMessageEvent",paid ? "superChatDetails":"textMessageDetails":paid ? ["amountDisplayString":"R$ 20,00","userComment":text]:["messageText":text]]])!
        }
        let bitmap:NSBitmapImageRep?
        if type=="dante_youtube_alert" {
            bitmap=YouTubeActivityRaster.render(event:.init(id:"example",kind:.subscriber,name:"Exemplo • Marina",total:nil),total:nil,settings:settings)
        } else {
            let examples=[message("sample-1","Exemplo • Marina","Boa noite, pessoal!"),message("sample-2","Exemplo • Lucas","Como você preparou essa cena?"),message("sample-3","Exemplo • Bia","Gostei! Obrigada por compartilhar.")]
            bitmap=ChatRaster.render(messages:examples,featured:message("sample-paid","Exemplo • Rafael","Prévia de Super Chat para ajustar o estilo. Não vai ao ar.",paid:true),page:0,lower:type=="dante_superchat",settings:settings)
        }
        guard let bitmap else{return nil}
        let image=NSImage(size:NSSize(width:bitmap.pixelsWide,height:bitmap.pixelsHigh));image.addRepresentation(bitmap);return image
    }
}
