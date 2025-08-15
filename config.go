// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

package myexporter

import (
	"fmt"
	"time"

	"go.opentelemetry.io/collector/component"
	"go.opentelemetry.io/collector/config/configopaque"
	"go.opentelemetry.io/collector/config/configretry"
	"go.opentelemetry.io/collector/exporter/exporterhelper"
)

// Config は my-log エクスポーターの設定を定義します。
type Config struct {
	// エクスポーター標準設定（新しいAPIに対応）
	TimeoutSettings           exporterhelper.TimeoutConfig `mapstructure:",squash"`
	configretry.BackOffConfig `mapstructure:"retry_on_failure"`
	QueueSettings             exporterhelper.QueueBatchConfig `mapstructure:"sending_queue"`

	// 既存の設定
	Prefix   string `mapstructure:"prefix"`
	Detailed bool   `mapstructure:"detailed"`

	// DB接続設定（clickhouseexporterを参考）
	Endpoint         string              `mapstructure:"endpoint"`          // データベースのエンドポイント
	Username         string              `mapstructure:"username"`          // 認証用ユーザー名
	Password         configopaque.String `mapstructure:"password"`          // 認証用パスワード
	Database         string              `mapstructure:"database"`          // データベース名
	TableName        string              `mapstructure:"table_name"`        // テーブル名
	ConnectionParams map[string]string   `mapstructure:"connection_params"` // 追加接続パラメータ

	// 新しく追加された設定（clickhouseexporterと同様）
	CreateSchema    bool          `mapstructure:"create_schema"`     // データベース作成の制御
	Compress        string        `mapstructure:"compress"`          // 圧縮アルゴリズム
	AsyncInsert     bool          `mapstructure:"async_insert"`      // 非同期挿入
	TTL             time.Duration `mapstructure:"ttl"`               // データ保持期間
	TTLDays         int           `mapstructure:"ttl_days"`          // データ保持期間（日数）
	TracesTableName string        `mapstructure:"traces_table_name"` // トレーステーブル名
	LogsTableName   string        `mapstructure:"logs_table_name"`   // ログテーブル名
	TableEngine     string        `mapstructure:"table_engine"`      // ClickHouseテーブルエンジン
	ClusterName     string        `mapstructure:"cluster_name"`      // ClickHouseクラスタ名
}

func createDefaultConfig() component.Config {
	return &Config{
		TimeoutSettings:  exporterhelper.NewDefaultTimeoutConfig(),
		QueueSettings:    exporterhelper.NewDefaultQueueConfig(),
		BackOffConfig:    configretry.NewDefaultBackOffConfig(),
		Prefix:           "[MyLogExporter]",
		Detailed:         false,
		Database:         "otel",        // 独自のデータベース名
		TableName:        "otel_logs",   // ClickHouseらしいテーブル名
		TracesTableName:  "otel_traces", // トレーステーブル名
		LogsTableName:    "otel_logs",   // ログテーブル名
		ConnectionParams: map[string]string{},
		CreateSchema:     true,        // デフォルトでスキーマ作成を有効
		Compress:         "lz4",       // clickhouseexporterと同様のデフォルト圧縮
		AsyncInsert:      true,        // 非同期挿入をデフォルトで有効
		TTL:              0,           // デフォルトではTTL無効（0 = 無制限）
		TableEngine:      "MergeTree", // ClickHouseの標準的なエンジン
	}
}

// shouldCreateSchema - スキーマ作成が必要かどうかを判定します
func (cfg *Config) shouldCreateSchema() bool {
	return cfg.CreateSchema
}

// database - データベース名を返します（空の場合はdefaultを返す）
func (cfg *Config) database() string {
	if cfg.Database == "" {
		return "default"
	}
	return cfg.Database
}

// clusterString - クラスター指定文字列を生成します
func (cfg *Config) clusterString() string {
	if cfg.ClusterName == "" {
		return ""
	}
	return fmt.Sprintf("ON CLUSTER '%s'", cfg.ClusterName)
}

// tableEngineString - テーブルエンジン文字列を生成します
func (cfg *Config) tableEngineString() string {
	if cfg.TableEngine == "" {
		return "MergeTree"
	}
	return cfg.TableEngine
}
