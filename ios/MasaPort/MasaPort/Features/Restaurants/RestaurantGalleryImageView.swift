import SwiftUI

struct RestaurantGalleryImageView: View {
    let source: String

    var body: some View {
        Group {
            if let url = MPImageURL.variantURL(for: .media(source), role: .hero) {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    case .failure:
                        placeholder
                    case .empty:
                        placeholder.overlay { ProgressView().tint(.white.opacity(0.8)) }
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [MP.placeholderTop, MP.placeholderBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "photo")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(MP.placeholderSymbol)
        }
        .aspectRatio(4 / 3, contentMode: .fit)
    }
}
