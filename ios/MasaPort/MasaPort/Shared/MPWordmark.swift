import SwiftUI

struct MPWordmark: View {
    var body: some View {
        Text("MasaPort")
            .font(.system(.headline, design: .rounded, weight: .bold))
            .tracking(-0.2)
            .foregroundStyle(MP.brand)
            .accessibilityLabel("MasaPort")
    }
}
