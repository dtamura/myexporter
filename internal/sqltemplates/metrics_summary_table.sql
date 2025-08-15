-- ClickHouse メトリクス Summary テーブル スキーマ (OpenTelemetry データ用)
-- このテーブルはsummaryメトリクスデータポイント（分位数ベースの分布測定）を格納します
-- Summariesは観測値の事前計算済み分位数を表します（P50、P95、P99レイテンシなど）
-- OpenTelemetry メトリクスデータモデルに基づく: https://opentelemetry.io/docs/specs/otel/metrics/data-model/

CREATE TABLE IF NOT EXISTS "%s"."%s" %s (
    -- ===== リソース識別 =====
    -- メトリクスを出力するリソース（サービス、ホスト、コンテナ）に関するメタデータ
    ResourceAttributes Map(LowCardinality(String), String) CODEC(ZSTD(1)),
                                                                  -- リソースメタデータ: service.name, host.name, k8s.pod.name
                                                                  -- Map型によりリソースプロパティの柔軟なクエリが可能
    ResourceSchemaUrl String CODEC(ZSTD(1)),                    -- リソース属性のスキーマバージョンURL
    
    -- ===== インストルメンテーションスコープ =====
    -- メトリクス収集ライブラリ/フレームワークに関する情報
    ScopeName String CODEC(ZSTD(1)),                            -- インストルメンテーションライブラリ名 (例: "prometheus-client", "custom-metrics")
    ScopeVersion String CODEC(ZSTD(1)),                         -- インストルメンテーションライブラリのバージョン
    ScopeAttributes Map(LowCardinality(String), String) CODEC(ZSTD(1)),
                                                                  -- インストルメンテーションスコープに関する追加メタデータ
    ScopeDroppedAttrCount UInt32 CODEC(ZSTD(1)),               -- 制限により削除されたスコープ属性の数
    ScopeSchemaUrl String CODEC(ZSTD(1)),                       -- スコープ属性のスキーマバージョンURL
    
    -- ===== サービスとメトリクス識別 =====
    ServiceName LowCardinality(String) CODEC(ZSTD(1)),          -- グループ化とフィルタリング用のサービス名
                                                                  -- LowCardinalityは反復値に対して最適化
    MetricName String CODEC(ZSTD(1)),                           -- メトリクス名 (例: "http_request_duration_summary", "gc_duration_summary")
    MetricDescription String CODEC(ZSTD(1)),                    -- メトリクスの人間が読める説明
    MetricUnit String CODEC(ZSTD(1)),                           -- 測定単位 (例: "seconds", "bytes", "1")
    
    -- ===== メトリクスディメンション =====
    -- メトリクス値にコンテキストを提供するラベル/ディメンション
    Attributes Map(LowCardinality(String), String) CODEC(ZSTD(1)),
                                                                  -- メトリクスディメンション: job, instance, method, handler
                                                                  -- これらがユニークな時系列アイデンティティを作成
    
    -- ===== 時系列フィールド =====
    -- summaryメトリクス測定のタイムスタンプ情報
    StartTimeUnix DateTime64(9) CODEC(Delta, ZSTD(1)),          -- 観測期間の開始時刻
                                                                  -- 計算ウィンドウの理解に重要
    TimeUnix DateTime64(9) CODEC(Delta, ZSTD(1)),              -- このsummaryが観測された時刻
                                                                  -- クエリの主要な時系列ディメンション
    
    -- ===== サマリー コア値 =====
    -- 重要な集計統計
    Count UInt64 CODEC(Delta, ZSTD(1)),                        -- サマリー化された観測値の総数
                                                                  -- 単調増加カウンターにDeltaコーデックが最適
    Sum Float64 CODEC(ZSTD(1)),                                 -- すべての観測値の合計
                                                                  -- 平均値の計算を可能にする: Sum/Count
    
    -- ===== 分位数値 =====
    -- 分布の洞察を提供する事前計算された分位数
    -- ヒストグラムとは異なり、Summaryはクライアント側で計算された正確な分位数値を保存します
    ValueAtQuantiles Nested(
        Quantile Float64,                                        -- 分位数レベル (例: 0.5は中央値、0.95はP95、0.99はP99)
        Value Float64                                            -- この分位数における実際の値
    ) CODEC(ZSTD(1)),                                           -- Nested型により、1つのSummaryに複数の分位数を格納可能
                                                                  -- 一般的な分位数: 0.5 (中央値), 0.9, 0.95, 0.99
                                                                  -- バケット計算なしで直接SLAモニタリングが可能
    
    -- ===== メタデータとフラグ =====
    Flags UInt32 CODEC(ZSTD(1)),                               -- OpenTelemetryデータポイントフラグ (将来の利用のために予約)
    
    -- ===== パフォーマンス インデックス =====
    -- 高速属性検索のためのBloomフィルタインデックス
    -- ラベル/ディメンションによるクエリのパフォーマンスに必須
    INDEX idx_res_attr_key mapKeys(ResourceAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
                                                                  -- リソース属性キーの高速検索
    INDEX idx_res_attr_value mapValues(ResourceAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
                                                                  -- リソース属性値の高速検索
    INDEX idx_scope_attr_key mapKeys(ScopeAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
                                                                  -- スコープ属性キーの高速検索
    INDEX idx_scope_attr_value mapValues(ScopeAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
                                                                  -- スコープ属性値の高速検索
    INDEX idx_attr_key mapKeys(Attributes) TYPE bloom_filter(0.01) GRANULARITY 1,
                                                                  -- メトリクス属性キー（ラベル）の高速検索
    INDEX idx_attr_value mapValues(Attributes) TYPE bloom_filter(0.01) GRANULARITY 1
                                                                  -- メトリクス属性値（ラベル値）の高速検索
    ) ENGINE = %s
    %s
    PARTITION BY toDate(TimeUnix)                               -- 効率的なデータライフサイクル管理のための日次パーティション
    ORDER BY (ServiceName, MetricName, Attributes, toUnixTimestamp64Nano(TimeUnix))
                                                                  -- 典型的なSummaryクエリに最適化されたソート順序:
                                                                  -- 1. サービス名でフィルタ
                                                                  -- 2. メトリクス名でフィルタ（例: レイテンシーサマリー）
                                                                  -- 3. ディメンションでフィルタ（job, instanceなど）
                                                                  -- 4. トレンド分析のための時系列順序
    SETTINGS index_granularity=8192, ttl_only_drop_parts = 1   -- パフォーマンス調整:
                                                                  -- index_granularity: メモリと精度のバランス調整
                                                                  -- ttl_only_drop_parts: パーティション レベルの効率的なTTL

-- SUMMARY VS HISTOGRAMの比較:
-- Summary:
-- - クライアント側で計算された事前計算済み分位数（P50, P95, P99）
-- - 正確な分位数値、近似値なし
-- - 複数のインスタンス間で集約不可
-- - 特定の分位数に対するストレージオーバーヘッドが低い
-- - クライアント側SLAモニタリングに最適
--
-- Histogram:  
-- - 設定可能な境界を持つバケット ベースの分布
-- - バケットからサーバー側で分位数を計算（近似値）
-- - 複数のインスタンス間で集約可能
-- - ストレージオーバーヘッドが高いが、より柔軟
-- - サーバー側分析と集約に最適
