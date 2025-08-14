// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

package myexporter

import (
	"go.opentelemetry.io/collector/component"
	"go.opentelemetry.io/collector/config/configopaque"
	"go.opentelemetry.io/collector/exporter/exporterhelper"
)

// Config は my-log エクスポーターの設定を定義します。
type Config struct {
	// exporterhelper標準設定
	exporterhelper.TimeoutSettings `mapstructure:",squash"`
	exporterhelper.RetrySettings   `mapstructure:"retry_on_failure"`
	exporterhelper.QueueSettings   `mapstructure:"sending_queue"`

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
	// clickhouseexporterと同様の標準設定を適用
	queueSettings := exporterhelper.NewDefaultQueueSettings()
	queueSettings.NumConsumers = 1

	return &Config{
		TimeoutSettings:  exporterhelper.NewDefaultTimeoutSettings(),
		QueueSettings:    queueSettings,
		RetrySettings:    exporterhelper.NewDefaultRetrySettings(),
		Prefix:           "[MyLogExporter]",
		Detailed:         false,
		Database:         "default",   // ClickHouseのデフォルトデータベース
		TableName:        "otel_logs", // ClickHouseらしいテーブル名
		ConnectionParams: map[string]string{},
	}
}
