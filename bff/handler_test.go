package main

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
)

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

func TestRejectsNonPost(t *testing.T) {
	p := newTestProxy(t)
	req := httptest.NewRequest(http.MethodGet, "/v1/chat/completions", nil)
	rec := httptest.NewRecorder()
	p.HandleCompletions(rec, req)
	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405, got %d", rec.Code)
	}
}

func TestRejectsMissingToken(t *testing.T) {
	p := newTestProxy(t)
	req := httptest.NewRequest(http.MethodPost, "/v1/chat/completions", strings.NewReader(`{"stream":false}`))
	rec := httptest.NewRecorder()
	p.HandleCompletions(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}
}

func TestRejectsWrongToken(t *testing.T) {
	p := newTestProxy(t)
	req := httptest.NewRequest(http.MethodPost, "/v1/chat/completions", strings.NewReader(`{"stream":false}`))
	req.Header.Set("X-App-Token", "wrong")
	rec := httptest.NewRecorder()
	p.HandleCompletions(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}
}

func TestRejectsOversizedBody(t *testing.T) {
	p := newTestProxy(t)
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

	p := newTestProxy(t)
	req := httptest.NewRequest(http.MethodPost, "/v1/chat/completions", strings.NewReader(`{"stream":false}`))
	req.Header.Set("X-App-Token", "test-token")
	req.Header.Set("X-Device-ID", "dev-test")
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

	p := newTestProxy(t)
	req := httptest.NewRequest(http.MethodPost, "/v1/chat/completions", strings.NewReader(`{"stream":true}`))
	req.Header.Set("X-App-Token", "test-token")
	req.Header.Set("X-Device-ID", "dev-test")
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

func TestUnauthenticatedDoesNotWriteDeviceQuota(t *testing.T) {
	newOKUpstream(t)
	p := newTestProxy(t)
	p.AllowUnauthenticated = true
	req := httptest.NewRequest(http.MethodPost, "/v1/chat/completions", strings.NewReader(`{"stream":false}`))
	req.Header.Set("X-Device-ID", "dev-x") // 无 X-App-Token,但携带设备 ID
	rec := httptest.NewRecorder()
	p.HandleCompletions(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	if got, _ := p.Store.globalCount(); got != 1 {
		t.Fatalf("global budget must count unauthenticated requests, got %d", got)
	}
	if got, _ := p.Store.deviceCount("dev-x"); got != 0 {
		t.Fatalf("unauthenticated request must not write device quota, got %d", got)
	}
}

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
