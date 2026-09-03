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
