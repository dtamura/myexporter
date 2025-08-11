// Package mylogexporter provides a custom OpenTelemetry Collector exporter
// that logs received telemetry data similar to the debug exporter.
package mylogexporter

import (
	"context"
	"fmt"

	"go.opentelemetry.io/collector/component"
	"go.opentelemetry.io/collector/consumer"
	"go.opentelemetry.io/collector/exporter"
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

type myLogExporter struct {
	config *Config
	logger *zap.Logger
}

func createTracesExporter(
	_ context.Context,
	set exporter.Settings,
	cfg component.Config,
) (exporter.Traces, error) {
	config := cfg.(*Config)
	return &myLogExporter{
		config: config,
		logger: set.Logger,
	}, nil
}

func createMetricsExporter(
	_ context.Context,
	set exporter.Settings,
	cfg component.Config,
) (exporter.Metrics, error) {
	config := cfg.(*Config)
	return &myLogExporter{
		config: config,
		logger: set.Logger,
	}, nil
}

func createLogsExporter(
	_ context.Context,
	set exporter.Settings,
	cfg component.Config,
) (exporter.Logs, error) {
	config := cfg.(*Config)
	return &myLogExporter{
		config: config,
		logger: set.Logger,
	}, nil
}

// Start is invoked during service startup.
func (e *myLogExporter) Start(ctx context.Context, host component.Host) error {
	e.logger.Info("My Log Exporter starting", zap.String("prefix", e.config.Prefix))
	return nil
}

// Shutdown is invoked during service shutdown.
func (e *myLogExporter) Shutdown(ctx context.Context) error {
	e.logger.Info("My Log Exporter shutting down")
	return nil
}

// Capabilities returns the capabilities of the exporter.
func (e *myLogExporter) Capabilities() consumer.Capabilities {
	return consumer.Capabilities{MutatesData: false}
}

// ConsumeTraces receives and processes trace data.
func (e *myLogExporter) ConsumeTraces(ctx context.Context, td ptrace.Traces) error {
	resourceSpans := td.ResourceSpans()
	totalSpans := 0
	
	for i := 0; i < resourceSpans.Len(); i++ {
		rs := resourceSpans.At(i)
		scopeSpans := rs.ScopeSpans()
		for j := 0; j < scopeSpans.Len(); j++ {
			ss := scopeSpans.At(j)
			spans := ss.Spans()
			totalSpans += spans.Len()
			
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
	
	e.logger.Info(fmt.Sprintf("%s Traces processed", e.config.Prefix),
		zap.Int("resource_spans", resourceSpans.Len()),
		zap.Int("total_spans", totalSpans),
	)
	
	return nil
}

// ConsumeMetrics receives and processes metric data.
func (e *myLogExporter) ConsumeMetrics(ctx context.Context, md pmetric.Metrics) error {
	resourceMetrics := md.ResourceMetrics()
	totalMetrics := 0
	
	for i := 0; i < resourceMetrics.Len(); i++ {
		rm := resourceMetrics.At(i)
		scopeMetrics := rm.ScopeMetrics()
		for j := 0; j < scopeMetrics.Len(); j++ {
			sm := scopeMetrics.At(j)
			metrics := sm.Metrics()
			totalMetrics += metrics.Len()
			
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
	
	e.logger.Info(fmt.Sprintf("%s Metrics processed", e.config.Prefix),
		zap.Int("resource_metrics", resourceMetrics.Len()),
		zap.Int("total_metrics", totalMetrics),
	)
	
	return nil
}

// ConsumeLogs receives and processes log data.
func (e *myLogExporter) ConsumeLogs(ctx context.Context, ld plog.Logs) error {
	resourceLogs := ld.ResourceLogs()
	totalLogs := 0
	
	for i := 0; i < resourceLogs.Len(); i++ {
		rl := resourceLogs.At(i)
		scopeLogs := rl.ScopeLogs()
		for j := 0; j < scopeLogs.Len(); j++ {
			sl := scopeLogs.At(j)
			logRecords := sl.LogRecords()
			totalLogs += logRecords.Len()
			
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
	
	e.logger.Info(fmt.Sprintf("%s Logs processed", e.config.Prefix),
		zap.Int("resource_logs", resourceLogs.Len()),
		zap.Int("total_logs", totalLogs),
	)
	
	return nil
}
