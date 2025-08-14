// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

package myexporter

import (
	"time"

	"go.opentelemetry.io/collector/component"
	"go.opentelemetry.io/collector/config/configopaque"
	"go.opentelemetry.io/collector/config/configretry"
	"go.opentelemetry.io/collector/exporter/exporterhelper"
)

// Config は my-log エクスポーターの設定を定義します。
type Config struct {
	// エクスポーター標準設定
	Timeout time.Duration                   `mapstructure:"timeout"`
	Retry   configretry.BackOffConfig       `mapstructure:"retry_on_failure"`
	Queue   exporterhelper.QueueBatchConfig `mapstructure:"sending_queue"`

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
}

func createDefaultConfig() component.Config {
	return &Config{
		Timeout:          5 * time.Second,
		Retry:            configretry.NewDefaultBackOffConfig(),
		Queue:            exporterhelper.QueueBatchConfig{Enabled: false},
		Prefix:           "[MyLogExporter]",
		Detailed:         false,
		Database:         "default",   // ClickHouseのデフォルトデータベース
		TableName:        "otel_logs", // ClickHouseらしいテーブル名
		ConnectionParams: map[string]string{},
	}
}
