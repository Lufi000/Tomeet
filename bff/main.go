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
