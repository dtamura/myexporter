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
	"go.opentelemetry.io/collector/pdata/plog"
	"go.uber.org/zap"

	"github.com/dtamura/myexporter/internal"
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
// DB接続テスト、データベース作成、テーブル作成を実行
func (e *logsExporter) start(ctx context.Context, host component.Host) error {
	e.logger.Info("ログエクスポーターを開始しています",
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

		// 2. ログテーブル作成
		if err := e.createLogsTable(ctx); err != nil {
			e.logger.Error("ログテーブル作成に失敗しました", zap.Error(err))
			return err
		}

		// 3. 接続テスト
		if err := e.db.Ping(); err != nil {
			e.logger.Error("データベースへの接続テストに失敗しました", zap.Error(err))
			return err
		}
		e.logger.Info("データベース接続とテーブル作成に成功しました")
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
	var processingErr error

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

			// 現在はデータ投入を無効化（DB接続テストのみ）
			// TODO: 将来的にデータ投入機能を実装予定
			//
			// デモ目的：意図的にエラーをシミュレートしてメトリクスを生成
			// 8%の確率でエラーを発生させる（メトリクス確認用）
			if i%12 == 5 {
				processingErr = fmt.Errorf("デモエラー: ログ処理でシミュレートされたエラー (resource %d)", i)
				e.logger.Warn("ログ検証用のシミュレートエラー", zap.Error(processingErr))
			}
		}
	}

	// 処理したログデータのサマリーをログ出力
	e.logger.Info(fmt.Sprintf("%s ログ処理が完了しました", e.config.Prefix),
		zap.Int("resource_logs", resourceLogs.Len()),
		zap.Int("total_logs", totalLogs),
		zap.Bool("db_connected", e.db != nil),
		zap.Bool("has_error", processingErr != nil),
	)

	// エラーがある場合はそれを返す（exporterhelperがFailedメトリクスを記録）
	// エラーがない場合はnilを返す（exporterhelperがSentメトリクスを記録）
	return processingErr
}

// insertLogToDB は将来実装予定のDB挿入機能
// 現在は DB接続テストのみ実装
// func (e *logsExporter) insertLogToDB(ctx context.Context, lr plog.LogRecord) error {
// 	// TODO: ClickHouse用の挿入処理を実装
// 	return nil
// }

// createLogsTable は包括的なスキーマと最適化を持つログテーブルをClickHouseに作成します
func (e *logsExporter) createLogsTable(ctx context.Context) error {
	// ログテーブル作成用のSQLテンプレートを読み込み
	sqlTemplate, err := internal.LoadSQLTemplate("logs_table.sql")
	if err != nil {
		return fmt.Errorf("ログテーブルSQLテンプレートの読み込みに失敗しました: %w", err)
	}

	// 設定パラメータでSQLテンプレートをレンダリング
	sql := e.renderLogsTableSQL(sqlTemplate)

	// テーブル作成SQLを実行
	if err := e.executeSQL(ctx, sql); err != nil {
		return fmt.Errorf("ログテーブルの作成に失敗しました: %w", err)
	}

	e.logger.Info("ログテーブルが正常に作成されました",
		zap.String("table", e.getLogsTableName()),
		zap.String("database", e.config.Database))
	return nil
}

// renderLogsTableSQL は設定値でログテーブルSQLテンプレートをレンダリングします
func (e *logsExporter) renderLogsTableSQL(template string) string {
	// 実際の設定値でテンプレートパラメータを置換
	// テンプレートは順番に置換される %s プレースホルダーを使用:
	// 1. データベース名
	// 2. テーブル名
	// 3. クラスター句（該当する場合）
	// 4. エンジン句
	// 5. TTL句（設定されている場合）

	replacements := []string{
		e.config.Database,         // Database name
		e.getLogsTableName(),      // Table name
		e.buildClusterClause(),    // Cluster clause
		e.buildLogsEngineClause(), // Engine clause
		e.buildTTLClause(),        // TTL clause
	}

	// 順番に置換を適用
	sql := template
	for _, replacement := range replacements {
		sql = strings.Replace(sql, "%s", replacement, 1)
	}

	return sql
}

// getLogsTableName は適切なフォールバックを持つ設定済みログテーブル名を返します
func (e *logsExporter) getLogsTableName() string {
	if e.config.LogsTableName != "" {
		return e.config.LogsTableName
	}
	return "otel_logs" // OpenTelemetry命名規則に従ったデフォルトテーブル名
}

// buildLogsEngineClause はログテーブル用のClickHouseエンジン句を構築します
func (e *logsExporter) buildLogsEngineClause() string {
	switch {
	case e.config.ClusterName != "":
		// クラスター展開用の分散エンジン
		// 分散書き込み用に各シャードのローカルテーブルを指定
		return fmt.Sprintf("Distributed(%s, %s, %s_local, rand())",
			e.config.ClusterName, e.config.Database, e.getLogsTableName())
	default:
		// シングルノード展開用のMergeTreeエンジン
		// 自動マージ機能を持つ時系列ログデータに最適
		return "MergeTree()"
	}
}

// buildClusterClause はクラスター展開が設定されている場合にクラスター句を構築します
func (e *logsExporter) buildClusterClause() string {
	if e.config.ClusterName != "" {
		return fmt.Sprintf("ON CLUSTER %s", e.config.ClusterName)
	}
	return ""
}

// buildTTLClause は自動データ期限切れ用のTTL句を構築します
func (e *logsExporter) buildTTLClause() string {
	if e.config.TTLDays > 0 {
		// 自動クリーンアップ用にログタイムスタンプベースのTTL
		return fmt.Sprintf("TTL toDateTime(Timestamp) + toIntervalDay(%d)", e.config.TTLDays)
	}
	return ""
}

// executeSQL は適切なエラー処理とログ記録でSQL文を実行します
func (e *logsExporter) executeSQL(ctx context.Context, sql string) error {
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
