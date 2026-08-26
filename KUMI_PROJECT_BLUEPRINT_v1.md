# Kumi Project Blueprint

> **Kumi — Application-as-Code for Elixir/Phoenix**
>
> 小さな宣言から、DB・Migration・Admin UI・API・Realtime・権限・Workflowまでを一貫して生成・実行する、AI時代のアプリケーション基盤。

---

## 0. このドキュメントの目的

このドキュメントは、Kumiを「Phoenix版Payload」というアイデアで終わらせず、実際にOSSとして開発開始できる状態まで具体化するための設計書です。

対象は以下です。

- 何を作るのか
- 何を作らないのか
- Kumiのコア思想
- MVPで必要な機能
- 技術アーキテクチャ
- DSL / Application Definition
- Migration / Schema Diff
- Admin UI / API
- Event / Action / Workflow
- AIとの接続方法
- OSSとしての構成
- 開発ロードマップ
- 最初に作るBenchmark Application
- 将来のCloud / Enterprise / Marketplace構想
- 未決定事項と技術検証項目

このファイルを、当面の **Project Source of Truth** として扱います。

---

# 1. Vision

## 1.1 一言で言うと

Kumiは、**アプリケーションの構造をコードで宣言すると、一般的な業務SaaSに必要な共通機能を自動で提供するApplication Framework / Platform**です。

```text
Application Definition
        ↓
       Kumi
        ↓
┌────────────────────────────┐
│ PostgreSQL Schema          │
│ Migration                  │
│ CRUD                       │
│ Admin UI                   │
│ REST API                   │
│ Validation                 │
│ Permission                 │
│ Realtime                   │
│ Audit                      │
│ Event                      │
│ Workflow                   │
└────────────────────────────┘
```

目標は「CMSを作ること」ではありません。

Kumiを使って、以下のようなアプリケーションを共通基盤から作れることを目指します。

- CRM
- CMS
- ERP
- Booking / Reservation
- Store Operations
- Helpdesk
- Email Marketing
- Inventory
- Membership
- HR / Recruiting
- Internal Tools
- Analyticsの管理部分
- Vertical SaaS

---

## 1.2 Kumiの本質

Kumiの本質は次の3つです。

```text
Data
+
Event
+
Action
```

### Data

- Resource / Collection
- Field
- Relation
- Validation
- Index
- Permission

### Event

- Created
- Updated
- Deleted
- State Changed
- Custom Event
- Scheduled Event

### Action

- Create / Update Record
- Send Email
- Call Webhook
- Start Background Job
- Emit Event
- Custom Elixir Function

この3つをApplication Definitionとして宣言し、Kumiが実行可能なアプリケーションへ変換します。

---

# 2. Why Kumi

## 2.1 現在のWeb/SaaS開発の問題

一般的なSaaSを作るだけでも、構成が分散しやすいです。

```text
Frontend
+ API
+ ORM
+ PostgreSQL
+ Auth
+ Queue
+ Redis
+ WebSocket
+ Storage
+ Admin
+ Validation
+ Audit
+ Workflow
```

それぞれは優秀でも、開発者は以下を常に管理する必要があります。

- 各サービス間の設定
- 接続情報
- schema同期
- 型同期
- API同期
- frontend/backend state同期
- deploy順序
- migration
- preview environment
- local/staging/production差分

Kumiでは、Phoenix/BEAMとPostgreSQLを中心に可能な限り一つのApplication Runtimeへ集約します。

---

## 2.2 GUI-firstではなくSource-first

Kumiでは以下を基本原則とします。

> **The application is source code, not production database state.**

GUIやAIはSource of Truthそのものではありません。

```text
Developer ───────┐
                 │
GUI ─────────────┼──→ Application Definition → Git
                 │
AI ──────────────┘
```

すべての変更は、最終的に確認可能なApplication Definitionへ変換されます。

その結果、以下が可能になります。

- Git diff
- Pull Request
- Code Review
- CI
- Automated Test
- Migration Review
- Preview Environment
- Rollback
- AI Agentによる安全な変更

---

# 3. Product Positioning

Kumiは以下の単純なコピーを目指しません。

- Phoenix版Payload
- Phoenix版Directus
- Phoenix版Salesforce
- Phoenix版Retool

それらの共通部分を、より下のApplication Layerで抽象化します。

```text
Elixir
  ↓
Phoenix
  ↓
Kumi
  ↓
Applications
```

将来的な位置付けは次です。

> **Application-as-Code framework for building data-driven SaaS on Elixir/Phoenix.**

AIを含める場合も、AIそのものを製品名やコア依存にはしません。

> **AI writes the definition. Kumi guarantees the application.**

---

# 4. Core Principles

Kumiの設計判断は以下を優先します。

## P1. Source-first

Application構造はコードで管理する。

## P2. Convention over generated boilerplate

大量のコードを生成して所有させるのではなく、少量のDefinitionをKumi Runtimeが解釈する。

## P3. Safe change over instant change

「すぐ本番DBを変更できる」より、Diff / Validation / Migration / Testを通して安全に変更できることを優先する。

## P4. PostgreSQL first

初期段階ではDB abstractionを広げすぎない。

PostgreSQLを最大限活用する。

## P5. Phoenix-native

Phoenixの強みを隠さない。

- LiveView
- PubSub
- OTP
- Process
- Supervision
- Ecto

を積極的に利用する。

## P6. One-person maintainable

最初から巨大Platformを作らない。

1人 + AI coding agentで継続可能なサイズを守る。

## P7. Extensible, not everything built-in

専門領域はPlugin / Adapterへ逃がす。

例:

- ClickHouse
- Search Engine
- Email provider
- Object Storage
- Payment
- AI Provider

---

# 5. Initial Target User

最初のターゲットは非エンジニアではありません。

## Primary

- Phoenix / Elixir developer
- Small SaaS team
- AI-assisted solo developer
- Internal tool developer
- Vertical SaaS developer

## Secondary

- Rails developer looking for a stronger realtime/runtime model
- Node / Next.js developer tired of fragmented backend infrastructure

## Later

- Non-technical admin using GUI Builder
- Enterprise internal platform teams

---

# 6. Kumi Application Definition

Application DefinitionがKumiの最重要インターフェースです。

最初はElixir DSLを採用します。

## 6.1 Example

```elixir
defmodule Demo.CRM do
  use Kumi.App

  resource :customer do
    field :name, :string, required: true
    field :email, :email

    field :status, :enum do
      values [:lead, :active, :lost]
      default :lead
    end

    has_many :deals

    permissions do
      read :authenticated
      create :sales
      update :sales
      delete :admin
    end
  end

  resource :deal do
    field :name, :string, required: true
    field :amount, :decimal

    field :stage, :enum do
      values [:new, :proposal, :won, :lost]
    end

    belongs_to :customer
    belongs_to :owner, resource: :user
  end
end
```

KumiはこのDefinitionを内部IRへ変換します。

```text
DSL
 ↓
Application AST / IR
 ↓
Validation
 ↓
Schema Planner
 ↓
Runtime
```

---

# 7. Internal Representation

DSLそのものをコアに依存させすぎないため、内部では中間表現を持ちます。

例:

```elixir
%Kumi.Schema.Resource{
  name: :customer,
  table: "customers",
  fields: [...],
  relations: [...],
  permissions: [...]
}
```

これにより将来、同じIRを以下から生成できます。

```text
Elixir DSL ─┐
YAML/JSON ──┼→ Kumi IR
GUI ────────┤
AI ─────────┘
```

重要なのは、**RuntimeはGUIやAIを知らない**ことです。

---

# 8. MVP Field Types

v0.1では種類を増やしすぎません。

必須:

- string
- text
- integer
- decimal
- boolean
- date
- datetime
- enum
- uuid
- json
- belongs_to
- has_many

v0.2以降:

- money
- email
- url
- phone
- rich_text
- media
- polymorphic relation
- embedded object
- encrypted field

`email`などはDB型ではなくSemantic Typeとして扱う設計も検討します。

---

# 9. Schema Diff Engine

Kumiの最重要コアの1つです。

## Input

```text
Current Database Schema
+
Current Kumi Metadata
+
New Application Definition
```

## Output

```text
Schema Change Plan
```

例:

```text
Resource: customers

+ add column birthday :date
+ add column status :string
+ create index customers_status_idx
~ name nullable true → false
```

Schema Diffを直接SQLにせず、一度IRへ変換します。

```elixir
%Kumi.ChangePlan{
  operations: [
    {:add_column, ...},
    {:create_index, ...}
  ]
}
```

---

# 10. Migration Engine

## 10.1 Goal

Application Definition変更からmigrationを生成する。

```text
Definition Change
 ↓
Diff
 ↓
Safety Analysis
 ↓
Migration File
 ↓
Test
 ↓
Apply
```

CLI案:

```bash
mix kumi.diff
mix kumi.migration.generate add_customer_status
mix kumi.migrate
```

最終的には:

```bash
mix kumi.change
```

でDiff確認 → migration生成まで統合してもよい。

---

## 10.2 Safe Migration Classification

変更は最低でも3段階に分類します。

### SAFE

- nullable column追加
- index追加
- enum option追加

### REVIEW

- NOT NULL追加
- unique追加
- rename
- relation変更

### DANGEROUS

- column削除
- incompatible type change
- destructive relation change

Dangerous変更は自動適用しない。

---

# 11. Runtime Data Access

重要な設計判断:

**ユーザーResourceごとにElixir Module生成を必須にしない。**

Kumi RuntimeがApplication Definitionを参照して、共通Data LayerからCRUDを処理できる構造を優先します。

```text
Request
 ↓
Resource Definition
 ↓
Validation
 ↓
Permission
 ↓
Kumi Query Layer
 ↓
Ecto
 ↓
PostgreSQL
```

これによりKumi内部のboilerplateを減らします。

ただし、開発者が必要ならCustom Ecto/Ash Resourceと接続できるExtension Pointを提供します。

---

# 12. Ash Strategy

Ashは非常に有力ですが、Kumi Core全体を最初からAshへ固定しない方針で開始します。

## Phase 0で比較する

### Option A

```text
Phoenix + Ecto + Kumi
```

### Option B

```text
Phoenix + Ash + Kumi
```

確認項目:

- Dynamic Resourceへの適合性
- Compile-time dependency
- Generated APIとの重複
- Permission modelとの重複
- Migration ownership
- Plugin architecture
- Developer Experience
- 将来のAsh breaking change影響

### 初期仮説

- Kumi CoreのSchema / Migration / IRは独自
- Auth / fixed system resourcesでAshを利用する余地あり
- Ash Adapterは後から追加できる構造にする

---

# 13. Admin UI

AdminはPhoenix LiveViewを第一選択にします。

## v0.1

自動生成する画面:

```text
/admin/customers
/admin/customers/new
/admin/customers/:id
/admin/customers/:id/edit
```

機能:

- list
- create
- edit
- delete
- pagination
- basic search
- filter
- sort
- relation picker
- validation error

## v0.2

- bulk action
- inline edit
- saved view
- column customization
- audit history
- realtime refresh

## v0.3

- Dashboard Builder
- Form Builder
- GUI Resource Builder

---

# 14. REST API

v0.1ではRESTを優先します。

例:

```http
GET    /api/kumi/customers
POST   /api/kumi/customers
GET    /api/kumi/customers/:id
PATCH  /api/kumi/customers/:id
DELETE /api/kumi/customers/:id
```

Query:

```text
?filter[status]=active
?sort=-inserted_at
?page=2
?limit=50
```

将来:

- OpenAPI auto generation
- GraphQL adapter
- JSON:API adapter
- Typed SDK generation

---

# 15. Validation

ValidationはDefinitionから一元生成します。

```text
Kumi Definition
    ↓
DB constraint
Server validation
Admin form validation
API validation
OpenAPI schema
```

同じルールを複数箇所へ手作業コピーしないことが重要です。

---

# 16. Auth / Permission

v0.1ではSimple RBACから開始します。

System resources:

- User
- Role
- API Key

Permission例:

```elixir
permissions do
  read :authenticated
  create [:sales, :admin]
  update [:sales, :admin]
  delete :admin
end
```

将来:

- Field-level permission
- Row-level condition
- ABAC
- Organization / Tenant scope
- SSO

---

# 17. Multi-tenancy

v0.1で設計だけは入れるが、複雑な機能を全部実装しない。

候補:

```text
Shared Schema + tenant_id
```

を初期標準とする。

将来:

```text
Postgres Schema per tenant
Database per tenant
```

をadapterとして検討する。

---

# 18. Event System

CRUDだけではDirectus系の範囲から抜けられないため、Eventは早い段階で設計します。

標準Event:

```text
resource.created
resource.updated
resource.deleted
field.changed
```

例:

```text
order.updated
status: pending → paid
        ↓
order.paid
```

内部はPhoenix PubSubを第一候補とします。

---

# 19. Action System

ActionはEventに対して実行される処理です。

v0.2候補:

- create record
- update record
- send webhook
- enqueue job
- emit event
- run custom function

v0.3以降:

- email
- Slack
- HTTP request
- conditional branch
- schedule
- retry policy

---

# 20. Workflow

最終形:

```elixir
workflow :close_won do
  on event(:deal_won)

  action :create_contract
  action :notify_sales_manager
  action :enqueue_invoice_job
end
```

ただしWorkflow BuilderはMVPには含めない。

---

# 21. Realtime

KumiがPhoenixを選ぶ重要な理由の1つ。

例:

```text
Record Update
 ↓
Kumi Event
 ↓
Phoenix PubSub
 ├ Admin LiveView
 ├ Client subscription
 ├ Workflow
 └ Audit
```

v0.1ではAdmin UI realtime更新のみでもよい。

外部Client Subscription APIはv0.2以降。

---

# 22. Background Jobs

MVPではBackground Job abstractionのinterfaceだけ決めます。

第一候補:

- Oban adapter

Kumi CoreがOban implementationへ強く結合しないようにする。

---

# 23. Audit

業務Application Frameworkとして重要。

最低限:

```text
who
when
resource
record_id
action
before
after
```

MVPでは後回し可能だが、schema設計時点で拡張可能にしておく。

---

# 24. Search

v0.1:

- PostgreSQL LIKE / ILIKE
- indexed filter

v0.2:

- PostgreSQL full text

Later:

- OpenSearch Adapter
- Meilisearch Adapter

専用検索エンジンをCore必須依存にしない。

---

# 25. Media

MVPのCore対象外。

将来的なAdapter:

```text
Local
S3-compatible
Railway Bucket
Cloudflare R2
```

画像処理も別Pluginとする。

---

# 26. AI Integration

AIをKumi Runtimeへ直接埋め込まない。

AIの役割はApplication Definitionの変更案を作ること。

```text
Prompt
 ↓
AI
 ↓
Definition Patch
 ↓
Kumi Validate
 ↓
Schema Diff
 ↓
Tests
 ↓
Preview
 ↓
Human Review
```

例:

```text
「商談に承認フローを追加して」
```

AIが変更するのはKumi Definitionのみ。

Kumiが以下を保証する。

- Definition validity
- schema consistency
- permission validation
- migration safety
- runtime behavior

---

# 27. GUI Builder Philosophy

将来GUIを提供しても、GUIから直接production DB schemaを書き換えることを標準にはしない。

GUIは:

```text
GUI
 ↓
Definition Change
 ↓
Diff
 ↓
Change Set / PR
```

を作る。

Developer Modeでは即時applyするLocal Development UXも検討可能。

---

# 28. Development Experience

理想の開発体験:

```bash
mix kumi.new crm
```

```elixir
resource :customer do
  field :name, :string
end
```

```bash
mix kumi.diff
mix kumi.migration.generate
mix ecto.migrate
mix phx.server
```

すると:

```text
/admin/customers
/api/kumi/customers
```

が利用できる。

---

# 29. Kumi CLI

候補コマンド:

```bash
mix kumi.init
mix kumi.check
mix kumi.diff
mix kumi.migration.generate NAME
mix kumi.migrate
mix kumi.rollback
mix kumi.resource.new NAME
mix kumi.inspect RESOURCE
```

将来的には独立CLIも検討するが、最初はMix taskで十分。

---

# 30. Proposed Repository Structure

最初から多数repoへ分割しない。

```text
kumi/
├ lib/
│  ├ kumi/
│  │  ├ app.ex
│  │  ├ schema/
│  │  ├ definition/
│  │  ├ diff/
│  │  ├ migration/
│  │  ├ data/
│  │  ├ permissions/
│  │  ├ events/
│  │  └ runtime/
│  ├ kumi.ex
│  └ mix/tasks/
│
├ test/
│
├ examples/
│  ├ mini_crm/
│  └ mini_cms/
│
├ guides/
├ README.md
├ CHANGELOG.md
└ mix.exs
```

Admin packageが大きくなった段階で:

```text
kumi_core
kumi_phoenix
kumi_admin
kumi_oban
```

などへの分割を検討する。

---

# 31. MVP Scope — v0.1

## 必須

### Definition

- [ ] `use Kumi.App`
- [ ] resource DSL
- [ ] field DSL
- [ ] belongs_to
- [ ] has_many
- [ ] basic validation

### Schema

- [ ] Application IR
- [ ] Schema inspector
- [ ] Schema diff
- [ ] migration generation
- [ ] migration safety classification

### Data

- [ ] generic query layer
- [ ] create
- [ ] read
- [ ] update
- [ ] delete
- [ ] filter
- [ ] sort
- [ ] pagination

### Phoenix

- [ ] generated Admin index
- [ ] generated form
- [ ] record detail
- [ ] REST CRUD API

### Security

- [ ] basic authentication integration
- [ ] simple role permission

### Developer Experience

- [ ] Mix tasks
- [ ] useful error messages
- [ ] example project
- [ ] installation guide

### Quality

- [ ] unit tests
- [ ] migration tests
- [ ] integration tests
- [ ] CRUD E2E smoke test

---

# 32. Explicitly NOT in v0.1

以下は魅力的でもv0.1から外す。

- GUI Schema Builder
- AI Chat Builder
- GraphQL
- Dashboard Builder
- Workflow Builder
- Marketplace
- Email Marketing
- Analytics Engine
- Page Builder
- Rich Text Editor
- Object Storage
- Multi-region
- Visual automation
- Enterprise SSO
- ABAC
- ClickHouse
- Search engine integration

v0.1の目的は **Framework Coreが成立するか証明すること**。

---

# 33. First Benchmark App — Mini CRM

Kumi Coreの設計検証にはCRMを使う。

理由:

- Relationが必要
- Permissionが必要
- List/Formが必要
- Search/Filterが必要
- Eventへ拡張しやすい
- CMS固有機能に引っ張られない

Resource:

```text
User
Account
Contact
Deal
Activity
```

v0.1 Benchmark:

```text
Account
 ├ Contacts
 └ Deals
```

Definitionはできれば100〜200行以内を目標にする。

Kumi側へCRM固有ロジックを追加せず実現できることが成功条件。

---

# 34. Second Benchmark App — Mini CMS

CRMが成立した後にCMSを作る。

```text
Page
Post
Category
Author
```

ここで以下を検証する。

- draft/publish拡張性
- slug
- rich text plugin
- media adapter

Payload比較用のDemoとして利用する。

---

# 35. Third Benchmark App — Booking

```text
Customer
Facility
Resource
Reservation
TimeSlot
```

検証対象:

- concurrency
- conflict prevention
- realtime
- transaction
- event

Phoenixらしさを示すBenchmark Applicationにする。

---

# 36. Success Metrics for v0.1

v0.1はStar数ではなく以下で判断する。

## Technical

- Mini CRMをKumi Core変更なしで作れる
- Resource追加時のboilerplateを大幅削減できる
- migration diffが安定している
- Admin/API schemaが一致する
- testsでschema changeを検証できる

## Developer Experience

新規ユーザーが:

```text
Install
→ Resourceを書く
→ Migration
→ CRUD
```

まで短時間で到達できる。

## OSS

- READMEだけで動かせる
- ExampleがCIで常にgreen
- Architectureが理解できる
- Contribution可能なissueがある

---

# 37. Phase 0 — Technical Spikes

実装開始前に小さい検証を行う。

## Spike A — DSL → IR

Goal:

```elixir
resource :customer do
  field :name, :string
end
```

をIRへ変換する。

## Spike B — IR → DB Diff

既存DBとの差分を取得できるか確認。

## Spike C — Migration Generator

`add field`をEcto migrationへ変換。

## Spike D — Generic CRUD

Resource-specific moduleを大量生成せずCRUDできるか確認。

## Spike E — Generic LiveView Form

Definitionからformを描画。

## Spike F — Ash Comparison

同じMini ResourceをPure EctoとAshで作り、Kumi Coreとの責務境界を決める。

---

# 38. Recommended Implementation Order

## Step 1

Kumi DSL / IRだけ作る。

DBにはまだ触れない。

## Step 2

PostgreSQL schema introspection。

## Step 3

Diff Engine。

## Step 4

Migration Generator。

## Step 5

Generic Data Layer。

## Step 6

REST API。

## Step 7

Admin LiveView。

## Step 8

Auth / RBAC。

## Step 9

Mini CRM完成。

## Step 10

OSS Alpha公開。

この順番なら、Admin UIに時間を使った後でコア設計をやり直すリスクを下げられる。

---

# 39. Suggested Milestones

## M0 — Architecture Proof

成果物:

- DSL
- IR
- Diff prototype
- Migration prototype

## M1 — Data Framework

成果物:

- CRUD
- Relation
- Validation
- REST

## M2 — Application Framework Alpha

成果物:

- Admin LiveView
- Auth
- Permission
- Mini CRM

## M3 — OSS Developer Preview

成果物:

- Hex package candidate
- README
- Docs
- Example
- CI
- release process

## M4 — Phoenix-native Differentiation

成果物:

- Realtime
- Event
- Background action

## M5 — AI-native Workflow

成果物:

- structured Definition patch
- validation report
- migration impact report
- PR-friendly output

---

# 40. Testing Strategy

FrameworkなのでTestは製品機能と同等に重要。

## Unit

- DSL parser
- IR
- validation
- diff
- type mapper
- permission evaluator

## Database

- migration up
- migration rollback
- data preservation
- relation integrity
- destructive change detection

## Integration

- Definition → DB → CRUD
- Definition → API
- Definition → Admin Form

## E2E

Mini CRMで:

```text
create account
create contact
link contact
update deal
filter list
permission reject
```

---

# 41. Security Baseline

最低限、最初から考慮する。

- arbitrary table/column injection防止
- identifier sanitization
- query parameter allowlist
- tenant isolation
- permission bypass test
- API key hashing
- CSRF
- rate limit extension point
- migration privilege separation
- dangerous schema operation guard

Frameworkは利用アプリへ脆弱性を拡散するため、Security Regression Testを重要視する。

---

# 42. Performance Philosophy

ベンチマーク競争をプロジェクトの主目的にしない。

Kumiの価値は:

```text
Less application code
+ Fewer moving parts
+ Safe changes
+ Phoenix runtime
```

ただし以下は測定する。

- CRUD latency
- LiveView memory
- 1k concurrent realtime connections
- migration time
- list/filter performance
- permission overhead

最適化は測定後に行う。

---

# 43. Deployment

最初の公式Deploy Guide:

## Primary

Railway

```text
Kumi/Phoenix
+
PostgreSQL
```

理由:

- 初期導入が簡単
- DBを近くに置ける
- Preview環境を構成しやすい
- Solo OSS demoとの相性が良い

## Secondary

Fly.io

将来:

- Docker
- AWS
- Render
- Kubernetes

Kumi CoreはHosting Provider非依存にする。

---

# 44. OSS Strategy

CoreはOSS前提。

## Initial License

候補:

- Apache-2.0
- MIT

企業利用・Plugin ecosystemを重視するならApache-2.0を第一候補として検討。

最終決定前にBusiness ModelとTrademark Policyを確認する。

---

# 45. Repository / Community Basics

公開前に最低限用意する。

- README
- LICENSE
- CODE_OF_CONDUCT
- CONTRIBUTING
- SECURITY.md
- CHANGELOG
- GitHub Issue Templates
- Discussions
- Roadmap
- Example apps
- Architecture Decision Records

---

# 46. Architecture Decision Records

重要な判断はADRとして残す。

例:

```text
ADR-001: PostgreSQL-first
ADR-002: Source-first application definition
ADR-003: Elixir DSL as first authoring format
ADR-004: Kumi IR independent from DSL
ADR-005: Generic runtime instead of code generation everywhere
ADR-006: Ash is optional until Phase 0 evaluation
ADR-007: LiveView for first-party Admin
```

AI Agentに開発させる場合もADRが非常に有効。

---

# 47. AI Coding Agent Development Rules

Claude Code / Codex等を利用する前提でRepoに以下を置く。

```text
AGENTS.md
ARCHITECTURE.md
CONTRIBUTING.md
```

AGENTS.mdに最低限書く:

- Core Principles
- dependency rules
- module ownership
- test requirement
- no hidden schema changes
- migration rules
- backward compatibility rule
- public API rule

AIに自由実装させるのではなく、Architecture Boundaryを守らせる。

---

# 48. Semantic Versioning

Alpha段階からVersioningを意識する。

```text
0.1.x experimental
0.2.x events/realtime
0.3.x workflow
...
1.0 stable public API
```

特にApplication Definition DSL変更は利用者への影響が大きいため、migration guideを用意する。

---

# 49. Long-term Plugin Model

Kumi Coreを巨大化させないためPlugin Interfaceを作る。

候補:

```text
Kumi.Oban
Kumi.S3
Kumi.Resend
Kumi.Search
Kumi.Analytics
Kumi.CMS
Kumi.Workflow
```

Third-partyでも:

```text
community package
```

を作れる構造を目指す。

---

# 50. Future Application Templates

将来的にKumi自体だけでなくApplication Templatesを公開する。

```text
kumi-crm
kumi-cms
kumi-booking
kumi-helpdesk
kumi-storeops
```

TemplateはKumi Coreの利用例であり、Coreへ業務固有機能を混ぜない。

---

# 51. Business Model — Later

最初はProduct-Market FitではなくOSS utilityの証明を優先。

将来の収益候補:

## Kumi Cloud

- managed deployment
- PostgreSQL
- backup
- storage
- domain
- preview
- monitoring

## Enterprise

- SSO
- private deployment
- advanced audit
- compliance support
- SLA
- migration support

## Marketplace

- paid templates
- integrations
- plugins

## AI

- Prompt → Kumi Change Set
- architecture assistant
- migration assistant

CloudなしでもOSS Core単体で価値がある状態を維持する。

---

# 52. What Would Make Kumi Truly Important

単にPhoenixでCMSを作れるだけでは不十分。

以下が成立した時にKumiの価値が大きくなる。

```text
CRM
CMS
Booking
StoreOps
Helpdesk
```

を、それぞれKumi Coreへ業務固有機能を追加せずに構築できること。

その結果:

```text
Application-specific code ↓
Framework guarantees ↑
```

となる。

AI Agentは大量のWeb application codeではなく、少量のApplication Definitionを書くようになる。

---

# 53. Project Risks

## Risk 1 — Scope explosion

対策:

v0.1からWorkflow / CMS / AI / Analyticsを作らない。

## Risk 2 — Ashとの責務重複

対策:

Phase 0 comparison。

## Risk 3 — Generic abstraction becomes too weak

対策:

Mini CRM / CMS / Bookingの3種類で継続Benchmark。

## Risk 4 — Generic abstraction becomes too complex

対策:

80% common functionalityを対象にし、専門処理はCustom Code escape hatchへ。

## Risk 5 — Migration safety

対策:

Schema DiffとSafety AnalyzerをCore featureとして扱う。

## Risk 6 — Framework magic becomes impossible to debug

対策:

以下を必須にする。

```text
mix kumi.inspect
mix kumi.diff
Debug logs
Explainable generated plan
```

「何が起きているか見える魔法」にする。

---

# 54. Escape Hatches

Frameworkは100%を抽象化しない。

必ず以下を可能にする。

- custom validation
- custom query
- custom LiveView component
- custom controller
- custom background job
- custom Ecto transaction
- custom event handler

Kumiを使うためにPhoenixの能力を失わないこと。

---

# 55. Naming

Project Name:

# Kumi

意味:

- 組む
- 組み合わせる
- 小さな部品から構造を作る

Concept:

```text
Data + Event + Action
        ↓
      Kumi
        ↓
  Application
```

Tagline候補:

> **Compose applications, not infrastructure.**

または:

> **Application-as-Code for Elixir and Phoenix.**

または:

> **Define the application. Kumi builds the rest.**

正式OSS公開前に商標、GitHub organization、Hex package、主要domainの利用可能性を確認する。

---

# 56. Immediate Next Actions

ここから実際に開始する場合の順番。

## Day 0 — Project Decisions

- [ ] Kumi nameをworking nameとして固定
- [ ] Git repository作成
- [ ] License仮決定
- [ ] ARCHITECTURE.md作成
- [ ] AGENTS.md作成
- [ ] ADR directory作成

## First Coding Session

- [ ] Phoenixから独立したKumi library skeleton
- [ ] `use Kumi.App`
- [ ] `resource/2`
- [ ] `field/3`
- [ ] DSL → IR test

Target:

```elixir
defmodule TestApp do
  use Kumi.App

  resource :customer do
    field :name, :string
  end
end
```

を:

```elixir
Kumi.definition(TestApp)
```

でIRとして取得できるところまで。

## Second Coding Session

- [ ] PostgreSQL schema inspector
- [ ] desired schema生成
- [ ] current vs desired diff

## Third Coding Session

- [ ] add table migration
- [ ] add column migration
- [ ] add index migration
- [ ] migration tests

ここまででKumiの最大の技術仮説を検証できる。

---

# 57. First Public Demo Goal

最初の公開Demoは派手なAI UIではなく、Developer Experienceを見せる。

README:

```elixir
defmodule MyCRM do
  use Kumi.App

  resource :account do
    field :name, :string, required: true
    has_many :contacts
  end

  resource :contact do
    field :name, :string, required: true
    field :email, :string
    belongs_to :account
  end
end
```

```bash
mix kumi.change
mix ecto.migrate
mix phx.server
```

Then:

```text
/admin/accounts
/admin/contacts
/api/kumi/accounts
/api/kumi/contacts
```

Message:

> **Build a working CRM model with a few lines of Elixir.**

---

# 58. Definition of Done for Alpha

Kumi Alpha公開条件:

- [ ] Resource DSL安定
- [ ] basic relation
- [ ] schema diff
- [ ] migration generation
- [ ] migration rollback test
- [ ] generic CRUD
- [ ] REST API
- [ ] Admin LiveView CRUD
- [ ] basic RBAC
- [ ] Mini CRM example
- [ ] 80%+ Core unit coverage目標
- [ ] end-to-end smoke test
- [ ] README Quick Start
- [ ] Architecture document
- [ ] SECURITY.md
- [ ] CI green

---

# 59. Questions Still Open

実装中に決める必要がある。

## Architecture

- [ ] Pure Ecto vs Ash boundary
- [ ] DSL compile-time vs runtime metadata
- [ ] migration file format
- [ ] runtime schema caching strategy
- [ ] relation query strategy
- [ ] permission evaluation architecture

## Product

- [ ] `resource` vs `collection` terminology
- [ ] REST endpoint convention
- [ ] default Admin styling
- [ ] multi-tenantをv0.1へ入れるか

## OSS

- [ ] Apache-2.0 vs MIT
- [ ] Hex package naming availability
- [ ] GitHub organization availability
- [ ] trademark check

---

# 60. Final Direction

Kumiは次のように育てる。

```text
Phase 1
Application Definition
      ↓
Schema + CRUD

Phase 2
Admin + API + Permission

Phase 3
Realtime + Event + Action

Phase 4
Workflow + Plugins

Phase 5
GUI / AI → Definition Change

Phase 6
Cloud / Marketplace / Enterprise
```

最初から「何でも作れるPlatform」を実装しない。

最初は:

> **数十行のDefinitionから、小さなCRMを安全に作れる。**

これを証明する。

そのコアがCRM、CMS、Bookingの3種類で崩れなければ、Kumiは単なるCMS Frameworkではなく、より一般的なApplication Frameworkとして成立する可能性が高い。

---

# Project North Star

> **HumanもAIも、Application Definitionだけを変更する。**  
> **KumiがDatabase・Migration・Admin・API・Realtime・Securityの整合性を担保する。**

```text
Human Developer ─┐
                 │
GUI ─────────────┼──→ Kumi Definition
                 │          ↓
AI Agent ────────┘        Git / PR
                            ↓
                     Validate / Test
                            ↓
                        Migration
                            ↓
                         Runtime
                            ↓
                       Application
```

これをKumiの中心思想とする。
