import Foundation

/// Keeps 100% at a clear point on the control while reserving its final
/// quarter for optional voice boost. The engine applies peak protection there.
enum AudioBoostScale {
    static let maximumVolume = 3.0
    static let normalPosition = 0.75
    static var maximumDecibels: Double { 20 * log10(maximumVolume) }

    static func position(for volume: Double) -> Double {
        let value = min(max(volume.isFinite ? volume : 1, 0), maximumVolume)
        return value <= 1 ? value * normalPosition
            : normalPosition + (value - 1) * (1 - normalPosition) / (maximumVolume - 1)
    }

    static func volume(for position: Double) -> Double {
        let value = min(max(position.isFinite ? position : normalPosition, 0), 1)
        return value <= normalPosition ? value / normalPosition
            : 1 + (value - normalPosition) * (maximumVolume - 1) / (1 - normalPosition)
    }
}
