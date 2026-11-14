import SwiftUI
import UIKit
import ImageIO

/// Loads, downsamples and caches remote images (memory + the shared disk URL cache).
/// Species photos from iNaturalist are immutable, so cached copies stay valid offline.
actor ImagePipeline {
    static let shared = ImagePipeline()

    private let memory = NSCache<NSString, UIImage>()
    private var tasks: [String: Task<UIImage?, Never>] = [:]
    private let session: URLSession

    init() {
        memory.countLimit = 400
        memory.totalCostLimit = 120 * 1024 * 1024
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 400 * 1024 * 1024,
                                   directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("WildIDImages"))
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpAdditionalHeaders = ["User-Agent": HTTPClient.userAgent]
        session = URLSession(configuration: config)
    }

    func image(for url: URL, maxPixel: CGFloat) async -> UIImage? {
        let key = "\(url.absoluteString)#\(Int(maxPixel))"
        if let hit = memory.object(forKey: key as NSString) { return hit }
        if let task = tasks[key] { return await task.value }
        let task = Task<UIImage?, Never> { [session] in
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            guard let (data, _) = try? await session.data(for: request) else { return nil }
            return Self.downsample(data, maxPixel: maxPixel)
        }
        tasks[key] = task
        let image = await task.value
        tasks[key] = nil
        if let image {
            memory.setObject(image, forKey: key as NSString, cost: Int(image.size.width * image.size.height * image.scale * image.scale * 4))
        }
        return image
    }

    nonisolated static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        let thumbOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions) else { return nil }
        return UIImage(cgImage: cg)
    }

    func clear() {
        memory.removeAllObjects()
        session.configuration.urlCache?.removeAllCachedResponses()
    }
}

/// A remote image with a tasteful placeholder. `maxPixel` keeps memory low in long lists.
struct RemoteImage: View {
    let url: URL?
    var maxPixel: CGFloat = 400
    var placeholderSymbol: String = "leaf.fill"
    var tint: Color = Theme.fern
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                Rectangle()
                    .fill(tint.opacity(0.12))
                    .overlay {
                        Image(systemName: placeholderSymbol)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(tint.opacity(failed ? 0.5 : 0.35))
                    }
            }
        }
        .clipped()
        .task(id: url) {
            guard let url else { image = nil; return }
            let loaded = await ImagePipeline.shared.image(for: url, maxPixel: maxPixel)
            withAnimation(.easeOut(duration: 0.2)) {
                image = loaded
                failed = loaded == nil
            }
        }
    }
}
