import SwiftUI
import AppKit

struct YouTubeActivitySettings: View {
    @Binding var settings:[String:Any]
    @ObservedObject var activity:YouTubeActivity
    var changed:()->Void
    private func enabled(_ key:String)->Binding<Bool>{Binding(get:{settings.flag(key,true)},set:{settings[key]=$0;changed()})}
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Label("Likes e inscrições",systemImage:"hand.thumbsup.fill").font(.headline)
            Toggle("Mostrar contador de likes",isOn:enabled("showLikes"))
            Toggle("Avisar novos inscritos públicos",isOn:enabled("showSubscribers"))
            Text(activity.status).font(.caption).foregroundStyle(.secondary)
            GraphicColorPicker(title:"Destaque",settings:$settings,key:"accent",fallback:0x57CDDF){changed()}
            GraphicColorPicker(title:"Fundo",settings:$settings,key:"background",fallback:0x14212C){changed()}
            GraphicColorPicker(title:"Texto",settings:$settings,key:"ink",fallback:0xFFFFFF){changed()}
            Text("Arraste e redimensione este componente no canvas. Novos inscritos aparecem um por vez, durante 5 segundos; a mesma pessoa não se repete nesta live.").font(.caption).foregroundStyle(.secondary)
            Text("Likes são totais consultados a cada 15 segundos; podem chegar agrupados e não revelam nomes. Inscritos públicos são consultados a cada 30 segundos. O YouTube pode atrasar ou limitar a lista.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

@MainActor enum YouTubeActivityRaster {
    static func render(event:YouTubeActivityEvent?,total:UInt64?,settings:[String:Any])->NSBitmapImageRep? {
        guard event != nil || total != nil else{return nil}
        let width=Int(min(1920,max(240,settings.number("layoutWidth",620)))),height=Int(min(2160,max(140,settings.number("layoutHeight",180))))
        guard let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bitmapFormat:[],bytesPerRow:width*4,bitsPerPixel:32),let context=NSGraphicsContext(bitmapImageRep:bitmap) else{return nil}
        NSGraphicsContext.saveGraphicsState();defer{NSGraphicsContext.restoreGraphicsState()};NSGraphicsContext.current=context
        let cg=context.cgContext;cg.clear(CGRect(x:0,y:0,width:width,height:height));cg.translateBy(x:0,y:CGFloat(height));cg.scaleBy(x:1,y:-1)
        NSGraphicsContext.current=NSGraphicsContext(cgContext:cg,flipped:true)
        let accent=chatColor(UInt32(min(0xFFFFFF,max(0,settings.number("accent",0x57CDDF)))))
        let background=chatColor(UInt32(min(0xFFFFFF,max(0,settings.number("background",0x14212C)))))
        let ink=chatColor(UInt32(min(0xFFFFFF,max(0,settings.number("ink",0xFFFFFF)))))
        let rect=CGRect(x:4,y:4,width:width-8,height:height-8),path=NSBezierPath(roundedRect:rect,xRadius:24,yRadius:24)
        background.withAlphaComponent(0.96).setFill();path.fill();accent.withAlphaComponent(0.45).setStroke();path.lineWidth=1.5;path.stroke()
        let subscribed=event?.kind == .subscriber
        let iconRect=CGRect(x:24,y:CGFloat(height)/2-40,width:80,height:80)
        accent.withAlphaComponent(0.18).setFill();NSBezierPath(ovalIn:iconRect).fill()
        if let icon=NSImage(systemSymbolName:subscribed ? "person.badge.plus.fill":"hand.thumbsup.fill",accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:42,weight:.semibold)) {
            let image=icon.copy() as! NSImage;image.isTemplate=false
            image.lockFocus();accent.set();NSRect(origin:.zero,size:image.size).fill(using:.sourceAtop);image.unlockFocus()
            image.draw(in:iconRect.insetBy(dx:18,dy:18),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        }
        let x:CGFloat=124,available=CGFloat(width)-x-24
        let label=subscribed ? "NOVO INSCRITO PÚBLICO" : "LIKES NA LIVE"
        let value=subscribed ? (event?.name ?? "") : (total ?? event?.total ?? 0).formatted(.number.locale(Locale(identifier:"pt_BR")))
        func text(_ value:String,y:CGFloat,size:CGFloat,color:NSColor,bold:Bool) {
            let paragraph=NSMutableParagraphStyle();paragraph.lineBreakMode = .byTruncatingTail
            (value as NSString).draw(in:CGRect(x:x,y:y,width:available,height:size*1.4),withAttributes:[.font:NSFont.systemFont(ofSize:size,weight:bold ? .bold:.regular),.foregroundColor:color,.paragraphStyle:paragraph])
        }
        text(label,y:CGFloat(height)/2-48,size:14,color:accent,bold:true)
        text(value,y:CGFloat(height)/2-22,size:subscribed ? 30:42,color:ink,bold:true)
        text(subscribed ? "Boas-vindas ao canal!":"Obrigado pelo apoio!",y:CGFloat(height)/2+33,size:16,color:ink.withAlphaComponent(0.8),bold:false)
        return bitmap
    }
}
