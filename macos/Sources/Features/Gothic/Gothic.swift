import AppKit
import SwiftUI

/// Ghostty Gothic: shared art, colours and fonts for the cathedral chrome.
///
/// Art lives in `Resources/ghostty/gothic/art` (installed from `gothic/art`
/// by the zig build). PNGs are authored at 2x, so their point size is half
/// their pixel size.
enum Gothic {
    static let limestone = NSColor(srgbRed: 0.83, green: 0.77, blue: 0.67, alpha: 1)
    static let parchment = NSColor(srgbRed: 0.96, green: 0.93, blue: 0.87, alpha: 1)
    static let nave = NSColor(srgbRed: 0.07, green: 0.055, blue: 0.08, alpha: 1)
    static let ink = NSColor(srgbRed: 0.24, green: 0.13, blue: 0.08, alpha: 1)
    static let ruby = NSColor(srgbRed: 0.81, green: 0.29, blue: 0.32, alpha: 1)
    static let gilt = NSColor(srgbRed: 0.83, green: 0.64, blue: 0.23, alpha: 1)
    static let emerald = NSColor(srgbRed: 0.31, green: 0.62, blue: 0.38, alpha: 1)
    static let cobalt = NSColor(srgbRed: 0.29, green: 0.47, blue: 0.88, alpha: 1)

    private static var cache: [String: NSImage] = [:]

    static func image(_ name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        guard let url = Bundle.main.resourceURL?
            .appendingPathComponent("ghostty/gothic/art/\(name).png"),
              let image = NSImage(contentsOf: url),
              let rep = image.representations.first else { return nil }
        image.size = NSSize(width: CGFloat(rep.pixelsWide) / 2, height: CGFloat(rep.pixelsHigh) / 2)
        cache[name] = image
        return image
    }

    /// The bundled blackletter (Grenze Gotisch, registered through
    /// ATSApplicationFontsPath), falling back to the system title font.
    static func font(_ size: CGFloat) -> NSFont {
        NSFont(name: "GrenzeGotisch-Medium", size: size) ?? .titleBarFont(ofSize: size)
    }
}

/// Split dividers: a stone colonnette between side-by-side panes and a
/// carved string course between stacked ones. Falls back to the plain
/// divider colour if the art is missing.
struct GothicDivider: View {
    let direction: SplitViewDirection
    let color: Color

    var body: some View {
        switch direction {
        case .horizontal:
            if let top = Gothic.image("column-top"),
               let shaft = Gothic.image("column-shaft"),
               let bottom = Gothic.image("column-bottom") {
                VStack(spacing: 0) {
                    Image(nsImage: top).resizable().aspectRatio(contentMode: .fit)
                    Image(nsImage: shaft).resizable(resizingMode: .tile)
                    Image(nsImage: bottom).resizable().aspectRatio(contentMode: .fit)
                }
            } else {
                Rectangle().fill(color)
            }

        case .vertical:
            if let left = Gothic.image("beam-left"),
               let shaft = Gothic.image("beam-shaft"),
               let right = Gothic.image("beam-right") {
                HStack(spacing: 0) {
                    Image(nsImage: left).resizable().aspectRatio(contentMode: .fit)
                    Image(nsImage: shaft).resizable(resizingMode: .tile)
                    Image(nsImage: right).resizable().aspectRatio(contentMode: .fit)
                }
            } else {
                Rectangle().fill(color)
            }
        }
    }
}
