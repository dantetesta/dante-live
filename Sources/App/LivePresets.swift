import Foundation

enum LiveQuality: String, CaseIterable, Identifiable, Codable {
    case fullHD, qhd, ultraHD
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fullHD: return "1080p • Full HD"
        case .qhd: return "2K • 1440p QHD"
        case .ultraHD: return "4K • 2160p UHD"
        }
    }
    var width: Int { switch self { case .fullHD: 1920; case .qhd: 2560; case .ultraHD: 3840 } }
    var height: Int { switch self { case .fullHD: 1080; case .qhd: 1440; case .ultraHD: 2160 } }
    func minimumKbps(fps: Int) -> Int {
        switch self {
        case .fullHD: return fps == 60 ? 6000 : 5000
        case .qhd: return fps == 60 ? 8000 : 7000
        case .ultraHD: return fps == 60 ? 14000 : 11000
        }
    }
    func recommendedKbps(fps: Int) -> Int {
        switch self {
        case .fullHD: return fps == 60 ? 17000 : 14000
        case .qhd: return fps == 60 ? 34000 : 21000
        case .ultraHD: return fps == 60 ? 50000 : 42000
        }
    }
}

struct LiveRecommendation {
    let quality: LiveQuality
    let fps: Int
    let bitrate: Int
    let minimumBitrate: Int
    let recommendedBitrate: Int
    let uploadKnown: Bool
    let uploadSufficient: Bool
    let audioBitrate = 128
    /// Dante reserves 30% of observed upload. This is our policy, not a
    /// guarantee or a YouTube requirement. No resolution/FPS downgrade occurs.
    static let usableUploadFraction = 0.70

    init(quality: LiveQuality, fps: Int, uploadMbps: Double?) {
        self.quality = quality
        self.fps = fps == 60 ? 60 : 30
        minimumBitrate = quality.minimumKbps(fps: self.fps)
        recommendedBitrate = quality.recommendedKbps(fps: self.fps)
        if let uploadMbps, uploadMbps.isFinite, uploadMbps > 0, uploadMbps <= 100_000 {
            uploadKnown = true
            // Reserve audio within the payload budget; the remaining 30%
            // accommodates protocol overhead and variable available capacity.
            let available = max(0, Int(floor(uploadMbps * 1000 * Self.usableUploadFraction)) - 128)
            uploadSufficient = available >= minimumBitrate
            bitrate = min(recommendedBitrate, max(0, available / 100 * 100))
        } else {
            uploadKnown = false
            uploadSufficient = true // Proposal only; not a measured approval.
            bitrate = recommendedBitrate
        }
    }
    var minimumUploadMbps: Double { Double(minimumBitrate + audioBitrate) / 1000 / Self.usableUploadFraction }
    var recommendedUploadMbps: Double { Double(recommendedBitrate + audioBitrate) / 1000 / Self.usableUploadFraction }
    var explanation: String {
        if !uploadKnown { return "Upload ainda não medido. Proposta baseada na recomendação do YouTube; confirme sua conexão antes da live." }
        if !uploadSufficient { return "O upload informado não sustenta este preset com a margem de segurança. A resolução e o FPS não serão reduzidos automaticamente." }
        if bitrate < recommendedBitrate { return "Bitrate ajustado ao upload, dentro da faixa do YouTube. Pode haver mais compressão que no bitrate recomendado; teste uma cena com movimento." }
        return "A proposta cabe no upload informado, reservando 30% da capacidade. Isso não garante estabilidade nem mede o caminho até o YouTube."
    }
}

struct OutputConfiguration: Codable {
    var bitrate = 14000
    var audioBitrate = 128
    var encoder = ""
    var uploadMbps: Double?
    var uploadMeasuredAt: Date?
    static let key = "DanteLive.outputConfiguration.v1"

    static func load(defaults: UserDefaults = .standard) -> OutputConfiguration {
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode(Self.self, from: data),
              (100...200000).contains(value.bitrate),
              [128,160,192,256,320].contains(value.audioBitrate),
              value.encoder.count < 512,
              value.uploadMbps == nil || (value.uploadMbps!.isFinite && value.uploadMbps! > 0 && value.uploadMbps! <= 100_000)
        else { return Self() }
        return value
    }
    func save(defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

/// Explains upload capacity, not latency, network stability or Mac performance.
/// Suggestions stop at QHD; 4K remains an explicit user choice.
struct ConnectionDiagnosis {
    enum State { case unknown, insufficient, limited, comfortable }
    let state: State
    let uploadMbps: Double?
    let suggestedQuality: LiveQuality?
    let suggestedFPS: Int
    let currentFits: Bool
    let supports4K: Bool
    let title: String
    let summary: String

    init(uploadMbps: Double, fps: Int, videoBitrate: Int, audioBitrate: Int) {
        let requestedFPS = fps == 60 ? 60 : 30
        self.suggestedFPS = requestedFPS
        guard uploadMbps.isFinite, uploadMbps > 0, uploadMbps <= 100_000 else {
            self.uploadMbps = nil; state = .unknown; suggestedQuality = nil; currentFits = false; supports4K = false
            title = "Vamos conferir sua internet?"
            summary = "Meça a velocidade de envio para descobrir qual qualidade de live combina com sua conexão."
            return
        }
        self.uploadMbps = uploadMbps
        let budget = uploadMbps * 1000 * LiveRecommendation.usableUploadFraction
        currentFits = budget >= Double(videoBitrate + audioBitrate)
        supports4K = budget >= Double(LiveQuality.ultraHD.recommendedKbps(fps: requestedFPS) + 128)
        if budget >= Double(LiveQuality.qhd.recommendedKbps(fps: requestedFPS) + 128) {
            suggestedQuality = .qhd; state = currentFits ? .comfortable : .limited
            title = currentFits ? "Sua internet tem folga para esta live" : "Sua configuração pede mais internet do que há disponível"
            summary = currentFits ? "A velocidade de envio é suficiente para uma imagem bem nítida em 2K. Você pode usar a sugestão abaixo ou manter sua qualidade atual." : "Reduza a qualidade ou a quantidade de dados enviada. O preset sugerido abaixo cabe na velocidade informada."
        } else if budget >= Double(LiveQuality.fullHD.minimumKbps(fps: requestedFPS) + 128) {
            suggestedQuality = .fullHD
            let full = budget >= Double(LiveQuality.fullHD.recommendedKbps(fps: requestedFPS) + 128)
            state = currentFits && full ? .comfortable : .limited
            title = currentFits ? (full ? "Sua internet atende bem a esta live" : "Dá para fazer a live, com qualidade ajustada") : "Sua qualidade atual está pesada para esta conexão"
            summary = full ? "Full HD é uma boa escolha para câmera, apresentações e compartilhamento de tela." : "Use Full HD com a quantidade de dados ajustada à sua internet. Movimentos rápidos podem perder um pouco de definição."
        } else {
            suggestedQuality = nil; state = .insufficient
            title = "A conexão está fraca para os presets disponíveis"
            summary = "Não recomendamos iniciar uma live em Full HD com essa velocidade. Pause outros envios, tente uma conexão por cabo e meça novamente."
        }
    }
    var suggestionLabel: String {
        guard let suggestedQuality else { return "" }
        return "\(suggestedQuality == .qhd ? "2K · 1440p" : "Full HD · 1080p") · \(suggestedFPS) FPS"
    }
    var suggestionReason: String {
        suggestedQuality == .qhd ? "Mais nitidez para textos, câmera e apresentações." : "Uma escolha prática para câmera, tela e apresentações."
    }
}
