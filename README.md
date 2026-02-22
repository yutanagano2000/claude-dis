# DIS - Development Intelligence System

Claude Code を「使うたびに賢くなる開発環境」にするスキル & スクリプト群。

エラーの解決策、レビュー結果、ユーザーの好みをローカルDBに蓄積し、
次のセッションで自動的に過去の知見を活用する。

```
普通の Claude Code:  毎回ゼロからスタート
DIS 搭載:           過去の失敗・成功を踏まえて開発
```

## Quick Start

```bash
# 1. Clone
git clone https://github.com/yourname/claude-dis.git
cd claude-dis

# 2. Install
./setup.sh

# 3. Use
cd your-project && claude
> /dev ログインバリデーションを追加
```

**前提条件:** Claude Code, Python 3.6+, sqlite3, jq, git

## 何が変わるのか

| 普通の Claude Code | DIS 搭載後 |
|---|---|
| 同じエラーに毎回ハマる | 過去の解決策を自動検索して適用 |
| 「useEffect じゃなくて useMemo」を何度も言う | 1回言えば DB に記録、次から自動で正しい方を使う |
| レビューは自分の目だけ | Codex + Gemini + Claude の 3-AI で自動レビュー |
| テストを手書き | 「何をテストしたいか」を言うだけで自動生成 |
| コード品質は感覚 | 5軸スコア (DQS) で定量計測 |

## Architecture

```
┌─────────────────────────────────────────────────┐
│  Claude Code                                    │
│                                                 │
│  ┌──────────┐ ┌──────────┐ ┌──────────────────┐│
│  │ /dev     │ │ /test    │ │ /review          ││
│  │ 開発全体 │ │ テスト   │ │ 3-AI レビュー    ││
│  └────┬─────┘ └────┬─────┘ └────┬─────────────┘│
│       │            │            │               │
│  ┌────▼────────────▼────────────▼─────────────┐ │
│  │              DIS Layer                     │ │
│  │  ┌─────────┐ ┌──────────┐ ┌─────────────┐ │ │
│  │  │ Record  │ │ Lookup   │ │ Measure     │ │ │
│  │  │ 記録    │ │ 検索     │ │ 品質計測    │ │ │
│  │  └────┬────┘ └────┬─────┘ └──────┬──────┘ │ │
│  └───────┼───────────┼──────────────┼────────┘ │
│          │           │              │           │
│  ┌───────▼───────────▼──────────────▼────────┐  │
│  │              SQLite (dev.db)              │  │
│  │  events | solutions | feedback | sessions │  │
│  └───────────────────────────────────────────┘  │
│                                                 │
│  ┌──────────────────────────────────────────┐   │
│  │  Hooks (自動実行)                        │   │
│  │  エラー捕捉 → DB記録 → レビュー実行     │   │
│  └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

## Skills 一覧

### `/dev` — フル開発パイプライン

要件テキストから設計 → 実装 → テスト → レビュー → 記録まで自動実行する。

```
/dev ログインAPIのエラーハンドリングを改善
/dev --no-test ドキュメントコメントを追加      # テストをスキップ
/dev --no-review 型定義を修正                  # レビューをスキップ
/dev --test-only ユーザー登録のテストを追加     # テストだけ生成
```

**処理フロー:**

```
Phase 0  DQS Baseline 計測     ← 変更前の品質スコアを記録
Phase 1  DIS Prep              ← 過去の知見を全量検索
Phase 2  Design                ← 設計 + 影響範囲の特定
Phase 3  Implement             ← コード変更 + 型チェック (最大3回リトライ)
Phase 3.5 Quality Gate         ← 品質劣化をブロック
Phase 4  Test                  ← テスト自動生成 + 実行 (最大3回リトライ)
Phase 5  Review                ← 3-AI レビュー + 自動修正 (最大2回リトライ)
Phase 6  Record                ← DIS に全結果を永続化
Phase 7  Report                ← 統合レポート出力
```

**出力例:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Dev Complete
  要件:   ログインバリデーションを追加
  状態:   PASS
  変更:   3ファイル (+45/-12行)
  テスト: pass (5/5)
  レビュー: 72 → 85 (iterations: 1)
  DQS:   0.71 → 0.78 (delta: +0.07) [Good]
  DIS:   2 solutions参照, 1 feedback参照
  所要時間: 94秒
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

### `/test` — テスト自動生成

「何をテストしたいか」を日本語で指定するだけでテストファイルを生成・実行する。

```
/test バリデーション計算が正しいか
/test APIのエラーレスポンスが正しいか
```

**特徴:**
- テスト観点からテストタイプを自動判定 (unit / integration / e2e)
- 失敗したらテスト側だけを修正してリトライ (実装は壊さない)
- 最大3回リトライ後、結果を DIS に記録

---

### `/review` — 3-AI レビュー

異なる AI を使って多角的にコードレビューし、指摘を自動修正する。

```
/review
```

**レビュー順序:**
1. **Codex** がレビュー (利用可能な場合)
2. **Gemini** が根本原因を分析 (利用可能な場合)
3. **Claude** が修正を適用

いずれかの AI が使えない場合は、利用可能な AI だけでフォールバック実行する。

**採点基準 (100点満点):**

| カテゴリ | 配点 | 見るポイント |
|---|---|---|
| Security | 25 | 脆弱性、入力検証 |
| Correctness | 25 | ロジックの正しさ |
| Performance | 20 | 不要な処理、N+1 |
| Maintainability | 20 | 可読性、複雑度 |
| Testing | 10 | テストカバレッジ |

80点以上で合格。最大5イテレーション、同スコアが2回続いたら停止。

---

### `/feedback` — 学習の記録

Claude への訂正を DB に記録する。同じ間違いを繰り返さなくなる。

```
/feedback useEffectではなくuseMemoを使って
/feedback ファイル名はkebab-caseで統一
```

**昇格パイプライン:**

記録が繰り返し確認されると、自動的に上位の設定に昇格する:

```
feedback (DB)  →  patterns (DB)  →  MEMORY.md  →  .claude/rules/
  Tier 2            Tier 3           Tier 4         Tier 5
  1回記録           score≥4          score≥5        score≥8
```

---

### `/kb-lookup` — 過去のエラー検索

エラーメッセージを入力すると、過去に解決した類似エラーの解決策を表示する。

```
/kb-lookup TypeError: Cannot read properties of undefined
```

TF-IDF コサイン類似度で意味的に近いエラーパターンもヒットする。

---

### `/que` — 質問トラッカー

開発中の疑問を記録し、後で検索・解決できる。

```
/que このAPIのレート制限はいくつ？
/que --search レート制限
/que --resolve 3 1分間100リクエスト
/que --list
```

---

### `/parallel-tasks` — 並列実行

大規模なタスクを独立したサブタスクに分解し、最大5並列で実行する。

```
/parallel-tasks 全コンポーネントにアクセシビリティ属性を追加
```

---

### `/industry-check` — AI 業界動向

Anthropic, OpenAI, DeepMind, xAI, Cursor, Devin のブログ・changelog を取得し、
開発ワークフローへの影響を分析する。

```
/industry-check
```

---

### `/kb-maintain` — DB メンテナンス

イベント集約、類似パターンのマージ、古いデータの減衰、統計レポートを一括実行する。
月1回程度の実行を推奨。

```
/kb-maintain
```

---

### `/refactoring` — リファクタリングガイド

Next.js / React のリファクタリングパターンを適用する。

```
/refactoring
```

500行超のファイルを自動検出し、分割パターンを提案する。

---

### `/tdd-workflow` — TDD ガイド

Red → Green → Refactor のサイクルでテスト駆動開発を支援する。

```
/tdd-workflow
```

カバレッジターゲット: Statements 80%+, Branches 80%+

## 技術詳細

### DQS (品質スコア)

コード品質を0.0 - 1.0で定量化する5軸の統合指標。

| 軸 | 重み | 何を測るか | 計算方法 |
|---|---|---|---|
| CDI | 15% | コード密度 | gzip圧縮率 (高いほど冗長) |
| SE | 15% | 構造の複雑さ | identifier の多様性 (低いほど良い) |
| CLS | 20% | 認知負荷 | ネストの深さ + 制御フロー分岐数 |
| CRS | 15% | 変更リスク | git churn / ownership |
| DRS | 35% | DIS の学習度 | テスト・レビュー・履歴からの RL 報酬 |

**グレード:**
- 0.85+: Excellent
- 0.70+: Good
- 0.50+: Needs Work
- 0.50未満: Poor

### 時間減衰

古い知識は自動的にスコアが下がる。半減期を過ぎると影響力が半分になる。

| データ | 半減期 | 理由 |
|---|---|---|
| solutions (エラー解決策) | 70日 | ライブラリ更新で陳腐化しやすい |
| patterns (昇格パターン) | 70日 | 同上 |
| feedback (ユーザー訂正) | 140日 | 好みは安定的 |
| dev_sessions (開発履歴) | 116日 | 中期的な参照価値 |
| questions (質問) | 140日 | 長期的な参照価値 |

### Hooks (自動実行)

Claude Code のイベントに連動して自動実行されるスクリプト群。

| タイミング | Hook | 何をするか |
|---|---|---|
| MCP tool 使用前 | `log-mcp.sh` | 使用ログを記録 |
| Bash 実行後 | `capture-error.sh` | エラーを DB に記録 |
| セッション終了時 | `tri-review.sh` | Codex レビューを自動実行 |
| セッション終了時 | `capture-session.sh` | セッション統計を記録 |

## ディレクトリ構成

```
claude-dis/
├── README.md                          ← このファイル
├── setup.sh                           ← インストーラー
├── settings.dis.json                  ← DIS hook 設定テンプレート
├── codex-review-config.json           ← レビュー設定
│
├── hooks/                             ← 自動実行スクリプト
│   ├── capture-error.sh               ← Bash エラー捕捉
│   ├── capture-session.sh             ← セッション統計記録
│   ├── log-mcp.sh                     ← MCP 使用ログ
│   ├── notify-stop.sh                 ← 停止通知 (要カスタマイズ)
│   ├── sync-on-stop.sh               ← Turso 同期 (optional)
│   ├── tri-review.sh                  ← 自動 Codex レビュー
│   └── lib/
│       └── review-utils.sh            ← レビュー共通関数
│
├── intelligence/                      ← DIS コアエンジン
│   ├── init-db.sh                     ← DB スキーマ初期化
│   ├── .turso-env.sample              ← Turso 設定テンプレート
│   └── scripts/
│       ├── aggregate.py               ← イベント → solution 集約
│       ├── decay.py                   ← 時間減衰処理
│       ├── fetch_sources.py           ← AI 業界 RSS 取得
│       ├── measure-quality.py         ← DQS 品質計測
│       ├── record-dev-session.sh      ← /dev セッション記録
│       ├── record-feedback.sh         ← /feedback 記録
│       ├── record-question.sh         ← /que 記録
│       ├── record-test-session.sh     ← /test セッション記録
│       ├── report.py                  ← 統計レポート生成
│       ├── self-improve.py            ← RL 報酬計算 + 改善提案
│       ├── similarity.py              ← TF-IDF 類似度検索
│       └── sync.py                    ← Turso クラウド同期
│
├── skills/                            ← Claude Code スキル定義
│   ├── dev/SKILL.md
│   ├── test/SKILL.md
│   ├── review/SKILL.md
│   ├── feedback/SKILL.md
│   ├── kb-lookup/SKILL.md
│   ├── kb-maintain/SKILL.md
│   ├── que/SKILL.md
│   ├── parallel-tasks/SKILL.md
│   ├── industry-check/SKILL.md
│   ├── refactoring/
│   │   ├── SKILL.md
│   │   └── hook-patterns.md
│   └── tdd-workflow/
│       ├── SKILL.md
│       └── test-patterns.md
│
└── commands/                          ← スラッシュコマンド定義
    └── dev.md
```

## カスタマイズ

### 通知を変更する

`hooks/notify-stop.sh` の ntfy トピックを自分のものに変更:

```bash
# hooks/notify-stop.sh 内の URL を変更
curl -s "https://ntfy.sh/your-topic-name" ...
```

### Turso クラウド同期を有効にする

複数デバイス間で DIS の知識を同期する場合:

```bash
cp intelligence/.turso-env.sample ~/.claude/intelligence/.turso-env
# .turso-env を編集して Turso の URL とトークンを設定
```

### 3-AI レビューを最大限活用する

```bash
npm install -g @openai/codex    # OpenAI Codex CLI
# + Gemini CLI (利用可能な場合)
```

インストールしなくても動作する。Claude 単体でのレビューにフォールバックする。

### CLAUDE.md に DIS を統合する

プロジェクトの CLAUDE.md に以下を追加すると、DIS スキルがプロンプトに表示される:

```markdown
## DIS
- `/dev <要件>`: フル開発パイプライン
- `/test <観点>`: テスト自動生成
- `/review`: 3-AI コードレビュー
- `/feedback <訂正>`: 学習記録
- `/kb-lookup`: エラー解決策検索
```

## FAQ

**Q: Claude Code のアップデートで壊れない？**
A: DIS は Claude Code の公式 API (skills, hooks, settings.json) だけを使っている。
内部実装に依存していないので、基本的にアップデートの影響を受けない。

**Q: DB が大きくなりすぎない？**
A: `/kb-maintain` で時間減衰とアーカイブが行われる。月1回の実行を推奨。

**Q: Windows で動く？**
A: WSL2 (Windows Subsystem for Linux) 上なら動作する。
ネイティブ Windows は sqlite3, jq, bc の手動インストールが必要。

**Q: 既存の settings.json を上書きしない？**
A: `setup.sh` は上書きではなく、hooks セクションのマージを提案する。
既存の設定はバックアップされる。

## License

MIT
