import AppKit

let outputDirectory = URL(fileURLWithPath: "fastar/Resources/Assets.xcassets/AppIcon.appiconset")
let sizes = [16, 32, 64, 128, 256, 512, 1024]

func drawIcon(size: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let bounds = NSRect(x: 0, y: 0, width: size, height: size)
    let radius = CGFloat(size) * 0.22
    let path = NSBezierPath(roundedRect: bounds.insetBy(dx: CGFloat(size) * 0.045, dy: CGFloat(size) * 0.045), xRadius: radius, yRadius: radius)

    NSGraphicsContext.current?.imageInterpolation = .high

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.06, green: 0.16, blue: 0.20, alpha: 1),
        NSColor(calibratedRed: 0.08, green: 0.36, blue: 0.80, alpha: 1)
    ])
    gradient?.draw(in: path, angle: 45)

    NSColor(calibratedWhite: 1, alpha: 0.92).setFill()
    let stripeHeight = CGFloat(size) * 0.085
    for index in 0..<3 {
        let y = CGFloat(size) * (0.30 + CGFloat(index) * 0.17)
        let stripe = NSBezierPath(roundedRect: NSRect(x: CGFloat(size) * 0.23, y: y, width: CGFloat(size) * 0.54, height: stripeHeight), xRadius: stripeHeight / 2, yRadius: stripeHeight / 2)
        stripe.fill()
    }

    NSColor(calibratedRed: 0.98, green: 0.73, blue: 0.18, alpha: 1).setFill()
    let spark = NSBezierPath()
    spark.move(to: NSPoint(x: CGFloat(size) * 0.68, y: CGFloat(size) * 0.77))
    spark.line(to: NSPoint(x: CGFloat(size) * 0.74, y: CGFloat(size) * 0.63))
    spark.line(to: NSPoint(x: CGFloat(size) * 0.89, y: CGFloat(size) * 0.61))
    spark.line(to: NSPoint(x: CGFloat(size) * 0.76, y: CGFloat(size) * 0.53))
    spark.line(to: NSPoint(x: CGFloat(size) * 0.79, y: CGFloat(size) * 0.38))
    spark.line(to: NSPoint(x: CGFloat(size) * 0.68, y: CGFloat(size) * 0.49))
    spark.line(to: NSPoint(x: CGFloat(size) * 0.54, y: CGFloat(size) * 0.43))
    spark.line(to: NSPoint(x: CGFloat(size) * 0.62, y: CGFloat(size) * 0.57))
    spark.close()
    spark.fill()

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }

    try png.write(to: url)
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for size in sizes {
    let image = drawIcon(size: size)
    try writePNG(image, to: outputDirectory.appendingPathComponent("icon_\(size).png"))
}
