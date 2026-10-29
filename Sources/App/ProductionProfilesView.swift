import SwiftUI

struct ProductionProfilesView: View {
    @ObservedObject var model: StudioModel
    @LegacyState private var profileToRemove: ProductionProfile?
    @LegacyState private var confirmingRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Seus estúdios, prontos para abrir").font(.title2.bold())
                    Text("Cada perfil guarda suas cenas, fontes, posições e estilos. O último usado abre quando você iniciar o Dante Live.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Novo perfil…", systemImage: "plus") {
                    model.askName(title: "Novo perfil de produção") { model.createProfile(name: $0) }
                }.buttonStyle(.borderedProminent).disabled(!model.canSwitchProfile)
            }
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(model.profiles.sorted(by: { $0.lastOpened > $1.lastOpened })) { profile in
                        HStack(spacing: 14) {
                            Image(systemName: profile.id == model.selectedProfileID ? "square.stack.3d.up.fill" : "square.stack.3d.up")
                                .font(.title2).foregroundStyle(profile.id == model.selectedProfileID ? .teal : .secondary)
                                .frame(width: 34)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(profile.name).font(.headline).lineLimit(1).help(profile.name)
                                Text(profile.id == model.selectedProfileID ? "Aberto agora" : "Usado em \(profile.lastOpened.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Renomear") {
                                model.askName(title: "Renomear perfil", initial: profile.name) { model.renameProfile(profile.id, to: $0) }
                            }
                            if profile.id != model.selectedProfileID {
                                Button("Carregar") { model.selectProfile(profile.id) }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(!model.canSwitchProfile)
                            } else {
                                Label("Ativo", systemImage: "checkmark.circle.fill")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.green)
                            }
                            Button("Remover", systemImage: "trash", role: .destructive) {
                                profileToRemove = profile
                                confirmingRemoval = true
                            }
                            .disabled(!model.canSwitchProfile || profile.id == "default" || profile.id == model.selectedProfileID)
                            .help(profile.id == "default" ? "O perfil inicial é preservado." : profile.id == model.selectedProfileID ? "Carregue outro perfil antes de remover este." : "Remover este perfil e enviar seu projeto para a Lixeira.")
                            .accessibilityLabel("Remover perfil \(profile.name)")
                        }
                        .padding(14)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            Divider()
            HStack {
                Label("Configurações de transmissão e contas continuam globais.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Fechar") { model.showingProfiles = false }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 720, height: 480)
        .alert("Remover perfil?", isPresented: $confirmingRemoval, presenting: profileToRemove) { profile in
            Button("Cancelar", role: .cancel) {}
            Button("Remover", role: .destructive) { model.removeProfile(profile.id) }
        } message: { profile in
            Text("O perfil “\(profile.name)” será removido da lista e seu projeto irá para a Lixeira. Arquivos de mídia originais, outros perfis, contas e configurações de transmissão serão preservados.")
        }
    }
}
