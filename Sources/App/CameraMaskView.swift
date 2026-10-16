import SwiftUI

struct CameraMaskView: View {
    @ObservedObject var model: StudioModel
    let item: [String: Any]
    @LegacyState private var undoSnapshot: String?
    private var values: [String: Any] { item.object("cameraMask") }
    private var shape: Int { Int(values.number("shape")) }
    private struct Format: Identifiable {
        let id: String
        let shape: Int
        let title: String
        let aspect: Double
        var oriented: Bool { [2,5,6].contains(shape) }
    }
    // Keep the existing shape IDs and store orientation in the existing aspect field.
    // Older projects retain their custom proportions and framing without migration.
    private let formats: [Format] = [
        .init(id:"square",shape:1,title:"Quadrado",aspect:1),
        .init(id:"circle",shape:3,title:"Redondo",aspect:1),
        .init(id:"oval-landscape",shape:2,title:"Oval horizontal",aspect:4/3.0),
        .init(id:"oval-portrait",shape:2,title:"Oval vertical",aspect:3/4.0),
        .init(id:"rectangle-landscape",shape:5,title:"Retângulo horizontal",aspect:16/9.0),
        .init(id:"rectangle-portrait",shape:5,title:"Retângulo vertical",aspect:9/16.0),
        .init(id:"rounded-landscape",shape:6,title:"Retângulo arredondado\nHorizontal",aspect:16/9.0),
        .init(id:"rounded-portrait",shape:6,title:"Retângulo arredondado\nVertical",aspect:9/16.0),
        .init(id:"rounded-square",shape:4,title:"Quadrado arredondado",aspect:1)
    ]
    private func isSelected(_ format: Format) -> Bool {
        shape == format.shape && (!format.oriented || (values.number("aspect",16/9.0) < 1) == (format.aspect < 1))
    }
    private func symbol(_ format: Format) -> some View {
        let width: CGFloat = format.aspect < 1 ? 20 : 32
        let height: CGFloat = format.aspect > 1 ? 20 : 32
        return Group {
            if [2,3].contains(format.shape) { Ellipse().strokeBorder(lineWidth:2).frame(width:width,height:height) }
            else { RoundedRectangle(cornerRadius:[4,6].contains(format.shape) ? 7 : 2).strokeBorder(lineWidth:2).frame(width:width,height:height) }
        }.frame(height:34).accessibilityHidden(true)
    }
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
                ForEach(formats) { format in
                    Button { update(["shape":format.shape,"aspect":format.aspect]) } label: {
                        VStack(spacing:6) {
                            symbol(format)
                            Text(format.title).font(.caption).lineLimit(3).multilineTextAlignment(.center)
                        }.padding(.horizontal,4).frame(maxWidth:.infinity).frame(height:94)
                            .background(isSelected(format) ? Color.teal.opacity(0.14) : Color.primary.opacity(0.04),in:RoundedRectangle(cornerRadius:8))
                            .overlay(RoundedRectangle(cornerRadius:8).strokeBorder(isSelected(format) ? Color.teal : .clear))
                    }.buttonStyle(.plain).accessibilityLabel(format.title.replacingOccurrences(of:"\n",with:" "))
                        .accessibilityAddTraits(isSelected(format) ? .isSelected : [])
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
