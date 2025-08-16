-- OpenTelemetryデータのためのClickHouse Metrics Histogramテーブル スキーマ
-- このテーブルはHistogramメトリクス データポイント（分布測定値）を保存します
-- Histogramは事前定義されたバケットでの値の分布を表します（レイテンシー、レスポンスサイズなど）
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
    MetricName String CODEC(ZSTD(1)),                           -- メトリクス名（例: "http_request_duration", "response_size_bytes"）
    MetricDescription String CODEC(ZSTD(1)),                    -- メトリクスの人間が読める説明
    MetricUnit String CODEC(ZSTD(1)),                           -- 測定単位（例: "seconds", "bytes", "1"）
    
    -- ===== メトリクス ディメンション =====
    -- メトリクス値にコンテキストを提供するラベル/ディメンション
    Attributes Map(LowCardinality(String), String) CODEC(ZSTD(1)),
                                                                  -- メトリクス ディメンション: method, endpoint, status_code, instance
                                                                  -- これらがユニークな時系列の識別子を作成する
    
    -- ===== 時間フィールド =====
    -- Histogram測定のタイムスタンプ情報
    StartTimeUnix DateTime64(9) CODEC(Delta, ZSTD(1)),          -- 測定期間の開始時刻
                                                                  -- 蓄積ウィンドウの理解に重要
    TimeUnix DateTime64(9) CODEC(Delta, ZSTD(1)),              -- このHistogramが観測されたタイムスタンプ
                                                                  -- クエリの主要な時間ディメンション
    
    -- ===== HISTOGRAM中核値 =====
    -- 分布の基本統計サマリー
    Count UInt64 CODEC(Delta, ZSTD(1)),                        -- Histogramでの観測総数
                                                                  -- Deltaコーデックは単調増加カウンターに最適
    Sum Float64 CODEC(ZSTD(1)),                                 -- 全観測値の合計
                                                                  -- 平均の計算が可能: Sum/Count
    
    -- ===== HISTOGRAMバケット =====
    -- 値の頻度を示す実際の分布データ
    BucketCounts Array(UInt64) CODEC(ZSTD(1)),                 -- 各バケットでの観測数
                                                                  -- 配列長はExplicitBounds長 + 1と一致
    ExplicitBounds Array(Float64) CODEC(ZSTD(1)),              -- 各バケットの上限（例: [0.1, 0.5, 1.0, 5.0]）
                                                                  -- 最後のバケットは暗黙的に(+Inf)
                                                                  -- パーセンタイル計算に重要
    
    -- ===== エグゼンプラー =====
    -- このHistogramに寄与したサンプル トレース
    -- エグゼンプラーはレイテンシー スパイクに寄与した特定のリクエストの特定に役立つ
    Exemplars Nested (
        FilteredAttributes Map(LowCardinality(String), String), -- 追加のエグゼンプラー属性（user.id, trace.sampledなど）
        TimeUnix DateTime64(9),                                  -- このエグゼンプラーがキャプチャされた時刻
        Value Float64,                                           -- 実際に測定された値（例: 特定のレイテンシー）
        SpanId String,                                           -- このエグゼンプラーを生成したトレースのSpan ID
        TraceId String                                           -- 深掘り分析用のTrace ID
    ) CODEC(ZSTD(1)),                                           -- Nested型により、1つのHistogramに複数のエグゼンプラーが可能
    
    -- ===== メタデータとフラグ =====
    Flags UInt32 CODEC(ZSTD(1)),                               -- OpenTelemetryデータポイントフラグ（将来の利用のために予約）
    
    -- ===== HISTOGRAM拡張 =====
    -- 拡張統計情報のオプション フィールド
    Min Float64 CODEC(ZSTD(1)),                                 -- 最小観測値（利用可能な場合）
                                                                  -- 分布の広がりの理解に有用
    Max Float64 CODEC(ZSTD(1)),                                 -- 最大観測値（利用可能な場合）  
                                                                  -- 外れ値の特定に有用
    
    -- ===== 集約メタデータ =====
    AggregationTemporality Int32 CODEC(ZSTD(1)),               -- Histogramデータポイントの集約方法:
                                                                  -- 1 = DELTA（バケットは最後のレポート以降の変化を表す）
                                                                  -- 2 = CUMULATIVE（バケットは開始以降の合計を表す）
    
    -- ===== パフォーマンス インデックス =====
    -- 高速属性検索のためのBloomフィルタインデックス
    -- ディメンション/ラベルによるフィルタリングのパフォーマンスに重要
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
                                                                  -- 典型的なHistogramクエリに最適化されたソート順序:
                                                                  -- 1. サービス名でフィルタ
                                                                  -- 2. メトリクス名でフィルタ（例: レイテンシー メトリクス）
                                                                  -- 3. ディメンションでフィルタ（endpoint, methodなど）
                                                                  -- 4. トレンド分析のための時系列順序
    SETTINGS index_granularity=8192, ttl_only_drop_parts = 1   -- パフォーマンス調整:
                                                                  -- index_granularity: メモリと精度のバランス調整
                                                                  -- ttl_only_drop_parts: パーティション レベルの効率的なTTL
