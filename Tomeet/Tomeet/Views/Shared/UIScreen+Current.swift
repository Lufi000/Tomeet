import UIKit

extension UIScreen {
    /// iOS 26 起 `UIScreen.main` 弃用；按官方建议改从前台 window scene 取 screen
    /// （iPhone 单场景即唯一屏幕，多场景时取当前激活的那个）。
    static var current: UIScreen? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive })?.screen
            ?? scenes.first?.screen
    }
}
