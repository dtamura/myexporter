-- OpenTelemetryデータのためのClickHouse Logsテーブル スキーマ
-- このテーブルは包括的なインデックス化と最適化を備えた構造化ログデータを保存します
-- OpenTelemetryログ データモデルに基づく: https://opentelemetry.io/docs/specs/otel/logs/data-model/

CREATE TABLE IF NOT EXISTS "%s"."%s" %s (
    -- ===== タイムスタンプ フィールド =====
    -- これらのフィールドはログデータの重要な時間的側面を処理します
    Timestamp DateTime64(9) CODEC(Delta, ZSTD(1)),              -- ナノ秒精度での主要ログイベント タイムスタンプ
                                                                  -- Deltaコーデックは時系列データに最適
    ObservedTimestamp DateTime64(9) CODEC(Delta, ZSTD(1)),      -- ログが観測/収集された時刻
                                                                  -- 分散システムでは多くの場合Timestampと異なる
    
    -- ===== 相関識別子 =====  
    -- これらのフィールドにより分散トレースとスパンとの相関が可能になります
    TraceId String CODEC(ZSTD(1)),                              -- ログを分散トレースにリンクする（32文字の16進文字列）
    SpanId String CODEC(ZSTD(1)),                               -- ログを特定のスパンにリンクする（16文字の16進文字列）
    TraceFlags UInt32 CODEC(ZSTD(1)),                           -- W3Cトレース コンテキストからのトレース サンプリング フラグ
    
    -- ===== 重要度と分類 =====
    -- 数値とテキスト表現の両方を持つOpenTelemetry重要度モデル
    SeverityText LowCardinality(String) CODEC(ZSTD(1)),         -- 人間が読める重要度（ERROR, WARN, INFO, DEBUG など）
                                                                  -- LowCardinalityにより重複値が最適化される
    SeverityNumber Int32 CODEC(ZSTD(1)),                        -- 数値重要度レベル（OTel仕様の1-24）
                                                                  -- 範囲クエリと数値比較が可能
    
    -- ===== サービスとソース識別 =====
    -- これらのフィールドはソースサービスとインストルメンテーションを識別します
    ServiceName LowCardinality(String) CODEC(ZSTD(1)),          -- ログを生成するサービス（フィルタリング/グループ化用）
    ServiceVersion String CODEC(ZSTD(1)),                       -- デプロイメント トラッキング用のサービス バージョン
    
    -- ===== ログ内容 =====
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
