// Package myexporter provides a custom OpenTelemetry Collector exporter
// that logs received telemetry data similar to the debug exporter.
package myexporter

import (
	"context"
	"fmt"

	"go.opentelemetry.io/collector/component"
	"go.opentelemetry.io/collector/consumer"
	"go.opentelemetry.io/collector/exporter"
	"go.opentelemetry.io/collector/exporter/exporterhelper"
	"go.opentelemetry.io/collector/pdata/plog"
	"go.opentelemetry.io/collector/pdata/pmetric"
	"go.opentelemetry.io/collector/pdata/ptrace"
	"go.uber.org/zap"
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

// Config defines configuration for the my-log exporter.
type Config struct {
	// Prefix is added to each log message
	Prefix string `mapstructure:"prefix"`
	// Detailed enables more verbose logging
	Detailed bool `mapstructure:"detailed"`
}

func createDefaultConfig() component.Config {
	return &Config{
		Prefix:   "[MyLogExporter]",
		Detailed: false,
	}
}

// myLogExporter はテレメトリーデータをログ出力するカスタムエクスポーター
// exporterhelperを使用することで、標準的なエラーハンドリングや設定管理が自動化される
type myLogExporter struct {
	config *Config
	logger *zap.Logger
}

func createTracesExporter(
	ctx context.Context,
	set exporter.Settings,
	cfg component.Config,
) (exporter.Traces, error) {
	config := cfg.(*Config)
	exporter := &myLogExporter{
		config: config,
		logger: set.Logger,
	}
	// exporterhelper.NewTracesを使用してトレースエクスポーターを作成
	// これにより、リトライ、キューイング、タイムアウトなどの標準機能が自動で組み込まれる
	return exporterhelper.NewTraces(ctx, set, cfg,
		exporter.pushTraces, // 実際のデータ送信処理を行う関数
		// データを変更しないことを明示（読み取り専用）
		exporterhelper.WithCapabilities(consumer.Capabilities{MutatesData: false}),
		// タイムアウト設定: 0は無制限を意味する（ログ出力のため即座に完了するので制限不要）
		exporterhelper.WithTimeout(exporterhelper.TimeoutConfig{Timeout: 0}),
	)
}

func createMetricsExporter(
	ctx context.Context,
	set exporter.Settings,
	cfg component.Config,
) (exporter.Metrics, error) {
	config := cfg.(*Config)
	exporter := &myLogExporter{
		config: config,
		logger: set.Logger,
	}
	// exporterhelper.NewMetricsを使用してメトリクスエクスポーターを作成
	// 標準的なエラーハンドリング、リトライ機能などが自動で提供される
	return exporterhelper.NewMetrics(ctx, set, cfg,
		exporter.pushMetrics, // 実際のメトリクス処理を行う関数
		// データを変更しないことを明示（読み取り専用）
		exporterhelper.WithCapabilities(consumer.Capabilities{MutatesData: false}),
		// タイムアウト設定: 0は無制限（ログ出力は高速なのでタイムアウト不要）
		exporterhelper.WithTimeout(exporterhelper.TimeoutConfig{Timeout: 0}),
	)
}

func createLogsExporter(
	ctx context.Context,
	set exporter.Settings,
	cfg component.Config,
) (exporter.Logs, error) {
	config := cfg.(*Config)
	exporter := &myLogExporter{
		config: config,
		logger: set.Logger,
	}
	// exporterhelper.NewLogsを使用してログエクスポーターを作成
	// バッチ処理、リトライ、メトリクス収集などの機能が自動で組み込まれる
	return exporterhelper.NewLogs(ctx, set, cfg,
		exporter.pushLogs, // 実際のログ処理を行う関数
		// データを変更しないことを明示（読み取り専用）
		exporterhelper.WithCapabilities(consumer.Capabilities{MutatesData: false}),
		// タイムアウト設定: 0は無制限（ログ出力は即座に完了するためタイムアウト不要）
		exporterhelper.WithTimeout(exporterhelper.TimeoutConfig{Timeout: 0}),
	)
}

// exporterhelper経由で呼び出される実際のトレースデータ処理関数
// エラーが返された場合、exporterhelperが自動的にリトライやエラー処理を行う
func (e *myLogExporter) pushTraces(ctx context.Context, td ptrace.Traces) error {
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
					e.logger.Info(fmt.Sprintf("%s Trace received", e.config.Prefix),
						zap.String("span_id", span.SpanID().String()),
						zap.String("trace_id", span.TraceID().String()),
						zap.String("name", span.Name()),
						zap.String("kind", span.Kind().String()),
						zap.Duration("duration", span.EndTimestamp().AsTime().Sub(span.StartTimestamp().AsTime())),
					)
				}
			}
		}
	}

	// 処理したトレースデータのサマリーをログ出力
	e.logger.Info(fmt.Sprintf("%s Traces processed", e.config.Prefix),
		zap.Int("resource_spans", resourceSpans.Len()),
		zap.Int("total_spans", totalSpans),
	)

	return nil
}

// exporterhelper経由で呼び出される実際のメトリクスデータ処理関数
// 処理に失敗した場合のリトライやエラー処理はexporterhelperが自動で行う
func (e *myLogExporter) pushMetrics(ctx context.Context, md pmetric.Metrics) error {
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
					e.logger.Info(fmt.Sprintf("%s Metric received", e.config.Prefix),
						zap.String("name", metric.Name()),
						zap.String("description", metric.Description()),
						zap.String("unit", metric.Unit()),
						zap.String("type", metric.Type().String()),
					)
				}
			}
		}
	}

	// 処理したメトリクスデータのサマリーをログ出力
	e.logger.Info(fmt.Sprintf("%s Metrics processed", e.config.Prefix),
		zap.Int("resource_metrics", resourceMetrics.Len()),
		zap.Int("total_metrics", totalMetrics),
	)

	return nil
}

// exporterhelper経由で呼び出される実際のログデータ処理関数
// バッチ処理やメトリクス収集などの付加機能はexporterhelperが自動で提供
func (e *myLogExporter) pushLogs(ctx context.Context, ld plog.Logs) error {
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
					logRecord := logRecords.At(k)
					e.logger.Info(fmt.Sprintf("%s Log received", e.config.Prefix),
						zap.String("severity", logRecord.SeverityText()),
						zap.String("body", logRecord.Body().AsString()),
						zap.Time("timestamp", logRecord.Timestamp().AsTime()),
					)
				}
			}
		}
	}

	// 処理したログデータのサマリーをログ出力
	e.logger.Info(fmt.Sprintf("%s Logs processed", e.config.Prefix),
		zap.Int("resource_logs", resourceLogs.Len()),
		zap.Int("total_logs", totalLogs),
	)

	return nil
}
