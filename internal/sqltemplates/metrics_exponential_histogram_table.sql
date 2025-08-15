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
                                                                  -- Metric dimensions: method, endpoint, status_code, instance
                                                                  -- These create the unique time series identity
    
    -- ===== TEMPORAL FIELDS =====
    -- Timestamp information for exponential histogram measurements
    StartTimeUnix DateTime64(9) CODEC(Delta, ZSTD(1)),          -- When the measurement period started
                                                                  -- Critical for understanding accumulation window
    TimeUnix DateTime64(9) CODEC(Delta, ZSTD(1)),              -- Timestamp when this histogram was observed
                                                                  -- Primary temporal dimension for queries
    
    -- ===== EXPONENTIAL HISTOGRAM CORE VALUES =====
    -- Essential summary statistics of the distribution
    Count UInt64 CODEC(Delta, ZSTD(1)),                        -- Total number of observations in the histogram
                                                                  -- Delta codec optimal for monotonically increasing counters
    Sum Float64 CODEC(ZSTD(1)),                                 -- Sum of all observed values
                                                                  -- Enables calculation of average: Sum/Count
    
    -- ===== EXPONENTIAL HISTOGRAM SCALE AND ZERO BUCKET =====
    -- Core parameters that define the exponential bucket structure
    Scale Int32 CODEC(ZSTD(1)),                                 -- Scale parameter that determines bucket precision
                                                                  -- Higher scale = more buckets = better precision
                                                                  -- Typical range: -10 to +15
    ZeroCount UInt64 CODEC(ZSTD(1)),                           -- Count of observations that are exactly zero
                                                                  -- Special bucket for zero values
    
    -- ===== POSITIVE BUCKETS =====
    -- Exponentially-sized buckets for positive values
    PositiveOffset Int32 CODEC(ZSTD(1)),                       -- Offset for the first positive bucket index
                                                                  -- Allows sparse representation of bucket arrays
    PositiveBucketCounts Array(UInt64) CODEC(ZSTD(1)),         -- Count of observations in each positive bucket
                                                                  -- Array is sparse - only non-zero buckets are stored
                                                                  -- Bucket boundaries: base^(scale) * 2^(offset + i)
    
    -- ===== NEGATIVE BUCKETS =====  
    -- Exponentially-sized buckets for negative values
    NegativeOffset Int32 CODEC(ZSTD(1)),                       -- Offset for the first negative bucket index
                                                                  -- Symmetric to positive offset
    NegativeBucketCounts Array(UInt64) CODEC(ZSTD(1)),         -- Count of observations in each negative bucket
                                                                  -- Handles negative values with same precision as positive
                                                                  -- Bucket boundaries: -(base^(scale) * 2^(offset + i))
    
    -- ===== EXEMPLARS =====
    -- Sample traces that contributed to this exponential histogram
    -- Exemplars help identify specific requests that contributed to latency patterns
    Exemplars Nested (
        FilteredAttributes Map(LowCardinality(String), String), -- Additional exemplar attributes (user.id, trace.sampled)
        TimeUnix DateTime64(9),                                  -- When this exemplar was captured
        Value Float64,                                           -- The actual measured value (e.g., specific latency)
        SpanId String,                                           -- Span ID of the trace that generated this exemplar
        TraceId String                                           -- Trace ID for deep-dive analysis
    ) CODEC(ZSTD(1)),                                           -- Nested type allows multiple exemplars per histogram
    
    -- ===== METADATA AND FLAGS =====
    Flags UInt32 CODEC(ZSTD(1)),                               -- OpenTelemetry data point flags (reserved for future use)
    
    -- ===== EXPONENTIAL HISTOGRAM EXTENSIONS =====
    -- Optional fields for enhanced statistical information  
    Min Float64 CODEC(ZSTD(1)),                                 -- Minimum observed value (if available)
                                                                  -- Useful for understanding distribution spread
    Max Float64 CODEC(ZSTD(1)),                                 -- Maximum observed value (if available)
                                                                  -- Useful for identifying outliers and range analysis
    
    -- ===== AGGREGATION METADATA =====
    AggregationTemporality Int32 CODEC(ZSTD(1)),               -- How histogram data points are aggregated:
                                                                  -- 1 = DELTA (buckets represent change since last report)
                                                                  -- 2 = CUMULATIVE (buckets represent total since start)
    
    -- ===== PERFORMANCE INDEXES =====
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
