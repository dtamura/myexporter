// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

package myexporter

import (
	"context"
	"fmt"

	"go.opentelemetry.io/collector/component"
	"go.opentelemetry.io/collector/exporter"
	"go.opentelemetry.io/collector/exporter/exporterhelper"
)

const (
	typeStr = "mylogexporter" // component type
)

// NewFactory creates a factory for the my-log exporter.
func NewFactory() exporter.Factory {
	return exporter.NewFactory(
		component.MustNewType(typeStr),
		createDefaultConfig,
		exporter.WithTraces(createTracesExporter, component.StabilityLevelDevelopment),
		exporter.WithMetrics(createMetricsExporter, component.StabilityLevelDevelopment),
		exporter.WithLogs(createLogsExporter, component.StabilityLevelDevelopment),
	)
}

func createTracesExporter(
	ctx context.Context,
	set exporter.Settings,
	cfg component.Config,
) (exporter.Traces, error) {
	config := cfg.(*Config)
	exporter, err := newTracesExporter(set.Logger, config)
	if err != nil {
		return nil, fmt.Errorf("cannot configure my-log traces exporter: %w", err)
	}

	// exporterhelper.NewTracesを使用してトレースエクスポーターを作成
	// これにより、リトライ、キューイング、タイムアウトなどの標準機能が自動で組み込まれる
	return exporterhelper.NewTraces(ctx, set, cfg,
		exporter.pushTraces, // 実際のデータ送信処理を行う関数
		// clickhouseexporterと同様の設定を適用
		exporterhelper.WithStart(exporter.start),       // 開始時の処理（DB接続確認など）
		exporterhelper.WithShutdown(exporter.shutdown), // 終了時の処理（DB接続クローズなど）
		exporterhelper.WithTimeout(exporterhelper.TimeoutConfig{Timeout: config.Timeout}),
		exporterhelper.WithRetry(config.Retry),
		exporterhelper.WithQueue(config.Queue),
		// データを変更しないことを明示（読み取り専用）
		exporterhelper.WithCapabilities(exporter.Capabilities()),
	)
}

func createMetricsExporter(
	ctx context.Context,
	set exporter.Settings,
	cfg component.Config,
) (exporter.Metrics, error) {
	config := cfg.(*Config)
	exporter, err := newMetricsExporter(set.Logger, config)
	if err != nil {
		return nil, fmt.Errorf("cannot configure my-log metrics exporter: %w", err)
	}

	// exporterhelper.NewMetricsを使用してメトリクスエクスポーターを作成
	// 標準的なエラーハンドリング、リトライ機能などが自動で提供される
	return exporterhelper.NewMetrics(ctx, set, cfg,
		exporter.pushMetrics, // 実際のメトリクス処理を行う関数
		exporterhelper.WithStart(exporter.start),
		exporterhelper.WithShutdown(exporter.shutdown),
		exporterhelper.WithTimeout(exporterhelper.TimeoutConfig{Timeout: config.Timeout}),
		exporterhelper.WithRetry(config.Retry),
		exporterhelper.WithQueue(config.Queue),
		// データを変更しないことを明示（読み取り専用）
		exporterhelper.WithCapabilities(exporter.Capabilities()),
	)
}

func createLogsExporter(
	ctx context.Context,
	set exporter.Settings,
	cfg component.Config,
) (exporter.Logs, error) {
	config := cfg.(*Config)
	exporter, err := newLogsExporter(set.Logger, config)
	if err != nil {
		return nil, fmt.Errorf("cannot configure my-log logs exporter: %w", err)
	}

	// exporterhelper.NewLogsを使用してログエクスポーターを作成
	// バッチ処理、リトライ、メトリクス収集などの機能が自動で組み込まれる
	return exporterhelper.NewLogs(ctx, set, cfg,
		exporter.pushLogs, // 実際のログ処理を行う関数
		exporterhelper.WithStart(exporter.start),
		exporterhelper.WithShutdown(exporter.shutdown),
		exporterhelper.WithTimeout(exporterhelper.TimeoutConfig{Timeout: config.Timeout}),
		exporterhelper.WithRetry(config.Retry),
		exporterhelper.WithQueue(config.Queue),
		// データを変更しないことを明示（読み取り専用）
		exporterhelper.WithCapabilities(exporter.Capabilities()),
	)
}
