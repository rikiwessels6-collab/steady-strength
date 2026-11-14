import SwiftUI

/// Tide palette, dark-first: deep ocean ground (night), aqua for progress and actions (emerald), coral for highlights (gold).
/// The asset names are kept from the first palette so nothing else has to change.
extension Color {
    static let night = Color("Night")
    static let surface = Color("Surface")
    static let surfaceRaised = Color("SurfaceRaised")
    static let hairline = Color("Hairline")
    static let emerald = Color("Emerald")
    static let gold = Color("Gold")
    static let goldDeep = Color("GoldDeep")
    static let ink = Color("Ink")
    static let inkMuted = Color("InkMuted")
    /// A lighter aqua, for the far end of the main gradient.
    static let mint = Color(red: 0x7B / 255, green: 0xE3 / 255, blue: 0xD6 / 255)
}

extension LinearGradient {
    /// Main buttons and progress: aqua into a lighter aqua.
    static let brand = LinearGradient(colors: [.emerald, .mint], startPoint: .leading, endPoint: .trailing)
    static let night = LinearGradient(colors: [Color("SurfaceRaised"), Color("Night")], startPoint: .top, endPoint: .bottom)
}

/// A raised card on the night background.
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.hairline, lineWidth: 1))
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }

    /// Lists and forms on the night background.
    func themedList() -> some View {
        self.scrollContentBackground(.hidden)
            .background(Color.night.ignoresSafeArea())
            .listRowBackground(Color.surface)
    }
}

/// Thin emerald-to-gold progress bar.
struct BrandProgress: View {
    let value: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.hairline)
                Capsule().fill(LinearGradient.brand)
                    .frame(width: max(6, g.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 6)
        .animation(.snappy, value: value)
        .accessibilityElement()
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}
