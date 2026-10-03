import Foundation
import Nuke

enum ImagePipelineConfig {
    static func configure() {
        let pipeline = ImagePipeline {
            $0.imageCache = ImageCache(
                costLimit: 50 * 1024 * 1024,
                countLimit: 200
            )

            do {
                let dataCache = try DataCache(name: "com.alton.image-data")
                dataCache.sizeLimit = 200 * 1024 * 1024
                $0.dataCache = dataCache
            } catch {
                // Fall back to memory-only if disk cache can't be created.
            }

            $0.dataCachePolicy = .automatic
        }
        ImagePipeline.shared = pipeline
    }

    static func clearMemoryCache() {
        ImagePipeline.shared.cache.removeAll()
    }
}
