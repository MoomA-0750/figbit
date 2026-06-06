import UIKit
import WebKit

class PencilAwareWebView: WKWebView {
    var pencilMode: PencilMode = .figurative {
        didSet { updateRightClickTouchType() }
    }

    // ロングプレスを右クリックに変換中は、進行中の左ポインタ操作（移動/離上）を抑制する。
    private var isRightClicking = false
    private weak var rightClickGesture: UILongPressGestureRecognizer?

    // 修飾キーホールドボタンがアクティブな間、全タッチをインジェクションに切り替えてフラグを付与する。
    var activeModifiers: Set<ShortcutItem.KeyModifier> = []

    // 修飾キー保持中だけCanvasに被せる透明オーバーレイ。WebKitにtouchを一切渡さず、
    // 捕捉した指座標を pointerType:'mouse' として注入することで、Figmaのマウス経路に乗せる
    // （ネイティブtouchによるピンチ／touch経路のAlt無視を根絶する）。
    private weak var modifierOverlay: ModifierTouchOverlay?

    // スクイーズ通知用：直近のペン先位置（自分座標系）
    private(set) var lastPencilLocation: CGPoint = CGPoint(x: 200, y: 400)

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        setupRightClickGesture()
        setupPencilInteraction()
        setupHoverTracking()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupRightClickGesture()
        setupPencilInteraction()
        setupHoverTracking()
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let t = touches.first(where: { $0.type == .pencil }) {
            lastPencilLocation = t.location(in: self)
        }
        // 修飾キーがアクティブな時は全タッチをインジェクションに回してフラグを付与する。
        // ネイティブに渡すとWKWebViewが modifier なしのポインタイベントを生成してしまうため。
        guard activeModifiers.isEmpty else {
            touches.forEach { injectPointerDown($0) }
            return
        }
        let (injected, native) = split(touches)
        injected.forEach { injectPointerDown($0) }
        if !native.isEmpty { super.touchesBegan(Set(native), with: event) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let t = touches.first(where: { $0.type == .pencil }) {
            lastPencilLocation = t.location(in: self)
        }
        guard activeModifiers.isEmpty else {
            if !isRightClicking { touches.forEach { injectPointerMove($0) } }
            return
        }
        let (injected, native) = split(touches)
        if !isRightClicking { injected.forEach { injectPointerMove($0) } }
        if !native.isEmpty { super.touchesMoved(Set(native), with: event) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeModifiers.isEmpty else {
            if isRightClicking { isRightClicking = false } else { touches.forEach { injectPointerUp($0) } }
            return
        }
        let (injected, native) = split(touches)
        if isRightClicking {
            isRightClicking = false
        } else {
            injected.forEach { injectPointerUp($0) }
        }
        if !native.isEmpty { super.touchesEnded(Set(native), with: event) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeModifiers.isEmpty else {
            if isRightClicking { isRightClicking = false } else { touches.forEach { injectPointerCancel($0) } }
            return
        }
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

    func activateModifier(_ modifier: ShortcutItem.KeyModifier) {
        let wasEmpty = activeModifiers.isEmpty
        activeModifiers.insert(modifier)
        // スクロール無効化：WKWebViewのパンジェスチャーが touchesCancelled を呼んで
        // pointermove が届かなくなるのを防ぐ（実機用）。
        scrollView.isScrollEnabled = false
        if wasEmpty { showModifierOverlay() }
        dispatchModifierEvent("keydown", modifier: modifier)
        syncModifierPatchJS()
    }

    func deactivateModifier(_ modifier: ShortcutItem.KeyModifier) {
        activeModifiers.remove(modifier)
        if activeModifiers.isEmpty {
            scrollView.isScrollEnabled = true
            removeModifierOverlay()
        }
        dispatchModifierEvent("keyup", modifier: modifier)
        syncModifierPatchJS()
    }

    // MARK: - Modifier Touch Overlay

    private func showModifierOverlay() {
        guard modifierOverlay == nil else { return }
        let overlay = ModifierTouchOverlay()
        overlay.webView = self
        overlay.frame = bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.backgroundColor = .clear
        // scrollView より前面に被せ、WebKit のコンテンツビューに touch を届かせない。
        addSubview(overlay)
        modifierOverlay = overlay
        // ピンチ用ジェスチャーは祖先（scrollView）に付いており、オーバーレイ上の touch も
        // 配送されてしまうため、保持中は明示的に無効化して二本指ズームを止める。
        scrollView.pinchGestureRecognizer?.isEnabled = false
    }

    private func removeModifierOverlay() {
        modifierOverlay?.removeFromSuperview()
        modifierOverlay = nil
        scrollView.pinchGestureRecognizer?.isEnabled = true
    }

    // オーバーレイから転送される touch を注入する。座標は WKWebView 基準（CSS px と一致）。
    fileprivate func overlayInject(_ touch: UITouch, type: String) {
        injectPointer(touch, type: type)
    }

    // タップ（移動なし）の時に呼ぶ。クリック選択（Shift+クリックの複数選択など）は
    // pointerup だけでは成立せず、mousedown/mouseup/click の MouseEvent が必要なため。
    fileprivate func overlayInjectClick(_ touch: UITouch) {
        let loc = touch.location(in: self)
        let modFlags = activeModifiers.map { "\($0.jsKey): true," }.joined(separator: " ")
        let js = """
        (function() {
            var x = \(loc.x), y = \(loc.y);
            var el = document.elementFromPoint(x, y) || document.body;
            var base = {
                clientX: x, clientY: y, screenX: x, screenY: y,
                \(modFlags)bubbles: true, cancelable: true, composed: true, view: window
            };
            function mouse(type, props) {
                el.dispatchEvent(new MouseEvent(type, Object.assign({}, base, props)));
            }
            mouse('mousedown', { button: 0, buttons: 1 });
            mouse('mouseup',   { button: 0, buttons: 0 });
            mouse('click',     { button: 0, buttons: 0, detail: 1 });
        })();
        """
        evaluateJavaScript(js, completionHandler: nil)
    }

    // シミュレーターでは NSEvent がそのまま WKWebView に渡るため touchesBegan が通らない。
    // JS のキャプチャフェーズでネイティブポインターイベントの modifier フラグを上書きする。
    private func syncModifierPatchJS() {
        let activeKeysJS = activeModifiers.map { "'\($0.jsKey)'" }.joined(separator: ",")
        // getModifierState が参照する内部スロットは defineProperty で書き換えられないため、
        // メソッド自体をプロトタイプで上書きして active な修飾キーに true を返させる。
        let activeStatesJS = activeModifiers.map { "'\($0.keyName)'" }.joined(separator: ",")
        let js = """
        (function() {
            // getModifierState をプロトタイプで上書きし、active な修飾キーに true を返させる。
            // Figma は e.altKey ではなく e.getModifierState('Alt') を読むため、これが本命の修正。
            if (!window.__figbitGmsPatch) {
                window.__figbitGmsPatch = true;
                [window.PointerEvent, window.MouseEvent, window.KeyboardEvent, window.WheelEvent].forEach(function(Ctor) {
                    if (!Ctor || !Ctor.prototype || !Ctor.prototype.getModifierState) return;
                    var orig = Ctor.prototype.getModifierState;
                    Ctor.prototype.getModifierState = function(key) {
                        var states = window.__figbitActiveModStates;
                        if (states && states.indexOf(key) !== -1) return true;
                        return orig.call(this, key);
                    };
                });
            }

            if (!window.__figbitModPatch) {
                function patch(e) {
                    var keys = window.__figbitActiveModKeys;
                    var active = keys && keys.length;
                    // 修飾キー保持中はネイティブの touch イベントを Figma に渡さない。
                    // Figma の touch 入力パスは修飾キーリサイズ非対応＆二本指でピンチになるため、
                    // capture 段階で伝播を止め、注入した pointerType:'mouse' イベントだけを通す。
                    if (active && (e.pointerType === 'touch'
                        || e.type.indexOf('touch') === 0)) {
                        e.stopImmediatePropagation();
                        if (e.cancelable) e.preventDefault();
                        return;
                    }
                    if (active) {
                        keys.forEach(function(k) {
                            try { Object.defineProperty(e, k, {value: true, configurable: true, writable: true}); } catch(x) {}
                        });
                    }
                }
                ['pointerdown','pointermove','pointerup','pointercancel',
                 'mousedown','mousemove','mouseup',
                 'touchstart','touchmove','touchend','touchcancel'].forEach(function(t) {
                    document.addEventListener(t, patch, true);
                });
                window.__figbitModPatch = patch;
            }
            window.__figbitActiveModKeys = [\(activeKeysJS)];
            window.__figbitActiveModStates = [\(activeStatesJS)];
        })();
        """
        evaluateJavaScript(js, completionHandler: nil)
    }

    private func dispatchModifierEvent(_ type: String, modifier: ShortcutItem.KeyModifier) {
        let kc = modifier.legacyKeyCode
        let js = """
        (function() {
            var t = document.activeElement || document.body;
            var e = new KeyboardEvent('\(type)', {
                key: "\(modifier.keyName)", code: "\(modifier.jsCode)",
                \(modifier.jsKey): true,
                bubbles: true, cancelable: true, composed: true, view: window
            });
            try {
                Object.defineProperty(e, 'keyCode', { get: function() { return \(kc); } });
                Object.defineProperty(e, 'which',   { get: function() { return \(kc); } });
            } catch(err) {}
            t.dispatchEvent(e);
        })();
        """
        evaluateJavaScript(js, completionHandler: nil)
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
        let modFlags = activeModifiers.map { "\($0.jsKey): true," }.joined(separator: " ")

        // pointerdown の直前だけ keydown を再送する。WKWebView がフォーカスを失った際に
        // Figma が modifier state をリセットしても、ドラッグ開始時点で確実に反映させるため。
        let modKeydownsJS: String
        if type == "pointerdown", !activeModifiers.isEmpty {
            modKeydownsJS = activeModifiers.map { mod in
                let kc = mod.legacyKeyCode
                return """
                    (function(){
                        var e = new KeyboardEvent('keydown', {
                            key: "\(mod.keyName)", code: "\(mod.jsCode)",
                            \(mod.jsKey): true,
                            bubbles: true, cancelable: true, composed: true, view: window
                        });
                        try {
                            Object.defineProperty(e,'keyCode',{get:function(){return \(kc);}});
                            Object.defineProperty(e,'which',  {get:function(){return \(kc);}});
                        } catch(err) {}
                        el.dispatchEvent(e);
                    })();
                """
            }.joined()
        } else {
            modKeydownsJS = ""
        }

        let js = """
        (function() {
            var el = document.elementFromPoint(\(loc.x), \(loc.y)) || document.body;
            \(modKeydownsJS)
            el.dispatchEvent(new PointerEvent('\(type)', {
                pointerId: 1,
                pointerType: 'mouse',
                clientX: \(loc.x),
                clientY: \(loc.y),
                screenX: \(loc.x),
                screenY: \(loc.y),
                pressure: \(pressure),
                isPrimary: true,
                \(modFlags)bubbles: true,
                cancelable: true,
                view: window
            }));
        })();
        """
        evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Pencil Interaction (squeeze / double tap)

    private func setupPencilInteraction() {
        let interaction = UIPencilInteraction()
        interaction.delegate = self
        addInteraction(interaction)
    }

    // ペンのホバー位置を継続追跡する。スクイーズ/ダブルタップ時はペンが画面に触れていない
    // （タッチイベントが来ない）ため、ホバーで現在位置を掴んでおく必要がある。
    private func setupHoverTracking() {
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
        hover.delegate = self
        hover.cancelsTouchesInView = false
        addGestureRecognizer(hover)
    }

    @objc private func handleHover(_ g: UIHoverGestureRecognizer) {
        lastPencilLocation = g.location(in: self)
    }

    fileprivate func notifyPencilAction() {
        // UIWindow座標に変換して渡す（GeometryReaderとの座標系を合わせるため）
        let windowLoc = convert(lastPencilLocation, to: nil)
        NotificationCenter.default.post(
            name: .figbitPencilAction,
            object: nil,
            userInfo: ["windowLocation": windowLoc]
        )
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

extension PencilAwareWebView: UIPencilInteractionDelegate {
    // Apple Pencil Pro (iOS 17.5+): スクイーズで発火
    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        guard squeeze.phase == .ended else { return }
        notifyPencilAction()
    }

    // 2nd gen Apple Pencil: ダブルタップで発火
    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        notifyPencilAction()
    }
}

extension Notification.Name {
    static let figbitPencilAction = Notification.Name("figbit.pencilAction")
}

// 修飾キー保持中だけWKWebViewの最前面に被さり、WebKitに一切touchを渡さず、
// 単一の指（プライマリタッチ）だけを pointerType:'mouse' として注入する。
// これによりFigmaはマウス経路で処理し、Altリサイズ等が効き、二本指ピンチも発生しない。
private final class ModifierTouchOverlay: UIView {
    weak var webView: PencilAwareWebView?
    // 複数指の同時注入（pointerId衝突）と誤ピンチを避けるため、1本目だけを追従する。
    private weak var primaryTouch: UITouch?
    // タップ（クリック選択）とドラッグ（リサイズ等）を区別するため、開始位置と移動有無を持つ。
    private var startLocation: CGPoint = .zero
    private var didMove = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard primaryTouch == nil, let t = touches.first else { return }
        primaryTouch = t
        startLocation = t.location(in: self)
        didMove = false
        webView?.overlayInject(t, type: "pointerdown")
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = primaryTouch, touches.contains(t) else { return }
        let loc = t.location(in: self)
        if hypot(loc.x - startLocation.x, loc.y - startLocation.y) > 5 { didMove = true }
        webView?.overlayInject(t, type: "pointermove")
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = primaryTouch, touches.contains(t) else { return }
        webView?.overlayInject(t, type: "pointerup")
        // 移動していなければクリック（選択）。mousedown/mouseup/click を追加で注入する。
        if !didMove { webView?.overlayInjectClick(t) }
        primaryTouch = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = primaryTouch, touches.contains(t) else { return }
        webView?.overlayInject(t, type: "pointercancel")
        primaryTouch = nil
    }
}
