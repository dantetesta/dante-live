import AppKit
import Vision

@main struct SceneGraphicsTests {
    static func rejects(_ body: () throws -> Void) { do { try body(); fatalError("Expected rejection") } catch {} }
    static func main() throws {
        let out = URL(fileURLWithPath: "build/scene-graphics-qa")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let pix: [String: Any] = ["qrType": "pix", "pixKeyType": "random", "pixKey": "123e4567-e12b-12d1-a456-426655440000", "pixName": "Fulano de Tal", "pixCity": "BRASILIA"]
        let official = "00020126580014br.gov.bcb.pix0136123e4567-e12b-12d1-a456-4266554400005204000053039865802BR5913Fulano de Tal6008BRASILIA62070503***63041D3D"
        precondition(try! QRContent.payload(pix) == official)
        var fixed = pix; fixed["pixAmount"] = "25,5"
        precondition(try! QRContent.payload(fixed).contains("540525.50"))
        fixed["pixAmount"] = "0"; rejects { _ = try QRContent.payload(fixed) }
        fixed["pixAmount"] = "25,123"; rejects { _ = try QRContent.payload(fixed) }
        precondition(try! QRContent.pixKey("00038166000105", kind: "cnpj") == "00038166000105")
        precondition(try! QRContent.pixKey("12ABC34501DE35", kind: "cnpj") == "12ABC34501DE35")
        precondition(try! QRContent.pixKey("529.982.247-25", kind: "cpf") == "52998224725")
        rejects { _ = try QRContent.pixKey("529.982.247-26", kind: "cpf") }
        rejects { _ = try QRContent.pixKey("11111111111", kind: "cpf") }
        rejects { _ = try QRContent.pixKey("not-a-key", kind: "random") }
        rejects { _ = try QRContent.pixKey("user@", kind: "email") }
        rejects { _ = try QRContent.payload(["qrType": "url", "qrValue": "javascript:alert(1)"]) }
        rejects { _ = try QRContent.payload(["qrType": "url", "qrValue": "https://user:secret@example.org"]) }
        rejects { _ = try QRContent.payload(["qrType": "text", "qrValue": String(repeating: "a", count: 1001)]) }
        print("PASS: official BCB static Pix vector and CRC; optional exact decimal amount, CPF/CNPJ numeric and alphanumeric, invalid keys and URLs rejected")
        let logo = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 256, bitsPerPixel: 32)!
        for i in stride(from: 0, to: 64*64*4, by: 4) { logo.bitmapData![i] = 40; logo.bitmapData![i+1] = 90; logo.bitmapData![i+2] = 120; logo.bitmapData![i+3] = 255 }
        let logoData = logo.representation(using: .png, properties: [:])!
        for kind in ["url", "text", "pix"] { for style in ["square", "round", "dots"] { for withLogo in [false, true] {
            var s = kind == "pix" ? pix : ["qrType": kind, "qrValue": kind == "url" ? "https://example.org/cupom" : "Olá, live! Café e ideias 💛"]
            s["qrStyle"] = style
            if withLogo { s["qrLogo"] = logoData.base64EncodedString() }
            let art = try QRArtwork.generate(s)
            try art.png.write(to: out.appendingPathComponent("qr-\(kind)-\(style)-\(withLogo ? "logo" : "plain").png"))
            if kind == "url" && style == "square" && !withLogo {
                s["imagePNG"] = art.png.base64EncodedString();s["qrPayload"] = art.payload
                try JSONSerialization.data(withJSONObject: s).write(to: out.appendingPathComponent("qr-settings.json"))
            }
        } } }
        rejects { _ = try QRArtwork.generate(["qrType": "url", "qrValue": "https://example.org", "qrInk": 0xEEEEEE, "qrBackground": 0xFFFFFF]) }
        print("PASS: 18 native QR readbacks: links, Unicode text and Pix × three styles × with/without logo; low contrast blocked")
    }
}
