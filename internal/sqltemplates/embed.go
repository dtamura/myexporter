// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

package sqltemplates

import _ "embed"

// TracesCreateTable - トレースのメインテーブル作成用のSQLテンプレート
//
//go:embed traces_table.sql
var TracesCreateTable string

// TracesCreateTsTable - トレースID-タイムスタンプ検索用テーブル作成SQLテンプレート
//
//go:embed traces_id_ts_lookup_table.sql
var TracesCreateTsTable string

// TracesCreateTsView - トレースID-タイムスタンプマテリアライズドビュー作成SQLテンプレート
//
//go:embed traces_id_ts_lookup_mv.sql
var TracesCreateTsView string

// TracesInsert - トレースデータ挿入用のSQLテンプレート
//
//go:embed traces_insert.sql
var TracesInsert string
