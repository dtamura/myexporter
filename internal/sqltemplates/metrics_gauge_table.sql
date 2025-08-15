-- OpenTelemetryデータのためのClickHouse Metrics Gaugeテーブル スキーマ
-- このテーブルはGaugeメトリクス データポイント（瞬間的な測定値）を保存します
-- Gaugeメトリクスは任意に上下する値を表します（CPU使用率、メモリ、温度など）
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
    ScopeName String CODEC(ZSTD(1)),                            -- インストルメンテーション ライブラリ名（例: "prometheus", "custom-metrics"）
    ScopeVersion String CODEC(ZSTD(1)),                         -- インストルメンテーション ライブラリのバージョン
    ScopeAttributes Map(LowCardinality(String), String) CODEC(ZSTD(1)),
                                                                  -- インストルメンテーション スコープに関する追加メタデータ
    ScopeDroppedAttrCount UInt32 CODEC(ZSTD(1)),               -- 制限により削除されたスコープ属性数
    ScopeSchemaUrl String CODEC(ZSTD(1)),                       -- スコープ属性のスキーマ バージョンURL
    
    -- ===== サービスとメトリクス識別 =====
    ServiceName LowCardinality(String) CODEC(ZSTD(1)),          -- グループ化とフィルタリングのためのサービス名
                                                                  -- LowCardinalityにより重複値が最適化される
    MetricName String CODEC(ZSTD(1)),                           -- メトリクス名（例: "cpu_usage_percent", "memory_bytes"）
    MetricDescription String CODEC(ZSTD(1)),                    -- メトリクスの人間が読める説明
    MetricUnit String CODEC(ZSTD(1)),                           -- 測定単位（例: "percent", "bytes", "seconds"）
    
    -- ===== メトリクス ディメンション =====
    -- メトリクス値にコンテキストを提供するラベル/ディメンション
    Attributes Map(LowCardinality(String), String) CODEC(ZSTD(1)),
                                                                  -- メトリクス ディメンション: instance, job, endpoint, status_code
                                                                  -- これらがユニークな時系列の識別子を作成する
    
    -- ===== 時間フィールド =====
    -- Gauge測定のタイムスタンプ情報
    StartTimeUnix DateTime64(9) CODEC(Delta, ZSTD(1)),          -- 測定期間の開始時刻（コンテキスト用）
                                                                  -- Deltaコーデックは時系列データに最適
    TimeUnix DateTime64(9) CODEC(Delta, ZSTD(1)),              -- Gauge測定の実際のタイムスタンプ
                                                                  -- クエリの主要な時間ディメンション
    
    -- ===== GAUGE値 =====
    -- 特定の時点で実際に測定された値
    Value Float64 CODEC(ZSTD(1)),                               -- Gauge測定値（正、負、またはゼロが可能）
                                                                  -- Float64はほとんどのユースケースで十分な精度を提供
    
    -- ===== メタデータとフラグ =====
    Flags UInt32 CODEC(ZSTD(1)),                               -- OpenTelemetryデータポイントフラグ（将来の利用のために予約）
    
    -- ===== エグゼンプラー =====
    -- このメトリクス データポイントに寄与したサンプル トレース
    -- エグゼンプラーはメトリクスと分散トレースの間のリンクを提供する
    Exemplars Nested (
        FilteredAttributes Map(LowCardinality(String), String), -- 追加のエグゼンプラー属性
        TimeUnix DateTime64(9),                                  -- このエグゼンプラーがキャプチャされた時刻
        Value Float64,                                           -- このエグゼンプラーに関連する値
        SpanId String,                                           -- このエグゼンプラーを生成したトレースのSpan ID
        TraceId String                                           -- トレーシング データとの相関用のTrace ID
    ) CODEC(ZSTD(1)),                                           -- Nested型により、1つのデータポイントに複数のエグゼンプラーが可能
    
    -- ===== 集約メタデータ =====
    AggregationTemporality Int32 CODEC(ZSTD(1)),               -- データポイントの集約方法:
                                                                  -- 0 = UNSPECIFIED, 1 = DELTA, 2 = CUMULATIVE
    IsMonotonic Boolean CODEC(Delta, ZSTD(1)),                 -- Gaugeが増加のみかどうか（ほとんどのGaugeではfalse）
                                                                  -- Deltaコーデックはboolean値に効率的
    
    -- ===== パフォーマンス インデックス =====
    -- 高速属性検索のためのBloomフィルタインデックス
    -- ラベル/ディメンションによるクエリのパフォーマンスに重要
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
                                                                  -- 典型的なメトリクス クエリに最適化されたソート順序:
                                                                  -- 1. サービス名でフィルタ
                                                                  -- 2. メトリクス名でフィルタ  
                                                                  -- 3. ディメンション/ラベルでフィルタ
                                                                  -- 4. 時系列順序（最新が先）
    SETTINGS index_granularity=8192, ttl_only_drop_parts = 1   -- パフォーマンス調整:
                                                                  -- index_granularity: メモリと精度のバランス調整
                                                                  -- ttl_only_drop_parts: パーティション レベルの効率的なTTL
