import UIKit

/// 免费配额用的设备标识。identifierForVendor 在同厂商 App 间稳定,
/// 卸载全部同厂商 App 重装后会变化(可接受,见 spec「不做的事」)。
struct DeviceIDProvider: Sendable {
    var id: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    }
}
