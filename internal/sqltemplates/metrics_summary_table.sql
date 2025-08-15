-- ClickHouse Metrics Summary Table Schema for OpenTelemetry Data  
-- This table stores summary metric data points (quantile-based distribution measurements)
-- Summaries represent pre-calculated quantiles of observed values (P50, P95, P99 latencies, etc.)
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
    ScopeName String CODEC(ZSTD(1)),                            -- Name of instrumentation library (e.g., "prometheus-client", "custom-metrics")
    ScopeVersion String CODEC(ZSTD(1)),                         -- Version of instrumentation library
    ScopeAttributes Map(LowCardinality(String), String) CODEC(ZSTD(1)),
                                                                  -- Additional metadata about the instrumentation scope
    ScopeDroppedAttrCount UInt32 CODEC(ZSTD(1)),               -- Count of scope attributes dropped due to limits
    ScopeSchemaUrl String CODEC(ZSTD(1)),                       -- Schema version URL for scope attributes
    
    -- ===== SERVICE AND METRIC IDENTIFICATION =====
    ServiceName LowCardinality(String) CODEC(ZSTD(1)),          -- Service name for grouping and filtering
                                                                  -- LowCardinality optimizes for repeated values
    MetricName String CODEC(ZSTD(1)),                           -- Name of the metric (e.g., "http_request_duration_summary", "gc_duration_summary")
    MetricDescription String CODEC(ZSTD(1)),                    -- Human-readable description of the metric
    MetricUnit String CODEC(ZSTD(1)),                           -- Unit of measurement (e.g., "seconds", "bytes", "1")
    
    -- ===== METRIC DIMENSIONS =====
    -- Labels/dimensions that provide context to the metric value
    Attributes Map(LowCardinality(String), String) CODEC(ZSTD(1)),
                                                                  -- Metric dimensions: job, instance, method, handler
                                                                  -- These create the unique time series identity
    
    -- ===== TEMPORAL FIELDS =====
    -- Timestamp information for summary measurements
    StartTimeUnix DateTime64(9) CODEC(Delta, ZSTD(1)),          -- When the observation period started
                                                                  -- Important for understanding the calculation window
    TimeUnix DateTime64(9) CODEC(Delta, ZSTD(1)),              -- Timestamp when this summary was observed
                                                                  -- Primary temporal dimension for queries
    
    -- ===== SUMMARY CORE VALUES =====
    -- Essential aggregation statistics
    Count UInt64 CODEC(Delta, ZSTD(1)),                        -- Total number of observations summarized
                                                                  -- Delta codec optimal for monotonically increasing counters
    Sum Float64 CODEC(ZSTD(1)),                                 -- Sum of all observed values
                                                                  -- Enables calculation of average: Sum/Count
    
    -- ===== QUANTILE VALUES =====
    -- Pre-calculated quantiles providing distribution insights
    -- Unlike histograms, summaries store exact quantile values calculated on the client side
    ValueAtQuantiles Nested(
        Quantile Float64,                                        -- Quantile level (e.g., 0.5 for median, 0.95 for P95, 0.99 for P99)
        Value Float64                                            -- Actual value at this quantile
    ) CODEC(ZSTD(1)),                                           -- Nested type allows multiple quantiles per summary
                                                                  -- Common quantiles: 0.5 (median), 0.9, 0.95, 0.99
                                                                  -- Enables direct SLA monitoring without bucket calculations
    
    -- ===== METADATA AND FLAGS =====
    Flags UInt32 CODEC(ZSTD(1)),                               -- OpenTelemetry data point flags (reserved for future use)
    
    -- ===== PERFORMANCE INDEXES =====
    -- Bloom filter indexes for high-speed attribute searches
    -- Essential for performance when querying by labels/dimensions
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
                                                                  -- Optimal sort order for typical summary queries:
                                                                  -- 1. Filter by service
                                                                  -- 2. Filter by metric name (e.g., latency summaries)
                                                                  -- 3. Filter by dimensions (job, instance)
                                                                  -- 4. Time-based ordering for trend analysis
    SETTINGS index_granularity=8192, ttl_only_drop_parts = 1   -- Performance tuning:
                                                                  -- index_granularity: Balance memory vs precision
                                                                  -- ttl_only_drop_parts: Efficient partition-level TTL

-- SUMMARY VS HISTOGRAM COMPARISON:
-- Summaries:
-- - Pre-calculated quantiles (P50, P95, P99) computed on client side
-- - Exact quantile values, no approximation
-- - Cannot aggregate across multiple instances
-- - Lower storage overhead for specific quantiles
-- - Ideal for client-side SLA monitoring
--
-- Histograms:  
-- - Bucket-based distribution with configurable bounds
-- - Quantiles calculated server-side from buckets (approximate)
-- - Can aggregate across multiple instances
-- - Higher storage overhead but more flexible
-- - Ideal for server-side analysis and aggregation
