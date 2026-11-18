import Foundation
import SwiftUI
import Testing
@testable import MyApp

@Suite("Ícone do app")
struct AppIconTests {
    @Test("A arte do ícone gera uma imagem quadrada de 1024 pixels")
    func rendersAt1024() throws {
        let renderer = ImageRenderer(content: AppIconView(size: 1024))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        #expect(image.width == 1024)
        #expect(image.height == 1024)
    }

    @Test("O app usa o conjunto AppIcon do catálogo de imagens")
    func bundleDeclaresAppIcon() {
        // Os testes rodam dentro do app, então Bundle.main é o próprio app.
        let info = Bundle.main.infoDictionary ?? [:]
        let topLevelName = info["CFBundleIconName"] as? String
        let icons = info["CFBundleIcons"] as? [String: Any]
        let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        let iOSName = primary?["CFBundleIconName"] as? String
        #expect(topLevelName == "AppIcon" || iOSName == "AppIcon")
    }
}
