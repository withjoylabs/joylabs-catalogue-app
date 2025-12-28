import SwiftUI

/// AsyncImage replacement that uses custom URLSession with aggressive caching
/// Drop-in replacement for AsyncImage with identical API
struct CachedAsyncImage<Content: View>: View {
    let url: URL
    let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase = .empty

    init(url: URL, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.content = content
    }

    var body: some View {
        content(phase)
            .task(id: url) {
                await loadImage()
            }
    }

    @MainActor
    private func loadImage() async {
        // Check if already loading or loaded
        if case .success = phase {
            return
        }

        phase = .empty

        do {
            // Use custom URLSession with aggressive caching
            let urlSession = ImageCacheManager.shared.urlSession
            let (data, response) = try await urlSession.data(from: url)

            // Validate response
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                phase = .failure(URLError(.badServerResponse))
                return
            }

            // Convert to UIImage
            guard let uiImage = UIImage(data: data) else {
                phase = .failure(URLError(.cannotDecodeContentData))
                return
            }

            // Success - create SwiftUI Image
            let image = Image(uiImage: uiImage)
            phase = .success(image)

        } catch {
            phase = .failure(error)
        }
    }
}
