import SwiftUI
import AppKit

struct GuestNameSettingsView: View {
    @Binding var settings: [String: Any]
    var onEdit: (Bool) -> Void
    private let styles = ["Tarja", "Vidro", "Contorno", "Linha superior", "Cor sólida", "Tipografia"]
    private var selectedStyle: Int { min(5, max(0, Int(settings.number("style")))) }
    private func rgb(_ key: String, fallback: Int) -> Color {
        let value=Int(settings.number(key,Double(fallback)))
        return Color(red:Double((value>>16)&255)/255,green:Double((value>>8)&255)/255,blue:Double(value&255)/255)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("Nome do convidado",systemImage:"person.text.rectangle").font(.headline)
            Text("O nome acompanha o campo do convidado na página do convite. Ele pode atualizá-lo durante a live, sem interromper câmera ou áudio.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            HStack {
                Text("Nome atual").font(.caption.weight(.semibold))
                Spacer()
                Text(settings.string("guestName","Convidado")).font(.caption).lineLimit(1)
            }
            VStack(alignment:.leading,spacing:7) {
                Text("Estilo").font(.subheadline.weight(.semibold))
                LazyVGrid(columns:[GridItem(.flexible(),spacing:8),GridItem(.flexible(),spacing:8)],spacing:8) {
                    ForEach(styles.indices,id:\.self) { index in
                        Button { settings["style"]=index;onEdit(true) } label: {
                            VStack(alignment:.leading,spacing:7) {
                                Text("Marina Costa")
                                    .font(.system(size:14,weight:.bold))
                                    .foregroundStyle(index == 4 ? rgb("background",fallback:0x121923) : rgb("ink",fallback:0xFFFFFF))
                                    .lineLimit(1)
                                    .padding(.horizontal,12).frame(maxWidth:.infinity,alignment:.leading).frame(height:39)
                                    .background(index == 5 ? Color.clear : index == 4 ? rgb("accent",fallback:0x51D4DF) : rgb("background",fallback:0x121923).opacity(index == 1 ? 0.68 : 0.95),in:RoundedRectangle(cornerRadius:index == 3 ? 2 : 9))
                                    .overlay(alignment:index == 3 ? .top : .leading) {
                                        if [0,1,2,3].contains(index) { Rectangle().fill(rgb("accent",fallback:0x51D4DF)).frame(width:index == 3 ? nil : 4,height:index == 3 ? 3 : nil).padding(index == 3 ? .horizontal : .vertical,2) }
                                    }
                                    .overlay(RoundedRectangle(cornerRadius:9).stroke(index == 2 ? rgb("accent",fallback:0x51D4DF) : .clear,lineWidth:1))
                                Text(styles[index]).font(.caption.weight(.medium)).foregroundStyle(.primary)
                            }.padding(7).frame(maxWidth:.infinity,alignment:.leading)
                                .background(selectedStyle==index ? Color.teal.opacity(0.11) : Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:9))
                                .overlay(RoundedRectangle(cornerRadius:9).strokeBorder(selectedStyle==index ? .teal : .secondary.opacity(0.16),lineWidth:selectedStyle==index ? 2 : 1))
                        }.buttonStyle(.plain).accessibilityLabel(styles[index])
                    }
                }
            }
            InstalledFontPicker(title: "Fonte", selection: Binding(get:{settings.string("fontFace","Helvetica Neue")},set:{settings["fontFace"]=$0;onEdit(true)}))
            FontStyleControls(title:"nome do convidado",settings:$settings,prefix:"guestName",changed:{onEdit(true)})
            HStack {
                Text("Tamanho da letra")
                Spacer()
                Text("\(Int(settings.number("fontSize",48))) px").monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value:Binding(get:{settings.number("fontSize",48)},set:{settings["fontSize"]=Int($0);onEdit(false)}),in:18...120,step:1)
            GraphicColorPicker(title:"Destaque",settings:$settings,key:"accent",fallback:0x51D4DF) {onEdit(true)}
            GraphicColorPicker(title:"Fundo",settings:$settings,key:"background",fallback:0x121923) {onEdit(true)}
            GraphicColorPicker(title:"Texto",settings:$settings,key:"ink",fallback:0xFFFFFF) {onEdit(true)}
            Text("Mova e redimensione esta fonte diretamente no canvas. O nome se ajusta à largura disponível, sem esticar as letras. Use o olho da camada ou do participante para ocultar.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }
}
