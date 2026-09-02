import Foundation

/// 免费额度状态:进入 AI Tab 时拉取,对话后由响应头本地更新(不重复请求)。
/// @MainActor 类隐式 Sendable,可安全捕获进 @Sendable 回调。
@MainActor
@Observable
final class QuotaService {
    /// 今日剩余次数;nil 表示尚未拉取/拉取失败(未知不阻塞对话)。
    private(set) var remaining: Int?
    /// 额度重置时间(次日 0 点,东八区)。
    private(set) var resetAt: Date?

    var isExhausted: Bool {
        guard let remaining else { return false }
        return remaining <= 0
    }

    private let baseURL: URL
    private let appToken: String
    private let deviceID: String
    private let session: URLSession

    init(baseURL: URL = URL(string: "https://tomeet-api.smallbeebee.com/v1/quota")!,
         appToken: String = Secrets.bffAppToken,
         deviceID: String = DeviceIDProvider().id,
         session: URLSession = .shared) {
        self.baseURL = baseURL
        self.appToken = appToken
        self.deviceID = deviceID
        self.session = session
    }

    private struct Status: Decodable {
        let remaining: Int
        let resetAt: String?
    }

    /// 从 BFF 拉取当日额度。失败保持现状,下次进入页面重试。
    func refresh() async {
        var request = URLRequest(url: baseURL)
        request.setValue(appToken, forHTTPHeaderField: "X-App-Token")
        request.setValue(deviceID, forHTTPHeaderField: "X-Device-ID")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let status = try? JSONDecoder().decode(Status.self, from: data)
        else { return }
        remaining = status.remaining
        resetAt = status.resetAt.flatMap { ISO8601DateFormatter().date(from: $0) }
    }

    /// 对话响应头 X-Quota-Remaining 的本地更新。
    func noteRemaining(_ value: Int) {
        remaining = value
    }

    /// 收到 429 时调用:标记用完并记录重置时间。
    func noteExhausted(resetAt: Date?) {
        remaining = 0
        if let resetAt { self.resetAt = resetAt }
    }
}
