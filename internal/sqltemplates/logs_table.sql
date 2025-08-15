-- ClickHouse Logs Table Schema for OpenTelemetry Data
-- This table stores structured log data with comprehensive indexing and optimization
-- Based on OpenTelemetry logs data model: https://opentelemetry.io/docs/specs/otel/logs/data-model/

CREATE TABLE IF NOT EXISTS "%s"."%s" %s (
    -- ===== TIMESTAMP FIELDS =====
    -- These fields handle the critical temporal aspects of log data
    Timestamp DateTime64(9) CODEC(Delta, ZSTD(1)),              -- Primary log event timestamp with nanosecond precision
                                                                  -- Delta codec is optimal for time series data
    ObservedTimestamp DateTime64(9) CODEC(Delta, ZSTD(1)),      -- When the log was observed/collected
                                                                  -- Often differs from Timestamp in distributed systems
    
    -- ===== CORRELATION IDENTIFIERS =====  
    -- These fields enable correlation with distributed traces and spans
    TraceId String CODEC(ZSTD(1)),                              -- Links log to distributed trace (32-char hex string)
    SpanId String CODEC(ZSTD(1)),                               -- Links log to specific span (16-char hex string)
    TraceFlags UInt32 CODEC(ZSTD(1)),                           -- Trace sampling flags from W3C trace context
    
    -- ===== SEVERITY AND CLASSIFICATION =====
    -- OpenTelemetry severity model with both numeric and text representations
    SeverityText LowCardinality(String) CODEC(ZSTD(1)),         -- Human-readable severity (ERROR, WARN, INFO, DEBUG, etc.)
                                                                  -- LowCardinality optimizes repeated values
    SeverityNumber Int32 CODEC(ZSTD(1)),                        -- Numeric severity level (1-24 per OTel spec)
                                                                  -- Enables range queries and numerical comparisons
    
    -- ===== SERVICE AND SOURCE IDENTIFICATION =====
    -- These fields identify the source service and instrumentation
    ServiceName LowCardinality(String) CODEC(ZSTD(1)),          -- Service generating the log (for filtering/grouping)
    ServiceVersion String CODEC(ZSTD(1)),                       -- Service version for deployment tracking
    
    -- ===== LOG CONTENT =====
    -- The actual log message content with flexible structure
    Body String CODEC(ZSTD(1)),                                 -- Primary log message content
                                                                  -- Can be structured (JSON) or unstructured text
    
    -- ===== RESOURCE ATTRIBUTES =====  
    -- Metadata about the resource (container, host, cloud instance) generating logs
    ResourceAttributes Map(LowCardinality(String), String) CODEC(ZSTD(1)),
                                                                  -- Key-value pairs: host.name, k8s.pod.name, cloud.region, etc.
                                                                  -- Map type enables flexible querying of nested attributes
    ResourceSchemaUrl String CODEC(ZSTD(1)),                    -- Schema version URL for resource attributes
    
    -- ===== INSTRUMENTATION SCOPE =====
    -- Information about the logging library/framework used
    ScopeName String CODEC(ZSTD(1)),                            -- Name of instrumentation library (e.g., "myapp.logging")
    ScopeVersion String CODEC(ZSTD(1)),                         -- Version of instrumentation library
    ScopeAttributes Map(LowCardinality(String), String) CODEC(ZSTD(1)),
                                                                  -- Additional scope metadata
    ScopeDroppedAttrCount UInt32 CODEC(ZSTD(1)),               -- Count of dropped attributes due to limits
    ScopeSchemaUrl String CODEC(ZSTD(1)),                       -- Schema version URL for scope attributes
    
    -- ===== LOG ATTRIBUTES =====
    -- Custom attributes specific to this log entry
    LogAttributes Map(LowCardinality(String), String) CODEC(ZSTD(1)),
                                                                  -- Application-specific key-value pairs
                                                                  -- Examples: user.id, request.method, error.code
    LogDroppedAttrCount UInt32 CODEC(ZSTD(1)),                 -- Count of dropped log attributes
    
    -- ===== PERFORMANCE INDEXES =====
    -- Bloom filter indexes for high-speed attribute searches
    -- These dramatically improve query performance on Map-type columns
    INDEX idx_res_attr_key mapKeys(ResourceAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
                                                                  -- Fast lookup of resource attribute keys
    INDEX idx_res_attr_value mapValues(ResourceAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
                                                                  -- Fast lookup of resource attribute values
    INDEX idx_scope_attr_key mapKeys(ScopeAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
                                                                  -- Fast lookup of scope attribute keys  
    INDEX idx_scope_attr_value mapValues(ScopeAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
                                                                  -- Fast lookup of scope attribute values
    INDEX idx_log_attr_key mapKeys(LogAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
                                                                  -- Fast lookup of log attribute keys
    INDEX idx_log_attr_value mapValues(LogAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
                                                                  -- Fast lookup of log attribute values
    INDEX idx_trace_id TraceId TYPE bloom_filter(0.01) GRANULARITY 1,
                                                                  -- Fast trace ID lookups for correlation
    INDEX idx_span_id SpanId TYPE bloom_filter(0.01) GRANULARITY 1,
                                                                  -- Fast span ID lookups for correlation
    INDEX idx_body Body TYPE tokenbf_v1(32768, 3, 0) GRANULARITY 1
                                                                  -- Full-text search index on log body content
                                                                  -- tokenbf_v1 is optimized for text search
    ) ENGINE = %s
    %s
    PARTITION BY toDate(Timestamp)                               -- Daily partitions for efficient data management
    ORDER BY (ServiceName, SeverityNumber, Timestamp, TraceId)  -- Optimal sort order for typical queries:
                                                                  -- 1. Filter by service
                                                                  -- 2. Filter by severity 
                                                                  -- 3. Time-based ordering
                                                                  -- 4. Trace correlation
    SETTINGS index_granularity=8192, ttl_only_drop_parts = 1    -- Performance tuning:
                                                                  -- index_granularity: Balance between memory and precision
                                                                  -- ttl_only_drop_parts: Drop entire partitions when TTL expires
