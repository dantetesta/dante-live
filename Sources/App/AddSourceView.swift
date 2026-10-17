import SwiftUI
import AppKit

struct AddSourceView: View {
    @ObservedObject var model: StudioModel
    @StudioDismiss private var dismiss
    @LegacyState private var type = ""
    @LegacyState private var name = ""
    @LegacyState private var settings: [String: Any] = [:]
    @LegacyState private var properties: [[String: Any]] = []
    @LegacyState private var existing = ""
    @LegacyState private var instanceRequired = false
    @LegacyState private var query = ""
    @LegacyState private var category = "Todas"
    @LegacyState private var reuse = false

    private var choices: [SourceChoice] {
        model.catalog.array("sources").filter { !$0.string("id").hasPrefix("dante_guest_") }.map(SourceChoice.init).sorted {
            $0.order == $1.order ? $0.title.localizedStandardCompare($1.title) == .orderedAscending : $0.order < $1.order
        }
    }
    private var selection: SourceChoice? { choices.first { $0.id == type } }
    private var filtered: [SourceChoice] { choices.filter { (category == "Todas" || $0.category == category) && $0.matches(query.trimmingCharacters(in: .whitespacesAndNewlines)) } }
    private var existingNames: [String] { Array(Set(model.scenes.flatMap { $0.array("items").map { $0.string("name") } } + model.scenes.map { $0.string("name") })).sorted() }
    private var reusableNames: [String] { model.reusableSourceNames }
    private var canAdd: Bool { reuse ? reusableNames.contains(existing) : selection != nil && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var sheetSize: CGSize {
        let available = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1200, height: 900)
        return CGSize(width: min(1020, available.width - 80), height: min(720, available.height - 100))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                library.frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                details.frame(width: 310).frame(maxHeight: .infinity).background(Color(nsColor: .controlBackgroundColor))
            }
            Divider()
            footer
        }
        .frame(width: sheetSize.width, height: sheetSize.height)
        .background(Color(nsColor: .windowBackgroundColor)).tint(.teal)
        .onChange(of: type) { _, new in
            let props = model.properties(type: new)
            settings = props.object("settings"); properties = props.array("properties"); instanceRequired = props.flag("requiresInstance")
            let base = selection?.title ?? "Fonte"
            var candidate = base; var suffix = 2
            while existingNames.contains(candidate) { candidate = "\(base) \(suffix)"; suffix += 1 }
            name = candidate
        }
        .task(id: (reuse ? "reuse" : type) + jsonString(settings)) {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, !reuse, !type.isEmpty, let engine = model.engine else { return }
            let result = jsonObject(copied(dante_engine_type_properties_with_settings(engine, type, jsonString(settings))))
            properties = result.array("properties"); instanceRequired = result.flag("requiresInstance")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Adicionar à cena").font(.system(size: 25, weight: .bold))
                Text("Escolha o que vai aparecer ou tocar na sua live.").foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Origem", selection: $reuse) {
                Text("Nova fonte").tag(false)
                Text("Usar existente").tag(true)
            }.pickerStyle(.segmented).labelsHidden().frame(width: 250)
        }.padding(24)
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(reuse ? "Buscar no projeto" : "Buscar câmera, imagem, áudio…", text: $query).textFieldStyle(.plain)
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).help("Limpar busca").accessibilityLabel("Limpar busca") }
                }.padding(10).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                if !reuse {
                    Picker("Categoria", selection: $category) {
                        ForEach(["Todas", "Câmera e tela", "Áudio", "Elementos", "Compatibilidade", "Outras"].filter { categoryName in categoryName == "Todas" || choices.contains(where: { $0.category == categoryName }) }, id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().frame(width: 145)
                }
            }
            ScrollView {
                if reuse { existingLibrary }
                else if filtered.isEmpty {
                    ContentUnavailableView("Nenhuma fonte encontrada", systemImage: "magnifyingglass", description: Text("Tente outro nome ou selecione Todas nas categorias."))
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        ForEach(filtered) { choice in
                            SourceChoiceCard(choice: choice, selected: type == choice.id) { type = choice.id }
                        }
                    }.padding(3)
                }
            }
            Text(reuse ? "Use a mesma fonte em mais de uma cena." : "Só aparecem fontes disponíveis neste Mac.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(20)
    }

    private var existingLibrary: some View {
        let names = reusableNames.filter { query.isEmpty || $0.localizedStandardContains(query) }
        return VStack(spacing: 8) {
            if names.isEmpty {
                ContentUnavailableView("Nenhuma fonte encontrada", systemImage: "square.on.square", description: Text("Adicione uma nova fonte ou tente outro nome."))
            }
            ForEach(names, id: \.self) { value in
                Button { existing = value } label: {
                    HStack(spacing: 12) {
                        Image(systemName: model.scenes.contains { $0.string("name") == value } ? "rectangle.stack.fill" : "square.on.square").font(.title2).foregroundStyle(.teal).frame(width: 36)
                        Text(value).font(.headline).foregroundStyle(.primary).lineLimit(2)
                        Spacer()
                        if existing == value { Image(systemName: "checkmark.circle.fill").foregroundStyle(.teal) }
                    }.padding(14).background(existing == value ? Color.teal.opacity(0.1) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).accessibilityAddTraits(existing == value ? .isSelected : [])
            }
        }.padding(3)
    }

    private var details: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if reuse {
                    SourceIllustration(symbol: "square.on.square", color: .teal)
                    Text(existing.isEmpty ? "Reutilize uma fonte" : existing).font(.title2.bold())
                    Text("A fonte será compartilhada entre as cenas. Alterações em suas propriedades também valem onde ela já é usada.").foregroundStyle(.secondary)
                    Label("Posição e tamanho podem variar em cada cena.", systemImage: "arrow.up.left.and.arrow.down.right").font(.callout)
                } else if let selection {
                    SourceIllustration(symbol: selection.symbol, color: selection.color)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(selection.category.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(selection.color)
                        Text(selection.title).font(.title2.bold())
                        Text(selection.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nome na cena").font(.headline)
                        TextField("Nome da fonte", text: $name).textFieldStyle(.roundedBorder)
                    }
                    if instanceRequired {
                        Label("Depois de adicionar, escolha o dispositivo ou conteúdo em Propriedades.", systemImage: "slider.horizontal.3").font(.callout).foregroundStyle(.secondary)
                    } else { PropertyFields(properties: properties, settings: $settings) }
                } else {
                    SourceIllustration(symbol: "square.stack.3d.up.fill", color: .teal)
                    Text("Sua cena começa aqui").font(.title2.bold())
                    Text("Cada fonte traz uma parte da live: sua câmera, sua voz, a tela ou uma arte.").foregroundStyle(.secondary)
                    Divider()
                    Label("Escolha um cartão", systemImage: "cursorarrow").font(.headline)
                    Text("Veja aqui para que ele serve e personalize antes de adicionar.").foregroundStyle(.secondary)
                }
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield").foregroundStyle(.secondary)
            Text("Câmera e microfone só são abertos ao adicionar.").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
            Button(reuse ? "Usar nesta cena" : "Adicionar à cena", action: add).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!canAdd)
        }.controlSize(.large).padding(.horizontal, 24).padding(.vertical, 16)
    }

    private func add() {
        if reuse {
            guard reusableNames.contains(existing) else { existing = ""; return }
            if model.command("source.reuse", ["scene": model.sceneName, "name": existing]) { dismiss() }
            return
        }
        let add = {
            let sourceName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if model.command("source.add", ["scene": model.sceneName, "type": type, "name": sourceName, "settings": settings]) {
                if let last = model.items.last { model.selectedItem = last.sceneItemID }
                if isCameraSource(type) { model.cameraSourceName = sourceName }
                dismiss()
            }
        }
        model.requestPermission(for: type, completion: add)
    }
}

private extension SourceChoice {
    var color: Color { category == "Áudio" ? .orange : category == "Elementos" ? .blue : category == "Compatibilidade" ? .secondary : .teal }
}

private struct SourceChoiceCard: View {
    let choice: SourceChoice
    let selected: Bool
    let action: () -> Void
    @LegacyState private var hovered = false
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Image(systemName: choice.symbol).font(.system(size: 23, weight: .medium)).foregroundStyle(choice.color)
                        .frame(width: 46, height: 40).background(choice.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                    Spacer(minLength: 0)
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.teal) }
                }
                Text(choice.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary).lineLimit(2)
                Text(choice.subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).frame(height: 146)
                .background(selected ? Color.teal.opacity(0.08) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.teal : Color.primary.opacity(hovered ? 0.25 : 0.08), lineWidth: selected ? 2 : 1))
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).onHover { hovered = $0 }
            .accessibilityLabel(choice.title).accessibilityHint(choice.subtitle).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct SourceIllustration: View {
    let symbol: String
    let color: Color
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18).fill(color.opacity(0.06))
            RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.16), lineWidth: 1).frame(width: 124, height: 78).rotationEffect(.degrees(-9)).offset(x: -9, y: 3)
            RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)).frame(width: 124, height: 78)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.3)).frame(width: 124, height: 78))
            Image(systemName: symbol).font(.system(size: 38, weight: .medium)).foregroundStyle(color)
        }.frame(height: 124).accessibilityHidden(true)
    }
}
