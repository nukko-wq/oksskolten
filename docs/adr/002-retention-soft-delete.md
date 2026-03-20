# ADR-002: Soft delete for article retention policy

## Status

Accepted

## Context

Issue #10 で、古い記事を自動削除するリテンションポリシーの実装が求められた。DBが際限なく肥大化する問題への対策として、既読/未読記事をそれぞれ設定可能な日数で削除する。

削除方式として2つの選択肢があった:

1. **物理削除 + 別テーブル**: 記事を `DELETE` し、パージ済みURLを `purged_article_urls` テーブルに記録
2. **Soft delete**: `purged_at` カラムを追加し、コンテンツカラムをNULL化。行自体は残す

### 物理削除の問題

フィード取得時に `getExistingArticleUrls()` でDBに存在するURLを確認し、新規記事のみ `insertArticle()` する仕組みがある（`articles.url` の UNIQUE 制約も併用）。物理削除すると、次のフィード取得サイクル（5分ごと）でそのURLが「新規」と判定され再挿入されてしまう。

これを防ぐには `getExistingArticleUrls()` を修正してパージ済みURLテーブルも参照する必要があるが、フィード取得はクリティカルパスであり、変更によるバグリスクが高い。

## Decision

**Soft delete** を採用した。

### 仕組み

- `articles` テーブルに `purged_at TEXT` カラムを追加（`migrations/0006_retention.sql`）
- パージ時:
  - `full_text`, `full_text_translated`, `excerpt`, `summary`, `og_image` をNULL化（ストレージ回収）
  - `purged_at = datetime('now')` を設定
  - 検索インデックスから除去
  - アーカイブ済み画像を削除
- パージ対象外: `bookmarked_at` または `liked_at` が設定されている記事

### フィード取得への影響

- `getExistingArticleUrls()` は **変更不要** — URLが `articles` テーブルに残るため、既存の重複チェックがそのまま動く
- `insertArticle()` の UNIQUE 制約も引き続き機能する

### クエリへの影響

パージ済み記事をUIや集計から除外するため、`articles` テーブルを参照するすべてのクエリに `purged_at IS NULL` フィルタを追加する必要がある:

- `getArticles()`, `getArticlesByIds()` — 記事一覧
- `getFeeds()` — サイドバーのカウントサブクエリ
- `getLikeCount()`, `getBookmarkCount()` — カウント系
- `markAllSeenByFeed()`, `markAllSeenByCategory()` — 一括既読
- `getReadingStats()` — 統計
- `recalculateScores()` — スコア再計算
- `rebuildSearchIndex()`, `syncAllScoredArticlesToSearch()` — 検索インデックス

## Consequences

### メリット

- フィード取得のクリティカルパスに変更が不要
- マイグレーションがシンプル（カラム追加のみ、新テーブル不要）
- ストレージの大部分を占めるコンテンツカラムがNULL化されるため、十分なストレージ回収が可能
- 行メタデータ（URL、タイトル、タイムスタンプ）は保持されるため、将来的に履歴統計にも利用可能

### デメリット

- `articles` テーブルを参照する **すべてのクエリ** に `purged_at IS NULL` を追加する必要がある。新しいクエリ追加時にこのフィルタを忘れるとパージ済み記事が表示されるバグになる
- 行自体は残るため、URLとメタデータ分の軽微なストレージ消費は続く（1行あたり数百バイト程度）
- VACUUMを実行しないとNULL化した分のストレージがSQLiteに返却されない（週次VACUUMをcronで実施）
