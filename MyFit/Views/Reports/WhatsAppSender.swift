import SwiftUI
import UIKit

/// Intenta abrir WhatsApp con el texto. Si falla (no está instalado, o el
/// sistema no puede completar la apertura), llama a `fallback` para que quien
/// invoque muestre la hoja de compartir del sistema como alternativa.
@MainActor
enum WhatsAppSender {
    static func send(_ text: String, fallback: @escaping () -> Void) {
        guard let url = WhatsAppLink.url(for: text) else {
            fallback()
            return
        }
        UIApplication.shared.open(url, options: [:]) { success in
            if !success { fallback() }
        }
    }
}

/// Hoja de compartir estándar de iOS: fallback cuando WhatsApp no responde,
/// y también sirve para elegir otra app o copiar el texto.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
