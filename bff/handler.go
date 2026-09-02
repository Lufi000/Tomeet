package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"strconv"
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

	Store             *QuotaStore
	DailyFreeQuota    int // 每设备每日免费次数
	DailyGlobalBudget int // 全局每日请求熔断

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
