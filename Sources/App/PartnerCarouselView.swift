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
        PartnerBanner(imageName: "", sponsor: "Dante Live — seja parceiro",
            url: URL(string: "https://wa.me/5519998021956?text=Ol%C3%A1%21%20Gostaria%20de%20ser%20parceiro%20no%20Dante%20Live")!),
        PartnerBanner(imageName: "partner-academy", sponsor: "Academy — Aprenda Vibe Coding ao vivo",
            url: URL(string: "https://academy.dantetesta.com.br")!),
        PartnerBanner(imageName: "partner-napoleon", sponsor: "Napoleon — Hospedagem de sites",
            url: URL(string: "https://painel.napoleon.com.br/?aff=1202")!)
    ]

    var body: some View {
        let banner = banners[state.index]
        Button { NSWorkspace.shared.open(banner.url) } label: {
            if state.index == 0 {
                DanteLivePartnerBanner()
            } else if let imageURL = Bundle.main.url(forResource: banner.imageName, withExtension: "png"),
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

/// Render the house ad from the app's actual icon, so it cannot drift to another product's branding.
struct DanteLivePartnerBanner: View {
    var icon: NSImage? = nil

    private var appIcon: NSImage? {
        icon ?? Bundle.main.url(forResource: "DanteLive", withExtension: "icns")
            .flatMap(NSImage.init(contentsOf:))
    }

    var body: some View {
        HStack(spacing: 8) {
            if let appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
            }
            Text("DANTE\nLIVE")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineSpacing(-3)
                .fixedSize()
            Rectangle()
                .fill(Color(red: 0.20, green: 0.57, blue: 1))
                .frame(width: 1, height: 27)
                .padding(.horizontal, 2)
            HStack(spacing: 0) {
                Text("Seu anúncio ").foregroundStyle(.white)
                Text("aqui").foregroundStyle(Color(red: 0.28, green: 0.64, blue: 1))
            }
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Seja parceiro")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(Color(red: 0.08, green: 0.39, blue: 0.90), in: Capsule())
        }
        .padding(.horizontal, 10)
        .frame(width: 400, height: 55)
        .background(Color(red: 0.02, green: 0.04, blue: 0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(red: 0.12, green: 0.50, blue: 1), lineWidth: 1.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
