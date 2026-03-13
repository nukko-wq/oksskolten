# Oksskolten 実装仕様書 — クリップ

> [概要に戻る](./01_overview.ja.md)

## クリップ

### 概要

ユーザーが任意のURLを手動で保存（クリップ）する機能。RSSフィードとは独立したフローで記事を取り込む。

### クリップフィード

クリップ記事は「クリップフィード」と呼ばれる特殊なシングルトンフィードに所属する。これにより、記事の管理（既読・ブックマーク・要約・翻訳・検索等）を通常のRSS記事と完全に統一できる。

| 観点 | RSSフィード | クリップフィード |
|---|---|---|
| DB上の `type` | `'rss'` | `'clip'` |
| `url` | ブログURL | `'clip://saved'` |
| 個数 | 複数 | シングルトン（1つのみ） |
| 記事追加 | Cronで自動 | ユーザーが `POST /api/articles/from-url` で手動 |
| Cron対象 | `getEnabledFeeds()` で取得 | 除外（`type = 'rss'` のみ取得） |
| サイドバー配置 | フィード一覧セクション（カテゴリ付き） | 特殊セクション（Inbox・Bookmarks・Likesと並列） |
| 全体 unread 数 | 含まれる | 含まれない |
| カテゴリ | 所属可 | 不可 |
| Smart Floor | 適用 | 非適用（保存した記事は常に表示） |
| 記事削除 | 不可（403） | 可能（`DELETE /api/articles/:id`） |
| フィード削除 | 可能 | 不可（403） |
| アイコン | ドメインのfavicon | Archive アイコン |

### DB関数

| 関数 | 説明 |
|---|---|
| `ensureClipFeed()` | クリップフィードを取得。存在しなければ作成して返す（冪等） |
| `getClipFeed()` | クリップフィードを取得。未作成時は `undefined` |
| `getEnabledFeeds()` | `disabled = 0 AND type = 'rss'` のフィードのみ返す（クリップ除外） |
| `deleteArticle(id)` | 記事を削除。成功時 `true`、未存在時 `false` |

### クリップ保存フロー

```
ユーザーがURLを入力
    │
    ▼
POST /api/articles/from-url
    │
    ├─ 1. getClipFeed() → なければ 500
    ├─ 2. getArticleByUrl() → 既存なら 409
    ├─ 3. fetchArticleContent(url) → 共通フェッチパイプライン（下記参照）
    │     失敗時: last_error に記録し full_text = NULL で続行（graceful degradation）
    ├─ 4. タイトル決定: request.title > fetchedTitle > hostname
    └─ 5. insertArticle() → 201
```

保存後の記事は通常のRSS記事と同様に、要約・翻訳・ブックマーク・いいね・チャットが利用可能。

### RSSフィードとの共通フェッチパイプライン

クリップとRSSフィードは同じ `fetchArticleContent()` 関数（`server/fetcher.ts`）を使用する。フルテキスト取得・FlareSolverr フォールバック・bot block 検出・言語判定を統一パイプラインで処理する。差異は渡すオプションにある:

| 機能 | RSSフィード | クリップ |
|---|---|---|
| `fetchFullText` + FlareSolverr 自動フォールバック（短い/ゴミ抽出時） | ✅ | ✅ |
| `isBotBlockPage` 検出 | ✅ | ✅ |
| `detectLanguage`（ローカルCJK比率判定） | ✅ | ✅ |
| `requiresJsChallenge`（フィードレベルの明示FlareSolverr指定） | ✅（`feeds.requires_js_challenge` から） | ❌（`undefined` — 自動フォールバックのみ） |
| `listingExcerpt`（CSS Bridge excerpt フォールバック） | ✅（RSS item の excerpt から） | ❌（該当なし） |
| `existingArticle`（リトライ時のフェッチスキップ） | ✅（リトライ記事で使用） | ❌（該当なし） |

後半2つのオプションはクリップの性質上そもそも該当しない: CSS Bridge のリスティングページは存在せず、手動保存した記事にはリトライ機構がない。`requiresJsChallenge` はフィード単位の設定でありクリップには存在しないが、`fetchFullText()` 内の自動 FlareSolverr フォールバック（抽出結果が短い/ゴミの場合に発動）は引き続き有効。
