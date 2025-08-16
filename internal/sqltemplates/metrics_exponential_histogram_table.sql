-- OpenTelemetryデータのためのClickHouse Metrics Exponential Histogramテーブル スキーマ
-- このテーブルはExponential Histogramメトリクス データポイント（高度な分布測定値）を保存します
-- Exponential Histogramは指数的サイズのバケットを使用し、より良い精度とストレージ効率を実現します
-- OpenTelemetryメトリクス データモデルに基づく: https://opentelemetry.io/docs/specs/otel/metrics/data-model/

CREATE TABLE IF NOT EXISTS "%s"."%s" %s (
    -- ===== リソース識別 =====
    -- メトリクスを発行するリソース（サービス、ホスト、コンテナ）に関するメタデータ
    ResourceAttributes Map(LowCardinality(String), String) CODEC(ZSTD(1)),
                                                                  -- リソースメタデータ: service.name, host.name, k8s.pod.name
                                                                  -- Map型によりリソースプロパティの柔軟なクエリが可能
    ResourceSchemaUrl String CODEC(ZSTD(1)),                    -- リソース属性のスキーマ バージョンURL
    
    -- ===== インストルメンテーション スコープ =====
    -- メトリクス収集ライブラリ/フレームワークに関する情報
    ScopeName String CODEC(ZSTD(1)),                            -- インストルメンテーション ライブラリ名（例: "http-server", "database-client"）
    ScopeVersion String CODEC(ZSTD(1)),                         -- インストルメンテーション ライブラリのバージョン
    ScopeAttributes Map(LowCardinality(String), String) CODEC(ZSTD(1)),
                                                                  -- インストルメンテーション スコープに関する追加メタデータ
    ScopeDroppedAttrCount UInt32 CODEC(ZSTD(1)),               -- 制限により削除されたスコープ属性数
    ScopeSchemaUrl String CODEC(ZSTD(1)),                       -- スコープ属性のスキーマ バージョンURL
    
    -- ===== サービスとメトリクス識別 =====
    ServiceName LowCardinality(String) CODEC(ZSTD(1)),          -- グループ化とフィルタリングのためのサービス名
                                                                  -- LowCardinalityにより重複値が最適化される
    MetricName String CODEC(ZSTD(1)),                           -- メトリクス名（例: "http_request_duration", "memory_allocation_size"）
    MetricDescription String CODEC(ZSTD(1)),                    -- メトリクスの人間が読める説明
    MetricUnit String CODEC(ZSTD(1)),                           -- 測定単位（例: "seconds", "bytes", "1"）
    
    -- ===== メトリクス ディメンション =====
    -- メトリクス値にコンテキストを提供するラベル/ディメンション
    Attributes Map(LowCardinality(String), String) CODEC(ZSTD(1)),
                                                                  -- メトリクス ディメンション: method, endpoint, status_code, instance
                                                                  -- これらがユニークな時系列の識別子を作成する
    
    -- ===== 時間フィールド =====
    -- Exponential Histogram測定のタイムスタンプ情報
    StartTimeUnix DateTime64(9) CODEC(Delta, ZSTD(1)),          -- 測定期間の開始時刻
                                                                  -- 蓄積ウィンドウの理解に重要
    TimeUnix DateTime64(9) CODEC(Delta, ZSTD(1)),              -- このHistogramが観測されたタイムスタンプ
                                                                  -- クエリの主要な時間ディメンション
    
    -- ===== EXPONENTIAL HISTOGRAM中核値 =====
    -- 分布の基本統計サマリー
    Count UInt64 CODEC(Delta, ZSTD(1)),                        -- Histogramでの観測総数
                                                                  -- Deltaコーデックは単調増加カウンターに最適
    Sum Float64 CODEC(ZSTD(1)),                                 -- 全観測値の合計
                                                                  -- 平均の計算が可能: Sum/Count
    
    -- ===== EXPONENTIAL HISTOGRAMスケールとゼロバケット =====
    -- 指数バケット構造を定義する中核パラメータ
    Scale Int32 CODEC(ZSTD(1)),                                 -- バケット精度を決定するスケール パラメータ
                                                                  -- 高スケール = より多いバケット = より良い精度
                                                                  -- 典型的範囲: -10 ～ +15
    ZeroCount UInt64 CODEC(ZSTD(1)),                           -- 正確にゼロの観測数
                                                                  -- ゼロ値用の特別なバケット
    
    -- ===== 正のバケット =====
    -- 正の値に対する指数サイズのバケット
    PositiveOffset Int32 CODEC(ZSTD(1)),                       -- 最初の正のバケット インデックスのオフセット
                                                                  -- バケット配列のスパース表現を可能にする
    PositiveBucketCounts Array(UInt64) CODEC(ZSTD(1)),         -- 各正のバケットでの観測数
                                                                  -- 配列はスパース - 非ゼロバケットのみが保存される
                                                                  -- バケット境界: base^(scale) * 2^(offset + i)
    
    -- ===== 負のバケット =====  
    -- 負の値に対する指数サイズのバケット
    NegativeOffset Int32 CODEC(ZSTD(1)),                       -- 最初の負のバケット インデックスのオフセット
                                                                  -- 正のオフセットと対称
    NegativeBucketCounts Array(UInt64) CODEC(ZSTD(1)),         -- 各負のバケットでの観測数
                                                                  -- 正の値と同じ精度で負の値を処理
                                                                  -- バケット境界: -(base^(scale) * 2^(offset + i))
    
    -- ===== エグゼンプラー =====
    -- このExponential Histogramに寄与したサンプル トレース
    -- エグゼンプラーはレイテンシー パターンに寄与した特定のリクエストの特定に役立つ
    Exemplars Nested (
        FilteredAttributes Map(LowCardinality(String), String), -- 追加のエグゼンプラー属性（user.id, trace.sampledなど）
        TimeUnix DateTime64(9),                                  -- このエグゼンプラーがキャプチャされた時刻
        Value Float64,                                           -- 実際に測定された値（例: 特定のレイテンシー）
        SpanId String,                                           -- このエグゼンプラーを生成したトレースのSpan ID
        TraceId String                                           -- 深掘り分析用のTrace ID
    ) CODEC(ZSTD(1)),                                           -- Nested型により、1つのHistogramに複数のエグゼンプラーが可能
    
    -- ===== メタデータとフラグ =====
    Flags UInt32 CODEC(ZSTD(1)),                               -- OpenTelemetryデータポイントフラグ（将来の利用のために予約）
    
    -- ===== EXPONENTIAL HISTOGRAM拡張 =====
    -- 拡張統計情報のオプション フィールド  
    Min Float64 CODEC(ZSTD(1)),                                 -- 最小観測値（利用可能な場合）
                                                                  -- 分布の広がりの理解に有用
    Max Float64 CODEC(ZSTD(1)),                                 -- 最大観測値（利用可能な場合）
                                                                  -- 外れ値の特定と範囲分析に有用
    
    -- ===== 集約メタデータ =====
    AggregationTemporality Int32 CODEC(ZSTD(1)),               -- Histogramデータポイントの集約方法:
                                                                  -- 1 = DELTA（バケットは最後のレポート以降の変化を表す）
                                                                  -- 2 = CUMULATIVE（バケットは開始以降の合計を表す）
    
    -- ===== パフォーマンス インデックス =====
    -- Bloom filter indexes for high-speed attribute searches
    -- Critical for performance when filtering by dimensions/labels
    INDEX idx_res_attr_key mapKeys(ResourceAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
                                                                  -- Fast lookup of resource attribute keys
    INDEX idx_res_attr_value mapValues(ResourceAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
                                                                  -- Fast lookup of resource attribute values
    INDEX idx_scope_attr_key mapKeys(ScopeAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
                                                                  -- Fast lookup of scope attribute keys
    INDEX idx_scope_attr_value mapValues(ScopeAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
                                                                  -- Fast lookup of scope attribute values
    INDEX idx_attr_key mapKeys(Attributes) TYPE bloom_filter(0.01) GRANULARITY 1,
                                                                  -- Fast lookup of metric attribute keys (labels)
    INDEX idx_attr_value mapValues(Attributes) TYPE bloom_filter(0.01) GRANULARITY 1
                                                                  -- Fast lookup of metric attribute values (label values)
    ) ENGINE = %s
    %s
    PARTITION BY toDate(TimeUnix)                               -- Daily partitions for efficient data lifecycle management
    ORDER BY (ServiceName, MetricName, Attributes, toUnixTimestamp64Nano(TimeUnix))
                                                                  -- Optimal sort order for typical exponential histogram queries:
                                                                  -- 1. Filter by service
                                                                  -- 2. Filter by metric name (e.g., latency histograms)
                                                                  -- 3. Filter by dimensions (endpoint, method)
                                                                  -- 4. Time-based ordering for trend analysis
    SETTINGS index_granularity=8192, ttl_only_drop_parts = 1   -- Performance tuning:
                                                                  -- index_granularity: Balance memory vs precision
                                                                  -- ttl_only_drop_parts: Efficient partition-level TTL

-- EXPONENTIAL HISTOGRAM VS REGULAR HISTOGRAM COMPARISON:
-- Exponential Histograms:
-- - Exponentially-sized buckets with configurable precision (scale parameter)
-- - Automatic bucket boundary calculation: base^(scale) * 2^(bucket_index)
-- - More efficient storage for wide value ranges
-- - Better precision control with scale parameter
-- - Support for negative values with symmetric bucketing
-- - Native support in OpenTelemetry Protocol v1.0+
-- - Ideal for latency measurements with wide dynamic ranges
--
-- Regular Histograms:
-- - Fixed bucket boundaries defined at collection time
-- - Manual bucket boundary configuration required
-- - Good for known value distributions
-- - Simpler query logic for percentile calculations
-- - Better compatibility with Prometheus ecosystem
-- - Ideal for well-understood metrics with predictable ranges
