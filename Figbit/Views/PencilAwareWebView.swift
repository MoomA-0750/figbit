import UIKit
import WebKit

class PencilAwareWebView: WKWebView {
    var pencilMode: PencilMode = .figurative {
        didSet { updateRightClickTouchType() }
    }

    // ロングプレスを右クリックに変換中は、進行中の左ポインタ操作（移動/離上）を抑制する。
    private var isRightClicking = false
    private weak var rightClickGesture: UILongPressGestureRecognizer?

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        setupRightClickGesture()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupRightClickGesture()
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let (injected, native) = split(touches)
        injected.forEach { injectPointerDown($0) }
        if !native.isEmpty { super.touchesBegan(Set(native), with: event) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let (injected, native) = split(touches)
        if !isRightClicking { injected.forEach { injectPointerMove($0) } }
        if !native.isEmpty { super.touchesMoved(Set(native), with: event) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let (injected, native) = split(touches)
        if isRightClicking {
            isRightClicking = false
        } else {
            injected.forEach { injectPointerUp($0) }
        }
        if !native.isEmpty { super.touchesEnded(Set(native), with: event) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        let (injected, native) = split(touches)
        if isRightClicking {
            isRightClicking = false
        } else {
            injected.forEach { injectPointerCancel($0) }
        }
        if !native.isEmpty { super.touchesCancelled(Set(native), with: event) }
    }

    // MARK: - Shortcut Injection

    func send(shortcut: ShortcutItem) {
        // まずFigma本体のキーハンドラへ合成keydownを送る（ツール切替・⌘Z等のキャンバス操作用）。
        dispatchSyntheticKey(shortcut)

        // ⌘C/⌘V/⌘X/⌘AはWKWebViewが継承するUIResponderの編集アクションにもルーティングする。
        // WebKit経由で信頼されたクリップボードイベントが発火し、テキスト選択時のみ実効。
        // レイヤー（DOM選択を持たないキャンバス操作）には効かない（合成では原理的に不可）。
        if shortcut.modifiers == [.cmd], let selector = Self.editActionSelector(for: shortcut.key) {
            UIApplication.shared.sendAction(selector, to: nil, from: self, for: nil)
        }
    }

    private func dispatchSyntheticKey(_ shortcut: ShortcutItem) {
        // 各モディファイアは末尾カンマ付きで連結する。未指定でも空文字になり構文エラーにならない。
        let mods = shortcut.modifiers.map { "\($0.jsKey): true, " }.joined()
        let js = """
        (function() {
            var t = document.activeElement || document.body;
            var kc = \(shortcut.keyCodeValue);
            var opts = {
                key: "\(shortcut.key)",
                code: "\(shortcut.jsKeyCode)",
                \(mods)bubbles: true, cancelable: true, composed: true, view: window
            };
            function fire(type) {
                var e = new KeyboardEvent(type, opts);
                // KeyboardEventコンストラクタはkeyCode/whichを無視し0になる。getterで上書きする。
                try {
                    Object.defineProperty(e, 'keyCode', { get: function() { return kc; } });
                    Object.defineProperty(e, 'which',   { get: function() { return kc; } });
                } catch (err) {}
                t.dispatchEvent(e);
            }
            fire('keydown');
            fire('keyup');
        })();
        """
        evaluateJavaScript(js, completionHandler: nil)
    }

    // ⌘C/⌘V/⌘X/⌘Aを、WKWebViewが継承するUIResponderの編集アクションへマッピングする。
    private static func editActionSelector(for key: String) -> Selector? {
        switch key.lowercased() {
        case "c": return #selector(UIResponderStandardEditActions.copy(_:))
        case "v": return #selector(UIResponderStandardEditActions.paste(_:))
        case "x": return #selector(UIResponderStandardEditActions.cut(_:))
        case "a": return #selector(UIResponderStandardEditActions.selectAll(_:))
        default: return nil
        }
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

    // MARK: - Right Click (long press)

    private func setupRightClickGesture() {
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleRightClickGesture(_:)))
        lp.minimumPressDuration = 0.4
        lp.delegate = self
        // WebKit内部のジェスチャを止めないよう、タッチをビューに通したまま認識させる。
        lp.cancelsTouchesInView = false
        addGestureRecognizer(lp)
        rightClickGesture = lp
        updateRightClickTouchType()
    }

    // カーソルとして振る舞う入力（figurative=ペン / touchCursor=指）のロングプレスのみ右クリックにする。
    // これにより figurative の指パンや touchCursor のペンと競合しない。
    private func updateRightClickTouchType() {
        let cursorType: UITouch.TouchType = pencilMode == .figurative ? .pencil : .direct
        rightClickGesture?.allowedTouchTypes = [NSNumber(value: cursorType.rawValue)]
    }

    @objc private func handleRightClickGesture(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        isRightClicking = true
        injectRightClick(at: g.location(in: self))
    }

    private func injectRightClick(at loc: CGPoint) {
        let js = """
        (function() {
            var x = \(loc.x), y = \(loc.y);
            var el = document.elementFromPoint(x, y) || document.body;
            var base = {
                clientX: x, clientY: y, screenX: x, screenY: y,
                bubbles: true, cancelable: true, composed: true, view: window
            };
            function pointer(type, props) {
                var o = Object.assign({ pointerId: 1, pointerType: 'mouse', isPrimary: true }, base, props);
                el.dispatchEvent(new PointerEvent(type, o));
            }
            function mouse(type, props) {
                el.dispatchEvent(new MouseEvent(type, Object.assign({}, base, props)));
            }
            // ロングプレス開始時に注入済みの左ポインタ押下を打ち切る。
            pointer('pointercancel', { button: 0, buttons: 0 });
            // 右ボタンの押下→離上→コンテキストメニュー。
            pointer('pointerdown', { button: 2, buttons: 2 });
            mouse('mousedown', { button: 2, buttons: 2 });
            mouse('mouseup', { button: 2, buttons: 0 });
            pointer('pointerup', { button: 2, buttons: 0 });
            mouse('contextmenu', { button: 2, buttons: 0 });
        })();
        """
        evaluateJavaScript(js, completionHandler: nil)
    }
}

extension PencilAwareWebView: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
