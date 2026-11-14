// Local acceptance helper. Requires user-granted Accessibility permission.
// Coordinates are in desktop points. Never changes system permission settings.
import AppKit
import CoreGraphics
import Carbon

let args = CommandLine.arguments
func point(_ start: Int) -> CGPoint { CGPoint(x: Double(args[start])!, y: Double(args[start + 1])!) }
func post(_ type: CGEventType, _ p: CGPoint, button: CGMouseButton = .left, count: Int64 = 1) {
    let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: button)!
    event.setIntegerValueField(.mouseEventClickState, value: count)
    event.post(tap: .cghidEventTap)
}
switch args[1] {
case "input-source":
    let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    let identifier = Unmanaged<CFString>.fromOpaque(TISGetInputSourceProperty(current, kTISPropertyInputSourceID)).takeUnretainedValue() as String
    print(identifier)
    if args.count > 2 {
        let filter = [kTISPropertyInputSourceID as String: args[2]] as CFDictionary
        let sources = TISCreateInputSourceList(filter, false).takeRetainedValue() as NSArray
        guard let source = sources.firstObject else { exit(2) }
        guard TISSelectInputSource((source as! TISInputSource)) == noErr else { exit(3) }
    }
case "type":
    let units = Array(args[2].utf16)
    let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
    units.withUnsafeBufferPointer { down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: $0.baseAddress) }
    down.post(tap: .cghidEventTap)
    usleep(50_000)
    CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)!.post(tap: .cghidEventTap)
case "click":
    let p = point(2)
    post(.mouseMoved, p); post(.leftMouseDown, p); usleep(40_000); post(.leftMouseUp, p)
case "double":
    let p = point(2)
    post(.mouseMoved, p)
    for n: Int64 in 1...2 {
        post(.leftMouseDown, p, count: n); usleep(30_000)
        post(.leftMouseUp, p, count: n); usleep(60_000)
    }
case "right":
    let p = point(2)
    post(.rightMouseDown, p, button: .right); usleep(40_000)
    post(.rightMouseUp, p, button: .right)
case "drag":
    let from = point(2), to = point(4)
    post(.mouseMoved, from); post(.leftMouseDown, from); usleep(200_000)
    for n in 1...30 {
        let f = CGFloat(n) / 30
        post(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * f, y: from.y + (to.y - from.y) * f))
        usleep(20_000)
    }
    post(.leftMouseUp, to)
case "media-play", "media-next", "media-previous":
    let key = args[1] == "media-play" ? 16 : args[1] == "media-next" ? 17 : 18
    // Synthesized macOS media-key events: verifies the OS command path, not a physical keyboard.
    for state in [0xA, 0xB] {
        if let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil, subtype: 8, data1: (key << 16) | (state << 8), data2: -1) {
            event.cgEvent?.post(tap: .cghidEventTap)
        }
        usleep(80_000)
    }
case "windows":
    for w in CGWindowListCopyWindowInfo(.optionOnScreenOnly, 0) as? [[String: Any]] ?? [] {
        if (w[kCGWindowOwnerName as String] as? String ?? "").contains("Tom") {
            print(w[kCGWindowNumber as String] ?? "", w[kCGWindowName as String] ?? "")
        }
    }
default: fatalError("Usage: ui-input double|right x y; drag x y x y; windows")
}
