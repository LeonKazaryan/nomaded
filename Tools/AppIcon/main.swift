// Draws Nomaded's app icon: the globe with every country in the candy colors of a visited
// country, on the app's night sky, with a gold sparkle. The globe is the app's own: country
// outlines from world.nmgeo, the same palette, edge shading, key light and atmosphere glow as
// GlobeShading. Writes the three iOS 18 appearances into the asset catalog:
// - AppIcon.png: opaque, no alpha channel (App Store Connect rejects one);
// - AppIcon-Dark.png: the same art on a transparent background, the system puts its dark
//   gradient behind it;
// - AppIcon-Tinted.png: opaque grayscale on black, the system tints it by brightness.
// Usage: see README.md.

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
import simd

// MARK: - Palette (Nomaded/DesignSystem/Palette.swift)

let oceanHex: UInt32 = 0x1F45B5, idleHex: UInt32 = 0x4B4778, unclaimedHex: UInt32 = 0x3C3962
let candy: [UInt32] = [0xFF6AAE, 0xFF8A3D, 0xFFE04A, 0x4BE8A5, 0x84CEFF, 0xB68AFF]
let idleShades: [Float] = [0.86, 1.12, 0.95, 1.2, 0.9, 1.04]
let lemon: UInt32 = 0xFFE04A, night: UInt32 = 0x0D0A2E, deep: UInt32 = 0x07051A
let nebulaHex: UInt32 = 0x3B1F8C, atmosphere: UInt32 = 0x7DD3FC

func v3(_ hex: UInt32) -> SIMD3<Float> {
    SIMD3(Float((hex >> 16) & 0xFF), Float((hex >> 8) & 0xFF), Float(hex & 0xFF)) / 255
}
func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    let c = v3(hex)
    return CGColor(srgbRed: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: alpha)
}
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

// MARK: - World raster: which country covers each lon/lat

guard CommandLine.arguments.count == 3 else {
    print("usage: appicon <world.nmgeo> <AppIcon.appiconset>")
    exit(1)
}
let world = try WorldGeometry(data: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
let outDir = URL(fileURLWithPath: CommandLine.arguments[2])
let RW = 8192, RH = 4096
var raster = [UInt32](repeating: 0, count: RW * RH)
raster.withUnsafeMutableBytes { buffer in
    let ctx = CGContext(data: buffer.baseAddress, width: RW, height: RH, bitsPerComponent: 8, bytesPerRow: RW * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setShouldAntialias(false)
    for (i, country) in world.countries.enumerated() {
        let id = i + 1
        ctx.setFillColor(red: CGFloat(id & 0xFF) / 255, green: CGFloat((id >> 8) & 0xFF) / 255, blue: 0, alpha: 1)
        let path = CGMutablePath()
        for ring in country.rings where ring.count > 2 {
            path.addLines(between: ring.map { CGPoint(x: (Double($0.x) + 180) / 360 * Double(RW), y: (Double($0.y) + 90) / 180 * Double(RH)) })
            path.closeSubpath()
        }
        ctx.addPath(path)
        ctx.fillPath(using: .evenOdd)
    }
}
func countryIndex(lat: Double, lon: Double) -> Int? {
    let x = min(RW - 1, max(0, Int((lon + 180) / 360 * Double(RW))))
    let y = min(RH - 1, max(0, Int((lat + 90) / 180 * Double(RH))))
    let id = Int(raster[(RH - 1 - y) * RW + x] & 0xFFFF)
    return id == 0 ? nil : id - 1
}

// MARK: - Globe

struct View { var lat: Double; var lon: Double }
func rad(_ d: Double) -> Double { d * .pi / 180 }
func unit(_ lat: Double, _ lon: Double) -> SIMD3<Double> {
    SIMD3(cos(rad(lat)) * sin(rad(lon)), sin(rad(lat)), cos(rad(lat)) * cos(rad(lon)))
}
/// World → view (view center toward +z, north up).
func toView(_ p: SIMD3<Double>, _ v: View) -> SIMD3<Double> {
    let l = rad(-v.lon)
    let a = SIMD3(p.x * cos(l) + p.z * sin(l), p.y, -p.x * sin(l) + p.z * cos(l))
    let t = rad(v.lat)
    return SIMD3(a.x, a.y * cos(t) - a.z * sin(t), a.y * sin(t) + a.z * cos(t))
}
func toWorld(_ q: SIMD3<Double>, _ v: View) -> SIMD3<Double> {
    let t = rad(-v.lat)
    let a = SIMD3(q.x, q.y * cos(t) - q.z * sin(t), q.y * sin(t) + q.z * cos(t))
    let l = rad(v.lon)
    return SIMD3(a.x * cos(l) + a.z * sin(l), a.y, -a.x * sin(l) + a.z * cos(l))
}
typealias Paint = (_ point: SIMD3<Double>, _ country: Int?, _ base: SIMD3<Float>) -> SIMD3<Float>

func landColor(_ index: Int?, visited: Set<String>, all: Bool) -> SIMD3<Float> {
    guard let index else { return v3(oceanHex) }
    let c = world.countries[index]
    if c.code.isEmpty { return v3(unclaimedHex) }
    if all || visited.contains(c.code) { return v3(candy[c.colorSlot % 6]) }
    return v3(idleHex) * idleShades[c.colorSlot % 6]
}

func drawGlobe(_ ctx: CGContext, center: CGPoint, radius r: CGFloat, view: View, visited: Set<String>,
               all: Bool = false, paint: Paint? = nil, glow: Bool = true) {
    let size = Int(ceil(r * 2)) + 2
    var pixels = [UInt8](repeating: 0, count: size * size * 4)
    for py in 0..<size {
        for px in 0..<size {
            let nx = (Double(px) + 0.5 - Double(size) / 2) / Double(r)
            let ny = (Double(size) / 2 - Double(py) - 0.5) / Double(r)
            let d2 = nx * nx + ny * ny
            guard d2 <= 1.02 else { continue }
            let q = SIMD3(nx, ny, sqrt(max(0, 1 - d2)))
            let w = toWorld(q, view)
            let lat = asin(max(-1, min(1, w.y))) * 180 / .pi
            let lon = atan2(w.x, w.z) * 180 / .pi
            let index = countryIndex(lat: lat, lon: lon)
            var c = landColor(index, visited: visited, all: all)
            if let paint { c = paint(w, index, c) }
            let o = (py * size + px) * 4
            pixels[o] = UInt8(min(255, max(0, c.x * 255)))
            pixels[o + 1] = UInt8(min(255, max(0, c.y * 255)))
            pixels[o + 2] = UInt8(min(255, max(0, c.z * 255)))
            pixels[o + 3] = 255
        }
    }
    let provider = CGDataProvider(data: Data(pixels) as CFData)!
    let image = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4, space: sRGB,
                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
                        decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    let disk = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
    if glow {
        // Atmosphere, as GlobeShading draws it.
        let s = 1.45
        let stops: [(UInt32, CGFloat, CGFloat)] = [(atmosphere, 0, 0.84 / s), (atmosphere, 0.5, 0.995 / s), (atmosphere, 0.3, 1.03 / s),
                                                   (atmosphere, 0.08, 1.18 / s), (atmosphere, 0, 1)]
        let g = CGGradient(colorsSpace: sRGB, colors: stops.map { color($0.0, $0.1) } as CFArray, locations: stops.map(\.2))!
        ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: r * s, options: [])
    }
    ctx.saveGState()
    ctx.addEllipse(in: disk)
    ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: center.x - CGFloat(size) / 2, y: center.y - CGFloat(size) / 2, width: CGFloat(size), height: CGFloat(size)))
    // Darker edges and a soft key light from the upper left.
    let edges = CGGradient(colorsSpace: sRGB, colors: [color(0, 0), color(0, 0.22), color(0, 0.5)] as CFArray, locations: [0.5, 0.82, 1])!
    ctx.drawRadialGradient(edges, startCenter: center, startRadius: 0, endCenter: center, endRadius: r, options: [])
    let light = CGPoint(x: center.x - 0.4 * r, y: center.y + 0.5 * r)
    let key = CGGradient(colorsSpace: sRGB, colors: [color(0xFFFFFF, 0.18), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(key, startCenter: light, startRadius: 0, endCenter: light, endRadius: r * 1.1, options: [])
    ctx.restoreGState()
}

// MARK: - Space, stars, shapes

struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

func drawSpace(_ ctx: CGContext, _ S: CGFloat, nebulaAt: CGPoint = CGPoint(x: 0.5, y: 0.6), seed: UInt64 = 7, stars: Int = 90) {
    ctx.setFillColor(color(deep))
    ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
    let n = CGPoint(x: nebulaAt.x * S, y: nebulaAt.y * S)
    let neb = CGGradient(colorsSpace: sRGB, colors: [color(nebulaHex, 0.95), color(0x1A1458, 0.7), color(night, 0)] as CFArray, locations: [0, 0.45, 1])!
    ctx.drawRadialGradient(neb, startCenter: n, startRadius: 0, endCenter: n, endRadius: S * 0.75, options: [.drawsAfterEndLocation])
    let low = CGPoint(x: S * 0.15, y: S * 0.05)
    let plum = CGGradient(colorsSpace: sRGB, colors: [color(0x2A0F45, 0.9), color(0x2A0F45, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(plum, startCenter: low, startRadius: 0, endCenter: low, endRadius: S * 0.6, options: [])
    var random = SplitMix64(state: seed)
    for _ in 0..<stars {
        let x = Double.random(in: 0...1, using: &random) * S
        let y = Double.random(in: 0...1, using: &random) * S
        let r = Double.random(in: 1.6...5.5, using: &random)
        let a = Double.random(in: 0.25...0.9, using: &random)
        ctx.setFillColor(color(0xFFFFFF, a))
        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }
}

func glowDot(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, _ hex: UInt32, _ alpha: CGFloat) {
    let g = CGGradient(colorsSpace: sRGB, colors: [color(hex, alpha), color(hex, alpha * 0.35), color(hex, 0)] as CFArray, locations: [0, 0.35, 1])!
    ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
}

/// A four-pointed sparkle with curved sides.
func sparkle(_ c: CGPoint, _ r: CGFloat, pinch: CGFloat = 0.18) -> CGPath {
    let p = CGMutablePath()
    let pts = [CGPoint(x: c.x, y: c.y + r), CGPoint(x: c.x + r, y: c.y), CGPoint(x: c.x, y: c.y - r), CGPoint(x: c.x - r, y: c.y)]
    p.move(to: pts[0])
    for i in 0..<4 {
        let a = pts[i], b = pts[(i + 1) % 4]
        let mid = CGPoint(x: c.x + (a.x + b.x - 2 * c.x) * pinch, y: c.y + (a.y + b.y - 2 * c.y) * pinch)
        p.addQuadCurve(to: b, control: mid)
    }
    p.closeSubpath()
    return p
}

func fill(_ ctx: CGContext, _ path: CGPath, _ hex: UInt32, alpha: CGFloat = 1, shadow: (UInt32, CGFloat)? = nil) {
    ctx.saveGState()
    if let shadow { ctx.setShadow(offset: .zero, blur: shadow.1, color: color(shadow.0, 0.9)) }
    ctx.addPath(path)
    ctx.setFillColor(color(hex, alpha))
    ctx.fillPath()
    ctx.restoreGState()
}

func goldSparkle(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat) {
    glowDot(ctx, c, r * 1.6, lemon, 0.5)
    fill(ctx, sparkle(c, r), lemon, shadow: (lemon, r * 0.35))
    fill(ctx, sparkle(c, r * 0.45, pinch: 0.25), 0xFFF8D6)
}


// MARK: - Icon

let S: CGFloat = 2048

/// The globe and the sparkle, on whatever is already in `ctx`.
func drawArt(_ ctx: CGContext) {
    drawGlobe(ctx, center: CGPoint(x: S * 0.5, y: S * 0.47), radius: S * 0.36, view: View(lat: 22, lon: 15), visited: [], all: true)
    goldSparkle(ctx, CGPoint(x: S * 0.8, y: S * 0.82), S * 0.06)
}

func context(_ size: Int, opaque: Bool) -> CGContext {
    CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
              bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue)!
}

/// Drawn at 2048 and scaled down: smoother borders and limb than drawing at 1024.
func final(_ image: CGImage, opaque: Bool) -> CGImage {
    let ctx = context(1024, opaque: opaque)
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
    return ctx.makeImage()!
}

func save(_ image: CGImage, _ name: String) {
    let url = outDir.appending(path: name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(url.path)") }
    print("wrote \(url.path)")
}

let any = context(Int(S), opaque: true)
drawSpace(any, S, nebulaAt: CGPoint(x: 0.5, y: 0.5), seed: 21)
drawArt(any)
save(final(any.makeImage()!, opaque: true), "AppIcon.png")

let dark = context(Int(S), opaque: false)
drawArt(dark)
save(final(dark.makeImage()!, opaque: false), "AppIcon-Dark.png")

// Tinted: the dark art on black, as brightness only.
let tinted = context(Int(S), opaque: true)
tinted.setFillColor(color(0x000000))
tinted.fill(CGRect(x: 0, y: 0, width: S, height: S))
tinted.draw(dark.makeImage()!, in: CGRect(x: 0, y: 0, width: S, height: S))
let gray = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                     space: CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)!, bitmapInfo: CGImageAlphaInfo.none.rawValue)!
gray.draw(tinted.makeImage()!, in: CGRect(x: 0, y: 0, width: S, height: S))
// Back to RGB with equal channels: the asset compiler expects the same format in every slot.
let grayRGB = context(Int(S), opaque: true)
grayRGB.draw(gray.makeImage()!, in: CGRect(x: 0, y: 0, width: S, height: S))
save(final(grayRGB.makeImage()!, opaque: true), "AppIcon-Tinted.png")
