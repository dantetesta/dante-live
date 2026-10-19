import AppKit
import SwiftUI

private enum CreditsSupport: String {
    case pix = "Pix"
    case paypal = "PayPal"

    var value: String {
        switch self {
        case .pix: "44b40705-0339-4583-bb58-bab854c3eea3"
        case .paypal: "dante.testa@gmail.com"
        }
    }

    var label: String { self == .pix ? "Chave Pix aleatória" : "E-mail da conta PayPal" }
    var symbol: String { self == .pix ? "square.on.square" : "envelope" }
}

private final class CreditsViewState: ObservableObject {
    @Published var revealed: CreditsSupport?
    @Published var copied: CreditsSupport?
}

struct CreditsView: View {
    @StateObject private var state = CreditsViewState()

    private let authorURL = URL(string: "https://www.dantetesta.com.br")!
    private let communityURL = URL(string: "https://chat.whatsapp.com/Ih2k0jUf7xqJX31yo9Dzbs?mode=gi_t")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                HStack(alignment: .center, spacing: 20) {
                    if let avatar = Bundle.main.url(forResource: "credits-author", withExtension: "png")
                        .flatMap({ NSImage(contentsOf: $0) }) {
                        Image(nsImage: avatar)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 94, height: 94)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(.primary.opacity(0.12), lineWidth: 1))
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Idealização e desenvolvimento")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("Dante Testa")
                            .font(.system(size: 24, weight: .bold))
                        Text("Um estúdio de lives feito para colocar suas ideias no ar.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))

                VStack(spacing: 10) {
                    externalCard("Conheça o autor", detail: "www.dantetesta.com.br", symbol: "globe", url: authorURL)
                    externalCard("Comunidade no WhatsApp", detail: "Compartilhe ideias, sugira melhorias e relate bugs.", symbol: "bubble.left.and.bubble.right", url: communityURL)
                }

                VStack(alignment: .leading, spacing: 15) {
                    Label("Apoie o projeto", systemImage: "heart")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Se quiser contribuir com o Dante Live, faça uma doação voluntária por Pix ou PayPal.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        supportButton(.pix)
                        supportButton(.paypal)
                    }
                    if let revealed = state.revealed {
                        let didCopy = state.copied == revealed
                        VStack(alignment: .leading, spacing: 9) {
                            Text(revealed.label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            HStack(spacing: 10) {
                                Text(revealed.value)
                                    .font(.system(.callout, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityLabel("\(revealed.label): \(revealed.value)")
                                Button {
                                    NSPasteboard.general.clearContents()
                                    state.copied = NSPasteboard.general.setString(revealed.value, forType: .string) ? revealed : nil
                                } label: {
                                    Label(didCopy ? "Copiado" : "Copiar", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                                }
                                .accessibilityLabel("Copiar \(revealed.label)")
                            }
                        }
                        .padding(14)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityElement(children: .contain)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.08)))
                HStack {
                    Text("Obrigado por criar junto com a gente.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Fechar") { NSApp.keyWindow?.close() }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(28)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 16) {
            if let icon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Créditos").font(.system(size: 30, weight: .bold))
                Text("Dante Live · Versão \(appVersion)").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func externalCard(_ title: String, detail: String, symbol: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 22)).frame(width: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.1)))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), abre no navegador")
    }

    private func supportButton(_ method: CreditsSupport) -> some View {
        Button {
            state.revealed = state.revealed == method ? nil : method
            state.copied = nil
        } label: {
            Label(method.rawValue, systemImage: method.symbol)
                .frame(minWidth: 88)
        }
        .accessibilityLabel("\(state.revealed == method ? "Ocultar" : "Mostrar") dados de \(method.rawValue)")
    }
}
