import ImageIO
import UIKit

/// 插图载荷：`NSTextAttachment` 上挂的「待加载」标记。
///
/// 分页阶段**不解码位图**，只把 `ImageRef` 挂上去；真正渲染时才解码。
/// 原因：`ReaderViewModel` 会一次性分页整本书并把所有页常驻内存。
/// 如果分页时就把 `UIImage` 塞进 attachment，附件会**直接强引用**位图，
/// 缓存条数上限完全拦不住 —— 图多的书直接把内存吃爆（实测跑全库集成测试时进程被 OOM 杀掉）。
struct BookImagePayload: Sendable, Equatable {
    let ref: ImageRef
    let baseURL: URL?
}

/// 按需加载书内插图。
enum BookImageLoader {
    /// 解码后的图片缓存。键含降采样尺寸，避免不同显示尺寸互相覆盖。
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 16
        return cache
    }()

    /// 尺寸缓存。改字号/边距会重新分页，每次都去读图片头是纯浪费。
    private static let sizeCache: NSCache<NSString, NSValue> = {
        let cache = NSCache<NSString, NSValue>()
        cache.countLimit = 256
        return cache
    }()

    /// 只读文件头拿像素尺寸，**不解码位图**。分页只需要尺寸来算排版。
    static func pixelSize(of ref: ImageRef, baseURL: URL?) -> CGSize? {
        guard let url = resolvedURL(for: ref, baseURL: baseURL) else { return nil }
        let key = url.path as NSString
        if let cached = sizeCache.object(forKey: key) { return cached.cgSizeValue }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0
        else { return nil }

        let size = CGSize(width: width, height: height)
        sizeCache.setObject(NSValue(cgSize: size), forKey: key)
        return size
    }

    /// 解码并降采样到 `maxPixelSize`。降采样很关键：
    /// 原图动辄几千像素宽，按屏幕实际需要解码能让单页内存降一到两个数量级。
    static func image(for ref: ImageRef, baseURL: URL?, maxPixelSize: CGFloat) -> UIImage? {
        guard let url = resolvedURL(for: ref, baseURL: baseURL) else { return nil }
        let key = "\(url.path)#\(Int(maxPixelSize))" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        let image = UIImage(cgImage: cgImage)
        cache.setObject(image, forKey: key)
        return image
    }

    private static func resolvedURL(for ref: ImageRef, baseURL: URL?) -> URL? {
        guard let baseURL else { return nil }
        let path = ref.path.removingPercentEncoding ?? ref.path
        return baseURL.appendingPathComponent(path)
    }
}
