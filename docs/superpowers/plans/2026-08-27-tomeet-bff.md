# Tomeet BFF 代理实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 搭建独立 BFF 代理（Go，阿里云 ECS :8088），App 改用 X-App-Token 访问 `https://tomeet-api.smallbeebee.com`，DeepSeek key 只存服务端。

**Architecture:** 照搬 CycleAdvisor 生产验证的 Go SSE 透传代理（`cycle_advisor-main/bff/`），改端口/service 名；iOS 侧 `DeepSeekChatService` 仅换 baseURL 和鉴权头，其余不动。

**Tech Stack:** Go 1.26（交叉编译 linux/amd64）、systemd、Nginx Proxy Manager、Swift/SwiftUI、Xcode 工程（synchronized folders，新文件自动入 target）。

**Spec:** `docs/superpowers/specs/2026-08-27-tomeet-bff-design.md`

## Global Constraints

- BFF 监听端口 **8088**（服务器已确认空闲；现有服务占用 8080/8082/8084/8086）
- systemd 单元名 `tomeet-bff`，部署目录 `/opt/tomeet-bff`
- 上游固定 `https://api.deepseek.com/v1/chat/completions`（代码中为可测试的包级 `var`）
- body 上限 64KB；上游超时 180s；`ALLOW_UNAUTHENTICATED_APP` 默认关闭
- App 侧 App Store 传输安全要求 HTTPS；`http://IP:8088` 仅用于服务器本机健康检查
- `Secrets.swift`、`bff/.env` 均 gitignored，绝不提交
- 服务器 instance：`i-bp1bal3zezgaul8tc0m6`（workbench CLI 已配置）
- xcodebuild 需前缀 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`，destination `platform=iOS Simulator,name=iPhone 17`；模拟器偶发 "Busy" 启动失败，先 `xcrun simctl shutdown all` 再重试

---

### Task 1: Go BFF 核心（TDD：handler + main）

**Files:**
- Create: `bff/go.mod`
- Create: `bff/handler_test.go`
- Create: `bff/handler.go`
- Create: `bff/main.go`
- Create: `bff/.env.example`
- Modify: `.gitignore`（追加 `bff/.env`）

**Interfaces:**
- Consumes: 无（首个任务）
- Produces: `Proxy{APIKey string, AppTokens map[string]string, AllowUnauthenticated bool, UnauthRatePerMinute int}` 及其方法 `HandleCompletions(http.ResponseWriter, *http.Request)`；包级 `var upstreamURL string`（测试可替换）；`main()` 读取 `DEEPSEEK_API_KEY`/`APP_TOKEN(S)`/`LISTEN_ADDR`（默认 `:8088`）

- [ ] **Step 1: 写 go.mod 和失败测试**

`bff/go.mod`:
```go
module tomeet-bff

go 1.25.0
```

`bff/handler_test.go`:
```go
package main

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func newTestProxy() *Proxy {
	return &Proxy{APIKey: "upstream-key", AppTokens: map[string]string{"test-token": "tomeet"}}
}

func TestRejectsNonPost(t *testing.T) {
	p := newTestProxy()
	req := httptest.NewRequest(http.MethodGet, "/v1/chat/completions", nil)
	rec := httptest.NewRecorder()
	p.HandleCompletions(rec, req)
	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405, got %d", rec.Code)
	}
}

func TestRejectsMissingToken(t *testing.T) {
	p := newTestProxy()
	req := httptest.NewRequest(http.MethodPost, "/v1/chat/completions", strings.NewReader(`{"stream":false}`))
	rec := httptest.NewRecorder()
	p.HandleCompletions(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}
}

func TestRejectsWrongToken(t *testing.T) {
	p := newTestProxy()
	req := httptest.NewRequest(http.MethodPost, "/v1/chat/completions", strings.NewReader(`{"stream":false}`))
	req.Header.Set("X-App-Token", "wrong")
	rec := httptest.NewRecorder()
	p.HandleCompletions(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}
}

func TestRejectsOversizedBody(t *testing.T) {
	p := newTestProxy()
	body := strings.Repeat("x", maxBodySize+1)
	req := httptest.NewRequest(http.MethodPost, "/v1/chat/completions", strings.NewReader(body))
	req.Header.Set("X-App-Token", "test-token")
	rec := httptest.NewRecorder()
	p.HandleCompletions(rec, req)
	if rec.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("expected 413, got %d", rec.Code)
	}
}

func TestForwardsNonStreamWithBearerAuth(t *testing.T) {
	var gotAuth string
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAuth = r.Header.Get("Authorization")
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, `{"choices":[{"message":{"content":"你好"}}]}`)
	}))
	defer upstream.Close()
	orig := upstreamURL
	upstreamURL = upstream.URL
	defer func() { upstreamURL = orig }()

	p := newTestProxy()
	req := httptest.NewRequest(http.MethodPost, "/v1/chat/completions", strings.NewReader(`{"stream":false}`))
	req.Header.Set("X-App-Token", "test-token")
	rec := httptest.NewRecorder()
	p.HandleCompletions(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	if gotAuth != "Bearer upstream-key" {
		t.Fatalf("expected Bearer upstream-key, got %q", gotAuth)
	}
	if !strings.Contains(rec.Body.String(), "你好") {
		t.Fatalf("expected relayed body, got %q", rec.Body.String())
	}
}

func TestStreamsSSEResponse(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/event-stream")
		flusher := w.(http.Flusher)
		fmt.Fprint(w, "data: {\"choices\":[{\"delta\":{\"content\":\"你\"}}]}\n\n")
		flusher.Flush()
		fmt.Fprint(w, "data: [DONE]\n\n")
		flusher.Flush()
	}))
	defer upstream.Close()
	orig := upstreamURL
	upstreamURL = upstream.URL
	defer func() { upstreamURL = orig }()

	p := newTestProxy()
	req := httptest.NewRequest(http.MethodPost, "/v1/chat/completions", strings.NewReader(`{"stream":true}`))
	req.Header.Set("X-App-Token", "test-token")
	rec := httptest.NewRecorder()
	p.HandleCompletions(rec, req)

	if ct := rec.Header().Get("Content-Type"); ct != "text/event-stream" {
		t.Fatalf("expected text/event-stream, got %q", ct)
	}
	body := rec.Body.String()
	if !strings.Contains(body, `"content":"你"`) || !strings.Contains(body, "[DONE]") {
		t.Fatalf("expected SSE relay, got %q", body)
	}
}

func TestPeekStream(t *testing.T) {
	if !peekStream([]byte(`{"stream":true}`)) {
		t.Fatal("expected true")
	}
	if peekStream([]byte(`{"stream":false}`)) {
		t.Fatal("expected false")
	}
	if peekStream([]byte(`not json`)) {
		t.Fatal("expected false for invalid json")
	}
}
```

- [ ] **Step 2: 跑测试确认编译失败**

Run: `cd bff && go test ./...`
Expected: FAIL — `undefined: Proxy` / `undefined: maxBodySize` 等

- [ ] **Step 3: 写 handler.go 和 main.go 实现**

`bff/handler.go`:
```go
package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"io"
	"log"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
)

const (
	maxBodySize              = 64 * 1024 // 64 KB
	requestTimeout           = 180 * time.Second
	defaultUnauthRatePerMin  = 12
	unauthRateWindowDuration = time.Minute
)

// upstreamURL 是包级 var 以便测试用 httptest.Server 替换。
var upstreamURL = "https://api.deepseek.com/v1/chat/completions"

type Proxy struct {
	APIKey               string
	AppTokens            map[string]string // token -> app label
	AllowUnauthenticated bool
	UnauthRatePerMinute  int

	mu           sync.Mutex
	unauthCounts map[string]rateCounter
}

type rateCounter struct {
	windowStart time.Time
	count       int
}

func (p *Proxy) HandleCompletions(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	token := r.Header.Get("X-App-Token")
	appLabel, ok := p.AppTokens[token]
	if !ok || token == "" {
		if !p.AllowUnauthenticated {
			http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
			return
		}
		clientIP := clientIPFromRequest(r)
		if !p.allowUnauthenticatedRequest(clientIP) {
			http.Error(w, `{"error":"rate limited"}`, http.StatusTooManyRequests)
			return
		}
		appLabel = "unauthenticated:" + clientIP
	}

	body, err := io.ReadAll(io.LimitReader(r.Body, maxBodySize+1))
	if err != nil {
		http.Error(w, `{"error":"failed to read request body"}`, http.StatusBadRequest)
		return
	}
	if len(body) > maxBodySize {
		http.Error(w, `{"error":"request body too large"}`, http.StatusRequestEntityTooLarge)
		return
	}

	isStream := peekStream(body)
	log.Printf("app=%s stream=%t bytes=%d", appLabel, isStream, len(body))

	ctx := r.Context()
	upReq, err := http.NewRequestWithContext(ctx, http.MethodPost, upstreamURL, bytes.NewReader(body))
	if err != nil {
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	upReq.Header.Set("Content-Type", "application/json")
	upReq.Header.Set("Authorization", "Bearer "+p.APIKey)

	client := &http.Client{Timeout: requestTimeout}
	upResp, err := client.Do(upReq)
	if err != nil {
		log.Printf("upstream error: %v", err)
		http.Error(w, `{"error":"upstream request failed"}`, http.StatusBadGateway)
		return
	}
	defer upResp.Body.Close()

	if !isStream {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(upResp.StatusCode)
		io.Copy(w, upResp.Body)
		return
	}

	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, `{"error":"streaming not supported"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.WriteHeader(upResp.StatusCode)

	scanner := bufio.NewScanner(upResp.Body)
	scanner.Buffer(make([]byte, 0, 64*1024), 64*1024)
	for scanner.Scan() {
		line := scanner.Bytes()
		w.Write(line)
		w.Write([]byte("\n"))
		flusher.Flush()
	}
	if err := scanner.Err(); err != nil {
		log.Printf("stream relay error: %v", err)
	}
}

// peekStream 不完整解析 JSON，只看 "stream" 字段。
func peekStream(body []byte) bool {
	var peek struct {
		Stream bool `json:"stream"`
	}
	if err := json.Unmarshal(body, &peek); err != nil {
		return false
	}
	return peek.Stream
}

func clientIPFromRequest(r *http.Request) string {
	if forwarded := r.Header.Get("X-Forwarded-For"); forwarded != "" {
		parts := strings.Split(forwarded, ",")
		if ip := strings.TrimSpace(parts[0]); ip != "" {
			return ip
		}
	}
	if realIP := strings.TrimSpace(r.Header.Get("X-Real-IP")); realIP != "" {
		return realIP
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err == nil && host != "" {
		return host
	}
	return r.RemoteAddr
}

func (p *Proxy) allowUnauthenticatedRequest(clientIP string) bool {
	limit := p.UnauthRatePerMinute
	if limit <= 0 {
		limit = defaultUnauthRatePerMin
	}
	now := time.Now()

	p.mu.Lock()
	defer p.mu.Unlock()
	if p.unauthCounts == nil {
		p.unauthCounts = map[string]rateCounter{}
	}
	counter := p.unauthCounts[clientIP]
	if now.Sub(counter.windowStart) >= unauthRateWindowDuration {
		counter = rateCounter{windowStart: now}
	}
	if counter.count >= limit {
		p.unauthCounts[clientIP] = counter
		return false
	}
	counter.count++
	p.unauthCounts[clientIP] = counter
	return true
}
```

`bff/main.go`:
```go
package main

import (
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
)

// version 由 deploy.sh 通过 -ldflags "-X main.version=<commit>" 注入。
var version = "dev"

func main() {
	apiKey := os.Getenv("DEEPSEEK_API_KEY")
	if apiKey == "" {
		log.Fatal("DEEPSEEK_API_KEY environment variable is required")
	}

	tokens, err := loadAppTokens()
	if err != nil {
		log.Fatal(err)
	}

	addr := os.Getenv("LISTEN_ADDR")
	if addr == "" {
		addr = ":8088"
	}

	proxy := &Proxy{
		APIKey:               apiKey,
		AppTokens:            tokens,
		AllowUnauthenticated: envBool("ALLOW_UNAUTHENTICATED_APP"),
		UnauthRatePerMinute:  envInt("UNAUTH_RATE_LIMIT_PER_MINUTE", defaultUnauthRatePerMin),
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/v1/chat/completions", proxy.HandleCompletions)
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"status":"ok"}`))
	})

	labels := make([]string, 0, len(tokens))
	for _, l := range tokens {
		labels = append(labels, l)
	}
	log.Printf("BFF proxy listening on %s (version=%s, apps: %s, allow_unauthenticated=%t)",
		addr, version, strings.Join(labels, ", "), proxy.AllowUnauthenticated)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatal(err)
	}
}

// loadAppTokens 解析 APP_TOKENS（`token1:label1,token2:label2`），
// 未设置时回退单个 APP_TOKEN（label "default"）。
func loadAppTokens() (map[string]string, error) {
	out := map[string]string{}
	if multi := os.Getenv("APP_TOKENS"); multi != "" {
		for _, pair := range strings.Split(multi, ",") {
			pair = strings.TrimSpace(pair)
			if pair == "" {
				continue
			}
			parts := strings.SplitN(pair, ":", 2)
			token := strings.TrimSpace(parts[0])
			label := "unnamed"
			if len(parts) == 2 {
				label = strings.TrimSpace(parts[1])
			}
			if token != "" {
				out[token] = label
			}
		}
	}
	if single := os.Getenv("APP_TOKEN"); single != "" {
		if _, exists := out[single]; !exists {
			out[single] = "default"
		}
	}
	if len(out) == 0 {
		return nil, errEnv("APP_TOKENS or APP_TOKEN environment variable is required")
	}
	return out, nil
}

type errEnv string

func (e errEnv) Error() string { return string(e) }

func envBool(name string) bool {
	value := strings.TrimSpace(strings.ToLower(os.Getenv(name)))
	return value == "1" || value == "true" || value == "yes" || value == "on"
}

func envInt(name string, fallback int) int {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return fallback
	}
	parsed, err := strconv.Atoi(value)
	if err != nil || parsed <= 0 {
		return fallback
	}
	return parsed
}
```

`bff/.env.example`:
```bash
# DeepSeek API key (required) — 只存在服务端，绝不进 App 包
DEEPSEEK_API_KEY=sk-your-api-key-here

# iOS App 鉴权共享密钥，生成: openssl rand -hex 32
APP_TOKEN=your-64-char-hex-token-here

# 默认关闭；开启后无 token 请求按 IP 限流
ALLOW_UNAUTHENTICATED_APP=0
UNAUTH_RATE_LIMIT_PER_MINUTE=12

# 监听地址（可选，默认 :8088）
LISTEN_ADDR=:8088
```

`.gitignore` 追加：
```
bff/.env
```

- [ ] **Step 4: 跑测试确认全部通过**

Run: `cd bff && go test ./... -v`
Expected: 7 个测试全部 PASS

- [ ] **Step 5: 确认二进制能编译**

Run: `cd bff && GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o /tmp/tomeet-bff-check . && file /tmp/tomeet-bff-check && rm /tmp/tomeet-bff-check`
Expected: `ELF 64-bit LSB executable, x86-64`

- [ ] **Step 6: Commit**

```bash
git add bff/ .gitignore
git commit -m "feat(bff): add DeepSeek BFF proxy (Go) with auth and SSE relay"
```

---

### Task 2: 部署资产（systemd 单元 + deploy.sh）

**Files:**
- Create: `bff/tomeet-bff.service`
- Create: `bff/deploy.sh`

**Interfaces:**
- Consumes: Task 1 的 `bff/` Go 模块
- Produces: `bff/deploy.sh`（Task 4 部署时执行）；`tomeet-bff.service`（Task 4 安装到服务器）

- [ ] **Step 1: 写 systemd 单元**

`bff/tomeet-bff.service`:
```ini
[Unit]
Description=Tomeet BFF Proxy
After=network.target

[Service]
Type=simple
ExecStart=/opt/tomeet-bff/tomeet-bff
EnvironmentFile=/opt/tomeet-bff/.env
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 2: 写 deploy.sh**

`bff/deploy.sh`:
```bash
#!/usr/bin/env bash
# 部署 Tomeet BFF 到生产服务器：交叉编译 → workbench 上传 → 换二进制 → 重启 → 验证。
# 前置：本机已装 Go 和 workbench CLI；服务器已装 systemd 单元并配好 /opt/tomeet-bff/.env（见 Task 4）。
# 用法:  bff/deploy.sh
set -euo pipefail

INSTANCE_ID="${INSTANCE_ID:-i-bp1bal3zezgaul8tc0m6}"
REMOTE_DIR="/opt/tomeet-bff"
SERVICE="tomeet-bff"

cd "$(dirname "$0")"

VERSION="$(git rev-parse --short HEAD 2>/dev/null || echo nogit)"
if ! git diff --quiet -- . 2>/dev/null; then
    VERSION="${VERSION}-dirty"
fi

OUT="$(mktemp -t tomeet-bff)"
trap 'rm -f "$OUT"' EXIT

echo "==> Building linux/amd64 (version=$VERSION)"
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build \
    -ldflags "-X main.version=$VERSION" \
    -o "$OUT" .

echo "==> Uploading to $INSTANCE_ID:/tmp/tomeet-bff.new"
workbench upload "$OUT" /tmp/tomeet-bff.new --instance-id "$INSTANCE_ID" -f

echo "==> Swapping binary and restarting $SERVICE"
workbench exec --instance-id "$INSTANCE_ID" --timeout 60 --command "
  set -e
  cp $REMOTE_DIR/tomeet-bff $REMOTE_DIR/tomeet-bff.bak 2>/dev/null || true
  mv /tmp/tomeet-bff.new $REMOTE_DIR/tomeet-bff
  chmod +x $REMOTE_DIR/tomeet-bff
  systemctl restart $SERVICE
  sleep 1
  systemctl is-active $SERVICE
"

echo "==> Verifying startup log (expect version=$VERSION)"
workbench exec --instance-id "$INSTANCE_ID" --command \
    "journalctl -u $SERVICE -n 1 --no-pager | grep 'listening'"

echo "==> Checking local health endpoint"
workbench exec --instance-id "$INSTANCE_ID" --command \
    "curl -fsS --max-time 5 http://127.0.0.1:8088/health"
echo
echo "==> Deploy OK (version=$VERSION)"
```

- [ ] **Step 3: 语法检查 + 加执行权限**

Run: `bash -n bff/deploy.sh && chmod +x bff/deploy.sh && echo OK`
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add bff/tomeet-bff.service bff/deploy.sh
git commit -m "feat(bff): add systemd unit and deploy script"
```

---

### Task 3: iOS 切换到 BFF（TDD 改断言）

**Files:**
- Modify: `Tomeet/Tomeet/Services/DeepSeekChatService.swift`
- Modify: `Tomeet/TomeetTests/DeepSeekChatServiceTests.swift`
- Modify: `Tomeet/Tomeet/Services/Secrets.swift`（gitignored，不入库）
- Modify: `Tomeet/Tomeet/Services/Secrets.swift.template`

**Interfaces:**
- Consumes: 无
- Produces: `DeepSeekChatService(appToken:baseURL:session:)`（init 默认 `Secrets.bffAppToken`）；请求头 `X-App-Token`；baseURL 默认 `https://tomeet-api.smallbeebee.com/v1/chat/completions`

- [ ] **Step 1: 改测试断言（RED）**

`DeepSeekChatServiceTests.swift` 中 `buildRequestBodyUsesBearerAuthAndStream` 整个替换为：

```swift
    @Test func buildRequestBodyUsesAppTokenHeaderAndStream() throws {
        let service = DeepSeekChatService(appToken: "test-token")
        let messages = [ChatMessage(role: .user, text: "hi")]
        let request = try service.buildURLRequest(messages: messages, contextBook: nil)

        #expect(request.value(forHTTPHeaderField: "X-App-Token") == "test-token")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.url?.absoluteString == "https://tomeet-api.smallbeebee.com/v1/chat/completions")

        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any]
        #expect(body?["stream"] as? Bool == true)
        #expect(body?["model"] as? String == "deepseek-chat")
        let apiMessages = body?["messages"] as? [[String: String]]
        #expect(apiMessages?.first?["role"] == "system")
        #expect(apiMessages?.last?["role"] == "user")
        #expect(apiMessages?.last?["content"] == "hi")
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TomeetTests/DeepSeekChatServiceTests 2>&1 | tail -5`
Expected: 编译失败（`init(apiKey:)` 已改名）或断言失败

- [ ] **Step 3: 改 DeepSeekChatService 实现**

`DeepSeekChatService.swift` 三处修改：

```swift
    var baseURL = URL(string: "https://tomeet-api.smallbeebee.com/v1/chat/completions")!

    private let appToken: String
    private let session: URLSession

    init(appToken: String = Secrets.bffAppToken, session: URLSession = .shared) {
        self.appToken = appToken
        self.session = session
    }
```

`buildURLRequest` 中鉴权头替换：
```swift
        request.setValue(appToken, forHTTPHeaderField: "X-App-Token")
```
（删除原来的 `Authorization: Bearer` 行。类型顶部注释更新为「经自家 BFF 代理访问 DeepSeek（OpenAI 兼容格式）的流式实现」。）

- [ ] **Step 4: 更新 Secrets**

`Secrets.swift`（gitignored）内容改为：
```swift
import Foundation

/// 本地私有密钥，已 gitignore，请勿提交。模板见 Secrets.swift.template。
enum Secrets {
    /// BFF 代理共享密钥（对应服务器 /opt/tomeet-bff/.env 的 APP_TOKEN）。
    /// 部署 Task 4 生成后填入。
    static let bffAppToken = "<PENDING_DEPLOY>"
}
```

`Secrets.swift.template` 内容改为：
```swift
import Foundation

// Copy this file to Secrets.swift and fill in your own token.
// Secrets.swift is gitignored and must never be committed.
enum Secrets {
    static let bffAppToken = "<YOUR_BFF_APP_TOKEN>"
}
```

- [ ] **Step 5: 跑 iOS 全套测试确认通过**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -3`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add Tomeet/Tomeet/Services/DeepSeekChatService.swift Tomeet/TomeetTests/DeepSeekChatServiceTests.swift Tomeet/Tomeet/Services/Secrets.swift.template
git commit -m "feat(ai): point chat service at BFF proxy with X-App-Token auth"
```

（注意：git status 确认 Secrets.swift 不在暂存列表。）

---

### Task 4: 服务器 provisioning + 首次部署

**Files:** 无（服务器操作）

**Interfaces:**
- Consumes: Task 2 的 `bff/deploy.sh`、`bff/tomeet-bff.service`；本地 `Tomeet/Tomeet/Services/Secrets.swift` 的 DeepSeek key（迁移到服务器 .env）
- Produces: 运行中的 `tomeet-bff` systemd 服务（:8088）；服务器 `/opt/tomeet-bff/.env` 的 `APP_TOKEN` 值（回填进 App 的 `Secrets.swift`）

- [ ] **Step 1: 生成 APP_TOKEN**

Run: `openssl rand -hex 32`
Expected: 64 位 hex 字符串，记下来（下一步和 App Secrets 都要用）

- [ ] **Step 2: 服务器建目录和 .env**

Run（把 `<TOKEN>` 换成 Step 1 的值；DeepSeek key 从本地 `Tomeet/Tomeet/Services/Secrets.swift` 取）:
```bash
workbench exec --instance-id i-bp1bal3zezgaul8tc0m6 --timeout 30 --command "
  set -e
  mkdir -p /opt/tomeet-bff
  cat > /opt/tomeet-bff/.env <<'EOF'
DEEPSEEK_API_KEY=<deepseek-key>
APP_TOKEN=<TOKEN>
ALLOW_UNAUTHENTICATED_APP=0
LISTEN_ADDR=:8088
EOF
  chmod 600 /opt/tomeet-bff/.env
  ls -la /opt/tomeet-bff/.env
"
```
Expected: `-rw------- ... /opt/tomeet-bff/.env`

- [ ] **Step 3: 安装 systemd 单元**

Run:
```bash
workbench upload bff/tomeet-bff.service /etc/systemd/system/tomeet-bff.service --instance-id i-bp1bal3zezgaul8tc0m6 -f
workbench exec --instance-id i-bp1bal3zezgaul8tc0m6 --timeout 30 --command "systemctl daemon-reload && systemctl enable tomeet-bff"
```
Expected: `Created symlink ...`（enable 成功）

- [ ] **Step 4: 首次部署**

Run: `bff/deploy.sh`
Expected: 末尾打印 `{"status":"ok"}` 和 `Deploy OK`

- [ ] **Step 5: 服务器本机端到端验证（绕过 NPM，直连 8088）**

Run（`<TOKEN>` 同 Step 1）:
```bash
workbench exec --instance-id i-bp1bal3zezgaul8tc0m6 --timeout 60 --command "
  curl -sN --max-time 30 http://127.0.0.1:8088/v1/chat/completions \
    -H 'Content-Type: application/json' \
    -H 'X-App-Token: <TOKEN>' \
    -d '{\"model\":\"deepseek-chat\",\"messages\":[{\"role\":\"user\",\"content\":\"回复两个字：你好\"}],\"stream\":true,\"max_tokens\":10}'
"
```
Expected: 看到 `data: {...你好...}` 的 SSE 行和 `data: [DONE]`

再验证无 token 被拒：
```bash
workbench exec --instance-id i-bp1bal3zezgaul8tc0m6 --timeout 20 --command \
  "curl -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:8088/v1/chat/completions -H 'Content-Type: application/json' -d '{}'"
```
Expected: `401`

- [ ] **Step 6: 把 APP_TOKEN 回填进 App Secrets**

修改 `Tomeet/Tomeet/Services/Secrets.swift`：`<PENDING_DEPLOY>` → Step 1 的真实 token。

---

### Task 5: 用户操作（DNS + NPM）→ 端到端验证

**Files:** 无

**Interfaces:**
- Consumes: Task 4 运行中的服务
- Produces: `https://tomeet-api.smallbeebee.com` 公网可用；App 真机/模拟器可聊

- [ ] **Step 1: 【用户】阿里云 DNS 加 A 记录**

让用户在阿里云 DNS 控制台为 `smallbeebee.com` 添加：主机记录 `tomeet-api`，记录类型 A，记录值 = ECS 公网 IP。
先查出 IP 提供给用户：
Run: `workbench exec --instance-id i-bp1bal3zezgaul8tc0m6 --timeout 20 --command "curl -fsS --max-time 5 ifconfig.me"`
给用户清晰的图文指引后**停下等用户确认完成**。

- [ ] **Step 2: 【用户】NPM 加 Proxy Host**

指引用户打开 `http://<ECS IP>:5003`（Nginx Proxy Manager）：
- Add Proxy Host: Domain `tomeet-api.smallbeebee.com` → Forward Hostname `127.0.0.1`，Port `8088`
- SSL 标签：Request a new SSL certificate（Let's Encrypt），勾 Force SSL + HTTP/2
- Advanced 标签 Custom Nginx Configuration 填入：
  ```
  proxy_buffering off;
  proxy_cache off;
  proxy_read_timeout 300s;
  ```
**停下等用户确认完成。**

- [ ] **Step 3: 公网健康检查 + 端到端 SSE 验证**

Run:
```bash
curl -fsS --max-time 10 https://tomeet-api.smallbeebee.com/health
curl -sN --max-time 30 https://tomeet-api.smallbeebee.com/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -H "X-App-Token: $(grep bffAppToken Tomeet/Tomeet/Services/Secrets.swift | sed 's/.*"\(.*\)".*/\1/')" \
  -d '{"model":"deepseek-chat","messages":[{"role":"user","content":"回复两个字：你好"}],"stream":true,"max_tokens":10}'
```
Expected: `{"status":"ok"}` + SSE 流式输出含「你好」

- [ ] **Step 4: 模拟器里实聊验证**

引导用户在模拟器运行 App，AI Tab 发一条消息，确认流式回复正常。
（可选辅助：xcodebuild build 确认编译通过后由用户自己跑。）

- [ ] **Step 5: 收尾 commit（如有遗留改动）+ 更新 CLAUDE.md**

在 `CLAUDE.md` 的「已确认的技术决策」追加一行：
```markdown
- **AI 后端**：DeepSeek 经自家 BFF 代理（`https://tomeet-api.smallbeebee.com`，Go 源码在 `bff/`），
  App 持 `X-App-Token`（Secrets.swift，gitignored）；DeepSeek key 只存服务器 `/opt/tomeet-bff/.env`。
```

```bash
git add CLAUDE.md
git commit -m "docs: record BFF proxy decision in CLAUDE.md"
```

---

## Self-Review 记录

- Spec 覆盖：Go 服务（Task 1）、部署资产（Task 2）、App 切换（Task 3）、服务器部署（Task 4）、DNS/NPM + e2e（Task 5）—— spec 各节均有对应任务
- 类型一致性：`Proxy` 字段、`upstreamURL` var、`DeepSeekChatService(appToken:)`、`Secrets.bffAppToken` 跨任务一致
- 占位符：`<TOKEN>`/`<deepseek-key>` 均为执行期由命令生成的真实值，非计划缺失
