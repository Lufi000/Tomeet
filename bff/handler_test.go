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
