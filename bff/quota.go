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
