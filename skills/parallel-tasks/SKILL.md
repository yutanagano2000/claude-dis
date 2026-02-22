---
name: parallel-tasks
description: Decompose large tasks into parallel subtasks using subagents. Use for multi-file refactoring, codebase-wide changes, or research across many files. Maximizes throughput by running independent work concurrently.
allowed-tools: Task, Bash, Read, Grep, Glob, Write, Edit
---

# Parallel Task Decomposition

大規模タスクを独立サブタスクに分解し、並列実行するスキル。

## 手順

### Step 1: タスク分析
ユーザーのリクエストを分析し、以下を判断:
- 独立して実行可能なサブタスク数
- 各サブタスクの適切なエージェントタイプ
- サブタスク間の依存関係

### Step 2: サブタスク分解
タスクを独立したサブタスクに分割。以下のルールに従う:
- **独立性**: 各サブタスクは他のサブタスクの結果に依存しない
- **明確性**: 各サブタスクのゴールが明確で検証可能
- **適切な粒度**: 1サブタスク = 1ファイル or 1機能単位

### Step 3: エージェントタイプ選択
各サブタスクに最適なエージェントタイプを選択:
- `Explore`: コードベース調査、ファイル検索、パターン分析
- `general-purpose`: 複雑な検索・分析、マルチステップリサーチ
- `Bash`: コマンド実行、ビルド、テスト
- `Plan`: アーキテクチャ設計、実装計画

### Step 4: 並列起動
Taskツールで複数のサブタスクを**単一メッセージ内で**並列起動:
```
複数のTask tool callを1つのメッセージに含める
→ 全サブタスクが同時に実行開始
```

### Step 5: 結果統合
全サブタスクの完了を待ち、結果を統合:
- 各サブタスクの成果を要約
- コンフリクトや矛盾があれば解消
- メインコンテキストに簡潔な結果レポートを返す

## 使用例

### Multi-file Refactoring
```
サブタスク1 (Explore): src/components/ のコンポーネント一覧と依存関係を調査
サブタスク2 (Explore): src/hooks/ のカスタムフック一覧と使用箇所を調査
サブタスク3 (Explore): src/types/ の型定義と参照関係を調査
→ 統合して リファクタリング計画を立案
```

### Codebase-wide Search
```
サブタスク1: deprecated APIの使用箇所を検索
サブタスク2: テストカバレッジの低いファイルを特定
サブタスク3: 型エラーの可能性があるパターンを検索
→ 統合して 優先修正リストを作成
```

## 注意
- 最大5並列を推奨（コンテキスト圧迫回避）
- 各サブタスクのプロンプトには必要な情報を全て含める（コンテキスト共有なし）
- バックグラウンド実行（run_in_background: true）で長時間タスクを管理可能
