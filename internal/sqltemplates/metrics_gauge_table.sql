-- ClickHouse Metrics Gauge Table Schema for OpenTelemetry Data
-- This table stores gauge metric data points (instantaneous measurements)
-- Gauge metrics represent a value that can go up and down arbitrarily (CPU usage, memory, temperature, etc.)
-- Based on OpenTelemetry metrics data model: https://opentelemetry.io/docs/specs/otel/metrics/data-model/

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
    MetricName String CODEC(ZSTD(1)),                           -- Name of the metric (e.g., "cpu_usage_percent", "memory_bytes")
    MetricDescription String CODEC(ZSTD(1)),                    -- Human-readable description of the metric
    MetricUnit String CODEC(ZSTD(1)),                           -- Unit of measurement (e.g., "percent", "bytes", "seconds")
    
    -- ===== METRIC DIMENSIONS =====
    -- Labels/dimensions that provide context to the metric value
    Attributes Map(LowCardinality(String), String) CODEC(ZSTD(1)),
                                                                  -- Metric dimensions: instance, job, endpoint, status_code
                                                                  -- These create the unique time series identity
    
    -- ===== TEMPORAL FIELDS =====
    -- Timestamp information for gauge measurements
    StartTimeUnix DateTime64(9) CODEC(Delta, ZSTD(1)),          -- When the measurement period started (for context)
                                                                  -- Delta codec optimal for time series data
    TimeUnix DateTime64(9) CODEC(Delta, ZSTD(1)),              -- Actual timestamp of the gauge measurement
                                                                  -- Primary temporal dimension for queries
    
    -- ===== GAUGE VALUE =====
    -- The actual measured value at the specific point in time
    Value Float64 CODEC(ZSTD(1)),                               -- Gauge measurement value (can be positive, negative, or zero)
                                                                  -- Float64 provides sufficient precision for most use cases
    
    -- ===== METADATA AND FLAGS =====
    Flags UInt32 CODEC(ZSTD(1)),                               -- OpenTelemetry data point flags (reserved for future use)
    
    -- ===== EXEMPLARS =====
    -- Sample traces that contributed to this metric data point
    -- Exemplars provide linkage between metrics and distributed traces
    Exemplars Nested (
        FilteredAttributes Map(LowCardinality(String), String), -- Additional exemplar attributes
        TimeUnix DateTime64(9),                                  -- When this exemplar was captured
        Value Float64,                                           -- Value associated with this exemplar
        SpanId String,                                           -- Span ID of the trace that generated this exemplar
        TraceId String                                           -- Trace ID for correlation with tracing data
    ) CODEC(ZSTD(1)),                                           -- Nested type allows multiple exemplars per data point
    
    -- ===== AGGREGATION METADATA =====
    AggregationTemporality Int32 CODEC(ZSTD(1)),               -- How data points are aggregated:
                                                                  -- 0 = UNSPECIFIED, 1 = DELTA, 2 = CUMULATIVE
    IsMonotonic Boolean CODEC(Delta, ZSTD(1)),                 -- Whether the gauge only increases (false for most gauges)
                                                                  -- Delta codec efficient for boolean values
    
    -- ===== PERFORMANCE INDEXES =====
    -- Bloom filter indexes for high-speed attribute searches
    -- Critical for performance when querying by labels/dimensions
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
                                                                  -- 4. Time-based ordering (newest first)
    SETTINGS index_granularity=8192, ttl_only_drop_parts = 1   -- Performance tuning:
                                                                  -- index_granularity: Balance memory vs precision
                                                                  -- ttl_only_drop_parts: Efficient partition-level TTL
