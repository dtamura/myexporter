// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

package myexporter

import (
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
	CreateSchema bool   `mapstructure:"create_schema"` // データベース作成の制御
	Compress     string `mapstructure:"compress"`      // 圧縮アルゴリズム
	AsyncInsert  bool   `mapstructure:"async_insert"`  // 非同期挿入
}

func createDefaultConfig() component.Config {
	return &Config{
		TimeoutSettings:  exporterhelper.NewDefaultTimeoutConfig(),
		QueueSettings:    exporterhelper.NewDefaultQueueConfig(),
		BackOffConfig:    configretry.NewDefaultBackOffConfig(),
		Prefix:           "[MyLogExporter]",
		Detailed:         false,
		Database:         "default",   // ClickHouseのデフォルトデータベース
		TableName:        "otel_logs", // ClickHouseらしいテーブル名
		ConnectionParams: map[string]string{},
		CreateSchema:     true,  // デフォルトでスキーマ作成を有効
		Compress:         "lz4", // clickhouseexporterと同様のデフォルト圧縮
		AsyncInsert:      true,  // 非同期挿入をデフォルトで有効
	}
}
