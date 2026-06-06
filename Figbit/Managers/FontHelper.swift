import Foundation
import WebKit
import CoreText
import CoreGraphics

// 端末フォントをFigmaのWebアプリへ出すための橋渡し。
//
// 【経緯】最新のFigma Webは `https://figmadaemon.com:44960`（127.0.0.1へ解決する公開ドメイン＋
// 正規のCA署名TLS証明書）にフォントヘルパーを探しに行く。証明書の秘密鍵はFigmaしか持たないので
// ローカルHTTP/HTTPSサーバで成りすますことは不可能。さらにWebKitは https→http(loopback) を
// 混在コンテンツとして遮断する（Chromeのlocalhost例外が効かない）。
// そこでネットワークに出る前に、ページ内でfetch/XHRを乗っ取り、figmadaemon宛のリクエストを
// ネイティブ（CoreText）のデータで応答する。その応答を供給するのがこのクラス。
//
// JS（FigmaTab.fontBridgeScript）は `window.webkit.messageHandlers.figbitFontHelper.postMessage({op,...})`
// を await し、ここが replyHandler で値を返す（WKScriptMessageHandlerWithReply, iOS 14+）。
//
// プロトコル（github.com/neetly/figma-agent-linux 解析＋実機観測で確定）:
//   op "version"   -> {"package","version"}（ヘルパー検出プローブ）
//   op "font-files"-> {fontFiles:{<key>:[face...]}, modified_at, modified_fonts, package, version}
//   op "font-file" -> 指定キーのフォント実バイナリを base64 文字列で返す
//
// 【フォント実体の供給方法】kCTFontURLAttribute に依存しない。サンドボックスで実体ファイルが
// 読めないシステムフォントや、ファイルURLを返さないプロファイル導入フォントにも対応するため、
// CoreText が既にメモリに持っているフォントテーブル（CTFontCopyTable）から sfnt（TTF/OTF）を
// その場で再構築してバイト列を作る。一覧のキーには PostScript 名を使う（URL不要）。
final class FontHelper: NSObject, WKScriptMessageHandlerWithReply {
    static let shared = FontHelper()

    // Figmaが照合する定数。既知の動作実績があるagentと同じ値を使う。
    private static let package = "125.9.10"
    private static let version = 23

    private let queue = DispatchQueue(label: "figbit.fonthelper")
    // PostScript名（=font-filesのキー）-> そのフェイス
    private var facesByKey: [String: FontFace] = [:]
    private var loaded = false

    private override init() { super.init() }

    // 端末フォントを事前列挙しておく。アプリ起動時に呼ぶ。
    func start() {
        queue.async { [weak self] in
            self?.ensureLoaded()
        }
    }

    private func ensureLoaded() {
        guard !loaded else { return }
        loadFonts()
        loaded = true
        let families = Set(facesByKey.values.map { $0.family }).sorted()
        print("[FontHelper] loaded \(facesByKey.count) faces / \(families.count) families")
        print("[FontHelper] families: \(families.joined(separator: ", "))")
    }

    // MARK: - WKScriptMessageHandlerWithReply

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        guard message.name == "figbitFontHelper" else {
            replyHandler(nil, "unknown handler")
            return
        }
        guard let body = message.body as? [String: Any],
              let op = body["op"] as? String else {
            replyHandler(nil, "bad request")
            return
        }
        queue.async { [weak self] in
            guard let self else { replyHandler(nil, "gone"); return }
            self.ensureLoaded()
            switch op {
            case "version":
                replyHandler(["package": Self.package, "version": Self.version], nil)
            case "font-files":
                replyHandler(self.fontFilesPayload(), nil)
            case "font-file":
                guard let file = body["file"] as? String else {
                    replyHandler(nil, "missing file"); return
                }
                if let b64 = self.fontFileBase64(file) {
                    replyHandler(b64, nil)
                } else {
                    replyHandler(nil, "not found")
                }
            default:
                replyHandler(nil, "unknown op")
            }
        }
    }

    // MARK: - Payloads

    private func fontFilesPayload() -> [String: Any] {
        var fontFiles: [String: Any] = [:]
        for (key, face) in facesByKey {
            fontFiles[key] = [face.payload]
        }
        return [
            "fontFiles": fontFiles,
            "modified_at": NSNull(),
            "modified_fonts": NSNull(),
            "package": Self.package,
            "version": Self.version,
        ]
    }

    private func fontFileBase64(_ key: String) -> String? {
        guard let face = facesByKey[key] else { return nil }
        guard let data = Self.sfntData(for: face.descriptor) else {
            print("[FontHelper] cannot build sfnt: \(key)")
            return nil
        }
        return data.base64EncodedString()
    }

    // MARK: - Font enumeration

    private func loadFonts() {
        let collection = CTFontCollectionCreateFromAvailableFonts(nil)
        guard let descriptors = CTFontCollectionCreateMatchingFontDescriptors(collection) as? [CTFontDescriptor] else { return }

        var map: [String: FontFace] = [:]
        for desc in descriptors {
            guard let face = FontFace(descriptor: desc) else { continue }
            // PostScript名が衝突する場合は先勝ち。
            if map[face.key] == nil { map[face.key] = face }
        }
        facesByKey = map
    }

    // MARK: - sfnt reconstruction

    // CoreTextが保持するフォントテーブルから sfnt（TTF/OTF）コンテナを組み立てる。
    // ファイル実体の読み取り権限が無くても、メモリ上のフォントからバイト列を生成できる。
    static func sfntData(for descriptor: CTFontDescriptor) -> Data? {
        let font = CTFontCreateWithFontDescriptor(descriptor, 0, nil)
        let opts = CTFontTableOptions(rawValue: 0)
        guard let tagsArray = CTFontCopyAvailableTables(font, opts) else { return nil }
        let count = CFArrayGetCount(tagsArray)
        guard count > 0 else { return nil }

        var tables: [(tag: UInt32, bytes: [UInt8])] = []
        for i in 0..<count {
            let raw = CFArrayGetValueAtIndex(tagsArray, i)
            let tag = UInt32(truncatingIfNeeded: UInt(bitPattern: raw))
            guard let cfData = CTFontCopyTable(font, CTFontTableTag(tag), opts) else { continue }
            tables.append((tag, [UInt8](cfData as Data)))
        }
        guard !tables.isEmpty else { return nil }
        return buildSfnt(tables: tables)
    }

    private static func tag(_ s: String) -> UInt32 {
        let b = Array(s.utf8)
        return (UInt32(b[0]) << 24) | (UInt32(b[1]) << 16) | (UInt32(b[2]) << 8) | UInt32(b[3])
    }

    private static func sfntChecksum(_ bytes: [UInt8], from: Int = 0, count: Int? = nil) -> UInt32 {
        let n = count ?? (bytes.count - from)
        var sum: UInt32 = 0
        var i = 0
        while i < n {
            var word: UInt32 = 0
            for j in 0..<4 {
                let idx = from + i + j
                let byte: UInt32 = (i + j < n) ? UInt32(bytes[idx]) : 0
                word = (word << 8) | byte
            }
            sum = sum &+ word
            i += 4
        }
        return sum
    }

    private static func appendU32(_ a: inout [UInt8], _ v: UInt32) {
        a.append(UInt8((v >> 24) & 0xFF)); a.append(UInt8((v >> 16) & 0xFF))
        a.append(UInt8((v >> 8) & 0xFF));  a.append(UInt8(v & 0xFF))
    }
    private static func appendU16(_ a: inout [UInt8], _ v: UInt16) {
        a.append(UInt8((v >> 8) & 0xFF)); a.append(UInt8(v & 0xFF))
    }

    private static func buildSfnt(tables rawTables: [(tag: UInt32, bytes: [UInt8])]) -> Data {
        let tables = rawTables.sorted { $0.tag < $1.tag }
        let numTables = tables.count

        let hasCFF = tables.contains { $0.tag == tag("CFF ") }
        let sfntVersion: UInt32 = hasCFF ? 0x4F54544F /* 'OTTO' */ : 0x00010000

        var maxPow2 = 1, entrySelector: UInt16 = 0
        while maxPow2 * 2 <= numTables { maxPow2 *= 2; entrySelector += 1 }
        let searchRange = UInt16(maxPow2 * 16)
        let rangeShift = UInt16(truncatingIfNeeded: numTables * 16) &- searchRange

        let recordsSize = numTables * 16
        let dataStart = 12 + recordsSize

        // 本体（テーブルデータ＋4バイト境界パディング）を組み立てつつ、各テーブルの
        // オフセット・チェックサムを記録する。headテーブルの本体内位置も覚えておく。
        var body: [UInt8] = []
        var records: [(tag: UInt32, checksum: UInt32, offset: Int, length: Int)] = []
        var headBodyOffset: Int? = nil
        var offset = dataStart
        for t in tables {
            if t.tag == tag("head") { headBodyOffset = body.count }
            records.append((t.tag, sfntChecksum(t.bytes), offset, t.bytes.count))
            body.append(contentsOf: t.bytes)
            let pad = (4 - (t.bytes.count % 4)) % 4
            if pad > 0 { body.append(contentsOf: repeatElement(0, count: pad)) }
            offset += t.bytes.count + pad
        }

        var font: [UInt8] = []
        appendU32(&font, sfntVersion)
        appendU16(&font, UInt16(numTables))
        appendU16(&font, searchRange)
        appendU16(&font, entrySelector)
        appendU16(&font, rangeShift)
        for r in records {
            appendU32(&font, r.tag)
            appendU32(&font, r.checksum)
            appendU32(&font, UInt32(r.offset))
            appendU32(&font, UInt32(r.length))
        }
        font.append(contentsOf: body)

        // head.checkSumAdjustment（headテーブル先頭から8バイト目）を正しく埋める。
        if let hb = headBodyOffset {
            let adjPos = (12 + recordsSize) + hb + 8
            if adjPos + 4 <= font.count {
                font[adjPos] = 0; font[adjPos+1] = 0; font[adjPos+2] = 0; font[adjPos+3] = 0
                let total = sfntChecksum(font)
                let adjustment = 0xB1B0AFBA &- total
                font[adjPos]   = UInt8((adjustment >> 24) & 0xFF)
                font[adjPos+1] = UInt8((adjustment >> 16) & 0xFF)
                font[adjPos+2] = UInt8((adjustment >> 8) & 0xFF)
                font[adjPos+3] = UInt8(adjustment & 0xFF)
            }
        }
        return Data(font)
    }
}

// MARK: - FontFace

private struct FontFace {
    let key: String      // PostScript名（font-filesのキー兼 font-file の参照子）
    let family: String
    let style: String
    let postscript: String
    let weight: Int      // OS/2 usWeightClass 100...900
    let stretch: Int     // OS/2 usWidthClass 1...9
    let italic: Bool
    let modifiedAt: UInt64
    let descriptor: CTFontDescriptor

    init?(descriptor desc: CTFontDescriptor) {
        let family = CTFontDescriptorCopyAttribute(desc, kCTFontFamilyNameAttribute) as? String
        let style = CTFontDescriptorCopyAttribute(desc, kCTFontStyleNameAttribute) as? String
        let psName = CTFontDescriptorCopyAttribute(desc, kCTFontNameAttribute) as? String
        guard let family, let psName else { return nil }
        self.descriptor = desc
        self.key = psName
        self.family = family
        self.style = style ?? "Regular"
        self.postscript = psName

        var weightTrait: CGFloat = 0
        var widthTrait: CGFloat = 0
        var symbolic: CTFontSymbolicTraits = []
        if let traits = CTFontDescriptorCopyAttribute(desc, kCTFontTraitsAttribute) as? [CFString: Any] {
            if let n = traits[kCTFontWeightTrait] as? NSNumber { weightTrait = CGFloat(n.doubleValue) }
            if let n = traits[kCTFontWidthTrait] as? NSNumber { widthTrait = CGFloat(n.doubleValue) }
            if let n = traits[kCTFontSymbolicTrait] as? NSNumber {
                symbolic = CTFontSymbolicTraits(rawValue: n.uint32Value)
            }
        }
        weight = FontFace.usWeightClass(fromTrait: weightTrait)
        stretch = FontFace.usWidthClass(fromTrait: widthTrait)
        italic = symbolic.contains(.traitItalic)
        modifiedAt = 0
    }

    var payload: [String: Any] {
        [
            "family": family,
            "style": style,
            "postscript": postscript,
            "weight": weight,
            "stretch": stretch,
            "italic": italic,
            "modified_at": modifiedAt,
            "user_installed": true,
        ]
    }

    // CoreTextの正規化weight(-1...1)をOS/2 usWeightClass(100...900)へ最近傍で割り当てる。
    static func usWeightClass(fromTrait t: CGFloat) -> Int {
        let anchors: [(CGFloat, Int)] = [
            (-0.8, 100), (-0.6, 200), (-0.4, 300), (0.0, 400),
            (0.23, 500), (0.3, 600), (0.4, 700), (0.56, 800), (0.62, 900),
        ]
        var best = anchors[0]
        for a in anchors where abs(a.0 - t) < abs(best.0 - t) { best = a }
        return best.1
    }

    // 正規化width(-1...1)をusWidthClass(1...9, 5=normal)へ。
    static func usWidthClass(fromTrait t: CGFloat) -> Int {
        min(9, max(1, Int((t * 4).rounded()) + 5))
    }
}
