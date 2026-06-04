import SwiftUI

// 押下フィードバック。iOS 26ではインタラクティブなLiquid Glass（.glassEffect(.regular.interactive())）
// 自体が純正の膨らみ・発光を担うため、ここでは何もしない。iOS 25以前のみ、自前で
// スケールアップ＋明度＋グローを付けて純正風のフィードバックを再現する。
struct PressEffectButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 1.1
    var glowColor: Color = .white
    var glowRadius: CGFloat = 8

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26, *) {
            configuration.label
        } else {
            configuration.label
                .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
                .brightness(configuration.isPressed ? 0.07 : 0)
                .shadow(
                    color: glowColor.opacity(configuration.isPressed ? 0.6 : 0),
                    radius: configuration.isPressed ? glowRadius : 0
                )
                .animation(.spring(response: 0.3, dampingFraction: 0.45), value: configuration.isPressed)
        }
    }
}
