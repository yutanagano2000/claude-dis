# API仕様書テンプレート

## 使用方法

OpenAPI/Swagger形式を意識した、実装に直結するAPI仕様書。

---

# {プロジェクト名} API仕様書

**バージョン**: 1.0.0
**作成日**: {生成日}
**ベースURL**: `https://api.example.com/v1`

---

## 1. 概要

### 1.1 API基本情報

| 項目 | 内容 |
|------|------|
| プロトコル | HTTPS |
| 認証方式 | Bearer Token (JWT) |
| レスポンス形式 | JSON |
| 文字エンコーディング | UTF-8 |

### 1.2 共通ヘッダー

**リクエスト**

| ヘッダー | 必須 | 説明 |
|----------|------|------|
| `Content-Type` | Yes | `application/json` |
| `Authorization` | 条件 | `Bearer {access_token}` |
| `X-Request-ID` | No | リクエスト追跡用UUID |

**レスポンス**

| ヘッダー | 説明 |
|----------|------|
| `X-Request-ID` | リクエストID（エコーまたは自動生成） |
| `X-RateLimit-Limit` | レート制限の上限 |
| `X-RateLimit-Remaining` | 残りリクエスト数 |
| `X-RateLimit-Reset` | リセット時刻（Unix timestamp） |

---

## 2. 認証 API

### 2.1 POST /auth/register

新規ユーザー登録

**Request**

```json
{
  "name": "string (1-255文字)",
  "email": "string (有効なメールアドレス)",
  "password": "string (8文字以上、大小英数字含む)"
}
```

**Response 201**

```json
{
  "user": {
    "id": "uuid",
    "name": "string",
    "email": "string",
    "createdAt": "ISO8601"
  },
  "tokens": {
    "accessToken": "string",
    "refreshToken": "string",
    "expiresIn": 900
  }
}
```

**Errors**

| Code | Description | Response |
|------|-------------|----------|
| 400 | バリデーションエラー | `{"error": {"code": 2001, "message": "...", "details": {...}}}` |
| 409 | メール重複 | `{"error": {"code": 3001, "message": "Email already exists"}}` |

---

### 2.2 POST /auth/login

ログイン

**Request**

```json
{
  "email": "string",
  "password": "string"
}
```

**Response 200**

```json
{
  "user": {
    "id": "uuid",
    "name": "string",
    "email": "string"
  },
  "tokens": {
    "accessToken": "string",
    "refreshToken": "string",
    "expiresIn": 900
  }
}
```

**Errors**

| Code | Description |
|------|-------------|
| 401 | 認証失敗 |
| 429 | レート制限超過 |

---

### 2.3 POST /auth/refresh

トークンリフレッシュ

**Request**

```json
{
  "refreshToken": "string"
}
```

**Response 200**

```json
{
  "accessToken": "string",
  "refreshToken": "string",
  "expiresIn": 900
}
```

---

### 2.4 POST /auth/logout

ログアウト（要認証）

**Response 204**

No Content

---

## 3. Users API

### 3.1 GET /users

ユーザー一覧取得（要認証）

**Query Parameters**

| Param | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| page | integer | No | 1 | ページ番号 |
| limit | integer | No | 20 | 取得件数 (max: 100) |
| search | string | No | - | 名前・メールで検索 |
| sort | string | No | createdAt | ソートフィールド |
| order | string | No | desc | asc/desc |

**Response 200**

```json
{
  "data": [
    {
      "id": "uuid",
      "name": "string",
      "email": "string",
      "createdAt": "ISO8601",
      "updatedAt": "ISO8601"
    }
  ],
  "pagination": {
    "page": 1,
    "limit": 20,
    "total": 150,
    "totalPages": 8,
    "hasNext": true,
    "hasPrev": false
  }
}
```

---

### 3.2 GET /users/:id

ユーザー詳細取得（要認証）

**Path Parameters**

| Param | Type | Description |
|-------|------|-------------|
| id | uuid | ユーザーID |

**Response 200**

```json
{
  "id": "uuid",
  "name": "string",
  "email": "string",
  "profile": {
    "avatar": "string (URL)",
    "bio": "string"
  },
  "createdAt": "ISO8601",
  "updatedAt": "ISO8601"
}
```

**Errors**

| Code | Description |
|------|-------------|
| 404 | ユーザーが存在しない |

---

### 3.3 PUT /users/:id

ユーザー更新（要認証、本人のみ）

**Request**

```json
{
  "name": "string (optional)",
  "profile": {
    "bio": "string (optional)"
  }
}
```

**Response 200**

更新後のユーザーオブジェクト

**Errors**

| Code | Description |
|------|-------------|
| 403 | 権限なし（他人のデータ） |
| 404 | ユーザーが存在しない |

---

### 3.4 DELETE /users/:id

ユーザー削除（要認証、本人またはAdmin）

**Response 204**

No Content

---

## 4. Resources API（汎用テンプレート）

### 4.1 GET /resources

リソース一覧取得

**Query Parameters**

| Param | Type | Description |
|-------|------|-------------|
| page | integer | ページ番号 |
| limit | integer | 取得件数 |
| filter[field] | string | フィルター条件 |
| include | string | リレーション展開 (例: `user,tags`) |

**Response 200**

```json
{
  "data": [],
  "pagination": {},
  "meta": {
    "totalCount": 100,
    "filteredCount": 50
  }
}
```

---

### 4.2 POST /resources

リソース作成

**Request**

```json
{
  "field1": "value",
  "field2": "value"
}
```

**Response 201**

```json
{
  "id": "uuid",
  "field1": "value",
  "field2": "value",
  "createdAt": "ISO8601"
}
```

---

### 4.3 GET /resources/:id

リソース詳細取得

---

### 4.4 PUT /resources/:id

リソース更新（部分更新対応）

---

### 4.5 DELETE /resources/:id

リソース削除

---

## 5. エラーレスポンス

### 5.1 エラーフォーマット

```json
{
  "error": {
    "code": 1001,
    "message": "Human readable message",
    "details": {
      "field": ["エラー詳細1", "エラー詳細2"]
    },
    "timestamp": "ISO8601",
    "traceId": "uuid"
  }
}
```

### 5.2 HTTPステータスコード

| Code | Description | 使用場面 |
|------|-------------|----------|
| 200 | OK | 正常取得・更新 |
| 201 | Created | 新規作成成功 |
| 204 | No Content | 削除成功 |
| 400 | Bad Request | バリデーションエラー |
| 401 | Unauthorized | 認証必要・トークン無効 |
| 403 | Forbidden | 権限不足 |
| 404 | Not Found | リソース不存在 |
| 409 | Conflict | 重複エラー |
| 422 | Unprocessable Entity | ビジネスロジックエラー |
| 429 | Too Many Requests | レート制限 |
| 500 | Internal Server Error | サーバーエラー |

### 5.3 エラーコード一覧

| Range | Category | Example |
|-------|----------|---------|
| 1000-1999 | 認証・認可 | 1001: Invalid token |
| 2000-2999 | バリデーション | 2001: Required field missing |
| 3000-3999 | ビジネスロジック | 3001: Resource already exists |
| 4000-4999 | 外部サービス | 4001: Payment failed |
| 5000-5999 | システム | 5001: Database connection error |

---

## 6. レート制限

### 6.1 制限値

| Endpoint | Authenticated | Anonymous |
|----------|--------------|-----------|
| /auth/login | 5/min | 5/min |
| /auth/register | - | 3/hour |
| /api/* | 100/min | 20/min |
| /api/upload | 10/min | - |

### 6.2 レスポンスヘッダー

```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1640000000
```

### 6.3 制限超過時

**Response 429**

```json
{
  "error": {
    "code": 1003,
    "message": "Rate limit exceeded",
    "retryAfter": 60
  }
}
```

---

## 7. ページネーション

### 7.1 クエリパラメータ

| Param | Type | Default | Max | Description |
|-------|------|---------|-----|-------------|
| page | integer | 1 | - | ページ番号 |
| limit | integer | 20 | 100 | 1ページあたりの件数 |

### 7.2 レスポンス構造

```json
{
  "data": [],
  "pagination": {
    "page": 1,
    "limit": 20,
    "total": 150,
    "totalPages": 8,
    "hasNext": true,
    "hasPrev": false,
    "links": {
      "first": "/api/resources?page=1&limit=20",
      "prev": null,
      "next": "/api/resources?page=2&limit=20",
      "last": "/api/resources?page=8&limit=20"
    }
  }
}
```

---

## 8. フィルタリング・ソート

### 8.1 フィルター構文

```
GET /api/resources?filter[status]=active&filter[createdAt][gte]=2024-01-01
```

| Operator | Description | Example |
|----------|-------------|---------|
| (none) | 完全一致 | `filter[status]=active` |
| [gte] | 以上 | `filter[price][gte]=100` |
| [lte] | 以下 | `filter[price][lte]=1000` |
| [like] | 部分一致 | `filter[name][like]=test` |
| [in] | 含む | `filter[status][in]=active,pending` |

### 8.2 ソート構文

```
GET /api/resources?sort=createdAt&order=desc
GET /api/resources?sort=-createdAt,name  # マルチソート（-で降順）
```

---

## 9. Webhook

### 9.1 イベント一覧

| Event | Description | Payload |
|-------|-------------|---------|
| user.created | ユーザー作成時 | User object |
| user.updated | ユーザー更新時 | User object |
| order.completed | 注文完了時 | Order object |

### 9.2 Webhook構造

```json
{
  "id": "evt_uuid",
  "type": "user.created",
  "timestamp": "ISO8601",
  "data": {
    // イベント固有データ
  },
  "signature": "HMAC-SHA256 signature"
}
```

### 9.3 署名検証

```typescript
const isValid = crypto
  .createHmac('sha256', webhookSecret)
  .update(JSON.stringify(payload))
  .digest('hex') === signature;
```

---

## 10. SDK/クライアント例

### 10.1 TypeScript/JavaScript

```typescript
import { ApiClient } from '@project/api-client';

const api = new ApiClient({
  baseUrl: 'https://api.example.com/v1',
  accessToken: 'your-token',
});

// ユーザー一覧取得
const users = await api.users.list({ page: 1, limit: 20 });

// ユーザー作成
const newUser = await api.users.create({
  name: 'John',
  email: 'john@example.com',
});
```

### 10.2 cURL例

```bash
# ログイン
curl -X POST https://api.example.com/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "user@example.com", "password": "password123"}'

# ユーザー一覧取得
curl https://api.example.com/v1/users \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

---

## 付録

### A. OpenAPI仕様（抜粋）

```yaml
openapi: 3.0.3
info:
  title: Project API
  version: 1.0.0
servers:
  - url: https://api.example.com/v1
paths:
  /users:
    get:
      summary: ユーザー一覧取得
      security:
        - bearerAuth: []
      parameters:
        - name: page
          in: query
          schema:
            type: integer
            default: 1
      responses:
        '200':
          description: Success
components:
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT
```

### B. 変更履歴

| 日付 | バージョン | 変更内容 |
|------|------------|----------|
| {日付} | 1.0.0 | 初版作成 |
