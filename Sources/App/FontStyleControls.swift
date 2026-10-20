import SwiftUI

/// Saved beside the font family so each text role can be styled independently.
struct FontStyleControls: View {
    let title: String
    @Binding var settings: [String: Any]
    let prefix: String
    var defaultBold = false
    var changed: () -> Void

    private func choice(_ suffix: String) -> Binding<Bool> {
        let key = prefix + suffix
        return Binding(get: { settings.flag(key, suffix == "Bold" && defaultBold) }, set: { settings[key] = $0; changed() })
    }

    var body: some View {
        HStack {
            Toggle("Negrito", isOn: choice("Bold")).fontWeight(.bold)
            Toggle("Itálico", isOn: choice("Italic")).italic()
            Toggle("Sublinhado", isOn: choice("Underline")).underline()
        }
        .toggleStyle(.button)
        .accessibilityLabel("Estilo de \(title)")
    }
}
