import AppKit

// Turns the raw captures from capture.sh and capture-duo.sh into App Store screenshots: the app's
// night sky, a caption on top, the screens below in slim bezels. RGB without alpha: App Store
// Connect rejects screenshots with transparency. iPhone: 1206×2622 (6.3″, the size App Store
// Connect asks for); iPad: 2064×2752 (13″); iPhone Duo: 2853×2007 (its inner display held like a
// book), the folded phone beside the open one where both show.
//
//   swift Tools/Screenshots/compose.swift Tools/Screenshots/output
//   swift Tools/Screenshots/compose.swift Tools/Screenshots/output/ipad ipad
//   swift Tools/Screenshots/compose.swift Tools/Screenshots/output/duo duo

enum Device: String {
    case iPhone = "iphone", iPad = "ipad", duo
}

let arguments = CommandLine.arguments
guard (2...3).contains(arguments.count), let device = Device(rawValue: arguments.count == 3 ? arguments[2] : "iphone") else {
    print("usage: swift compose.swift <output folder with raw/en and raw/ru> [ipad|duo]")
    exit(1)
}

/// The layout is drawn in these units and scaled down to `output`: the iPhone's in 6.9″ units,
/// nearly the same shape, so nothing visibly stretches.
let canvas = switch device {
case .iPhone: CGSize(width: 1320, height: 2868)
case .iPad: CGSize(width: 2064, height: 2752)
case .duo: CGSize(width: 2853, height: 2007)
}
let output = switch device {
case .iPhone: CGSize(width: 1206, height: 2622)
case .iPad, .duo: canvas
}

// MARK: - iPhone and iPad

/// The screen's share of the width; the rest is margin, and the caption sits above.
let screenScale = device == .iPad ? 0.78 : 0.8
let screenTop = device == .iPad ? 500.0 : 520.0
/// The display's corner (iPhone 16 Pro Max, iPad Pro), in pixels at full size.
let screenCorner = device == .iPad ? 74.0 : 165.0
let bezel = device == .iPad ? 26.0 : 16.0
/// The caption's largest size; long captions shrink until they fit two lines.
let captionSize: CGFloat = device == .iPad ? 124 : 104

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

// MARK: - iPhone Duo

/// In App Store order: the first card shows both postures, since it's the one search results show.
/// A shot named `cover-…` is the folded phone's outer display, any other the open inner one.
let duoScenes: [(name: String, shots: [String])] = [
    ("both", ["cover-globe", "globe"]),
    ("card", ["card"]),
    ("folded", ["cover-card", "cover-statistics"]),
    ("statistics", ["statistics"]),
    ("medal", ["medal"]),
    ("story", ["story"]),
]
let duoCaptions: [String: [String: String]] = [
    "en": [
        "both": "Folded or open, your world fits",
        "card": "Passport on the left, world on the right",
        "folded": "Everything’s there, even folded",
        "statistics": "Your stats, open like a passport",
        "medal": "Medals across the whole spread",
        "story": "Share your world as a story",
    ],
    "ru": [
        "both": "Сложи или раскрой — мир поместится",
        "card": "Слева паспорт, справа — весь мир",
        "folded": "Всё под рукой, даже в сложенном",
        "statistics": "Статистика — разворотом паспорта",
        "medal": "Медали на весь разворот",
        "story": "Делись своим миром в сторис",
    ],
]
/// Under the phones on the card that shows both.
let duoLabels: [String: [String]] = ["en": ["Folded", "Open"], "ru": ["Сложен", "Раскрыт"]]
/// Both displays are 3x: a capture's pixels are its points times three, so the outer and inner
/// screens drawn at one scale keep their real sizes against each other.
let duoPointsPerPixel = 1.0 / 3
/// In points: the outer display's corner is a phone's, the inner one's tighter.
let duoFoldedCorner = 48.0
let duoOpenCorner = 40.0
let duoBezel = 9.0

// MARK: - Drawing

// Palette.swift: night, nebula, accent.
let night = CGColor(srgbRed: 0x0D / 255, green: 0x0A / 255, blue: 0x2E / 255, alpha: 1)
let nebula = CGColor(srgbRed: 0x3B / 255, green: 0x1F / 255, blue: 0x8C / 255, alpha: 1)
let accent = CGColor(srgbRed: 0x7C / 255, green: 0x5C / 255, blue: 0xFF / 255, alpha: 1)
let bezelColor = CGColor(srgbRed: 0.03, green: 0.025, blue: 0.08, alpha: 1)

func roundedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
}

/// Canvas units, top-left origin, like the screenshots themselves.
func makeContext() -> CGContext {
    let context = CGContext(
        data: nil, width: Int(output.width), height: Int(output.height), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    context.scaleBy(x: output.width / canvas.width, y: output.height / canvas.height)
    context.translateBy(x: 0, y: canvas.height)
    context.scaleBy(x: 1, y: -1)
    return context
}

/// Night above, the nebula's violet rising from below, a glow behind the screens.
func drawSky(in context: CGContext, glowCenter: CGPoint, glowRadius: CGFloat) {
    let sky = CGGradient(colorsSpace: nil, colors: [night, night, nebula] as CFArray, locations: [0, 0.35, 1])!
    context.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: canvas.height), options: [])
    let glow = CGGradient(colorsSpace: nil, colors: [accent.copy(alpha: 0.45)!, accent.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(glow, startCenter: glowCenter, startRadius: 0, endCenter: glowCenter, endRadius: glowRadius, options: [])
}

/// SF Pro Rounded, as in the app, centred in `box`. Captions break lines by hand, so no word is
/// left alone on a line; a long one shrinks until it fits `lines` lines.
func drawText(_ string: String, in box: CGRect, size: CGFloat, weight: NSFont.Weight, color: NSColor, lines: Int, context: CGContext) {
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineHeightMultiple = 0.95
    var size = size
    let smallest = size * 0.58
    var text: NSAttributedString
    var bounds: CGRect
    repeat {
        text = NSAttributedString(string: string, attributes: [
            .font: roundedFont(size: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ])
        bounds = text.boundingRect(with: CGSize(width: box.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
        size -= 4
    } while bounds.height > size * 1.3 * CGFloat(lines) && size > smallest
    text.draw(with: CGRect(x: box.minX, y: box.midY - bounds.height / 2, width: box.width, height: bounds.height), options: [.usesLineFragmentOrigin, .usesFontLeading])
    NSGraphicsContext.current = nil
}

/// The screen in a slim dark bezel with a soft shadow and a hairline highlight. `hinge` marks an
/// open iPhone Duo: the hairline breaks where the halves meet, and a faint crease runs down the
/// screen between them.
func drawDevice(_ screen: CGImage, in frame: CGRect, corner: CGFloat, bezel: CGFloat, hinge: Bool = false, context: CGContext) {
    let outer = CGPath(roundedRect: frame.insetBy(dx: -bezel, dy: -bezel), cornerWidth: corner + bezel, cornerHeight: corner + bezel, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 40), blur: 90, color: CGColor(gray: 0, alpha: 0.6))
    context.addPath(outer)
    context.setFillColor(bezelColor)
    context.fillPath()
    context.restoreGState()
    context.addPath(outer)
    context.setStrokeColor(CGColor(gray: 1, alpha: 0.18))
    context.setLineWidth(3)
    context.strokePath()
    if hinge {
        context.setFillColor(bezelColor)
        for y in [frame.minY - bezel - 3, frame.maxY + bezel - 3] {
            context.fill(CGRect(x: frame.midX - 4, y: y, width: 8, height: 6))
        }
    }

    context.saveGState()
    context.addPath(CGPath(roundedRect: frame, cornerWidth: corner, cornerHeight: corner, transform: nil))
    context.clip()
    context.saveGState()
    // CGContext draws images bottom-up; flip back for this one.
    context.translateBy(x: 0, y: frame.maxY + frame.minY)
    context.scaleBy(x: 1, y: -1)
    context.interpolationQuality = .high
    context.draw(screen, in: frame)
    context.restoreGState()
    if hinge {
        let crease = CGGradient(
            colorsSpace: nil,
            colors: [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.08), CGColor(gray: 1, alpha: 0.03), CGColor(gray: 0, alpha: 0)] as CFArray,
            locations: [0, 0.46, 0.56, 1]
        )!
        let half = bezel * 3
        context.drawLinearGradient(crease, start: CGPoint(x: frame.midX - half, y: 0), end: CGPoint(x: frame.midX + half, y: 0), options: [])
    }
    context.restoreGState()
}

/// iPhone and iPad: the caption on top, one screen below.
func compose(screen: CGImage, caption: String) -> CGImage {
    let context = makeContext()
    drawSky(in: context, glowCenter: CGPoint(x: canvas.width / 2, y: screenTop + canvas.width * 0.53), glowRadius: canvas.width * 0.83)
    drawText(
        caption, in: CGRect(x: 90, y: 30, width: canvas.width - 180, height: screenTop - 40),
        size: captionSize, weight: .heavy, color: .white, lines: 2, context: context
    )
    let width = canvas.width * screenScale
    let frame = CGRect(x: (canvas.width - width) / 2, y: screenTop, width: width, height: width * Double(screen.height) / Double(screen.width))
    drawDevice(screen, in: frame, corner: screenCorner * screenScale, bezel: bezel, context: context)
    return context.makeImage()!
}

/// iPhone Duo: the caption on one line, the screens side by side below it at one scale, so a
/// folded phone stands as tall as the open one and half as wide, as it does in the hand.
func composeDuo(screens: [(image: CGImage, isFolded: Bool)], caption: String, labels: [String]?) -> CGImage {
    let context = makeContext()
    let captionHeight = 400.0, margin = 150.0, gap = 190.0, bottom = 110.0
    let labelHeight = labels == nil ? 0.0 : 140.0
    let sizes = screens.map { CGSize(width: $0.image.width, height: $0.image.height) }
    let tallest = sizes.map(\.height).max()!
    let room = CGSize(
        width: canvas.width - 2 * margin - gap * CGFloat(screens.count - 1),
        height: canvas.height - captionHeight - bottom - labelHeight
    )
    let scale = min(room.width / sizes.map(\.width).reduce(0, +), room.height / tallest)
    let top = captionHeight + (room.height - tallest * scale) / 2
    var x = (canvas.width - sizes.map(\.width).reduce(0, +) * scale - gap * CGFloat(screens.count - 1)) / 2

    drawSky(in: context, glowCenter: CGPoint(x: canvas.width / 2, y: top + tallest * scale / 2), glowRadius: canvas.width * 0.6)
    drawText(
        caption, in: CGRect(x: margin, y: 50, width: canvas.width - 2 * margin, height: captionHeight - 50),
        size: 128, weight: .heavy, color: .white, lines: 1, context: context
    )
    let points = scale / duoPointsPerPixel
    for (index, screen) in screens.enumerated() {
        let size = sizes[index]
        let frame = CGRect(x: x, y: top + (tallest - size.height) * scale / 2, width: size.width * scale, height: size.height * scale)
        drawDevice(
            screen.image, in: frame, corner: (screen.isFolded ? duoFoldedCorner : duoOpenCorner) * points,
            bezel: duoBezel * points, hinge: !screen.isFolded, context: context
        )
        if let labels {
            drawText(
                labels[index], in: CGRect(x: frame.minX - gap / 2, y: top + tallest * scale + 40, width: frame.width + gap, height: labelHeight - 40),
                size: 64, weight: .semibold, color: NSColor.white.withAlphaComponent(0.7), lines: 1, context: context
            )
        }
        x += frame.width + gap
    }
    return context.makeImage()!
}

// MARK: - Files

func load(_ url: URL) -> CGImage {
    guard let data = try? Data(contentsOf: url), let image = NSBitmapImageRep(data: data)?.cgImage else {
        print("missing \(url.path), run \(device == .duo ? "capture-duo.sh" : "capture.sh") first")
        exit(1)
    }
    return image
}

func write(_ image: CGImage, to url: URL) {
    let writer = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(writer, image, nil)
    CGImageDestinationFinalize(writer)
    print(url.path)
}

let root = URL(fileURLWithPath: arguments[1])
for language in ["en", "ru"] {
    let folder = root.appending(path: language)
    let raw = root.appending(path: "raw/\(language)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    if device == .duo {
        for (index, scene) in duoScenes.enumerated() {
            let screens = scene.shots.map { shot in
                (image: load(raw.appending(path: "\(shot).png")), isFolded: shot.hasPrefix("cover-"))
            }
            let image = composeDuo(
                screens: screens,
                caption: duoCaptions[language]![scene.name]!,
                labels: scene.shots.count == 2 && screens[0].isFolded != screens[1].isFolded ? duoLabels[language] : nil
            )
            write(image, to: folder.appending(path: "\(index + 1)-\(scene.name).png"))
        }
    } else {
        for (index, scene) in scenes.enumerated() {
            let image = compose(screen: load(raw.appending(path: "\(scene).png")), caption: captions[language]![scene]!)
            write(image, to: folder.appending(path: "\(index + 1)-\(scene).png"))
        }
    }
}
