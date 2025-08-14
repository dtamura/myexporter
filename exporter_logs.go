// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

package myexporter

import (
	"context"
	"database/sql"
	"fmt"

	"go.opentelemetry.io/collector/component"
	"go.opentelemetry.io/collector/consumer"
	"go.opentelemetry.io/collector/pdata/plog"
	"go.uber.org/zap"
)

type logsExporter struct {
	config *Config
	logger *zap.Logger
	db     *sql.DB // DB接続（clickhouseexporterを参考）
}

// newLogsExporter はログエクスポーターの新しいインスタンスを作成します
func newLogsExporter(logger *zap.Logger, cfg *Config) (*logsExporter, error) {
	var db *sql.DB
	var err error

	// DB接続が設定されている場合のみ接続を確立
	if cfg.Endpoint != "" {
		db, err = buildDBConnection(cfg)
		if err != nil {
			logger.Warn("データベース接続に失敗しました、ログ出力のみモードにフォールバックします", zap.Error(err))
		}
	}

	return &logsExporter{
		config: cfg,
		logger: logger,
		db:     db, // DB接続がない場合はnil
	}, nil
}

// Capabilities はログエクスポーターの機能を返します
func (e *logsExporter) Capabilities() consumer.Capabilities {
	return consumer.Capabilities{MutatesData: false}
}

// start はエクスポーター開始時に呼び出されます
// DB接続テストのみ実行、テーブル作成は行わない
func (e *logsExporter) start(ctx context.Context, host component.Host) error {
	e.logger.Info("ログエクスポーターを開始しています",
		zap.String("prefix", e.config.Prefix),
		zap.Bool("db_enabled", e.db != nil),
	)

	// DB接続が有効な場合、接続テストのみ実行
	if e.db != nil {
		if err := e.db.Ping(); err != nil {
			e.logger.Error("データベースへの接続テストに失敗しました", zap.Error(err))
			return err
		}
		e.logger.Info("データベース接続に成功しました")
	}

	return nil
}

// shutdown はエクスポーター終了時に呼び出されます
// clickhouseexporterのshutdown関数を参考
func (e *logsExporter) shutdown(ctx context.Context) error {
	e.logger.Info("ログエクスポーターを終了しています")

	if e.db != nil {
		return e.db.Close()
	}

	return nil
}

// pushLogs はログデータを受信して処理します
// exporterhelper経由で呼び出される実際のログデータ処理関数
// エラーが返された場合、exporterhelperが自動的にリトライやエラー処理を行う
func (e *logsExporter) pushLogs(ctx context.Context, ld plog.Logs) error {
	resourceLogs := ld.ResourceLogs()
	totalLogs := 0

	// 各リソースのログデータを処理
	for i := 0; i < resourceLogs.Len(); i++ {
		rl := resourceLogs.At(i)
		scopeLogs := rl.ScopeLogs()
		for j := 0; j < scopeLogs.Len(); j++ {
			sl := scopeLogs.At(j)
			logRecords := sl.LogRecords()
			totalLogs += logRecords.Len()

			// 詳細モードが有効な場合、各ログレコードの詳細情報をログ出力
			if e.config.Detailed {
				for k := 0; k < logRecords.Len(); k++ {
					lr := logRecords.At(k)
					e.logger.Info(fmt.Sprintf("%s ログを受信しました", e.config.Prefix),
						zap.String("severity", lr.SeverityText()),
						zap.String("body", lr.Body().AsString()),
						zap.Time("timestamp", lr.Timestamp().AsTime()),
					)
				}
			}

			// データ投入は無効化（DB接続テストのみ）
			// TODO: 将来的にデータ投入機能を実装予定
		}
	}

	// 処理したログデータのサマリーをログ出力
	e.logger.Info(fmt.Sprintf("%s ログ処理が完了しました", e.config.Prefix),
		zap.Int("resource_logs", resourceLogs.Len()),
		zap.Int("total_logs", totalLogs),
		zap.Bool("db_connected", e.db != nil),
	)

	return nil
}

// insertLogToDB は将来実装予定のDB挿入機能
// 現在は DB接続テストのみ実装
// func (e *logsExporter) insertLogToDB(ctx context.Context, lr plog.LogRecord) error {
// 	// TODO: ClickHouse用の挿入処理を実装
// 	return nil
// }
