import SwiftUI

struct CameraMaskView: View {
    @ObservedObject var model: StudioModel
    let item: [String: Any]
    @LegacyState private var undoSnapshot: String?
    private var values: [String: Any] { item.object("cameraMask") }
    private var shape: Int { Int(values.number("shape")) }
    private let formats: [(Int,String,String)] = [(1,"Quadrado","square"),(2,"Oval","oval"),(3,"Redondo","circle"),(4,"Quadrado arredondado","square.on.square"),(5,"Retângulo","rectangle"),(6,"Retângulo arredondado","rectangle.roundedtop")]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Formato da câmera").font(.headline)
            Button {
                let snapshot = model.captureUndo()
                if model.command("source.cameraMask", ["name": item.string("name"), "settings": ["shape":0]], undo: false) {
                    _ = model.command("item.fit", ["scene":model.sceneName,"id":item.sceneItemID], undo:false)
                    if let snapshot { model.pushUndo(snapshot) }
                }
            } label: { Label("Nativo • ajustar à cena", systemImage:"arrow.up.left.and.arrow.down.right").frame(maxWidth:.infinity) }
                .buttonStyle(.bordered).tint(shape==0 ? .teal : .secondary)
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:8) {
                ForEach(formats,id:\.0) { format in
                    Button { select(format.0) } label: {
                        VStack(spacing:6) {
                            Image(systemName:format.2).font(.title2)
                            Text(format.1).font(.caption).lineLimit(2).multilineTextAlignment(.center)
                        }.frame(maxWidth:.infinity).frame(height:64)
                            .background(shape==format.0 ? Color.teal.opacity(0.14) : Color.primary.opacity(0.04),in:RoundedRectangle(cornerRadius:8))
                            .overlay(RoundedRectangle(cornerRadius:8).strokeBorder(shape==format.0 ? Color.teal : .clear))
                    }.buttonStyle(.plain).accessibilityAddTraits(shape==format.0 ? .isSelected : [])
                }
            }
            if shape != 0 {
                if [2,5,6].contains(shape) { control("Proporção",key:"aspect",range:0.5...2.4,fallback:16/9.0) }
                if [4,6].contains(shape) { control("Arredondamento",key:"roundness",range:0...1,fallback:0.2) }
                control("Zoom",key:"zoom",range:1...4,fallback:1)
                control("Horizontal",key:"panX",range:-1...1,fallback:0)
                control("Vertical",key:"panY",range:-1...1,fallback:0)
                Button("Centralizar enquadramento") { update(["zoom":1,"panX":0,"panY":0]) }.font(.caption)
                Text("O formato acompanha esta câmera em todas as cenas em que ela é reutilizada.").font(.caption2).foregroundStyle(.secondary)
            }
        }.disabled(item.flag("locked"))
            .onDisappear { if let undoSnapshot { model.pushUndo(undoSnapshot); self.undoSnapshot=nil } }
    }
    private func settings() -> [String:Any] {
        ["shape":shape,"aspect":values.number("aspect",16/9.0),"roundness":values.number("roundness",0.2),"zoom":values.number("zoom",1),"panX":values.number("panX"),"panY":values.number("panY")]
    }
    private func select(_ shape:Int) { update(["shape":shape,"aspect":shape==2 ? 0.75 : 16/9.0]) }
    private func update(_ changes:[String:Any],undo:Bool=true) {
        let candidate=settings().merging(changes,uniquingKeysWith:{_,new in new})
        _ = model.command("source.cameraMask",["name":item.string("name"),"settings":candidate],undo:undo)
    }
    private func control(_ title:String,key:String,range:ClosedRange<Double>,fallback:Double)->some View {
        VStack(spacing:5) {
            HStack { Text(title);Spacer();Text(values.number(key,fallback),format:.number.precision(.fractionLength(2))).monospacedDigit().foregroundStyle(.secondary) }.font(.caption)
            Slider(value:Binding(get:{ values.number(key,fallback) },set:{ update([key:$0],undo:false) }),in:range,onEditingChanged:{ editing in
                if editing { undoSnapshot=model.captureUndo() }
                else if let undoSnapshot {model.pushUndo(undoSnapshot);self.undoSnapshot=nil}
            }).accessibilityLabel(title)
        }
    }
}
