// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

package internal

import (
	"embed"
	"fmt"
	"time"
)

// SQL templates embedded at compile time for better distribution
//
//go:embed sqltemplates/*.sql
var sqlTemplates embed.FS

const DefaultDatabase = "default"

// GenerateTTLExpr - ClickHouseテーブル用のTTL式を生成します
func GenerateTTLExpr(ttl time.Duration, timeField string) string {
	if ttl > 0 {
		switch {
		case ttl%(24*time.Hour) == 0:
			return fmt.Sprintf(`TTL %s + toIntervalDay(%d)`, timeField, ttl/(24*time.Hour))
		case ttl%(time.Hour) == 0:
			return fmt.Sprintf(`TTL %s + toIntervalHour(%d)`, timeField, ttl/time.Hour)
		case ttl%(time.Minute) == 0:
			return fmt.Sprintf(`TTL %s + toIntervalMinute(%d)`, timeField, ttl/time.Minute)
		default:
			return fmt.Sprintf(`TTL %s + toIntervalSecond(%d)`, timeField, ttl/time.Second)
		}
	}

	return ""
}

// LoadSQLTemplate は組み込みファイルシステムからSQLテンプレートを読み込みます
func LoadSQLTemplate(filename string) (string, error) {
	path := fmt.Sprintf("sqltemplates/%s", filename)
	data, err := sqlTemplates.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("SQLテンプレート %s の読み込みに失敗しました: %w", path, err)
	}
	return string(data), nil
}
