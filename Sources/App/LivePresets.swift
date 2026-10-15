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
