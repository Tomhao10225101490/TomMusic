import AppKit

let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let s = CGFloat(size)
    let rect = NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.20, yRadius: s * 0.20)
    let gradient = NSGradient(starting: NSColor(calibratedRed: 1, green: 0.34, blue: 0.38, alpha: 1), ending: NSColor(calibratedRed: 0.88, green: 0.12, blue: 0.30, alpha: 1))!
    gradient.draw(in: path, angle: -70)
    // Own double-stem monogram: a music note with a T-shaped upper beam.
    let note = NSBezierPath()
    note.move(to: NSPoint(x: s * 0.47, y: s * 0.29))
    note.line(to: NSPoint(x: s * 0.47, y: s * 0.70))
    note.line(to: NSPoint(x: s * 0.76, y: s * 0.76))
    note.line(to: NSPoint(x: s * 0.76, y: s * 0.37))
    note.lineWidth = s * 0.055
    note.lineCapStyle = .round
    note.lineJoinStyle = .round
    NSColor.white.setStroke(); note.stroke()
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: s * 0.28, y: s * 0.22, width: s * 0.22, height: s * 0.14)).fill()
    NSBezierPath(ovalIn: NSRect(x: s * 0.57, y: s * 0.30, width: s * 0.22, height: s * 0.14)).fill()
    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let data = rep.representation(using: .png, properties: [:])!
    let names: [String]
    switch size {
    case 16: names = ["icon_16x16.png"]
    case 32: names = ["icon_16x16@2x.png", "icon_32x32.png"]
    case 64: names = ["icon_32x32@2x.png"]
    case 128: names = ["icon_128x128.png"]
    case 256: names = ["icon_128x128@2x.png", "icon_256x256.png"]
    case 512: names = ["icon_256x256@2x.png", "icon_512x512.png"]
    default: names = ["icon_512x512@2x.png"]
    }
    for name in names { try data.write(to: URL(fileURLWithPath: destination).appendingPathComponent(name)) }
}
