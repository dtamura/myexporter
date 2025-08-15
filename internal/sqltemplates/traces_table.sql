-- OpenTelemetry トレースデータ格納用ClickHouseテーブル作成SQL
-- 大規模分散トレーシングデータの効率的な保存・検索のために最適化
CREATE TABLE IF NOT EXISTS "%s"."%s" %s (
    -- === 基本トレーシング情報 ===
    -- スパン開始時刻（ナノ秒精度、Delta+ZSTD圧縮で時系列データを最適化）
    Timestamp DateTime64(9) CODEC(Delta, ZSTD(1)),
    
    -- W3C Trace Context 識別子群（ZSTD圧縮でUUID文字列を効率化）
    TraceId String CODEC(ZSTD(1)),          -- トレース識別子（16進数文字列）
    SpanId String CODEC(ZSTD(1)),           -- スパン識別子（16進数文字列）
    ParentSpanId String CODEC(ZSTD(1)),     -- 親スパン識別子
    TraceState String CODEC(ZSTD(1)),       -- トレース状態情報（vendor=value形式）
    
    -- === ビジネス・メタデータ（LowCardinality最適化） ===
    -- 重複値が多いカテゴリカルデータは辞書圧縮でメモリ・CPU効率向上
    SpanName LowCardinality(String) CODEC(ZSTD(1)),     -- 操作名・エンドポイント名
    SpanKind LowCardinality(String) CODEC(ZSTD(1)),     -- スパン種別（CLIENT/SERVER等）
    ServiceName LowCardinality(String) CODEC(ZSTD(1)),  -- マイクロサービス名
    
    -- === 動的属性データ（Map型で柔軟なスキーマ） ===
    -- OpenTelemetryセマンティックコンベンションに準拠した動的属性
    ResourceAttributes Map(LowCardinality(String), String) CODEC(ZSTD(1)), -- リソース属性
    
    -- インストゥルメンテーション情報
    ScopeName String CODEC(ZSTD(1)),        -- ライブラリ名
    ScopeVersion String CODEC(ZSTD(1)),     -- ライブラリバージョン
    
    -- スパン固有の属性（HTTP、DB、RPC等のプロトコル情報）
    SpanAttributes Map(LowCardinality(String), String) CODEC(ZSTD(1)),
    
    -- === 性能・状態情報 ===
    Duration UInt64 CODEC(ZSTD(1)),                    -- スパン実行時間（ナノ秒）
    StatusCode LowCardinality(String) CODEC(ZSTD(1)),  -- 実行結果（OK/ERROR/TIMEOUT）
    StatusMessage String CODEC(ZSTD(1)),               -- エラーメッセージ等の詳細
    
    -- === 複雑なネスト構造（配列型データ） ===
    -- スパン内で発生したイベント群（例外、ログ、チェックポイント等）
    Events Nested (
        Timestamp DateTime64(9),                                    -- イベント発生時刻
        Name LowCardinality(String),                               -- イベント名
        Attributes Map(LowCardinality(String), String)             -- イベント属性
    ) CODEC(ZSTD(1)),
    
    -- 他のトレース・スパンとの関係性（バッチ処理、非同期処理等）
    Links Nested (
        TraceId String,                                            -- リンク先トレースID
        SpanId String,                                             -- リンク先スパンID
        TraceState String,                                         -- リンク先状態
        Attributes Map(LowCardinality(String), String)             -- リンク属性
    ) CODEC(ZSTD(1)),
    
    -- === 高速検索用インデックス群 ===
    -- TraceID検索（最重要・最高精度）: デバッグ時の特定トレース詳細調査
    INDEX idx_trace_id TraceId TYPE bloom_filter(0.001) GRANULARITY 1,
    
    -- 属性検索（探索的分析用）: サービス・環境・バージョン等での絞り込み
    INDEX idx_res_attr_key mapKeys(ResourceAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
    INDEX idx_res_attr_value mapValues(ResourceAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
    INDEX idx_span_attr_key mapKeys(SpanAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
    INDEX idx_span_attr_value mapValues(SpanAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
    
    -- 実行時間範囲検索: 性能問題の特定・SLA監視
    INDEX idx_duration Duration TYPE minmax GRANULARITY 1
) ENGINE = %s                              -- 通常はMergeTree（高性能分析エンジン）
PARTITION BY toDate(Timestamp)             -- 日付単位の物理分割（効率的な範囲検索・TTL削除）
ORDER BY (ServiceName, SpanName, toDateTime(Timestamp))  -- クラスタリング（サービス・操作別の高速検索）
%s                                        -- TTL設定（自動データ削除）のプレースホルダー
SETTINGS index_granularity=8192, ttl_only_drop_parts = 1  -- 性能・運用最適化設定
