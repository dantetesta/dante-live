import SwiftUI
import AppKit

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    static let defaultsKey = "DanteLive.appearance"
    var id: String { rawValue }
    var title: String { switch self { case .system: "Automático"; case .light: "Claro"; case .dark: "Escuro" } }
    var symbol: String { switch self { case .system: "circle.lefthalf.filled"; case .light: "sun.max.fill"; case .dark: "moon.fill" } }
    @MainActor func apply() { NSApp.appearance = self == .system ? nil : NSAppearance(named: self == .dark ? .darkAqua : .aqua) }
    @MainActor static func restore() { (AppAppearance(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .system).apply() }
    @MainActor static func select(_ value: AppAppearance) { UserDefaults.standard.set(value.rawValue, forKey: defaultsKey); value.apply() }
}

struct PreferencesView: View {
    @AppStorage(AppAppearance.defaultsKey) private var appearance = AppAppearance.system.rawValue
    @AppStorage(AgentSocket.enabledKey) private var localMCPEnabled = false
    let agent: AgentSocket
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Preferências").font(.system(size: 26, weight: .bold))
                Text("Deixe o Dante Live do seu jeito.").foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("Aparência").font(.headline)
                HStack(spacing: 12) {
                    ForEach(AppAppearance.allCases) { value in
                        Button { appearance = value.rawValue } label: {
                            VStack(spacing: 12) {
                                Image(systemName: value.symbol).font(.system(size: 28)).foregroundStyle(.teal)
                                Text(value.title).font(.headline)
                                Image(systemName: appearance == value.rawValue ? "checkmark.circle.fill" : "circle").foregroundStyle(appearance == value.rawValue ? .teal : .secondary)
                            }.frame(maxWidth: .infinity).padding(.vertical, 22)
                                .background(appearance == value.rawValue ? Color.teal.opacity(0.08) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(appearance == value.rawValue ? Color.teal : Color.primary.opacity(0.1), lineWidth: appearance == value.rawValue ? 2 : 1))
                        }.buttonStyle(.plain).accessibilityLabel(value.title).accessibilityAddTraits(appearance == value.rawValue ? .isSelected : [])
                    }
                }
                Text("Automático acompanha o modo claro ou escuro do macOS, inclusive quando ele muda ao longo do dia.").font(.callout).foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Permitir edição local por IA (MCP)", isOn: $localMCPEnabled).font(.headline)
                Text("Com o Dante Live aberto, uma IA configurada neste Mac pode ler e editar cenas e elementos. A edição pausa durante a transmissão; iniciar uma live, acessar convidados e ler credenciais não são ferramentas MCP.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Label(localMCPEnabled && agent.running ? "Conexão local ativa" : "Conexão local desativada",
                          systemImage: localMCPEnabled && agent.running ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(localMCPEnabled && agent.running ? .green : .secondary)
                    Spacer()
                    Button("Copiar configuração MCP") { copyMCPConfiguration() }.disabled(!agent.running)
                }
                if let problem = agent.problem { Text(problem).font(.caption).foregroundStyle(.orange) }
            }
            Divider()
            Label("Sua preferência é salva automaticamente neste Mac.", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
        }.padding(28).frame(width: 510).background(Color(nsColor: .windowBackgroundColor))
            .onChange(of: appearance) { _, _ in AppAppearance.restore() }
            .onChange(of: localMCPEnabled) { _, _ in agent.applyPreference() }
    }

    private func copyMCPConfiguration() {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/DanteLiveMCP").path
        let json = jsonString(["mcpServers": ["dante-live": ["command": helper]]])
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
    }
}
