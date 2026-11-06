import AppKit

// Turns the raw captures from capture.sh into App Store screenshots: the app's night sky, a
// caption on top, the screen below in a slim bezel. 1206×2622 (iPhone 6.3″, the size App Store
// Connect asks for), RGB without alpha: it rejects screenshots with transparency.
//
//   swift Tools/Screenshots/compose.swift Tools/Screenshots/output

/// The layout is drawn in these units (iPhone 6.9″) and scaled down to `output`: nearly the same
/// shape, so nothing visibly stretches.
let canvas = CGSize(width: 1320, height: 2868)
let output = CGSize(width: 1206, height: 2622)
/// The screen's share of the width; the rest is margin, and the caption sits above.
let screenScale = 0.8
let screenTop = 520.0
/// iPhone 16 Pro Max's display corner, in pixels at full size.
let screenCorner = 165.0
let bezel = 16.0

/// In App Store order: the first three show up in search results.
let scenes = ["globe", "mark", "statistics", "cities", "medal", "continent"]
let captions: [String: [String: String]] = [
    "en": [
        "globe": "Your travels on a\nliving 3D globe",
        "mark": "Mark a country and\nwatch it light up",
        "statistics": "See how much of the\nworld you’ve explored",
        "cities": "Add the cities\nyou’ve been to",
        "medal": "Collect medals\nas you go",
        "continent": "Every continent,\ncountry by country",
    ],
    "ru": [
        "globe": "Твои путешествия\nна живом 3D-глобусе",
        "mark": "Отметь страну —\nи она засияет",
        "statistics": "Смотри, сколько мира\nты уже открыл",
        "cities": "Добавляй города,\nгде ты был",
        "medal": "Собирай медали\nза новые страны",
        "continent": "Каждый континент —\nпо странам",
    ],
]

// Palette.swift: night, nebula, accent.
let night = CGColor(srgbRed: 0x0D / 255, green: 0x0A / 255, blue: 0x2E / 255, alpha: 1)
let nebula = CGColor(srgbRed: 0x3B / 255, green: 0x1F / 255, blue: 0x8C / 255, alpha: 1)
let accent = CGColor(srgbRed: 0x7C / 255, green: 0x5C / 255, blue: 0xFF / 255, alpha: 1)

func roundedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
}

func compose(screen: CGImage, caption: String) -> CGImage {
    let context = CGContext(
        data: nil, width: Int(output.width), height: Int(output.height), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    // Canvas units, top-left origin, like the screenshots themselves.
    context.scaleBy(x: output.width / canvas.width, y: output.height / canvas.height)
    context.translateBy(x: 0, y: canvas.height)
    context.scaleBy(x: 1, y: -1)

    // Sky: night above, the nebula's violet rising from below, a glow behind the phone.
    let sky = CGGradient(colorsSpace: nil, colors: [night, night, nebula] as CFArray, locations: [0, 0.35, 1])!
    context.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: canvas.height), options: [])
    let glow = CGGradient(colorsSpace: nil, colors: [accent.copy(alpha: 0.45)!, accent.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
    let glowCenter = CGPoint(x: canvas.width / 2, y: screenTop + 700)
    context.drawRadialGradient(glow, startCenter: glowCenter, startRadius: 0, endCenter: glowCenter, endRadius: 1100, options: [])

    // Caption: SF Pro Rounded, as in the app. Captions break lines by hand, so no word is left alone
    // on the second; a long one shrinks until it fits two lines.
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineHeightMultiple = 0.95
    let box = CGRect(x: 90, y: 0, width: canvas.width - 180, height: screenTop - 40)
    var size: CGFloat = 104
    var text: NSAttributedString
    var bounds: CGRect
    repeat {
        text = NSAttributedString(string: caption, attributes: [
            .font: roundedFont(size: size, weight: .heavy),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ])
        bounds = text.boundingRect(with: CGSize(width: box.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
        size -= 4
    } while bounds.height > size * 2.6 && size > 60
    text.draw(with: CGRect(x: box.minX, y: box.midY - bounds.height / 2 + 30, width: box.width, height: bounds.height), options: [.usesLineFragmentOrigin, .usesFontLeading])
    NSGraphicsContext.current = nil

    // The screen in a slim dark bezel with a soft shadow and a hairline highlight.
    let width = canvas.width * screenScale
    let frame = CGRect(x: (canvas.width - width) / 2, y: screenTop, width: width, height: width * Double(screen.height) / Double(screen.width))
    let corner = screenCorner * screenScale
    let outer = CGPath(roundedRect: frame.insetBy(dx: -bezel, dy: -bezel), cornerWidth: corner + bezel, cornerHeight: corner + bezel, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 40), blur: 90, color: CGColor(gray: 0, alpha: 0.6))
    context.addPath(outer)
    context.setFillColor(CGColor(srgbRed: 0.03, green: 0.025, blue: 0.08, alpha: 1))
    context.fillPath()
    context.restoreGState()
    context.addPath(outer)
    context.setStrokeColor(CGColor(gray: 1, alpha: 0.18))
    context.setLineWidth(3)
    context.strokePath()

    context.saveGState()
    context.addPath(CGPath(roundedRect: frame, cornerWidth: corner, cornerHeight: corner, transform: nil))
    context.clip()
    // CGContext draws images bottom-up; flip back for this one.
    context.translateBy(x: 0, y: frame.maxY + frame.minY)
    context.scaleBy(x: 1, y: -1)
    context.interpolationQuality = .high
    context.draw(screen, in: frame)
    context.restoreGState()

    return context.makeImage()!
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    print("usage: swift compose.swift <output folder with raw/en and raw/ru>")
    exit(1)
}
let root = URL(fileURLWithPath: arguments[1])
for (language, texts) in captions.sorted(by: { $0.key < $1.key }) {
    let folder = root.appending(path: language)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for (index, scene) in scenes.enumerated() {
        let source = root.appending(path: "raw/\(language)/\(scene).png")
        guard let data = try? Data(contentsOf: source),
              let image = NSBitmapImageRep(data: data)?.cgImage
        else {
            print("missing \(source.path), run capture.sh first")
            exit(1)
        }
        let result = compose(screen: image, caption: texts[scene]!)
        let destination = folder.appending(path: "\(index + 1)-\(scene).png")
        let writer = CGImageDestinationCreateWithURL(destination as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(writer, result, nil)
        CGImageDestinationFinalize(writer)
        print(destination.path)
    }
}
