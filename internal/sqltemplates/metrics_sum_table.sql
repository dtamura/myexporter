-- OpenTelemetryデータのためのClickHouse Metrics Sumテーブル スキーマ
-- このテーブルはSum/Counterメトリクス データポイント（累積またはデルタ測定値）を保存します
-- Sumメトリクスは時間とともに蓄積される値を表します（リクエスト数、転送バイト数、エラーなど）
-- OpenTelemetryメトリクス データモデルに基づく: https://opentelemetry.io/docs/specs/otel/metrics/data-model/

CREATE TABLE IF NOT EXISTS "%s"."%s" %s (
    -- ===== リソース識別情報 =====
    -- メトリクスを送信するリソース（サービス、ホスト、コンテナ）に関するメタデータ
    ResourceAttributes Map(LowCardinality(String), String) CODEC(ZSTD(1)),
                                                                  -- リソースメタデータ: service.name, host.name, k8s.pod.name  
                                                                  -- Map型によりリソースプロパティの柔軟なクエリが可能
    ResourceSchemaUrl String CODEC(ZSTD(1)),                    -- リソース属性のスキーマバージョンURL
    
    -- ===== インストゥルメンテーションスコープ =====
    -- メトリクス収集ライブラリ/フレームワークに関する情報
    ScopeName String CODEC(ZSTD(1)),                            -- インストゥルメンテーションライブラリ名（例：「prometheus」、「custom-metrics」）
    ScopeVersion String CODEC(ZSTD(1)),                         -- インストゥルメンテーションライブラリのバージョン
    ScopeAttributes Map(LowCardinality(String), String) CODEC(ZSTD(1)),
                                                                  -- インストゥルメンテーションスコープに関する追加メタデータ
    ScopeDroppedAttrCount UInt32 CODEC(ZSTD(1)),               -- 制限により削除されたスコープ属性数
    ScopeSchemaUrl String CODEC(ZSTD(1)),                       -- スコープ属性のスキーマバージョンURL
    
    -- ===== サービスとメトリクス識別情報 =====
    ServiceName LowCardinality(String) CODEC(ZSTD(1)),          -- グループ化とフィルタリング用のサービス名
                                                                  -- LowCardinalityにより重複値を最適化
    MetricName String CODEC(ZSTD(1)),                           -- メトリクス名（例：「http_requests_total」、「bytes_sent」）
    MetricDescription String CODEC(ZSTD(1)),                    -- メトリクスの人間が読める説明
    MetricUnit String CODEC(ZSTD(1)),                           -- 測定単位（例：カウントの場合「1」、「bytes」、「seconds」）
    
    -- ===== メトリクスディメンション =====
    -- メトリクス値にコンテキストを提供するラベル/ディメンション
    Attributes Map(LowCardinality(String), String) CODEC(ZSTD(1)),
                                                                  -- メトリクスディメンション：method、status_code、endpoint、instance
                                                                  -- これらが固有の時系列アイデンティティを作成
    
    -- ===== 時間フィールド =====
    -- Sum測定のタイムスタンプ情報
    StartTimeUnix DateTime64(9) CODEC(Delta, ZSTD(1)),          -- 累積期間が開始した時刻
                                                                  -- デルタ vs 累積の解釈に重要
    TimeUnix DateTime64(9) CODEC(Delta, ZSTD(1)),              -- この合計値が観測された時刻
                                                                  -- クエリの主要な時間ディメンション
    
    -- ===== 合計値 =====
    -- 累積/合計値
    Value Float64 CODEC(ZSTD(1)),                               -- 合計測定値
                                                                  -- カウンターの場合：通常単調増加
                                                                  -- デルタ合計の場合：変化を表す任意の値
    
    -- ===== メタデータとフラグ =====
    Flags UInt32 CODEC(ZSTD(1)),                               -- OpenTelemetryデータポイントフラグ（将来使用のため予約済み）
    
    -- ===== エグゼンプラー =====
    -- このメトリクスデータポイントに貢献したサンプルトレース
    -- エグゼンプラーは根本原因分析のためのメトリクスと分散トレースの連携を提供
    Exemplars Nested (
        FilteredAttributes Map(LowCardinality(String), String), -- 追加のエグゼンプラー属性
        TimeUnix DateTime64(9),                                  -- このエグゼンプラーがキャプチャされた時刻
        Value Float64,                                           -- このエグゼンプラーに関連付けられた値（多くの場合単一のインクリメント）
        SpanId String,                                           -- このエグゼンプラーを生成したトレースのスパンID
        TraceId String                                           -- トレーシングデータとの相関用のトレースID
    ) CODEC(ZSTD(1)),                                           -- Nested型により1つのデータポイントあたり複数のエグゼンプラーが可能
    
    -- ===== Sum固有のメタデータ =====
    AggregationTemporality Int32 CODEC(ZSTD(1)),               -- データポイントの集約方法：
                                                                  -- 1 = DELTA（値は前回レポートからの変化を表す）
                                                                  -- 2 = CUMULATIVE（値は開始からの合計を表す）
    IsMonotonic Boolean CODEC(Delta, ZSTD(1)),                 -- 合計が増加のみか（カウンターの場合true）
                                                                  -- Deltaコーデックにより真偽値を効率化
                                                                  -- レート計算とアラートに重要
    
    -- ===== パフォーマンスインデックス =====
    -- 高速属性検索のためのBloom filterインデックス
    -- ラベル/ディメンションでのフィルタリング時のパフォーマンスに必須
    INDEX idx_res_attr_key mapKeys(ResourceAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
                                                                  -- リソース属性キーの高速ルックアップ
    INDEX idx_res_attr_value mapValues(ResourceAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
                                                                  -- リソース属性値の高速ルックアップ
    INDEX idx_scope_attr_key mapKeys(ScopeAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
                                                                  -- スコープ属性キーの高速ルックアップ
    INDEX idx_scope_attr_value mapValues(ScopeAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
                                                                  -- スコープ属性値の高速ルックアップ
    INDEX idx_attr_key mapKeys(Attributes) TYPE bloom_filter(0.01) GRANULARITY 1,
                                                                  -- メトリクス属性キー（ラベル）の高速ルックアップ
    INDEX idx_attr_value mapValues(Attributes) TYPE bloom_filter(0.01) GRANULARITY 1
                                                                  -- メトリクス属性値（ラベル値）の高速ルックアップ
    ) ENGINE = %s
    %s
    PARTITION BY toDate(TimeUnix)                               -- 効率的なデータライフサイクル管理のための日次パーティション
    ORDER BY (ServiceName, MetricName, Attributes, toUnixTimestamp64Nano(TimeUnix))
                                                                  -- 典型的なメトリクスクエリに最適なソート順序：
                                                                  -- 1. サービスでフィルタ
                                                                  -- 2. メトリクス名でフィルタ
                                                                  -- 3. ディメンション/ラベルでフィルタ
                                                                  -- 4. レート計算のための時系列順序付け
    SETTINGS index_granularity=8192, ttl_only_drop_parts = 1   -- パフォーマンスチューニング：
                                                                  -- index_granularity：メモリと精度のバランス
                                                                  -- ttl_only_drop_parts：効率的なパーティションレベルTTL
