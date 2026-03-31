import SwiftUI

enum BackgroundStyle: Equatable {
    case solid(Color)
    case gradient(Color, Color, Double) // start, end, angle in degrees
    case wallpaper(String) // image name

    static let presets: [(String, BackgroundStyle)] = [
        ("Ocean", .gradient(Color(red: 0.1, green: 0.1, blue: 0.3), Color(red: 0.2, green: 0.5, blue: 0.8), 135)),
        ("Sunset", .gradient(Color(red: 0.9, green: 0.3, blue: 0.2), Color(red: 0.9, green: 0.6, blue: 0.1), 135)),
        ("Forest", .gradient(Color(red: 0.1, green: 0.2, blue: 0.1), Color(red: 0.2, green: 0.7, blue: 0.4), 135)),
        ("Purple Haze", .gradient(Color(red: 0.3, green: 0.1, blue: 0.5), Color(red: 0.7, green: 0.3, blue: 0.9), 135)),
        ("Midnight", .gradient(Color(red: 0.05, green: 0.05, blue: 0.15), Color(red: 0.15, green: 0.15, blue: 0.35), 135)),
        ("Lava", .gradient(Color(red: 0.5, green: 0.0, blue: 0.0), Color(red: 1.0, green: 0.4, blue: 0.0), 135)),
        ("Arctic", .gradient(Color(red: 0.7, green: 0.85, blue: 0.95), Color(red: 0.95, green: 0.95, blue: 1.0), 135)),
        ("Candy", .gradient(Color(red: 1.0, green: 0.4, blue: 0.6), Color(red: 0.6, green: 0.3, blue: 1.0), 135)),
        ("Emerald", .gradient(Color(red: 0.0, green: 0.4, blue: 0.3), Color(red: 0.1, green: 0.8, blue: 0.6), 135)),
        ("Dusk", .gradient(Color(red: 0.15, green: 0.1, blue: 0.3), Color(red: 0.9, green: 0.4, blue: 0.3), 135)),
        ("Peach", .gradient(Color(red: 1.0, green: 0.7, blue: 0.5), Color(red: 1.0, green: 0.85, blue: 0.75), 135)),
        ("Storm", .gradient(Color(red: 0.2, green: 0.2, blue: 0.3), Color(red: 0.4, green: 0.45, blue: 0.55), 135)),
        ("Noir", .solid(Color(red: 0.08, green: 0.08, blue: 0.08))),
        ("Clean White", .solid(Color(red: 0.95, green: 0.95, blue: 0.95))),
        ("Slate", .solid(Color(red: 0.2, green: 0.22, blue: 0.25))),
    ]
}

struct CursorStyle: Equatable {
    var highlightEnabled: Bool = true
    var highlightColor: Color = .yellow
    var highlightOpacity: Double = 0.3
    var highlightRadius: CGFloat = 30
    var clickPulseEnabled: Bool = true
}

struct CRTSettings: Equatable {
    var enabled: Bool = false
    var scanlineIntensity: CGFloat = 0.3  // 0-1 how visible scanlines are
    var curvature: CGFloat = 0.3          // 0-1 barrel distortion amount
    var rgbOffset: CGFloat = 1.5          // pixels of chromatic aberration
    var vignette: CGFloat = 0.4           // 0-1 edge darkening
    var flicker: Bool = true              // subtle brightness variation
}

struct EffectSettings: Equatable {
    var background: BackgroundStyle = .gradient(
        Color(red: 0.1, green: 0.1, blue: 0.3),
        Color(red: 0.2, green: 0.5, blue: 0.8),
        135
    )
    var cornerRadius: CGFloat = 10
    var shadowRadius: CGFloat = 20
    var shadowOpacity: Double = 0.5
    var padding: CGFloat = 40
    var cursorStyle: CursorStyle = CursorStyle()
    var autoZoomEnabled: Bool = true
    var autoZoomScale: CGFloat = 2.0
    var crt: CRTSettings = CRTSettings()
}
