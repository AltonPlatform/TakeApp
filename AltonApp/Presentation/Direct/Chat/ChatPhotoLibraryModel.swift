import Photos
import SwiftUI

enum ChatAttachGrid {
    static func cellSide(containerWidth: CGFloat, columns: Int = 3, spacing: CGFloat = 2) -> CGFloat {
        guard columns > 0, containerWidth > 0 else { return 0 }
        let totalSpacing = spacing * CGFloat(columns - 1)
        return floor((containerWidth - totalSpacing) / CGFloat(columns))
    }

    static func thumbPixelSize(
        containerWidth: CGFloat,
        scale: CGFloat,
        columns: Int = 3,
        spacing: CGFloat = 2
    ) -> CGSize {
        let side = cellSide(containerWidth: containerWidth, columns: columns, spacing: spacing) * max(scale, 1)
        return CGSize(width: side, height: side)
    }
}

struct ChatPhotoAlbum: Identifiable, Equatable {
    let id: String
    let title: String

    static let recentsID = "recents"
}

/// Lazy PhotoKit fetch for the attach sheet. Album and asset fetches run off the main thread.
@Observable
final class ChatPhotoLibraryModel: NSObject, PHPhotoLibraryChangeObserver {
    let imageManager = PHCachingImageManager()

    private(set) var authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    private(set) var albums: [ChatPhotoAlbum] = [ChatPhotoAlbum(id: ChatPhotoAlbum.recentsID, title: "Recents")]
    private(set) var selectedAlbumID = ChatPhotoAlbum.recentsID
    private(set) var isLoadingAssets = false
    /// Bumped when PhotoKit replaces thumbnails in place. Cells reload; the grid is not remounted.
    private(set) var thumbReloadToken = 0
    private var fetchResult = PHFetchResult<PHAsset>()
    private var collections: [String: PHAssetCollection] = [:]
    private var isObserving = false
    private var loadGeneration = 0
    private var cacheTask: Task<Void, Never>?
    private var cachedAssets: [PHAsset] = []
    private var cachedPixelSize: CGSize = .zero

    var assetCount: Int { fetchResult.count }

    var selectedAlbumTitle: String {
        albums.first { $0.id == selectedAlbumID }?.title ?? "Recents"
    }

    var canReadLibrary: Bool {
        authorization == .authorized || authorization == .limited
    }

    func asset(at index: Int) -> PHAsset? {
        guard index >= 0, index < fetchResult.count else { return nil }
        return fetchResult.object(at: index)
    }

    func prepare() {
        authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if !isObserving {
            PHPhotoLibrary.shared().register(self)
            isObserving = true
        }
        guard canReadLibrary else { return }
        reloadOffMain()
    }

    func refreshAuthorization() {
        authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if canReadLibrary {
            reloadOffMain()
        } else {
            fetchResult = PHFetchResult()
            isLoadingAssets = false
            thumbReloadToken &+= 1
        }
    }

    func selectAlbum(_ id: String) {
        guard id != selectedAlbumID else { return }
        selectedAlbumID = id
        reloadOffMain()
    }

    func noteVisibleIndex(_ index: Int, pixelSize: CGSize) {
        cacheTask?.cancel()
        cacheTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(90))
            guard let self, !Task.isCancelled else { return }
            self.updateThumbnailCache(centerIndex: index, pixelSize: pixelSize)
        }
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        let details = changeInstance.changeDetails(for: fetchResult)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let details {
                self.fetchResult = details.fetchResultAfterChanges
                if !details.hasIncrementalChanges {
                    self.thumbReloadToken &+= 1
                }
            } else {
                self.reloadOffMain()
            }
        }
    }

    deinit {
        if isObserving {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
        }
    }

    private func reloadOffMain() {
        loadGeneration &+= 1
        let generation = loadGeneration
        let albumID = selectedAlbumID
        isLoadingAssets = true
        Task.detached { [weak self] in
            let loaded = ChatPhotoLibraryFetch.load(selectedAlbumID: albumID)
            await MainActor.run { [weak self] in
                guard let self, self.loadGeneration == generation else { return }
                self.albums = loaded.albums
                self.collections = loaded.collections
                if !loaded.albums.contains(where: { $0.id == self.selectedAlbumID }) {
                    self.selectedAlbumID = ChatPhotoAlbum.recentsID
                }
                self.fetchResult = loaded.assets
                self.isLoadingAssets = false
                self.imageManager.stopCachingImagesForAllAssets()
                self.cachedAssets = []
            }
        }
    }

    private func updateThumbnailCache(centerIndex: Int, pixelSize: CGSize) {
        let count = fetchResult.count
        guard count > 0, pixelSize.width > 1 else { return }
        let start = max(0, centerIndex - 18)
        let end = min(count, centerIndex + 36)
        var assets: [PHAsset] = []
        assets.reserveCapacity(end - start)
        for index in start..<end {
            assets.append(fetchResult.object(at: index))
        }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        if cachedPixelSize != pixelSize {
            imageManager.stopCachingImagesForAllAssets()
            cachedAssets = []
            cachedPixelSize = pixelSize
        } else if !cachedAssets.isEmpty {
            imageManager.stopCachingImages(
                for: cachedAssets,
                targetSize: pixelSize,
                contentMode: .aspectFill,
                options: options
            )
        }
        imageManager.startCachingImages(
            for: assets,
            targetSize: pixelSize,
            contentMode: .aspectFill,
            options: options
        )
        cachedAssets = assets
    }

}

private enum ChatPhotoLibraryFetch {
    struct Snapshot {
        var albums: [ChatPhotoAlbum]
        var collections: [String: PHAssetCollection]
        var assets: PHFetchResult<PHAsset>
    }

    static func load(selectedAlbumID: String) -> Snapshot {
        var albums: [ChatPhotoAlbum] = [ChatPhotoAlbum(id: ChatPhotoAlbum.recentsID, title: "Recents")]
        var collections: [String: PHAssetCollection] = [:]
        let smart = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .any,
            options: nil
        )
        smart.enumerateObjects { collection, _, _ in
            guard collection.assetCollectionSubtype == .smartAlbumFavorites
                    || collection.assetCollectionSubtype == .smartAlbumScreenshots else { return }
            let title = collection.localizedTitle ?? "Album"
            albums.append(ChatPhotoAlbum(id: collection.localIdentifier, title: title))
            collections[collection.localIdentifier] = collection
        }
        let user = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: nil
        )
        user.enumerateObjects { collection, _, _ in
            let title = collection.localizedTitle ?? "Album"
            albums.append(ChatPhotoAlbum(id: collection.localIdentifier, title: title))
            collections[collection.localIdentifier] = collection
        }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        let assets: PHFetchResult<PHAsset>
        if selectedAlbumID == ChatPhotoAlbum.recentsID {
            assets = PHAsset.fetchAssets(with: options)
        } else if let collection = collections[selectedAlbumID] {
            assets = PHAsset.fetchAssets(in: collection, options: options)
        } else {
            assets = PHFetchResult()
        }
        return Snapshot(albums: albums, collections: collections, assets: assets)
    }
}
