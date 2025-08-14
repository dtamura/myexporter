// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

package myexporter

import (
	"context"
	"database/sql"
	"fmt"

	"go.opentelemetry.io/collector/component"
	"go.opentelemetry.io/collector/consumer"
	"go.opentelemetry.io/collector/pdata/pmetric"
	"go.uber.org/zap"
)

type metricsExporter struct {
	config *Config
	logger *zap.Logger
	db     *sql.DB // DB接続（clickhouseexporterを参考）
}

// newMetricsExporter はメトリクスエクスポーターの新しいインスタンスを作成します
func newMetricsExporter(logger *zap.Logger, cfg *Config) (*metricsExporter, error) {
	var db *sql.DB
	var err error

	// DB接続が設定されている場合のみ接続を確立
	if cfg.Endpoint != "" {
		db, err = buildDBConnection(cfg)
		if err != nil {
			logger.Warn("データベース接続に失敗しました、ログ出力のみモードにフォールバックします", zap.Error(err))
		}
	}

	return &metricsExporter{
		config: cfg,
		logger: logger,
		db:     db, // DB接続がない場合はnil
	}, nil
}

// Capabilities はメトリクスエクスポーターの機能を返します
func (e *metricsExporter) Capabilities() consumer.Capabilities {
	return consumer.Capabilities{MutatesData: false}
}

// start はエクスポーター開始時に呼び出されます
// DB接続テストのみ実行、テーブル作成は行わない
func (e *metricsExporter) start(ctx context.Context, host component.Host) error {
	e.logger.Info("メトリクスエクスポーターを開始しています",
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
} // shutdown はエクスポーター終了時に呼び出されます
// clickhouseexporterのshutdown関数を参考
func (e *metricsExporter) shutdown(ctx context.Context) error {
	e.logger.Info("メトリクスエクスポーターを終了しています")

	if e.db != nil {
		return e.db.Close()
	}

	return nil
}

// pushMetrics はメトリクスデータを受信して処理します
// exporterhelper経由で呼び出される実際のメトリクスデータ処理関数
// 処理に失敗した場合のリトライやエラー処理はexporterhelperが自動で行う
func (e *metricsExporter) pushMetrics(ctx context.Context, md pmetric.Metrics) error {
	resourceMetrics := md.ResourceMetrics()
	totalMetrics := 0

	// 各リソースのメトリクスデータを処理
	for i := 0; i < resourceMetrics.Len(); i++ {
		rm := resourceMetrics.At(i)
		scopeMetrics := rm.ScopeMetrics()
		for j := 0; j < scopeMetrics.Len(); j++ {
			sm := scopeMetrics.At(j)
			metrics := sm.Metrics()
			totalMetrics += metrics.Len()

			// 詳細モードが有効な場合、各メトリクスの詳細情報をログ出力
			if e.config.Detailed {
				for k := 0; k < metrics.Len(); k++ {
					metric := metrics.At(k)
					e.logger.Info(fmt.Sprintf("%s メトリクスを受信しました", e.config.Prefix),
						zap.String("name", metric.Name()),
						zap.String("description", metric.Description()),
						zap.String("unit", metric.Unit()),
						zap.String("type", metric.Type().String()),
					)
				}
			}

			// データ投入は無効化（DB接続テストのみ）
			// TODO: 将来的にデータ投入機能を実装予定
		}
	}

	// 処理したメトリクスデータのサマリーをログ出力
	e.logger.Info(fmt.Sprintf("%s メトリクス処理が完了しました", e.config.Prefix),
		zap.Int("resource_metrics", resourceMetrics.Len()),
		zap.Int("total_metrics", totalMetrics),
		zap.Bool("db_connected", e.db != nil),
	)

	return nil
}

// insertMetricToDB は将来実装予定のDB挿入機能
// 現在は DB接続テストのみ実装
// func (e *metricsExporter) insertMetricToDB(ctx context.Context, metric pmetric.Metric) error {
// 	// TODO: ClickHouse用の挿入処理を実装
// 	return nil
// }
