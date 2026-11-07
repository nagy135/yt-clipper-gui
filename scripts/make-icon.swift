import AppKit

// Draw at every native size so the small Dock/Finder variants stay crisp.
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let variants = [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)]
for (base, scale) in variants {
    let size = base * scale
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let plate = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 206, yRadius: 206)
    NSColor(calibratedRed: 0.88, green: 0.20, blue: 0.16, alpha: 1).setFill()
    plate.fill()
    NSGradient(starting: NSColor.white.withAlphaComponent(0.16), ending: NSColor.black.withAlphaComponent(0.12))!.draw(in: plate, angle: -90)
    // A cream video tile, with crop marks and a cut through the playhead.
    let tile = NSBezierPath(roundedRect: NSRect(x: 218, y: 268, width: 588, height: 488), xRadius: 88, yRadius: 88)
    NSColor(calibratedRed: 1, green: 0.97, blue: 0.90, alpha: 1).setFill()
    tile.fill()
    let play = NSBezierPath()
    play.move(to: NSPoint(x: 445, y: 382)); play.line(to: NSPoint(x: 445, y: 642))
    play.line(to: NSPoint(x: 654, y: 512)); play.close()
    NSColor(calibratedRed: 0.85, green: 0.20, blue: 0.16, alpha: 1).setFill(); play.fill()
    let cut = NSBezierPath()
    cut.move(to: NSPoint(x: 310, y: 214)); cut.line(to: NSPoint(x: 310, y: 810))
    cut.lineWidth = 20
    cut.setLineDash([24, 22], count: 2, phase: 0)
    NSColor(calibratedRed: 0.30, green: 0.10, blue: 0.10, alpha: 0.65).setStroke(); cut.stroke()
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let filename = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
    try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(filename))
}
