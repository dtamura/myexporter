-- OpenTelemetryデータのためのClickHouse Metrics Sumテーブル スキーマ
-- このテーブルはSum/Counterメトリクス データポイント（累積またはデルタ測定値）を保存します
-- Sumメトリクスは時間とともに蓄積される値を表します（リクエスト数、転送バイト数、エラーなど）
-- OpenTelemetryメトリクス データモデルに基づく: https://opentelemetry.io/docs/specs/otel/metrics/data-model/

CREATE TABLE IF NOT EXISTS "%s"."%s" %s (
    -- ===== RESOURCE IDENTIFICATION =====
    -- Metadata about the resource (service, host, container) emitting metrics
    ResourceAttributes Map(LowCardinality(String), String) CODEC(ZSTD(1)),
                                                                  -- Resource metadata: service.name, host.name, k8s.pod.name  
                                                                  -- Map type enables flexible querying of resource properties
    ResourceSchemaUrl String CODEC(ZSTD(1)),                    -- Schema version URL for resource attributes
    
    -- ===== INSTRUMENTATION SCOPE =====
    -- Information about the metrics collection library/framework
    ScopeName String CODEC(ZSTD(1)),                            -- Name of instrumentation library (e.g., "prometheus", "custom-metrics")
    ScopeVersion String CODEC(ZSTD(1)),                         -- Version of instrumentation library
    ScopeAttributes Map(LowCardinality(String), String) CODEC(ZSTD(1)),
                                                                  -- Additional metadata about the instrumentation scope
    ScopeDroppedAttrCount UInt32 CODEC(ZSTD(1)),               -- Count of scope attributes dropped due to limits
    ScopeSchemaUrl String CODEC(ZSTD(1)),                       -- Schema version URL for scope attributes
    
    -- ===== SERVICE AND METRIC IDENTIFICATION =====
    ServiceName LowCardinality(String) CODEC(ZSTD(1)),          -- Service name for grouping and filtering
                                                                  -- LowCardinality optimizes for repeated values
    MetricName String CODEC(ZSTD(1)),                           -- Name of the metric (e.g., "http_requests_total", "bytes_sent")
    MetricDescription String CODEC(ZSTD(1)),                    -- Human-readable description of the metric
    MetricUnit String CODEC(ZSTD(1)),                           -- Unit of measurement (e.g., "1" for counts, "bytes", "seconds")
    
    -- ===== METRIC DIMENSIONS =====
    -- Labels/dimensions that provide context to the metric value
    Attributes Map(LowCardinality(String), String) CODEC(ZSTD(1)),
                                                                  -- Metric dimensions: method, status_code, endpoint, instance
                                                                  -- These create the unique time series identity
    
    -- ===== TEMPORAL FIELDS =====
    -- Timestamp information for sum measurements
    StartTimeUnix DateTime64(9) CODEC(Delta, ZSTD(1)),          -- When the accumulation period started
                                                                  -- Critical for delta vs cumulative interpretation
    TimeUnix DateTime64(9) CODEC(Delta, ZSTD(1)),              -- Timestamp when this sum value was observed
                                                                  -- Primary temporal dimension for queries
    
    -- ===== SUM VALUE =====
    -- The accumulated/summed value
    Value Float64 CODEC(ZSTD(1)),                               -- Sum measurement value
                                                                  -- For counters: typically monotonically increasing
                                                                  -- For delta sums: can be any value representing change
    
    -- ===== METADATA AND FLAGS =====
    Flags UInt32 CODEC(ZSTD(1)),                               -- OpenTelemetry data point flags (reserved for future use)
    
    -- ===== EXEMPLARS =====
    -- Sample traces that contributed to this metric data point
    -- Exemplars provide linkage between metrics and distributed traces for root cause analysis
    Exemplars Nested (
        FilteredAttributes Map(LowCardinality(String), String), -- Additional exemplar attributes
        TimeUnix DateTime64(9),                                  -- When this exemplar was captured
        Value Float64,                                           -- Value associated with this exemplar (often a single increment)
        SpanId String,                                           -- Span ID of the trace that generated this exemplar
        TraceId String                                           -- Trace ID for correlation with tracing data
    ) CODEC(ZSTD(1)),                                           -- Nested type allows multiple exemplars per data point
    
    -- ===== SUM-SPECIFIC METADATA =====
    AggregationTemporality Int32 CODEC(ZSTD(1)),               -- How data points are aggregated:
                                                                  -- 1 = DELTA (value represents change since last report)
                                                                  -- 2 = CUMULATIVE (value represents total since start)
    IsMonotonic Boolean CODEC(Delta, ZSTD(1)),                 -- Whether the sum only increases (true for counters)
                                                                  -- Delta codec efficient for boolean values
                                                                  -- Critical for rate calculations and alerting
    
    -- ===== PERFORMANCE INDEXES =====
    -- Bloom filter indexes for high-speed attribute searches
    -- Essential for performance when filtering by labels/dimensions
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
                                                                  -- Optimal sort order for typical metric queries:
                                                                  -- 1. Filter by service  
                                                                  -- 2. Filter by metric name
                                                                  -- 3. Filter by dimensions/labels
                                                                  -- 4. Time-based ordering for rate calculations
    SETTINGS index_granularity=8192, ttl_only_drop_parts = 1   -- Performance tuning:
                                                                  -- index_granularity: Balance memory vs precision
                                                                  -- ttl_only_drop_parts: Efficient partition-level TTL
