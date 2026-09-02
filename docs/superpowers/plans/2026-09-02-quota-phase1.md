# 第一期:AI 配额与成本熔断 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 Tomeet 的 AI 对话加上每设备每日 10 次免费配额 + 全局每日请求熔断,BFF 引入 SQLite 持久层,App 端展示剩余额度与超额引导。

**Architecture:** BFF(Go)新增 `QuotaStore`(纯 Go SQLite),`HandleCompletions` 在转发上游前做配额/熔断检查、成功后计数并回传 `X-Quota-Remaining`;新增 `GET /v1/quota` 只读端点。App(SwiftUI)新增 `DeviceIDProvider` 与 `QuotaService`,`DeepSeekChatService` 发送 `X-Device-ID` 并解析配额响应,`AIAssistantView` 显示剩余次数与超额面板。

**Tech Stack:** Go 1.25(stdlib + `modernc.org/sqlite`)、httptest;SwiftUI + Swift Testing(`import Testing` / `@Test` / `#expect`)。

**Spec:** `docs/superpowers/specs/2026-09-02-subscription-quota-design.md`

## Global Constraints

- 配额日界固定东八区:用 `time.FixedZone("CST", 8*3600)`,**不依赖系统 tzdata**
- 仅当上游返回 2xx 才计数(设备 +1、全局 +1);流式请求在上游返回 200 时即计数,中途断线不退还
- 请求头:`X-Device-ID`;响应头:`X-Quota-Remaining`;两者大小写不敏感但代码里统一用这个写法
- 错误体:429 → `{"error":"quota_exceeded","resetAt":"<RFC3339>"}`;503 → `{"error":"service_unavailable"}`;缺设备 ID → 400 `{"error":"device_id_required"}`
- 环境变量:`QUOTA_DB_PATH`(默认 `./quota.db`)、`DAILY_FREE_QUOTA`(默认 10)、`DAILY_GLOBAL_BUDGET`(默认 3000)
- App UI 文案一律英文(与现有 AIAssistantView 一致)
- App 测试用 Swift Testing,BFF 测试用 `testing` + `httptest`(延续现有模式)
- 本分支工作区有无关的脏文件,**每次 commit 只 add 本任务涉及的文件**

---

### Task 1: BFF QuotaStore(SQLite 持久层)

**Files:**
- Create: `bff/quota.go`
- Test: `bff/quota_test.go`
- Modify: `bff/go.mod`(新增依赖)

**Interfaces:**
- Consumes: 无(新组件)
- Produces(后续 Task 依赖这些签名):
  - `func OpenQuotaStore(path string) (*QuotaStore, error)`
  - `func (s *QuotaStore) Close() error`
  - `func (s *QuotaStore) deviceCount(deviceID string) (int, error)`
  - `func (s *QuotaStore) globalCount() (int, error)`
  - `func (s *QuotaStore) increment(deviceID string) error` — deviceID 为空串时只计全局
  - `func (s *QuotaStore) resetAt() time.Time`
  - 测试辅助字段:`s.now func() time.Time`(默认 `time.Now`,测试可替换)

- [ ] **Step 1: 引入依赖**

```bash
cd bff && go get modernc.org/sqlite@latest && go mod tidy
```

Expected: `go.mod` 新增 `modernc.org/sqlite` require;`go.sum` 生成。

- [ ] **Step 2: 写失败测试 `bff/quota_test.go`**

```go
package main

import (
	"path/filepath"
	"testing"
	"time"
)

func openTestStore(t *testing.T) *QuotaStore {
	t.Helper()
	store, err := OpenQuotaStore(filepath.Join(t.TempDir(), "quota.db"))
	if err != nil {
		t.Fatalf("OpenQuotaStore: %v", err)
	}
	t.Cleanup(func() { store.Close() })
	return store
}

func TestDeviceCountStartsAtZero(t *testing.T) {
	s := openTestStore(t)
	count, err := s.deviceCount("dev-1")
	if err != nil {
		t.Fatalf("deviceCount: %v", err)
	}
	if count != 0 {
		t.Fatalf("expected 0, got %d", count)
	}
}

func TestIncrementCountsDeviceAndGlobal(t *testing.T) {
	s := openTestStore(t)
	for i := 0; i < 3; i++ {
		if err := s.increment("dev-1"); err != nil {
			t.Fatalf("increment: %v", err)
		}
	}
	if err := s.increment("dev-2"); err != nil {
		t.Fatalf("increment: %v", err)
	}
	if got, _ := s.deviceCount("dev-1"); got != 3 {
		t.Fatalf("dev-1: expected 3, got %d", got)
	}
	if got, _ := s.deviceCount("dev-2"); got != 1 {
		t.Fatalf("dev-2: expected 1, got %d", got)
	}
	if got, _ := s.globalCount(); got != 4 {
		t.Fatalf("global: expected 4, got %d", got)
	}
}

func TestIncrementEmptyDeviceIDCountsGlobalOnly(t *testing.T) {
	s := openTestStore(t)
	if err := s.increment(""); err != nil {
		t.Fatalf("increment: %v", err)
	}
	if got, _ := s.globalCount(); got != 1 {
		t.Fatalf("global: expected 1, got %d", got)
	}
	if got, _ := s.deviceCount(""); got != 0 {
		t.Fatalf("empty device must not be recorded, got %d", got)
	}
}

func TestQuotaResetsAcrossDays(t *testing.T) {
	s := openTestStore(t)
	// 把时钟拨到昨天,累计 10 次;拨回今天后应为 0
	yesterday := time.Now().In(quotaTimezone).Add(-24 * time.Hour)
	s.now = func() time.Time { return yesterday }
	for i := 0; i < 10; i++ {
		if err := s.increment("dev-1"); err != nil {
			t.Fatalf("increment: %v", err)
		}
	}
	s.now = time.Now
	if got, _ := s.deviceCount("dev-1"); got != 0 {
		t.Fatalf("expected 0 after day rollover, got %d", got)
	}
	if got, _ := s.globalCount(); got != 0 {
		t.Fatalf("global expected 0 after day rollover, got %d", got)
	}
}

func TestCountsPersistAcrossReopen(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "quota.db")
	s1, err := OpenQuotaStore(path)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	if err := s1.increment("dev-1"); err != nil {
		t.Fatalf("increment: %v", err)
	}
	s1.Close()

	s2, err := OpenQuotaStore(path)
	if err != nil {
		t.Fatalf("reopen: %v", err)
	}
	defer s2.Close()
	if got, _ := s2.deviceCount("dev-1"); got != 1 {
		t.Fatalf("expected 1 after reopen, got %d", got)
	}
}

func TestResetAtIsNextMidnightCST(t *testing.T) {
	s := openTestStore(t)
	s.now = func() time.Time {
		return time.Date(2026, 9, 2, 15, 30, 0, 0, quotaTimezone)
	}
	want := time.Date(2026, 9, 3, 0, 0, 0, 0, quotaTimezone)
	if got := s.resetAt(); !got.Equal(want) {
		t.Fatalf("expected %v, got %v", want, got)
	}
}
```

- [ ] **Step 3: 跑测试确认失败**

Run: `cd bff && go test ./...`
Expected: 编译失败 `undefined: OpenQuotaStore` / `undefined: quotaTimezone`

- [ ] **Step 4: 实现 `bff/quota.go`**

```go
package main

import (
	"database/sql"
	"time"

	_ "modernc.org/sqlite"
)

// 配额日界固定东八区(中国无夏令时),不依赖系统 tzdata。
var quotaTimezone = time.FixedZone("CST", 8*3600)

// QuotaStore 用 SQLite 持久化设备配额与全局日预算,重启/崩溃不丢计数。
// 单写者(MaxOpenConns=1)避免 SQLITE_BUSY;并发由 database/sql 串行化。
type QuotaStore struct {
	db  *sql.DB
	now func() time.Time // 测试可注入固定时钟
}

func OpenQuotaStore(path string) (*QuotaStore, error) {
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	if _, err := db.Exec(`
CREATE TABLE IF NOT EXISTS device_quota (
    device_id TEXT NOT NULL,
    day       TEXT NOT NULL,
    count     INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (device_id, day)
);
CREATE TABLE IF NOT EXISTS global_budget (
    day   TEXT PRIMARY KEY,
    count INTEGER NOT NULL DEFAULT 0
);`); err != nil {
		db.Close()
		return nil, err
	}
	return &QuotaStore{db: db, now: time.Now}, nil
}

func (s *QuotaStore) Close() error { return s.db.Close() }

func (s *QuotaStore) day() string {
	return s.now().In(quotaTimezone).Format("2006-01-02")
}

// resetAt 返回当前配额日结束(次日 0 点,东八区)的时刻。
func (s *QuotaStore) resetAt() time.Time {
	now := s.now().In(quotaTimezone)
	midnight := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, quotaTimezone)
	return midnight.Add(24 * time.Hour)
}

func (s *QuotaStore) deviceCount(deviceID string) (int, error) {
	var count int
	err := s.db.QueryRow(
		`SELECT count FROM device_quota WHERE device_id = ? AND day = ?`,
		deviceID, s.day(),
	).Scan(&count)
	if err == sql.ErrNoRows {
		return 0, nil
	}
	return count, err
}

func (s *QuotaStore) globalCount() (int, error) {
	var count int
	err := s.db.QueryRow(
		`SELECT count FROM global_budget WHERE day = ?`, s.day(),
	).Scan(&count)
	if err == sql.ErrNoRows {
		return 0, nil
	}
	return count, err
}

// increment 设备与全局计数同事务 +1,仅在请求成功转发上游(2xx)后调用。
// deviceID 为空(未认证请求)时只计全局。
func (s *QuotaStore) increment(deviceID string) error {
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	day := s.day()
	if deviceID != "" {
		if _, err := tx.Exec(
			`INSERT INTO device_quota (device_id, day, count) VALUES (?, ?, 1)
			 ON CONFLICT (device_id, day) DO UPDATE SET count = count + 1`,
			deviceID, day,
		); err != nil {
			return err
		}
	}
	if _, err := tx.Exec(
		`INSERT INTO global_budget (day, count) VALUES (?, 1)
		 ON CONFLICT (day) DO UPDATE SET count = count + 1`,
		day,
	); err != nil {
		return err
	}
	return tx.Commit()
}
```

- [ ] **Step 5: 跑测试确认通过**

Run: `cd bff && go test ./...`
Expected: 全部 PASS(含既有 handler 测试,它们此时尚未受影响)

- [ ] **Step 6: Commit**

```bash
git add bff/quota.go bff/quota_test.go bff/go.mod bff/go.sum
git commit -m "feat(bff): SQLite quota store with device quota and global daily budget"
```

---

### Task 2: BFF HandleCompletions 接线配额与熔断

**Files:**
- Modify: `bff/handler.go`(`Proxy` 结构与 `HandleCompletions`)
- Test: `bff/handler_test.go`

**Interfaces:**
- Consumes: Task 1 的 `OpenQuotaStore` / `deviceCount` / `globalCount` / `increment` / `resetAt`
- Produces:
  - `Proxy` 新字段:`Store *QuotaStore`、`DailyFreeQuota int`、`DailyGlobalBudget int`
  - 认证请求必须带 `X-Device-ID`,成功响应带 `X-Quota-Remaining`

处理顺序(token 认证 → 读 body → 设备 ID → 全局熔断 → 设备配额 → 转发 → 2xx 计数):

- [ ] **Step 1: 改造 `newTestProxy` 并让既有认证测试带设备 ID**

`bff/handler_test.go` 顶部替换 `newTestProxy`(签名加 `t *testing.T`,**既有测试里的 `newTestProxy()` 调用点全部改为 `newTestProxy(t)`**),并在 `TestForwardsNonStreamWithBearerAuth`、`TestStreamsSSEResponse` 的请求上加 `req.Header.Set("X-Device-ID", "dev-test")`(`TestRejectsOversizedBody` 不用改:body 超限检查在设备 ID 检查之前):

```go
func newTestProxy(t *testing.T) *Proxy {
	t.Helper()
	store, err := OpenQuotaStore(filepath.Join(t.TempDir(), "quota.db"))
	if err != nil {
		t.Fatalf("OpenQuotaStore: %v", err)
	}
	t.Cleanup(func() { store.Close() })
	return &Proxy{
		APIKey:            "upstream-key",
		AppTokens:         map[string]string{"test-token": "tomeet"},
		Store:             store,
		DailyFreeQuota:    10,
		DailyGlobalBudget: 3000,
	}
}
```

(import 增加 `"path/filepath"`。)

- [ ] **Step 2: 写失败测试(追加到 `bff/handler_test.go`)**

```go
func newAuthedRequest(t *testing.T, deviceID string) *http.Request {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/v1/chat/completions", strings.NewReader(`{"stream":false}`))
	req.Header.Set("X-App-Token", "test-token")
	if deviceID != "" {
		req.Header.Set("X-Device-ID", deviceID)
	}
	return req
}

// newOKUpstream 把 upstreamURL 指到总是 200 的测试服务器,cleanup 自动恢复。
func newOKUpstream(t *testing.T) {
	t.Helper()
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, `{"choices":[{"message":{"content":"ok"}}]}`)
	}))
	t.Cleanup(upstream.Close)
	orig := upstreamURL
	upstreamURL = upstream.URL
	t.Cleanup(func() { upstreamURL = orig })
}

func TestRejectsMissingDeviceID(t *testing.T) {
	p := newTestProxy(t)
	rec := httptest.NewRecorder()
	p.HandleCompletions(rec, newAuthedRequest(t, ""))
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), "device_id_required") {
		t.Fatalf("unexpected body: %q", rec.Body.String())
	}
}

func TestQuotaExceededReturns429WithResetAt(t *testing.T) {
	newOKUpstream(t)
	p := newTestProxy(t)
	for i := 0; i < 10; i++ {
		rec := httptest.NewRecorder()
		p.HandleCompletions(rec, newAuthedRequest(t, "dev-1"))
		if rec.Code != http.StatusOK {
			t.Fatalf("request %d: expected 200, got %d", i, rec.Code)
		}
	}
	rec := httptest.NewRecorder()
	p.HandleCompletions(rec, newAuthedRequest(t, "dev-1"))
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("expected 429, got %d", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), "quota_exceeded") ||
		!strings.Contains(rec.Body.String(), "resetAt") {
		t.Fatalf("unexpected body: %q", rec.Body.String())
	}
	// 别的设备不受影响
	rec2 := httptest.NewRecorder()
	p.HandleCompletions(rec2, newAuthedRequest(t, "dev-2"))
	if rec2.Code != http.StatusOK {
		t.Fatalf("dev-2: expected 200, got %d", rec2.Code)
	}
}

func TestSuccessResponseCarriesQuotaRemaining(t *testing.T) {
	newOKUpstream(t)
	p := newTestProxy(t)
	rec := httptest.NewRecorder()
	p.HandleCompletions(rec, newAuthedRequest(t, "dev-1"))
	if got := rec.Header().Get("X-Quota-Remaining"); got != "9" {
		t.Fatalf("expected X-Quota-Remaining=9, got %q", got)
	}
}

func TestUpstreamErrorDoesNotConsumeQuota(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "boom", http.StatusInternalServerError)
	}))
	t.Cleanup(upstream.Close)
	orig := upstreamURL
	upstreamURL = upstream.URL
	t.Cleanup(func() { upstreamURL = orig })

	p := newTestProxy(t)
	rec := httptest.NewRecorder()
	p.HandleCompletions(rec, newAuthedRequest(t, "dev-1"))
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("expected 502/500 passthrough, got %d", rec.Code)
	}
	if got, _ := p.Store.deviceCount("dev-1"); got != 0 {
		t.Fatalf("upstream failure must not consume quota, got %d", got)
	}
	if got, _ := p.Store.globalCount(); got != 0 {
		t.Fatalf("upstream failure must not consume global budget, got %d", got)
	}
}

func TestGlobalBudgetExceededReturns503(t *testing.T) {
	newOKUpstream(t)
	p := newTestProxy(t)
	p.DailyGlobalBudget = 1
	rec := httptest.NewRecorder()
	p.HandleCompletions(rec, newAuthedRequest(t, "dev-1"))
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	// 第二个请求换设备也一样被熔断(全局与身份无关)
	rec2 := httptest.NewRecorder()
	p.HandleCompletions(rec2, newAuthedRequest(t, "dev-2"))
	if rec2.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503, got %d", rec2.Code)
	}
	if !strings.Contains(rec2.Body.String(), "service_unavailable") {
		t.Fatalf("unexpected body: %q", rec2.Body.String())
	}
}
```

- [ ] **Step 3: 跑测试确认失败**

Run: `cd bff && go test ./...`
Expected: 编译失败(`Proxy` 无 `Store`/`DailyFreeQuota` 字段)或新测试 401/200 断言失败

- [ ] **Step 4: 修改 `bff/handler.go`**

`Proxy` 结构加字段(import 增加 `"fmt"`、`"strconv"`):

```go
type Proxy struct {
	APIKey               string
	AppTokens            map[string]string // token -> app label
	AllowUnauthenticated bool
	UnauthRatePerMinute  int

	Store             *QuotaStore
	DailyFreeQuota    int // 每设备每日免费次数
	DailyGlobalBudget int // 全局每日请求熔断

	mu           sync.Mutex
	unauthCounts map[string]rateCounter
}
```

`HandleCompletions` 中,在 body 大小检查(`if len(body) > maxBodySize` 块)之后、`isStream := peekStream(body)` 之前插入:

```go
	deviceID := r.Header.Get("X-Device-ID")
	authenticated := ok && token != ""
	if authenticated && deviceID == "" {
		http.Error(w, `{"error":"device_id_required"}`, http.StatusBadRequest)
		return
	}

	globalUsed, err := p.Store.globalCount()
	if err != nil {
		log.Printf("quota store error: %v", err)
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	if globalUsed >= p.DailyGlobalBudget {
		http.Error(w, `{"error":"service_unavailable"}`, http.StatusServiceUnavailable)
		return
	}

	deviceUsed := 0
	if authenticated {
		deviceUsed, err = p.Store.deviceCount(deviceID)
		if err != nil {
			log.Printf("quota store error: %v", err)
			http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
			return
		}
		if deviceUsed >= p.DailyFreeQuota {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusTooManyRequests)
			fmt.Fprintf(w, `{"error":"quota_exceeded","resetAt":%q}`,
				p.Store.resetAt().Format(time.RFC3339))
			return
		}
	}
```

注意:文件顶部原有的 `if !ok || token == "" { ... }` 未认证分支**原样保留**(它要么 return,要么走完 IP 限流后继续往下);上面插入的代码位于其后,`ok` 与 `token` 均已在作用域内,`authenticated` 据此推导。

上游响应处理后(`defer upResp.Body.Close()` 之后),在非流式/流式两个分支共用的前置位置插入计数与响应头(必须在任何 `w.WriteHeader` 之前):

```go
	if upResp.StatusCode >= 200 && upResp.StatusCode < 300 {
		if err := p.Store.increment(deviceID); err != nil {
			log.Printf("quota increment failed: %v", err)
		}
		if authenticated {
			remaining := p.DailyFreeQuota - deviceUsed - 1
			if remaining < 0 {
				remaining = 0
			}
			w.Header().Set("X-Quota-Remaining", strconv.Itoa(remaining))
		}
	}
```

- [ ] **Step 5: 跑测试确认通过**

Run: `cd bff && go test ./... -v`
Expected: 全部 PASS,包括 5 个新测试与全部既有测试

- [ ] **Step 6: Commit**

```bash
git add bff/handler.go bff/handler_test.go
git commit -m "feat(bff): enforce device quota and global budget in completions handler"
```

---

### Task 3: BFF `GET /v1/quota` 端点 + main.go 配置

**Files:**
- Modify: `bff/handler.go`(新增 `HandleQuota`)
- Modify: `bff/main.go`(打开 QuotaStore、注册路由、环境变量)
- Test: `bff/handler_test.go`

**Interfaces:**
- Consumes: Task 2 的 `Proxy` 新字段
- Produces: `func (p *Proxy) HandleQuota(w http.ResponseWriter, r *http.Request)`;路由 `GET /v1/quota`

- [ ] **Step 1: 写失败测试(追加到 `bff/handler_test.go`)**

```go
func TestQuotaEndpointReturnsRemainingAndResetAt(t *testing.T) {
	p := newTestProxy(t)
	// 预置:dev-1 今日已用 3 次
	for i := 0; i < 3; i++ {
		if err := p.Store.increment("dev-1"); err != nil {
			t.Fatalf("increment: %v", err)
		}
	}
	req := httptest.NewRequest(http.MethodGet, "/v1/quota", nil)
	req.Header.Set("X-App-Token", "test-token")
	req.Header.Set("X-Device-ID", "dev-1")
	rec := httptest.NewRecorder()
	p.HandleQuota(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	body := rec.Body.String()
	if !strings.Contains(body, `"remaining":7`) {
		t.Fatalf("expected remaining 7, got %q", body)
	}
	if !strings.Contains(body, "resetAt") {
		t.Fatalf("expected resetAt, got %q", body)
	}
	// 只读:不计数
	if got, _ := p.Store.globalCount(); got != 3 {
		t.Fatalf("quota endpoint must not count, global=%d", got)
	}
}

func TestQuotaEndpointRejectsBadAuth(t *testing.T) {
	p := newTestProxy(t)
	req := httptest.NewRequest(http.MethodGet, "/v1/quota", nil)
	rec := httptest.NewRecorder()
	p.HandleQuota(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}

	req2 := httptest.NewRequest(http.MethodGet, "/v1/quota", nil)
	req2.Header.Set("X-App-Token", "test-token")
	rec2 := httptest.NewRecorder()
	p.HandleQuota(rec2, req2)
	if rec2.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 without device id, got %d", rec2.Code)
	}
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd bff && go test ./... -run TestQuotaEndpoint -v`
Expected: 编译失败 `p.HandleQuota undefined`

- [ ] **Step 3: 实现**

`bff/handler.go` 追加:

```go
// HandleQuota 返回设备当日剩余免费额度;只读,不计数。
func (p *Proxy) HandleQuota(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}
	token := r.Header.Get("X-App-Token")
	if _, ok := p.AppTokens[token]; !ok || token == "" {
		http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
		return
	}
	deviceID := r.Header.Get("X-Device-ID")
	if deviceID == "" {
		http.Error(w, `{"error":"device_id_required"}`, http.StatusBadRequest)
		return
	}
	used, err := p.Store.deviceCount(deviceID)
	if err != nil {
		log.Printf("quota store error: %v", err)
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	remaining := p.DailyFreeQuota - used
	if remaining < 0 {
		remaining = 0
	}
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintf(w, `{"remaining":%d,"resetAt":%q}`,
		remaining, p.Store.resetAt().Format(time.RFC3339))
}
```

`bff/main.go` 中,`proxy := &Proxy{...}` 之前打开 store,结构体加字段,mux 注册路由:

```go
	quotaDBPath := os.Getenv("QUOTA_DB_PATH")
	if quotaDBPath == "" {
		quotaDBPath = "./quota.db"
	}
	store, err := OpenQuotaStore(quotaDBPath)
	if err != nil {
		log.Fatalf("open quota store %s: %v", quotaDBPath, err)
	}
	defer store.Close()
```

```go
	proxy := &Proxy{
		APIKey:               apiKey,
		AppTokens:            tokens,
		AllowUnauthenticated: envBool("ALLOW_UNAUTHENTICATED_APP"),
		UnauthRatePerMinute:  envInt("UNAUTH_RATE_LIMIT_PER_MINUTE", defaultUnauthRatePerMin),
		Store:                store,
		DailyFreeQuota:       envInt("DAILY_FREE_QUOTA", 10),
		DailyGlobalBudget:    envInt("DAILY_GLOBAL_BUDGET", 3000),
	}
```

```go
	mux.HandleFunc("/v1/chat/completions", proxy.HandleCompletions)
	mux.HandleFunc("/v1/quota", proxy.HandleQuota)
```

启动日志补充配额配置:

```go
	log.Printf("BFF proxy listening on %s (version=%s, apps: %s, allow_unauthenticated=%t, daily_free_quota=%d, daily_global_budget=%d, quota_db=%s)",
		addr, version, strings.Join(labels, ", "), proxy.AllowUnauthenticated,
		proxy.DailyFreeQuota, proxy.DailyGlobalBudget, quotaDBPath)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd bff && go test ./... && go build ./...`
Expected: 全部 PASS,编译成功

- [ ] **Step 5: Commit**

```bash
git add bff/handler.go bff/handler_test.go bff/main.go
git commit -m "feat(bff): GET /v1/quota endpoint and quota config wiring"
```

---

### Task 4: App DeviceIDProvider + `X-Device-ID` 请求头

**Files:**
- Create: `Tomeet/Tomeet/Services/DeviceIDProvider.swift`
- Modify: `Tomeet/Tomeet/Services/DeepSeekChatService.swift`
- Test: `Tomeet/TomeetTests/DeepSeekChatServiceTests.swift`(新建,含 `MockURLProtocol`,后续 Task 复用)

**Interfaces:**
- Consumes: 现有 `DeepSeekChatService(appToken:session:)`、`ChatMessage(id:role:text:date:)`(均有默认值)
- Produces:
  - `struct DeviceIDProvider: Sendable { var id: String { get } }`
  - `DeepSeekChatService` 新签名:`init(appToken:deviceID:session:)`,新属性 `var deviceID: String`

注意:Xcode 工程用 PBXFileSystemSynchronizedRootGroup,新 Swift 文件放进对应目录即自动入工程,无需手动加 pbxproj。

- [ ] **Step 1: 写失败测试 `Tomeet/TomeetTests/DeepSeekChatServiceTests.swift`**

```swift
import Foundation
import Testing
@testable import Tomeet

/// 测试用 URL 拦截器。handler 返回 (响应, 响应体)。
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

struct DeepSeekChatServiceTests {
    private func makeService(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> DeepSeekChatService {
        MockURLProtocol.handler = handler
        return DeepSeekChatService(
            appToken: "test-token",
            deviceID: "test-device",
            session: MockURLProtocol.makeSession()
        )
    }

    private func sseResponse(_ request: URLRequest, headers: [String: String] = [:]) -> (HTTPURLResponse, Data) {
        var allHeaders = ["Content-Type": "text/event-stream"]
        allHeaders.merge(headers) { _, new in new }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil, headerFields: allHeaders
        )!
        let body = "data: {\"choices\":[{\"delta\":{\"content\":\"hi\"}}]}\n\ndata: [DONE]\n\n"
        return (response, Data(body.utf8))
    }

    @Test func sendsDeviceIDHeader() async throws {
        nonisolated(unsafe) var gotDeviceID: String?
        let service = makeService { request in
            gotDeviceID = request.value(forHTTPHeaderField: "X-Device-ID")
            return self.sseResponse(request)
        }
        var text = ""
        for try await chunk in service.replyStream(
            to: [ChatMessage(role: .user, text: "hello")], contextBook: nil
        ) {
            text += chunk
        }
        #expect(gotDeviceID == "test-device")
        #expect(text == "hi")
    }
}

struct DeviceIDProviderTests {
    @Test func idIsNonEmptyAndStable() {
        #expect(!DeviceIDProvider().id.isEmpty)
        #expect(DeviceIDProvider().id == DeviceIDProvider().id)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

先列出可用模拟器,选一个存在的 iPhone:

```bash
xcrun simctl list devices available | grep iPhone
xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet \
  -destination 'platform=iOS Simulator,name=<上一步的机型>' \
  -only-testing:TomeetTests/DeepSeekChatServiceTests
```

Expected: 编译失败 — `DeepSeekChatService` 没有 `deviceID` 参数、`DeviceIDProvider` 不存在

- [ ] **Step 3: 实现**

新建 `Tomeet/Tomeet/Services/DeviceIDProvider.swift`:

```swift
import UIKit

/// 免费配额用的设备标识。identifierForVendor 在同厂商 App 间稳定,
/// 卸载全部同厂商 App 重装后会变化(可接受,见 spec「不做的事」)。
struct DeviceIDProvider: Sendable {
    var id: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    }
}
```

`DeepSeekChatService.swift` 修改:

```swift
    var baseURL = URL(string: "https://tomeet-api.smallbeebee.com/v1/chat/completions")!
    var deviceID: String

    private let appToken: String
    private let session: URLSession

    init(appToken: String = Secrets.bffAppToken,
         deviceID: String = DeviceIDProvider().id,
         session: URLSession = .shared) {
        self.appToken = appToken
        self.deviceID = deviceID
        self.session = session
    }
```

`buildURLRequest` 里 `X-App-Token` 那行后面加:

```swift
        request.setValue(deviceID, forHTTPHeaderField: "X-Device-ID")
```

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2 的 xcodebuild 命令
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Tomeet/Tomeet/Services/DeviceIDProvider.swift \
        Tomeet/Tomeet/Services/DeepSeekChatService.swift \
        Tomeet/TomeetTests/DeepSeekChatServiceTests.swift
git commit -m "feat(app): send X-Device-ID with AI requests for quota tracking"
```

---

### Task 5: App 解析 `X-Quota-Remaining` 与 429 错误

**Files:**
- Modify: `Tomeet/Tomeet/Services/DeepSeekChatService.swift`
- Test: `Tomeet/TomeetTests/DeepSeekChatServiceTests.swift`

**Interfaces:**
- Consumes: Task 4 的 `MockURLProtocol`、`deviceID`
- Produces:
  - `ChatServiceError.quotaExceeded(resetAt: Date?)`
  - `DeepSeekChatService.onQuotaRemaining: (@Sendable (Int) -> Void)?`
  - `DeepSeekChatService.readResetAt(from:) async throws -> Date?`(nonisolated static)

- [ ] **Step 1: 写失败测试(追加到 `DeepSeekChatServiceTests`)**

```swift
    @Test func reportsQuotaRemainingFromResponseHeader() async throws {
        final class Capture: @unchecked Sendable { var value: Int? }
        let capture = Capture()
        var service = makeService { request in
            self.sseResponse(request, headers: ["X-Quota-Remaining": "6"])
        }
        service.onQuotaRemaining = { capture.value = $0 }

        for try await _ in service.replyStream(
            to: [ChatMessage(role: .user, text: "hello")], contextBook: nil
        ) {}
        #expect(capture.value == 6)
    }

    @Test func throwsQuotaExceededOn429() async {
        let service = makeService { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil
            )!
            let body = #"{"error":"quota_exceeded","resetAt":"2026-09-03T00:00:00+08:00"}"#
            return (response, Data(body.utf8))
        }
        do {
            for try await _ in service.replyStream(
                to: [ChatMessage(role: .user, text: "hello")], contextBook: nil
            ) {}
            Issue.record("expected quotaExceeded to be thrown")
        } catch ChatServiceError.quotaExceeded(let resetAt) {
            #expect(resetAt != nil)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }
```

(放在 `DeepSeekChatServiceTests` struct 内,复用 Task 4 的 `makeService`/`sseResponse`。)

- [ ] **Step 2: 跑测试确认失败**

Run: 同 Task 4 Step 2
Expected: 编译失败 — `onQuotaRemaining`、`ChatServiceError.quotaExceeded` 不存在

- [ ] **Step 3: 实现 `DeepSeekChatService.swift`**

错误枚举加 case:

```swift
enum ChatServiceError: LocalizedError {
    case http(statusCode: Int)
    case emptyResponse
    case quotaExceeded(resetAt: Date?)

    var errorDescription: String? {
        switch self {
        case .http(let code): return "AI service returned HTTP \(code)."
        case .emptyResponse: return "AI service returned an empty response."
        case .quotaExceeded: return "Daily free conversation quota exhausted."
        }
    }
}
```

struct 加属性:

```swift
    /// 每次成功响应带上 X-Quota-Remaining 时回调(用于 QuotaService 本地更新)。
    var onQuotaRemaining: (@Sendable (Int) -> Void)?
```

`replyStream` 里的状态码检查替换为:

```swift
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw ChatServiceError.http(statusCode: -1)
                    }
                    if http.statusCode == 429 {
                        throw ChatServiceError.quotaExceeded(
                            resetAt: try await Self.readResetAt(from: bytes)
                        )
                    }
                    guard http.statusCode == 200 else {
                        throw ChatServiceError.http(statusCode: http.statusCode)
                    }
                    if let remaining = http.value(forHTTPHeaderField: "X-Quota-Remaining")
                        .flatMap(Int.init) {
                        onQuotaRemaining?(remaining)
                    }
```

新增解析方法(放在 SSE parsing 区):

```swift
    /// 从 429 响应体 {"error":"quota_exceeded","resetAt":"..."} 解析重置时间;失败返回 nil。
    nonisolated static func readResetAt(from bytes: URLSession.AsyncBytes) async throws -> Date? {
        struct QuotaErrorBody: Decodable { let resetAt: String? }
        var data = Data()
        for try await line in bytes.lines {
            data.append(contentsOf: line.utf8)
        }
        guard let decoded = try? JSONDecoder().decode(QuotaErrorBody.self, from: data),
              let raw = decoded.resetAt
        else { return nil }
        return ISO8601DateFormatter().date(from: raw)
    }
```

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Task 4 Step 2
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Tomeet/Tomeet/Services/DeepSeekChatService.swift \
        Tomeet/TomeetTests/DeepSeekChatServiceTests.swift
git commit -m "feat(app): parse quota remaining header and 429 quota_exceeded error"
```

---

### Task 6: App QuotaService

**Files:**
- Create: `Tomeet/Tomeet/Services/QuotaService.swift`
- Test: `Tomeet/TomeetTests/QuotaServiceTests.swift`

**Interfaces:**
- Consumes: `Secrets.bffAppToken`、`DeviceIDProvider().id`、Task 4 的 `MockURLProtocol`
- Produces(Task 7 依赖):
  - `@MainActor @Observable final class QuotaService`
  - `init(baseURL:appToken:deviceID:session:)`(默认值同 DeepSeek 的生产配置,baseURL 默认 `https://tomeet-api.smallbeebee.com/v1/quota`)
  - `private(set) var remaining: Int?`、`private(set) var resetAt: Date?`
  - `var isExhausted: Bool`
  - `func refresh() async`、`func noteRemaining(_ value: Int)`、`func noteExhausted(resetAt: Date?)`

- [ ] **Step 1: 写失败测试 `Tomeet/TomeetTests/QuotaServiceTests.swift`**

```swift
import Foundation
import Testing
@testable import Tomeet

struct QuotaServiceTests {
    @MainActor
    private func makeService(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> QuotaService {
        MockURLProtocol.handler = handler
        return QuotaService(
            baseURL: URL(string: "https://example.com/v1/quota")!,
            appToken: "test-token",
            deviceID: "test-device",
            session: MockURLProtocol.makeSession()
        )
    }

    @MainActor
    @Test func refreshParsesRemainingAndResetAt() async {
        let service = makeService { request in
            #expect(request.value(forHTTPHeaderField: "X-App-Token") == "test-token")
            #expect(request.value(forHTTPHeaderField: "X-Device-ID") == "test-device")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            let body = #"{"remaining":7,"resetAt":"2026-09-03T00:00:00+08:00"}"#
            return (response, Data(body.utf8))
        }
        await service.refresh()
        #expect(service.remaining == 7)
        #expect(service.resetAt != nil)
        #expect(!service.isExhausted)
    }

    @MainActor
    @Test func refreshFailureKeepsUnknownState() async {
        let service = makeService { _ in throw URLError(.notConnectedToInternet) }
        await service.refresh()
        #expect(service.remaining == nil)
        #expect(!service.isExhausted)
    }

    @MainActor
    @Test func noteRemainingUpdatesValue() {
        let service = makeService { _ in throw URLError(.unknown) }
        service.noteRemaining(3)
        #expect(service.remaining == 3)
        #expect(!service.isExhausted)
        service.noteRemaining(0)
        #expect(service.isExhausted)
    }

    @MainActor
    @Test func noteExhaustedMarksExhaustedAndKeepsResetAt() {
        let service = makeService { _ in throw URLError(.unknown) }
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        service.noteExhausted(resetAt: date)
        #expect(service.isExhausted)
        #expect(service.resetAt == date)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test ... -only-testing:TomeetTests/QuotaServiceTests`
Expected: 编译失败 — `QuotaService` 不存在

- [ ] **Step 3: 实现 `Tomeet/Tomeet/Services/QuotaService.swift`**

```swift
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
```

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Tomeet/Tomeet/Services/QuotaService.swift Tomeet/TomeetTests/QuotaServiceTests.swift
git commit -m "feat(app): QuotaService for daily free quota state"
```

---

### Task 7: ViewModel / UI 接线 + 隐私政策

**Files:**
- Modify: `Tomeet/Tomeet/Views/AI/AIChatViewModel.swift`
- Modify: `Tomeet/Tomeet/Views/AI/AIAssistantView.swift`
- Modify: `PRIVACY_POLICY.md`
- Test: `Tomeet/TomeetTests/AIChatViewModelTests.swift`(新建)

**Interfaces:**
- Consumes: `QuotaService`、`ChatServiceError.quotaExceeded`、`onQuotaRemaining`、`MockChatService`
- Produces: `AIChatViewModel` 新签名 `init(chatService:quota:books:)`,新属性 `let quota: QuotaService`

- [ ] **Step 1: 写失败测试 `Tomeet/TomeetTests/AIChatViewModelTests.swift`**

```swift
import Foundation
import Testing
@testable import Tomeet

struct AIChatViewModelTests {
    @MainActor
    private func makeQuota() -> QuotaService {
        QuotaService(
            baseURL: URL(string: "https://example.com/v1/quota")!,
            appToken: "test-token",
            deviceID: "test-device",
            session: MockURLProtocol.makeSession()
        )
    }

    @MainActor
    @Test func sendIsBlockedWhenQuotaExhausted() async {
        let quota = makeQuota()
        quota.noteExhausted(resetAt: nil)
        let viewModel = AIChatViewModel(
            chatService: MockChatService(chunkDelay: .zero),
            quota: quota,
            books: []
        )
        await viewModel.send("hello")
        #expect(viewModel.messages.isEmpty)
    }

    @MainActor
    @Test func sendStreamsWhenQuotaAvailable() async {
        let viewModel = AIChatViewModel(
            chatService: MockChatService(chunkDelay: .zero),
            quota: makeQuota(),
            books: []
        )
        await viewModel.send("hello")
        #expect(viewModel.messages.count == 2)
        #expect(viewModel.messages.last?.text.isEmpty == false)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test ... -only-testing:TomeetTests/AIChatViewModelTests`
Expected: 编译失败 — `AIChatViewModel` 没有 `quota` 参数

- [ ] **Step 3: 修改 `AIChatViewModel.swift`**

```swift
@MainActor
@Observable
final class AIChatViewModel {
    private let chatService: any ChatService
    let quota: QuotaService

    var messages: [ChatMessage] = []
    var selectedBook: Book?
    var isResponding = false

    init(chatService: (any ChatService)? = nil, quota: QuotaService? = nil, books: [Book] = []) {
        let quota = quota ?? QuotaService()
        self.quota = quota
        if let chatService {
            self.chatService = chatService
        } else {
            // 默认实参在调用点求值(非隔离上下文),DeepSeekChatService() 放这里会触发
            // MainActor 隔离告警;改为可选参数,在 @MainActor 的 init 体内构造默认值。
            var service = DeepSeekChatService()
            service.onQuotaRemaining = { remaining in
                Task { @MainActor in quota.noteRemaining(remaining) }
            }
            self.chatService = service
        }
        self.selectedBook = Self.mostRecentlyOpened(in: books)
    }
```

`send(_:)` 修改(exhausted 拦截 + 429 处理):

```swift
    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isResponding else { return }
        // UI 已禁用输入,这里双保险
        guard !quota.isExhausted else { return }

        messages.append(ChatMessage(role: .user, text: trimmed))
        let assistantID = UUID()
        messages.append(ChatMessage(id: assistantID, role: .assistant, text: ""))

        isResponding = true
        defer { isResponding = false }

        let stream = chatService.replyStream(to: messages, contextBook: selectedBook)
        do {
            for try await chunk in stream {
                guard let index = messages.firstIndex(where: { $0.id == assistantID }) else { return }
                messages[index].text += chunk
            }
        } catch ChatServiceError.quotaExceeded(let resetAt) {
            // 超额:移除空气泡,引导由 UI 面板承担
            quota.noteExhausted(resetAt: resetAt)
            messages.removeAll { $0.id == assistantID }
        } catch {
            guard let index = messages.firstIndex(where: { $0.id == assistantID }) else { return }
            messages[index].text = "Something went wrong. Please check your connection and try again."
        }
    }
```

- [ ] **Step 4: 修改 `AIAssistantView.swift`**

body 里 `.safeAreaInset(edge: .bottom) { inputBar }` 改为:

```swift
            .safeAreaInset(edge: .bottom) {
                if viewModel.quota.isExhausted {
                    exhaustedPanel
                } else {
                    inputBar
                }
            }
```

`.onAppear { viewModel.applyDefaultBook(from: books) }` 后面加:

```swift
            .task { await viewModel.quota.refresh() }
```

`inputBar` 改为带额度标签(完整替换现有 `inputBar`):

```swift
    private var inputBar: some View {
        VStack(spacing: 6) {
            if let remaining = viewModel.quota.remaining {
                Text(remaining == 1
                     ? "1 free conversation left today"
                     : "\(remaining) free conversations left today")
                    .font(.caption2)
                    .foregroundStyle(remaining <= 3 ? Theme.accent : Theme.inkTertiary)
            }
            HStack(spacing: 10) {
                TextField(inputPlaceholder, text: $input, axis: .vertical)
                    .font(.body)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Theme.card)
                    )
                    .onSubmit { send() }

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(canSend ? Theme.sendArrow : Theme.inkTertiary)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle().fill(canSend ? Theme.sendEnabled : Theme.inkFaint)
                        )
                }
                .disabled(!canSend)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.canvas)
    }
```

新增超额面板(放在 inputBar 之后):

```swift
    private var exhaustedPanel: some View {
        VStack(spacing: 8) {
            Text("That's today's 10 free conversations")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.ink)
            Text("Free conversations refresh at midnight.\nUnlimited conversations are coming with subscription.")
                .font(.caption)
                .foregroundStyle(Theme.inkTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .background(Theme.canvas)
    }
```

- [ ] **Step 5: 更新 `PRIVACY_POLICY.md`**

`### Information Collected Automatically` 一节的第一条替换为:

```markdown
- **Device information**: device model, iOS version, app version, and unique device identifiers used solely for crash analytics and for metering the daily free AI conversation quota (the vendor device identifier is stored with a daily counter on our server; it is not linked to your identity and is not used for tracking).
```

`**Last Updated:**` 改为 `2026-09-02`。

- [ ] **Step 6: 跑测试确认通过**

Run: `xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=<机型>'`(全量)
Expected: 全部 PASS

- [ ] **Step 7: Commit**

```bash
git add Tomeet/Tomeet/Views/AI/AIChatViewModel.swift \
        Tomeet/Tomeet/Views/AI/AIAssistantView.swift \
        Tomeet/TomeetTests/AIChatViewModelTests.swift \
        PRIVACY_POLICY.md
git commit -m "feat(app): quota-aware AI chat UI with exhausted state"
```

---

### Task 8: 部署与端到端验证

**Files:**
- 无代码改动;涉及服务器手动操作

- [ ] **Step 1: 服务器准备(用户手动,一次性)**

```bash
# 在生产服务器上执行(或让维护者执行):
sudo mkdir -p /var/lib/tomeet-bff
# 在 /opt/tomeet-bff/.env 追加:
#   QUOTA_DB_PATH=/var/lib/tomeet-bff/quota.db
#   DAILY_FREE_QUOTA=10
#   DAILY_GLOBAL_BUDGET=3000
```

- [ ] **Step 2: 部署**

```bash
bff/deploy.sh
```

Expected: `Deploy OK`,启动日志含 `daily_free_quota=10`

- [ ] **Step 3: 验证 BFF 行为(curl)**

```bash
TOKEN="<服务器 .env 里的 APP_TOKEN>"
# 查额度
curl -s https://tomeet-api.smallbeebee.com/v1/quota \
  -H "X-App-Token: $TOKEN" -H "X-Device-ID: curl-test"
# 期望: {"remaining":10,"resetAt":"..."}
# 缺设备 ID 应 400:
curl -s -o /dev/null -w '%{http_code}\n' -X POST https://tomeet-api.smallbeebee.com/v1/chat/completions \
  -H "X-App-Token: $TOKEN" -H "Content-Type: application/json" -d '{"stream":false}'
# 期望: 400
```

- [ ] **Step 4: App 端到端验证(真机或模拟器跑一次)**

跑 App(可用 `run` skill),进入 AI Tab 发一条消息:
- 输入框上方显示 "N free conversations left today"
- 发完后 N 减 1
- 杀掉 App 重进,剩余次数保持(服务器侧持久化)

- [ ] **Step 5: Commit 部署备忘(如有 .env 模板/文档更新则提交,否则跳过)**

---

## Self-Review 结论

- **Spec 覆盖**:QuotaStore/熔断/429+resetAt/X-Quota-Remaining → Task 1-2;`/v1/quota` + 环境变量 → Task 3;DeviceIDProvider/X-Device-ID → Task 4;429 解析 → Task 5;QuotaService → Task 6;额度 UI + 超额引导页 + 隐私政策 → Task 7;部署 → Task 8。第二期(StoreKit/entitlement)不在本计划,符合 spec 分期。
- **类型一致性**:`QuotaService` 的属性/方法名在 Task 6 定义、Task 7 使用(`remaining`/`isExhausted`/`noteExhausted`/`noteRemaining`/`refresh`),已对齐;`init(chatService:quota:books:)` 在 Task 7 定义并与测试一致。
- **已知取舍**:未认证请求(无 token)只占全局预算、不占设备配额(无设备 ID 可言,且有 IP 限流兜底);额度拉取失败不阻塞对话。
