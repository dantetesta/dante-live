import AVFoundation
import Foundation

struct CameraDeviceChoice: Identifiable {
    let id: String
    let name: String
}

enum CameraDevices {
    /// Discovery only: no capture session/input, permission request or device lock.
    static func discover() -> [CameraDeviceChoice] {
        let types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera]
        var seen = Set<String>()
        return [AVMediaType.video, .muxed].flatMap { media in
            AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: media, position: .unspecified).devices
        }.filter { seen.insert($0.uniqueID).inserted }
            .map { CameraDeviceChoice(id: $0.uniqueID, name: $0.localizedName) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static var authorizationMessage: String? {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return nil
        case .notDetermined: return "A permissão de câmera será solicitada quando você clicar em Aplicar e visualizar."
        case .denied: return "Acesso à câmera negado. Autorize o Dante Live em Ajustes do Sistema › Privacidade e Segurança › Câmera."
        case .restricted: return "O acesso à câmera está restrito pelas configurações deste Mac."
        @unknown default: return "Não foi possível determinar a permissão da câmera."
        }
    }

    static func isCameraSource(_ type: String) -> Bool {
        type == "macos-avcapture" || type == "macos-avcapture-fast" || type == "av_capture_input"
    }
}
