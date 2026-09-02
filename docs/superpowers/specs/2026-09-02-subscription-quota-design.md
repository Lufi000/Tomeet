# Tomeet 订阅变现与配额体系设计

- 日期:2026-09-02
- 分支:`feat/subscription-design`
- 状态:已确认(需求逐条与作者对齐)

## 背景与目标

Tomeet 的 AI 对话(DeepSeek,经 BFF 代理)是目前**唯一消耗 token 的功能**
(`AIChatViewModel.send()` 是唯一入口;阅读、听书、讲书稿均为本地内容,零成本)。
当前所有用户共用一个硬编码 `X-App-Token`,无配额、无计费,BFF 仅有按 IP 限流。
风险:API 费用无上限;token 被抓包后可随意刷接口。

本设计分阶段解决:**第一期先上配额与成本熔断(不做订阅)**,第二期再接 StoreKit 2 订阅。

### 已确认的产品决策

| 决策点 | 结论 |
|---|---|
| 收费形态 | 订阅 + 免费额度;**第一期只实现免费额度 + 熔断,订阅延后** |
| 用户体系 | 无账号,设备 ID(`identifierForVendor`) |
| 免费额度 | 每设备每天 10 次 AI 对话,北京时间 0 点重置 |
| 大上下文分析 | 未来功能(发书内原文),订阅专属;免费档由 BFF 收紧请求体上限物理隔离 |
| 成本兜底 | BFF 全局每日请求数熔断(与身份无关,防 token 泄露被刷) |
| 配额适用范围 | 次数制,不限书;内置书/名著/用户自上传书共用同一额度 |

### 成本模型(定价依据)

- 现状小对话(书名+作者上下文,无正文):~¥0.01/轮,10 轮会话约 ¥0.1~0.2
- 免费额度上限成本:10 次/天 ≈ 每重度用户 ~¥3/月
- 未来大上下文分析:5~15K token/轮,~¥0.05~0.1
- 全局熔断(如 3000 次/天)≈ 每日成本硬顶 ~¥40,环境变量可调

## 总体架构

```
┌─ App ─────────────────────────────┐      ┌─ BFF(新增 SQLite 持久层)─────────┐
│ AIChatViewModel                    │      │ POST /v1/chat/completions        │
│   └─ QuotaService(新)              │────▶│   ① 验证 X-App-Token              │
│        · 请求带 X-Device-ID        │      │   ② 设备当日配额检查(SQLite)      │
│        · 解析 X-Quota-Remaining    │      │   ③ 全局日预算检查                │
│   └─ 额度 UI + 超额引导页          │      │   ④ 转发 DeepSeek,成功后计数      │
│ StoreKit 2 订阅(第二期)           │      │ GET  /v1/quota(新,查剩余)        │
└───────────────────────────────────┘      │ POST /v1/entitlement(第二期)     │
                                           └───────────────────────────────────┘
```

## 第一期:配额与熔断(本次实现)

### BFF

**持久层:纯 Go SQLite(`modernc.org/sqlite`)**

选型理由:无 CGO、单二进制部署不变;重启/崩溃不丢计数;第二期订阅状态
(`originalTransactionId → 权益`)反正需要持久层,第一期引入避免二次改造。
否决项:纯内存(重启熔断失效)、JSON 快照(并发/恢复逻辑自研,第二期还得换)。

数据路径默认 `/var/lib/tomeet-bff/quota.db`(环境变量 `QUOTA_DB_PATH` 可覆盖)。

**表结构**:

```sql
CREATE TABLE IF NOT EXISTS device_quota (
    device_id TEXT NOT NULL,
    day       TEXT NOT NULL,            -- 'YYYY-MM-DD',Asia/Shanghai
    count     INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (device_id, day)
);

CREATE TABLE IF NOT EXISTS global_budget (
    day   TEXT PRIMARY KEY,             -- 'YYYY-MM-DD',Asia/Shanghai
    count INTEGER NOT NULL DEFAULT 0
);
-- 第二期新增:entitlements 表(original_transaction_id, expires_at, ...)
```

**请求处理流程**(`HandleCompletions` 改造,顺序固定):

1. 验证 `X-App-Token`(现有逻辑不变;无 token 且 `AllowUnauthenticated` 时走现有 IP 限流)
2. 读 `X-Device-ID`;缺失或为空 → 400 `{"error":"device_id_required"}`
3. 查全局日预算:超限 → 503 `{"error":"service_unavailable"}`
4. 查设备当日配额:≥10 → 429 `{"error":"quota_exceeded","resetAt":"<次日0点 RFC3339>"}`
5. 转发 DeepSeek;**仅当上游返回 2xx 才计数**(设备 +1、全局 +1),上游报错不占额度。
   流式请求在上游返回 200 时即计数,流中途断线不退还(简单优先,损失可忽略)
6. 响应头回传 `X-Quota-Remaining: <n>`(流式与非流式都带,在 `WriteHeader` 之前设置)

**新端点 `GET /v1/quota`**(App 冷启动进入 AI Tab 时查询当日剩余):

- 同样需要 `X-App-Token` + `X-Device-ID`,缺失返回 400/401(语义同主端点)
- 响应:`{"remaining": <n>, "resetAt": "<次日0点 RFC3339>"}`
- 只读,不计数、不消耗全局预算

**配置**(环境变量,均有默认值):

| 变量 | 默认 | 说明 |
|---|---|---|
| `QUOTA_DB_PATH` | `./quota.db` | SQLite 路径,生产配 `/var/lib/tomeet-bff/quota.db` |
| `DAILY_FREE_QUOTA` | `10` | 每设备每日免费次数 |
| `DAILY_GLOBAL_BUDGET` | `3000` | 全局每日请求熔断 |

保留现有 `UNAUTH_RATE_LIMIT_PER_MINUTE` 按 IP 限流,与配额是两层独立防线。

### App

- **`DeviceIDProvider`**(新,`Services/`):读 `UIDevice.identifierForVendor`,
  注入 `DeepSeekChatService`,所有 AI 请求带 `X-Device-ID` header
- **`QuotaService`**(新,`Services/`):进入 AI Tab 时调 `GET /v1/quota` 拉当日剩余,
  对话后改用响应头 `X-Quota-Remaining` 本地更新(不重复请求);
  429 时解析 `resetAt`,向 UI 暴露"今日剩余 N 次 / 已用完,明日恢复"
- **额度 UI**(`AIAssistantView`):输入框旁显示"今日剩余 N 次";剩 ≤3 次时变强调色
- **超额引导页**(新):撞墙后展示——第一期文案"今日 10 次对话已用完,明天 0 点恢复",
  附一行"订阅版即将上线,敬请期待"。**不放任何购买按钮**(避免引导不存在的商品)
- **隐私合规**:`identifierForVendor` 属 App Store 隐私问卷 Device ID 项,
  需在 App Store Connect 声明(用途:App 功能;不关联用户身份;不用于追踪),
  并更新 `PRIVACY_POLICY.md` 说明设备标识仅用于免费额度计量

### 错误处理

| 场景 | BFF 行为 | App 行为 |
|---|---|---|
| 缺 device ID | 400 | 不会发生(App 必带);测试可触发 |
| 设备超额 | 429 + resetAt | 引导页,输入框禁用至次日 |
| 全局熔断 | 503 | toast "服务繁忙,请稍后再试",不占额度 |
| 上游失败 | 透传 5xx,不计数 | 现有错误文案 |
| SQLite 不可用 | 启动即 fatal(宁可停服也不裸奔) | — |

## 第二期:StoreKit 2 订阅(设计定型,本期不实现)

- **商品**:自动续期订阅两档——月 ¥18、年 ¥128(数字为暂定,上架前再定;可加 7 天试用)
- **App 端**:StoreKit 2 `Transaction.currentEntitlements` 本地判权益;
  自定义 paywall(免费额度撞墙页即转化入口);
  "恢复购买"走 StoreKit 标准流程(交易绑 Apple ID,换机/重装自动找回)
- **权益同步 BFF**:App 把签名交易 JWS 发 `POST /v1/entitlement`,
  BFF 验 Apple 签名链、提取 `originalTransactionId` 与到期时间存入
  `entitlements` 表;该设备后续请求配额标记为无限
- **大上下文分析**(发书内原文)作为订阅核心卖点开放:
  - BFF 对免费档把 `maxBodySize` 从 64KB 收紧到 8KB,物理上发不了整章原文
  - 转化路径:免费用户对自己上传的书得到泛泛答案 → 引导"订阅后我会读原文再回答"
- **远期**(不进第二期):App Store Server Notifications V2 处理退款/续费失败;
  Sign in with Apple 账号体系(若做安卓版再议)

## 测试

**BFF**(延续 `handler_test.go` 的 httptest 模式):

- 配额计数:成功请求 +1,上游 5xx 不计数
- 第 11 次请求返回 429 且响应体含 `resetAt`
- 跨日(伪造时钟或手动改 `day`)后配额重置
- 全局预算超限返回 503,且不区分设备
- 缺 `X-Device-ID` 返回 400
- `GET /v1/quota` 返回正确的 `remaining` 与 `resetAt`,且不计数
- 重启(SQLite 重开)后计数保留
- 响应头 `X-Quota-Remaining` 数值正确(流式与非流式)

**App**:

- `QuotaService` 单测:解析响应头 / 429 错误体(MockChatService 模式延续)
- `DeviceIDProvider`:返回非空且同设备稳定
- 额度 UI 与超额引导页:Preview 覆盖(剩余充足 / 剩 1 次 / 已用完三态)

## 不做的事(YAGNI)

- 第一期不做任何形式的付费 UI、StoreKit 接入
- 不做按 token 计费/熔断(请求数足够,解析 SSE usage 得不偿失)
- 不做账号体系、不做跨设备额度合并
- 不防"重装刷额度"(小规模可接受,不值得账号系统)
- 第二期不做退款/续费失败的服务器通知(远期再说)
