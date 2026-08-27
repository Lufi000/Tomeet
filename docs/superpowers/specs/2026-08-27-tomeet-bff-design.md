# Tomeet BFF 代理设计

日期：2026-08-27
状态：已确认（2026-08-27，用户口头批准）

## 背景

Tomeet 的 AI Tab 目前直连 DeepSeek 官方 API，key 打进 App 包，可被提取滥用。参照 CycleAdvisor 已验证的方案，搭建独立 BFF 代理：App 持共享密钥（X-App-Token）访问自家代理，代理转发 DeepSeek，API key 只存在服务端。

CycleAdvisor 的 BFF 实现（`cycle_advisor-main/bff/`，Go，约 250 行）已在生产环境运行，同机还运行 slowtalk-bff、zhiji-bff、zhuofan-recipe-bff，形成固定模式：每应用一个独立 BFF 进程 + 独立偶数端口 + systemd 单元 + Nginx Proxy Manager 反代 + Let's Encrypt。

## 架构

```
iOS App ──X-App-Token──► tomeet-api.smallbeebee.com (NPM + Let's Encrypt)
                              │ proxy_pass (proxy_buffering off)
                              ▼
                        tomeet-bff (Go, :8088, systemd /opt/tomeet-bff)
                              │ Authorization: Bearer <DeepSeek key>
                              ▼
                        api.deepseek.com/v1/chat/completions
```

## 组件

### 1. Go 服务（Tomeet 仓库新增 `bff/`）

照搬 cycle_advisor/bff，仅改以下内容：

- module 名 `tomeet-bff`
- 监听端口 `LISTEN_ADDR` 默认 `:8088`
- systemd 单元 `tomeet-bff.service`，部署目录 `/opt/tomeet-bff`

保留的功能（行为与 CycleAdvisor BFF 一致）：

- `POST /v1/chat/completions`：校验 `X-App-Token`（环境变量 `APP_TOKEN`，单 token 即可）；body 上限 64KB；peek `stream` 字段，流式请求以 SSE 逐行透传（flush），非流式原样转发 JSON；上游超时 180s
- `GET /health`：返回 `{"status":"ok"}`
- `ALLOW_UNAUTHENTICATED_APP` 默认关闭（Tomeet 不需要）
- `deploy.sh`：交叉编译 linux/amd64 → workbench 上传 → 备份旧二进制 → systemctl 重启 → 验证启动日志和 health URL
- `.env.example`：`DEEPSEEK_API_KEY` / `APP_TOKEN` / `LISTEN_ADDR`

测试：`bff/handler_test.go`，用 httptest 覆盖：
- 无 token / 错 token → 401
- 正确 token 且 `stream:false` → 转发并回写响应
- `stream:true` → SSE 透传
- body 超过 64KB → 413

上游用 httptest.Server 替代真实 DeepSeek，测试不依赖外网。

### 2. App 侧改动（Tomeet iOS）

- `DeepSeekChatService` 泛化为 BFF 客户端：
  - `baseURL` 默认 `https://tomeet-api.smallbeebee.com/v1/chat/completions`
  - 请求头从 `Authorization: Bearer <key>` 改为 `X-App-Token: <token>`
  - SSE 解析、system prompt、错误处理不变
- `Secrets.swift`（gitignored）：删除 `deepSeekAPIKey`，改为 `bffAppToken`
- `Secrets.swift.template` 同步更新
- `AIChatViewModel` 默认服务仍是 `DeepSeekChatService()`，初始化签名不变（UI 零改动）
- 更新 `DeepSeekChatServiceTests` 断言：新 header、新 URL

### 3. 基础设施（用户手动两步 + Claude 部署）

用户手动（无控制台权限）：

1. 阿里云 DNS 控制台加 A 记录：`tomeet-api` → ECS 公网 IP
2. Nginx Proxy Manager（`http://<ECS IP>:5003`）加 Proxy Host：
   - Domain: `tomeet-api.smallbeebee.com` → Forward `127.0.0.1:8088`
   - SSL: 申请 Let's Encrypt 证书，Force SSL
   - Advanced / Custom Nginx Configuration: `proxy_buffering off;`（SSE 必需）

Claude 执行（workbench CLI 已配置，instance `i-bp1bal3zezgaul8tc0m6`）：

1. 服务器创建 `/opt/tomeet-bff/.env`（`DEEPSEEK_API_KEY` 复用现有 key、`APP_TOKEN` 用 `openssl rand -hex 32` 新生成）
2. `bff/deploy.sh`：编译、上传、安装 systemd 单元、启动、健康检查
3. DNS + NPM 就绪后端到端验证：curl 带 X-App-Token 打 `https://tomeet-api.smallbeebee.com/v1/chat/completions` 确认流式返回

## 数据流

1. App 发送 `POST /v1/chat/completions`，body 为 OpenAI 兼容格式（`model: deepseek-chat`、`messages`、`stream: true`），头 `X-App-Token`
2. BFF 校验 token，读 body（≤64KB），向上游 DeepSeek 发同样 body，头换成 `Authorization: Bearer`
3. `stream:true` 时逐行透传 SSE；App 端 `URLSession.bytes` 逐行解析（现有代码不变）

## 错误处理

- BFF：401（无/错 token）、413（body 过大）、405（非 POST）、502（上游失败）
- App：`ChatServiceError.http(statusCode:)`，ViewModel 在 AI 气泡显示「Something went wrong. Please check your connection and try again.」（现有行为）

## 安全

- DeepSeek key 只存于服务器 `.env`（systemd EnvironmentFile，权限 600）
- App 包内只有 `bffAppToken`（可被提取，但泄露后果仅限滥用本代理；后续可加 per-device token 或限流，本期不做）
- BFF 不记录消息内容日志，只记 `app=<label> stream=<bool> bytes=<n>`

## 不做的事（YAGNI）

- 计费/积分系统（CycleAdvisor 的 reserveChatCredits 不搬）
- 多 App token 管理（保留 `APP_TOKENS` 多 token 解析代码，但只配一个）
- unauthenticated 模式 + IP 限流（代码保留，默认关闭）
- 对话历史服务端存储（历史仍在 App 本地）
