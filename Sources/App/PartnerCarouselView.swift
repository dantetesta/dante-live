import AppKit
import SwiftUI

private struct PartnerBanner {
    let imageName: String
    let sponsor: String
    let url: URL
}

private final class PartnerCarouselState: ObservableObject {
    @Published var index = 0
    var paused = false
}

struct PartnerCarouselView: View {
    @StateObject private var state = PartnerCarouselState()

    private let banners = [
        PartnerBanner(imageName: "partner-dante-studio", sponsor: "Dante Studio — seja parceiro",
            url: URL(string: "https://wa.me/5519998021956?text=Ol%C3%A1%21%20Gostaria%20de%20ser%20parceiro%20no%20Dante%20Live")!),
        PartnerBanner(imageName: "partner-academy", sponsor: "Academy — Aprenda Vibe Coding ao vivo",
            url: URL(string: "https://academy.dantetesta.com.br")!),
        PartnerBanner(imageName: "partner-napoleon", sponsor: "Napoleon — Hospedagem de sites",
            url: URL(string: "https://painel.napoleon.com.br/?aff=1202")!)
    ]

    var body: some View {
        let banner = banners[state.index]
        Button { NSWorkspace.shared.open(banner.url) } label: {
            if let imageURL = Bundle.main.url(forResource: banner.imageName, withExtension: "png"),
               let image = NSImage(contentsOf: imageURL) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 400, height: 55)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text(banner.sponsor).frame(width: 400, height: 55)
            }
        }
        .buttonStyle(.plain)
        .help("Abrir \(banner.sponsor)")
        .accessibilityLabel("Publicidade: \(banner.sponsor). Abre o site do parceiro.")
        .onHover { state.paused = $0 }
        .onReceive(Timer.publish(every: 8, on: .main, in: .common).autoconnect()) { _ in
            if !state.paused { state.index = (state.index + 1) % banners.count }
        }
    }
}
