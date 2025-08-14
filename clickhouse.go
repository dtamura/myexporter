// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

package myexporter

import (
	"database/sql"
	"fmt"
	"net/url"

	// ClickHouse driver - clickhouseexporterと同様
	_ "github.com/ClickHouse/clickhouse-go/v2"
)

// buildDBConnection creates a database connection
// clickhouseexporterのbuildDB関数を参考
func buildDBConnection(cfg *Config) (*sql.DB, error) {
	dsn, err := buildDSN(cfg)
	if err != nil {
		return nil, err
	}

	// ClickHouseドライバーを使用（clickhouseexporterと同様）
	db, err := sql.Open("clickhouse", dsn)
	if err != nil {
		return nil, fmt.Errorf("failed to open database connection: %w", err)
	}

	// 接続テスト
	if err := db.Ping(); err != nil {
		db.Close()
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	return db, nil
}

// buildDSN constructs database connection string
// clickhouseexporterのbuildDSN関数を参考
func buildDSN(cfg *Config) (string, error) {
	if cfg.Endpoint == "" {
		return "", fmt.Errorf("endpoint must be specified")
	}

	dsnURL, err := url.Parse(cfg.Endpoint)
	if err != nil {
		return "", fmt.Errorf("invalid endpoint format: %w", err)
	}

	queryParams := dsnURL.Query()

	// 追加接続パラメータを適用
	for k, v := range cfg.ConnectionParams {
		queryParams.Set(k, v)
	}

	// HTTPSスキームの場合はセキュア接続を有効化（clickhouseexporterと同様）
	if dsnURL.Scheme == "https" {
		queryParams.Set("secure", "true")
	}

	// データベース名を設定
	if cfg.Database != "" {
		dsnURL.Path = "/" + cfg.Database
	}

	// ユーザー名とパスワードを設定
	if cfg.Username != "" {
		dsnURL.User = url.UserPassword(cfg.Username, string(cfg.Password))
	}

	dsnURL.RawQuery = queryParams.Encode()
	return dsnURL.String(), nil
}

// createDatabase と createTables は将来実装予定
// 現在は DB接続テストのみ実装

// func createDatabase(ctx context.Context, cfg *Config, logger *zap.Logger) error {
// 	// TODO: データベース作成処理を実装
// 	return nil
// }

// func createTables(ctx context.Context, cfg *Config, db *sql.DB, logger *zap.Logger) error {
// 	// TODO: テーブル作成処理を実装
// 	return nil
// }
