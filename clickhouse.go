// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

package myexporter

import (
	"context"
	"database/sql"
	"fmt"
	"net/url"

	"go.uber.org/zap"

	// ClickHouse driver - clickhouseexporterと同様
	_ "github.com/ClickHouse/clickhouse-go/v2"
)

var driverName = "clickhouse" // for testing - clickhouseexporterと同様

// buildDBConnection creates a database connection
// clickhouseexporterのnewClickhouseClient関数とbuildDB関数を参考
func buildDBConnection(cfg *Config) (*sql.DB, error) {
	return buildDB(cfg, cfg.Database)
}

// buildDB creates a database connection to specified database
// clickhouseexporterのbuildDB関数を参考
func buildDB(cfg *Config, database string) (*sql.DB, error) {
	dsn, err := buildDSN(cfg, database)
	if err != nil {
		return nil, err
	}

	// ClickHouse sql driver will read clickhouse settings from the DSN string.
	// clickhouseexporterと同様の実装
	conn, err := sql.Open(driverName, dsn)
	if err != nil {
		return nil, err
	}

	return conn, nil
}

// buildDSN constructs database connection string
// clickhouseexporterのbuildDSN関数を参考（アップデート版）
func buildDSN(cfg *Config, database string) (string, error) {
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

	// 圧縮設定を追加（clickhouseexporterアップデート版）
	if !queryParams.Has("compress") && (cfg.Compress == "" || cfg.Compress == "true") {
		queryParams.Set("compress", "lz4")
	} else if !queryParams.Has("compress") {
		queryParams.Set("compress", cfg.Compress)
	}

	// AsyncInsert設定を追加（clickhouseexporterアップデート版）
	if !queryParams.Has("async_insert") {
		queryParams.Set("async_insert", fmt.Sprintf("%t", cfg.AsyncInsert))
	}

	// データベース名を設定 - clickhouseexporterと同様のロジック
	if cfg.Database != "" {
		dsnURL.Path = cfg.Database
	}

	// Override database if specified in database param.
	if database != "" {
		dsnURL.Path = database
	}

	// Use default database if not specified in any other place.
	if database == "" && cfg.Database == "" && dsnURL.Path == "" {
		dsnURL.Path = "default"
	}

	// ユーザー名とパスワードを設定
	if cfg.Username != "" {
		dsnURL.User = url.UserPassword(cfg.Username, string(cfg.Password))
	}

	dsnURL.RawQuery = queryParams.Encode()
	return dsnURL.String(), nil
}

// createDatabase はデータベースのみを作成します（テーブルは作成しません）
// clickhouseexporterのCreateDatabase関数を参考にした実装（アップデート版）
func createDatabase(ctx context.Context, cfg *Config, logger *zap.Logger) error {
	// CreateSchemaが無効な場合は何もしない
	if !cfg.CreateSchema {
		logger.Info("スキーマ作成が無効化されています、データベース作成をスキップします")
		return nil
	}

	if cfg.Database == "" || cfg.Database == "default" {
		logger.Info("デフォルトデータベースを使用します、作成をスキップします")
		return nil
	}

	// データベース作成用に 'default' データベースに接続
	// clickhouseexporterと同様の実装
	db, err := buildDB(cfg, "default")
	if err != nil {
		return fmt.Errorf("データベース接続の構築に失敗しました: %w", err)
	}
	defer func() {
		_ = db.Close()
	}()

	// データベース作成クエリを実行 - clickhouseexporterと同様
	createDbQuery := fmt.Sprintf("CREATE DATABASE IF NOT EXISTS %s", cfg.Database)
	logger.Info("データベースを作成しています", zap.String("database", cfg.Database))

	_, err = db.ExecContext(ctx, createDbQuery)
	if err != nil {
		return fmt.Errorf("データベース作成に失敗しました: %w", err)
	}

	logger.Info("データベース作成が完了しました", zap.String("database", cfg.Database))
	return nil
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
