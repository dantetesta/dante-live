import Foundation

@main enum LivePresetsTests {
    static func main() {
        let expected = [(LiveQuality.fullHD, 30, 5000, 14000), (.fullHD, 60, 6000, 17000), (.qhd, 30, 7000, 21000), (.qhd, 60, 8000, 34000), (.ultraHD, 30, 11000, 42000), (.ultraHD, 60, 14000, 50000)]
        for (quality, fps, minimum, recommended) in expected {
            let unmeasured = LiveRecommendation(quality: quality, fps: fps, uploadMbps: nil)
            precondition(unmeasured.minimumBitrate == minimum && unmeasured.bitrate == recommended && !unmeasured.uploadKnown)
            let fast = LiveRecommendation(quality: quality, fps: fps, uploadMbps: 1000)
            precondition(fast.bitrate == recommended && fast.uploadSufficient)
            let poor = LiveRecommendation(quality: quality, fps: fps, uploadMbps: 1)
            precondition(!poor.uploadSufficient && poor.quality == quality && poor.fps == fps)
        }
        let limited = LiveRecommendation(quality: .fullHD, fps: 30, uploadMbps: 12)
        precondition(limited.bitrate == 8200 && limited.uploadSufficient)
        for invalid in [Double.nan, .infinity, -1, 0, 100_001] {
            precondition(!LiveRecommendation(quality: .qhd, fps: 30, uploadMbps: invalid).uploadKnown)
        }
        for invalid in [Double.nan, .infinity, -1, 0, 100_001] {
            precondition(ConnectionDiagnosis(uploadMbps: invalid, fps: 30, videoBitrate: 14000, audioBitrate: 128).state == .unknown)
        }
        precondition(ConnectionDiagnosis(uploadMbps: 2, fps: 30, videoBitrate: 14000, audioBitrate: 128).suggestedQuality == nil)
        let moderate = ConnectionDiagnosis(uploadMbps: 12, fps: 30, videoBitrate: 14000, audioBitrate: 128)
        precondition(moderate.suggestedQuality == .fullHD && !moderate.currentFits)
        let fast = ConnectionDiagnosis(uploadMbps: 265.405568, fps: 30, videoBitrate: 14000, audioBitrate: 128)
        precondition(fast.suggestedQuality == .qhd && fast.supports4K && fast.currentFits)
        let excessive = ConnectionDiagnosis(uploadMbps: 265, fps: 60, videoBitrate: 200000, audioBitrate: 320)
        precondition(!excessive.currentFits && excessive.suggestedFPS == 60)
        print("PASS: readable diagnosis unknown/weak/moderate/fast, QHD recommendation, custom bitrate assessment")
        let suite = "DanteLive.PresetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var config = OutputConfiguration(); config.bitrate = 8200; config.uploadMbps = 12
        config.save(defaults: defaults)
        precondition(OutputConfiguration.load(defaults: defaults).bitrate == 8200)
        defaults.set(Data("invalid".utf8), forKey: OutputConfiguration.key)
        precondition(OutputConfiguration.load(defaults: defaults).bitrate == 14000)
        print("PASS: six YouTube H264 presets, upload headroom, insufficient and unknown upload, no silent downgrade, configuration persistence")
    }
}
