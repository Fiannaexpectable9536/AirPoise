import AppKit
import CoreText
import SwiftUI

enum Comic {
    static let paper = Color(red: 0.949, green: 0.902, blue: 0.769)
    static let card = Color(red: 1.0, green: 0.973, blue: 0.910)
    static let ink = Color(red: 0.078, green: 0.067, blue: 0.051)
    static let mute = Color(red: 0.361, green: 0.325, blue: 0.275)
    static let pop = Color(red: 0.890, green: 0.106, blue: 0.137)
    static let burst = Color(red: 1.0, green: 0.839, blue: 0.039)
    static let sky = Color(red: 0.239, green: 0.710, blue: 1.0)

    static let nsPaper = NSColor(red: 0.949, green: 0.902, blue: 0.769, alpha: 1)

    static func registerFonts() {
        let names = ["Bangers-Regular", "ArchivoBlack-Regular"]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func art(_ name: String) -> NSImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Onboarding") {
            return NSImage(contentsOf: url)
        }
        return NSImage(contentsOfFile:
            Bundle.main.resourcePath.map { "\($0)/Onboarding/\(name).png" } ?? "")
    }
}

extension Font {
    static func comicSFX(_ size: CGFloat) -> Font {
        .custom("Bangers", size: size)
    }

    static func comicInk(_ size: CGFloat) -> Font {
        .custom("Archivo Black", size: size)
    }
}

struct ComicPanel<Content: View>: View {
    var padding: CGFloat = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Comic.card)
            .overlay(Rectangle().stroke(Comic.ink, lineWidth: 4))
    }
}

struct ComicBurstButton: View {
    let title: String
    var large = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.comicSFX(large ? 28 : 22))
                .tracking(1.2)
                .foregroundStyle(Comic.burst)
                .padding(.horizontal, large ? 22 : 16)
                .padding(.vertical, large ? 10 : 7)
                .background(Comic.ink)
                .overlay(Rectangle().stroke(Comic.ink, lineWidth: 3))
                .shadow(color: Comic.pop, radius: 0, x: 4, y: 4)
        }
        .buttonStyle(.plain)
        .rotationEffect(.degrees(-1.4))
    }
}

struct ComicCaption: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium, design: .serif))
            .italic()
            .foregroundStyle(Comic.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Comic.card)
            .overlay(Rectangle().stroke(Comic.ink, lineWidth: 2))
    }
}
