// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

package myexporter

import (
	"context"
	"database/sql"
	"fmt"
	"strings"

	"go.opentelemetry.io/collector/component"
	"go.opentelemetry.io/collector/consumer"
	"go.opentelemetry.io/collector/pdata/pmetric"
	"go.uber.org/zap"

	"github.com/dtamura/myexporter/internal"
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
// DB接続テスト、データベース作成、メトリクステーブル作成を実行
func (e *metricsExporter) start(ctx context.Context, host component.Host) error {
	e.logger.Info("メトリクスエクスポーターを開始しています",
		zap.String("prefix", e.config.Prefix),
		zap.Bool("db_enabled", e.db != nil),
	)

	// DB接続が有効な場合、データベース・テーブル作成と接続テストを実行
	if e.db != nil {
		// 1. データベース作成
		if err := createDatabase(ctx, e.config, e.logger); err != nil {
			e.logger.Error("データベース作成に失敗しました", zap.Error(err))
			return err
		}

		// 2. メトリクステーブル作成（複数の種類）
		if err := e.createMetricsTables(ctx); err != nil {
			e.logger.Error("メトリクステーブル作成に失敗しました", zap.Error(err))
			return err
		}

		// 3. 接続テスト
		if err := e.db.Ping(); err != nil {
			e.logger.Error("データベースへの接続テストに失敗しました", zap.Error(err))
			return err
		}
		e.logger.Info("データベース接続とメトリクステーブル作成に成功しました")
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
	var processingErr error

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

			// 現在はデータ投入を無効化（DB接続テストのみ）
			// TODO: 将来的にデータ投入機能を実装予定
			//
			// デモ目的：意図的にエラーをシミュレートしてメトリクスを生成
			// 15%の確率でエラーを発生させる（メトリクス確認用）
			if i%15 == 11 {
				processingErr = fmt.Errorf("デモエラー: メトリクス処理でシミュレートされたエラー (resource %d)", i)
				e.logger.Warn("メトリクス検証用のシミュレートエラー", zap.Error(processingErr))
			}
		}
	}

	// 処理したメトリクスデータのサマリーをログ出力
	e.logger.Info(fmt.Sprintf("%s メトリクス処理が完了しました", e.config.Prefix),
		zap.Int("resource_metrics", resourceMetrics.Len()),
		zap.Int("total_metrics", totalMetrics),
		zap.Bool("db_connected", e.db != nil),
		zap.Bool("has_error", processingErr != nil),
	)

	// エラーがある場合はそれを返す（exporterhelperがFailedメトリクスを記録）
	// エラーがない場合はnilを返す（exporterhelperがSentメトリクスを記録）
	return processingErr
}

// insertMetricToDB は将来実装予定のDB挿入機能
// 現在は DB接続テストのみ実装
// func (e *metricsExporter) insertMetricToDB(ctx context.Context, metric pmetric.Metric) error {
// 	// TODO: ClickHouse用の挿入処理を実装
// 	return nil
// }

// createMetricsTables はClickHouseに必要なすべてのメトリクステーブルを作成します
// 異なるメトリクスタイプ（gauge, sum, histogram, summary）用に別々のテーブルを作成します
func (e *metricsExporter) createMetricsTables(ctx context.Context) error {
	// メトリクスタイプとそれに対応するテーブル名を定義
	metricTypes := []struct {
		templateFile string
		tableName    string
		description  string
	}{
		{"metrics_gauge_table.sql", "otel_metrics_gauge", "Gauge metrics (instantaneous values)"},
		{"metrics_sum_table.sql", "otel_metrics_sum", "Sum metrics (counters and cumulative values)"},
		{"metrics_histogram_table.sql", "otel_metrics_histogram", "Histogram metrics (distribution with buckets)"},
		{"metrics_summary_table.sql", "otel_metrics_summary", "Summary metrics (pre-calculated quantiles)"},
		{"metrics_exponential_histogram_table.sql", "otel_metrics_exponential_histogram", "Exponential histogram metrics (exponentially-sized buckets)"},
	}

	// 各メトリクステーブルタイプを作成
	for _, metricType := range metricTypes {
		if err := e.createMetricTable(ctx, metricType.templateFile, metricType.tableName, metricType.description); err != nil {
			return fmt.Errorf("%s の作成に失敗しました: %w", metricType.description, err)
		}
	}

	return nil
}

// createMetricTable は提供されたテンプレートを使用して特定のメトリクステーブルを作成します
func (e *metricsExporter) createMetricTable(ctx context.Context, templateFile, tableName, description string) error {
	// このメトリクステーブルタイプ用のSQLテンプレートを読み込み
	sqlTemplate, err := internal.LoadSQLTemplate(templateFile)
	if err != nil {
		return fmt.Errorf("%s SQLテンプレートの読み込みに失敗しました: %w", templateFile, err)
	}

	// 設定パラメータでSQLテンプレートをレンダリング
	sql := e.renderMetricTableSQL(sqlTemplate, tableName)

	// テーブル作成SQLを実行
	if err := e.executeSQL(ctx, sql); err != nil {
		return fmt.Errorf("%s テーブルの作成に失敗しました: %w", description, err)
	}

	e.logger.Info("メトリクステーブルが正常に作成されました",
		zap.String("table", tableName),
		zap.String("type", description),
		zap.String("database", e.config.Database))
	return nil
}

// renderMetricTableSQL は設定値でメトリクステーブルSQLテンプレートをレンダリングします
func (e *metricsExporter) renderMetricTableSQL(template, tableName string) string {
	// 実際の設定値でテンプレートパラメータを置換
	// テンプレートは順番に置換される %s プレースホルダーを使用:
	// 1. データベース名
	// 2. テーブル名
	// 3. クラスター句（該当する場合）
	// 4. エンジン句
	// 5. TTL句（設定されている場合）

	replacements := []string{
		e.config.Database,            // Database name
		tableName,                    // Specific metric table name
		e.buildClusterClause(),       // Cluster clause
		e.buildMetricsEngineClause(), // Engine clause
		e.buildTTLClause(),           // TTL clause
	}

	// 順番に置換を適用
	sql := template
	for _, replacement := range replacements {
		sql = strings.Replace(sql, "%s", replacement, 1)
	}

	return sql
}

// buildMetricsEngineClause はメトリクステーブル用のClickHouseエンジン句を構築します
func (e *metricsExporter) buildMetricsEngineClause() string {
	switch {
	case e.config.ClusterName != "":
		// クラスター展開用の分散エンジン
		return fmt.Sprintf("Distributed(%s, %s, %s_local, rand())",
			e.config.ClusterName, e.config.Database, "otel_metrics")
	default:
		// シングルノード展開用のMergeTreeエンジン
		// 時系列メトリクスデータに最適
		return "MergeTree()"
	}
}

// buildClusterClause はクラスター展開が設定されている場合にクラスター句を構築します
func (e *metricsExporter) buildClusterClause() string {
	if e.config.ClusterName != "" {
		return fmt.Sprintf("ON CLUSTER %s", e.config.ClusterName)
	}
	return ""
}

// buildTTLClause は自動データ期限切れ用のTTL句を構築します
func (e *metricsExporter) buildTTLClause() string {
	if e.config.TTLDays > 0 {
		// 自動クリーンアップ用にメトリクスタイムスタンプベースのTTL
		return fmt.Sprintf("TTL toDateTime(TimeUnix) + toIntervalDay(%d)", e.config.TTLDays)
	}
	return ""
}

// executeSQL は適切なエラー処理とログ記録でSQL文を実行します
func (e *metricsExporter) executeSQL(ctx context.Context, sql string) error {
	if e.db == nil {
		return fmt.Errorf("データベース接続が利用できません")
	}

	e.logger.Debug("SQL文を実行中", zap.String("sql", sql))

	_, err := e.db.ExecContext(ctx, sql)
	if err != nil {
		e.logger.Error("SQLの実行に失敗しました", zap.Error(err), zap.String("sql", sql))
		return fmt.Errorf("SQLの実行に失敗しました: %w", err)
	}

	return nil
}
