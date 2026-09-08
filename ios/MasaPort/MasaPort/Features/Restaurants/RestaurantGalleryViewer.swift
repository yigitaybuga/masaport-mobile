import SwiftUI

struct RestaurantGalleryViewer: View {
    private enum Page: Hashable {
        case image(Int)
    }

    let images: [String]

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Page
    @State private var zoomScale: CGFloat = 1
    @State private var lastZoomScale: CGFloat = 1

    init(images: [String], initialIndex: Int) {
        self.images = images
        let clampedIndex = min(max(initialIndex, 0), max(images.count - 1, 0))
        _selection = State(initialValue: .image(clampedIndex))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selection) {
                ForEach(images.indices, id: \.self) { index in
                    RestaurantGalleryImageView(source: images[index])
                        .scaleEffect(selection == .image(index) ? zoomScale : 1)
                        .gesture(
                            MagnifyGesture()
                                .onChanged { value in
                                    guard selection == .image(index) else { return }
                                    zoomScale = min(max(lastZoomScale * value.magnification, 1), 4)
                                }
                                .onEnded { _ in
                                    guard selection == .image(index) else { return }
                                    lastZoomScale = zoomScale
                                }
                        )
                        .tag(Page.image(index))
                        .accessibilityLabel("Galeri fotoğrafı \(index + 1) / \(images.count)")
                        .accessibilityHint("Yakınlaştırmak için iki parmakla büyütün")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .automatic : .never))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
        .overlay(alignment: .topTrailing) {
            Button("Galeriyi kapat", systemImage: "xmark") {
                dismiss()
            }
            .labelStyle(.iconOnly)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .padding(16)
            .background(.black.opacity(0.45), in: Circle())
            .padding(.top, 12)
            .padding(.trailing, 16)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .onChange(of: selection) { _, _ in
            withAnimation(.easeOut(duration: 0.2)) {
                zoomScale = 1
                lastZoomScale = 1
            }
        }
    }
}
