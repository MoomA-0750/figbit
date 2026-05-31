import UIKit
import WebKit

class PencilAwareWebView: WKWebView {
    var pencilMode: PencilMode = .figurative

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let (injected, native) = split(touches)
        injected.forEach { injectPointerDown($0) }
        if !native.isEmpty { super.touchesBegan(Set(native), with: event) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let (injected, native) = split(touches)
        injected.forEach { injectPointerMove($0) }
        if !native.isEmpty { super.touchesMoved(Set(native), with: event) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let (injected, native) = split(touches)
        injected.forEach { injectPointerUp($0) }
        if !native.isEmpty { super.touchesEnded(Set(native), with: event) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        let (injected, native) = split(touches)
        injected.forEach { injectPointerCancel($0) }
        if !native.isEmpty { super.touchesCancelled(Set(native), with: event) }
    }

    // MARK: - Shortcut Injection

    func send(shortcut: ShortcutItem) {
        let mods = shortcut.modifiers.map { "\"\($0.jsKey)\": true" }.joined(separator: ", ")
        let js = """
        (function() {
            var t = document.activeElement || document.body;
            var opts = {
                key: "\(shortcut.key)",
                code: "\(shortcut.jsKeyCode)",
                \(mods),
                bubbles: true, cancelable: true
            };
            t.dispatchEvent(new KeyboardEvent('keydown', opts));
            t.dispatchEvent(new KeyboardEvent('keyup', opts));
        })();
        """
        evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Private

    private func split(_ touches: Set<UITouch>) -> (inject: [UITouch], native: [UITouch]) {
        let isInjectPencil = pencilMode == .figurative
        let inject = touches.filter { isInjectPencil ? $0.type == .pencil : $0.type != .pencil }
        let native = touches.filter { isInjectPencil ? $0.type != .pencil : $0.type == .pencil }
        return (Array(inject), Array(native))
    }

    private func injectPointerDown(_ touch: UITouch) { injectPointer(touch, type: "pointerdown") }
    private func injectPointerMove(_ touch: UITouch) { injectPointer(touch, type: "pointermove") }
    private func injectPointerUp(_ touch: UITouch) { injectPointer(touch, type: "pointerup") }
    private func injectPointerCancel(_ touch: UITouch) { injectPointer(touch, type: "pointercancel") }

    private func injectPointer(_ touch: UITouch, type: String) {
        let loc = touch.location(in: self)
        let pressure = touch.maximumPossibleForce > 0
            ? Double(touch.force / touch.maximumPossibleForce)
            : 0.5
        let js = """
        (function() {
            var el = document.elementFromPoint(\(loc.x), \(loc.y)) || document.body;
            el.dispatchEvent(new PointerEvent('\(type)', {
                pointerId: 1,
                pointerType: 'mouse',
                clientX: \(loc.x),
                clientY: \(loc.y),
                screenX: \(loc.x),
                screenY: \(loc.y),
                pressure: \(pressure),
                isPrimary: true,
                bubbles: true,
                cancelable: true,
                view: window
            }));
        })();
        """
        evaluateJavaScript(js, completionHandler: nil)
    }
}
