import SwiftUI

/// A single searchable font chooser for every source that stores a font family.
/// The list is read when opened so fonts installed while Dante Live is running appear.
struct InstalledFontPicker: View {
    let title: String
    @Binding var selection: String
    @LegacyState private var isOpen = false
    @LegacyState private var search = ""
    @LegacyState private var families: [String] = []

    private var matches: [String] {
        search.isEmpty ? families : families.filter { $0.localizedStandardContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                Button {
                    families = ChatFontCatalog.availableFamilies()
                    search = ""
                    isOpen = true
                } label: {
                    HStack {
                        Text(selection).lineLimit(1)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.up.chevron.down").font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.secondary.opacity(0.25)))
                .accessibilityLabel("\(title): \(selection). Escolher fonte instalada")
                .popover(isPresented: $isOpen, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Fontes deste Mac").font(.headline)
                        TextField("Buscar fonte", text: $search).textFieldStyle(.roundedBorder)
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(matches, id: \.self) { family in
                                    Button {
                                        selection = family
                                        isOpen = false
                                    } label: {
                                        HStack {
                                            Text(family).font(.custom(family, size: 15)).lineLimit(1)
                                            Spacer()
                                            if family == selection { Image(systemName: "checkmark").foregroundStyle(.teal) }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 8).padding(.vertical, 5)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(height: 300)
                        if matches.isEmpty { Text("Nenhuma fonte encontrada.").font(.caption).foregroundStyle(.secondary) }
                        Text("A fonte é salva no projeto. Em outro Mac, instale-a para manter a aparência.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14).frame(width: 340)
                }
            }
            if !ChatFontCatalog.isInstalled(selection) {
                Label("Fonte indisponível neste Mac; o texto usa a fonte do sistema.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }
}
