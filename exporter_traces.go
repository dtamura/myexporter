// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

package myexporter

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"go.opentelemetry.io/collector/component"
	"go.opentelemetry.io/collector/consumer"
	"go.opentelemetry.io/collector/pdata/ptrace"
	"go.uber.org/zap"
)

type tracesExporter struct {
	config *Config
	logger *zap.Logger
	db     *sql.DB // DB接続（clickhouseexporterを参考）
}

// newTracesExporter はトレースエクスポーターの新しいインスタンスを作成します
func newTracesExporter(logger *zap.Logger, cfg *Config) (*tracesExporter, error) {
	var db *sql.DB
	var err error

	// DB接続が設定されている場合のみ接続を確立
	if cfg.Endpoint != "" {
		db, err = buildDBConnection(cfg)
		if err != nil {
			logger.Warn("データベース接続に失敗しました、ログ出力のみモードにフォールバックします", zap.Error(err))
		}
	}

	return &tracesExporter{
		config: cfg,
		logger: logger,
		db:     db, // DB接続がない場合はnil
	}, nil
}

// Capabilities はトレースエクスポーターの機能を返します
func (e *tracesExporter) Capabilities() consumer.Capabilities {
	return consumer.Capabilities{MutatesData: false}
}

// start はエクスポーター開始時に呼び出されます
// DB接続テストとデータベース作成を実行（テーブル作成は行わない）
func (e *tracesExporter) start(ctx context.Context, host component.Host) error {
	e.logger.Info("トレースエクスポーターを開始しています",
		zap.String("prefix", e.config.Prefix),
		zap.Bool("db_enabled", e.db != nil),
	)

	// DB接続が有効な場合、データベース作成と接続テストを実行
	if e.db != nil {
		// 1. データベース作成（テーブル作成は無し）
		if err := createDatabase(ctx, e.config, e.logger); err != nil {
			e.logger.Error("データベース作成に失敗しました", zap.Error(err))
			return err
		}

		// 2. 接続テスト
		ctx, cancel := context.WithTimeout(ctx, time.Second*10)
		defer cancel()

		if err := e.db.PingContext(ctx); err != nil {
			e.logger.Error("データベースへの接続テストに失敗しました", zap.Error(err))
			return err
		}
		e.logger.Info("データベース接続に成功しました")
	}

	return nil
}

// shutdown はエクスポーター終了時に呼び出されます
// clickhouseexporterのshutdown関数を参考
func (e *tracesExporter) shutdown(ctx context.Context) error {
	e.logger.Info("トレースエクスポーターを終了しています")

	if e.db != nil {
		return e.db.Close()
	}

	return nil
}

// pushTraces はトレースデータを受信して処理します
// exporterhelper経由で呼び出される実際のトレースデータ処理関数
// エラーが返された場合、exporterhelperが自動的にリトライやエラー処理を行う
func (e *tracesExporter) pushTraces(ctx context.Context, td ptrace.Traces) error {
	resourceSpans := td.ResourceSpans()
	totalSpans := 0

	// 各リソースのスパンデータを処理
	for i := 0; i < resourceSpans.Len(); i++ {
		rs := resourceSpans.At(i)
		scopeSpans := rs.ScopeSpans()
		for j := 0; j < scopeSpans.Len(); j++ {
			ss := scopeSpans.At(j)
			spans := ss.Spans()
			totalSpans += spans.Len()

			// 詳細モードが有効な場合、各スパンの詳細情報をログ出力
			if e.config.Detailed {
				for k := 0; k < spans.Len(); k++ {
					span := spans.At(k)
					e.logger.Info(fmt.Sprintf("%s トレースを受信しました", e.config.Prefix),
						zap.String("span_id", span.SpanID().String()),
						zap.String("trace_id", span.TraceID().String()),
						zap.String("name", span.Name()),
						zap.String("kind", span.Kind().String()),
						zap.Duration("duration", span.EndTimestamp().AsTime().Sub(span.StartTimestamp().AsTime())),
					)
				}
			}

			// データ投入は無効化（DB接続テストのみ）
			// TODO: 将来的にデータ投入機能を実装予定
		}
	}

	// 処理したトレースデータのサマリーをログ出力
	e.logger.Info(fmt.Sprintf("%s トレース処理が完了しました", e.config.Prefix),
		zap.Int("resource_spans", resourceSpans.Len()),
		zap.Int("total_spans", totalSpans),
		zap.Bool("db_connected", e.db != nil),
	)

	return nil
}

// insertSpanToDB は将来実装予定のDB挿入機能
// 現在は DB接続テストのみ実装
// func (e *tracesExporter) insertSpanToDB(ctx context.Context, span ptrace.Span) error {
// 	// TODO: ClickHouse用の挿入処理を実装
// 	return nil
// }
