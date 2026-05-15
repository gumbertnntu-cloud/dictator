import AppKit
import Foundation

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: make_icon.swift <output_png_path>\n".utf8))
    exit(2)
}

let outputPath = CommandLine.arguments[1]
let size: CGFloat = 1024

let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size),
    pixelsHigh: Int(size),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

let inset: CGFloat = 88
let cornerRadius: CGFloat = 196
let squircleRect = NSRect(
    x: inset,
    y: inset,
    width: size - 2 * inset,
    height: size - 2 * inset
)

let path = NSBezierPath(roundedRect: squircleRect, xRadius: cornerRadius, yRadius: cornerRadius)
NSGraphicsContext.current?.saveGraphicsState()
path.addClip()

let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.40, green: 0.18, blue: 0.86, alpha: 1.0),
    NSColor(srgbRed: 0.78, green: 0.27, blue: 0.78, alpha: 1.0),
    NSColor(srgbRed: 0.97, green: 0.32, blue: 0.55, alpha: 1.0),
])!
gradient.draw(in: squircleRect, angle: -75)

let highlight = NSGradient(colors: [
    NSColor.white.withAlphaComponent(0.18),
    NSColor.white.withAlphaComponent(0.0),
])!
highlight.draw(in: squircleRect, angle: 90)

NSGraphicsContext.current?.restoreGraphicsState()

let centerX = size / 2
let bodyWidth: CGFloat = 240
let bodyHeight: CGFloat = 440
let bodyRect = NSRect(
    x: centerX - bodyWidth / 2,
    y: size / 2 - 30,
    width: bodyWidth,
    height: bodyHeight
)
let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: bodyWidth / 2, yRadius: bodyWidth / 2)

NSColor(white: 1.0, alpha: 0.16).setFill()
let shadowPath = NSBezierPath(roundedRect: bodyRect.offsetBy(dx: 0, dy: -10), xRadius: bodyWidth / 2, yRadius: bodyWidth / 2)
shadowPath.fill()

NSColor.white.setFill()
bodyPath.fill()

let strokeWidth: CGFloat = 44
let cradleWidth: CGFloat = 440
let cradleHeight: CGFloat = 260
let cradleRect = NSRect(
    x: centerX - cradleWidth / 2,
    y: bodyRect.minY - cradleHeight / 2 + 60,
    width: cradleWidth,
    height: cradleHeight
)

let cradlePath = NSBezierPath()
let leftTop = NSPoint(x: cradleRect.minX, y: cradleRect.maxY)
let rightTop = NSPoint(x: cradleRect.maxX, y: cradleRect.maxY)
let bottomCenter = NSPoint(x: cradleRect.midX, y: cradleRect.minY)
cradlePath.move(to: leftTop)
cradlePath.curve(
    to: rightTop,
    controlPoint1: NSPoint(x: cradleRect.minX, y: bottomCenter.y - 20),
    controlPoint2: NSPoint(x: cradleRect.maxX, y: bottomCenter.y - 20)
)
cradlePath.lineWidth = strokeWidth
cradlePath.lineCapStyle = .round
NSColor.white.setStroke()
cradlePath.stroke()

let stemTop = NSPoint(x: centerX, y: bottomCenter.y + 20)
let stemBottom = NSPoint(x: centerX, y: bottomCenter.y - 90)
let stemPath = NSBezierPath()
stemPath.move(to: stemTop)
stemPath.line(to: stemBottom)
stemPath.lineWidth = strokeWidth
stemPath.lineCapStyle = .round
stemPath.stroke()

let baseY = stemBottom.y - 6
let baseHalfWidth: CGFloat = 110
let basePath = NSBezierPath()
basePath.move(to: NSPoint(x: centerX - baseHalfWidth, y: baseY))
basePath.line(to: NSPoint(x: centerX + baseHalfWidth, y: baseY))
basePath.lineWidth = strokeWidth
basePath.lineCapStyle = .round
basePath.stroke()

func drawSparkle(at center: NSPoint, radius: CGFloat, alpha: CGFloat) {
    let arm = NSBezierPath()
    arm.move(to: NSPoint(x: center.x, y: center.y - radius))
    arm.curve(
        to: NSPoint(x: center.x + radius, y: center.y),
        controlPoint1: NSPoint(x: center.x + radius * 0.35, y: center.y - radius * 0.35),
        controlPoint2: NSPoint(x: center.x + radius * 0.35, y: center.y - radius * 0.35)
    )
    arm.curve(
        to: NSPoint(x: center.x, y: center.y + radius),
        controlPoint1: NSPoint(x: center.x + radius * 0.35, y: center.y + radius * 0.35),
        controlPoint2: NSPoint(x: center.x + radius * 0.35, y: center.y + radius * 0.35)
    )
    arm.curve(
        to: NSPoint(x: center.x - radius, y: center.y),
        controlPoint1: NSPoint(x: center.x - radius * 0.35, y: center.y + radius * 0.35),
        controlPoint2: NSPoint(x: center.x - radius * 0.35, y: center.y + radius * 0.35)
    )
    arm.curve(
        to: NSPoint(x: center.x, y: center.y - radius),
        controlPoint1: NSPoint(x: center.x - radius * 0.35, y: center.y - radius * 0.35),
        controlPoint2: NSPoint(x: center.x - radius * 0.35, y: center.y - radius * 0.35)
    )
    arm.close()
    NSColor.white.withAlphaComponent(alpha).setFill()
    arm.fill()
}

drawSparkle(at: NSPoint(x: 270, y: 760), radius: 34, alpha: 0.92)
drawSparkle(at: NSPoint(x: 800, y: 820), radius: 22, alpha: 0.78)
drawSparkle(at: NSPoint(x: 760, y: 340), radius: 28, alpha: 0.85)
drawSparkle(at: NSPoint(x: 220, y: 280), radius: 18, alpha: 0.70)

NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("failed to encode PNG\n".utf8))
    exit(1)
}

let outputURL = URL(fileURLWithPath: outputPath)
try pngData.write(to: outputURL)
print(outputPath)
