# Kumi Project Blueprint v3

> **Ash helps you model your application. Kumi helps you ship it as a product.**
>
> Payload級のDXで、CRM・CMS・Booking・StoreOpsなど完全なSaaSプロダクトを
> Phoenix/Ashの上に構築するApplication Platform。

Supersedes: `KUMI_PROJECT_BLUEPRINT_v2.md`（v2は「plan単機能」へ縮小しすぎた。
planはKumiの差別化機能の一つであり、Kumiそのものではない）

---

## 0. 確定事項（このv3で確定済み）

| 決定 | 内容 |
|---|---|
| **D1. Show Ash** | Ashを隠さない。Kumi DSLは**本物の・可視の・検査可能なAsh Resource**へコンパイルされる。複雑な場面ではAshを直接書く——これは「Kumiからの脱出」ではなくKumiの上級モード。Next.js/Reactの関係。 |
| **D2. Ecto adapter廃止** | コンパイルターゲットはAsh単一（Kumi → Ash → AshPostgres）。二重adapterは「二つの後端の共通部分に意味論が縛られる」＋互換マトリクス維持という長期コスト。Ashが将来倒れたらその時にcompiler書き直し。今日は払わない。 |
| **D3. North Star復帰** | v1の「PayloadのようなDXで何でも作れるPhoenix Application Platform」がNorth Star。v2の`kumi.plan`はwedge（楔）として維持。 |

独立性の正しい形：**Kumiの意味論（Application IR / Plan Model / Plugin Model /
UI Definition）はAshの内部詳細から独立**させる。persistence engineの抽象化はしない。

---

# 1. Positioning

## Ash と Kumi の分業

**Ash = Domain Application Framework** — 「Customerとは何か」を解く：

```text
attributes / actions / relationships / policies / calculations / storage
```

**Kumi = Product/Application Framework** — 「このSaaSとは何か」を解く：

```text
どのResourceを持つか / ナビゲーションの構成 / エンドユーザーが見るUI
どのworkflowがこの製品に属すか / どのpluginが有効か
どう初期化するか / どう安全に変更するか / どうpreviewするか
AIがどうapplicationを変更するか / production driftをどう検出するか
```

```text
Ash                          Kumi
Customer                     CRM Application
Order                        ├ Navigation
Invoice          ────→       ├ Product Admin UI
Actions                      ├ Sales workflow
Policies                     ├ Dashboard
                             ├ Plugins
                             ├ Deployment plan
                             └ AI-editable definition
```

一言：

> **Ash helps you model your application. Kumi helps you ship it as a product.**

---

# 2. Layering

```text
                 Kumi
        Product/Application Layer
      ┌─────────────────────────┐
      │ App Definition          │
      │ Product Admin           │
      │ Plugins                 │
      │ Plan / Safety           │
      │ AI Patching             │
      │ DX / CLI                │
      │ Preview / Deploy        │
      └───────────┬─────────────┘
                  ↓
                 Ash
        Domain Application Layer
      ┌─────────────────────────┐
      │ Resources / Actions     │
      │ Policies / Relations    │
      │ Calculations/Aggregates │
      │ Auth / Jobs / API 生態  │
      └───────────┬─────────────┘
                  ↓
               Phoenix
                  ↓
             PostgreSQL
```

役割：Phoenix = web/runtime、Ash = domain engine、Kumi = product framework、
その上 = Your SaaS（CRM/CMS/Booking/…）。

---

# 3. DSL — 二層の所有権

## 3.1 原則：Kumi DSLはAsh DSLの換皮ではない

```elixir
# これはやらない（改名しただけの重複）
# Ash:  attribute :name, :string
# Kumi: field :name, :string   ← 差がなければ価値ゼロ
```

Kumi DSLが所有するのは**app-level intent**。domain-levelはAshの主場であり奪わない。

```elixir
app :sales do
  title "Sales"

  admin do
    navigation [:accounts, :contacts, :opportunities]
  end

  resource Account
  resource Contact
  resource Opportunity

  workflow :sales_pipeline do
    stages [:lead, :qualified, :proposal, :won, :lost]
  end

  dashboard :overview do
    metric :pipeline_value
    metric :conversion_rate
  end
end
```

Resource自体は標準のAsh Resourceでよい：

```elixir
defmodule MyCRM.Account do
  use Ash.Resource, domain: MyCRM

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
  end

  actions do
    defaults [:read, :create, :update, :destroy]
  end
end
```

## 3.2 Shorthand（入門モード）

簡単な場面ではKumi shorthandも提供する。ただし**必ず標準Ash Resourceへ展開される糖衣**：

```elixir
use Kumi.App

resource Customer do
  field :name, :string
  field :email, :email
end
```

展開結果は常に可視化できる：

```bash
mix kumi.expand Customer
# → 生成されるAsh Resourceコードを表示（explainable magic）
```

calculations / aggregates / custom actions / 複雑なpolicyが必要になったら、
Ashを直接書く。二つの層は衝突しない：

```text
Kumi DSL  … app / navigation / workflow / dashboard / plugin有効化 / shorthand resource
Ash DSL   … attributes / actions / policies / calculations / relationships
```

---

# 4. 差別化の優先順位

重要度順（「我々にもResource DSLがある」は差別化に**入れない**）：

```text
1. Application-level model（app/navigation/workflow/dashboardが一つの定義）
2. Payload級 Product DX（mix kumi.new → 動く製品）
3. Production-quality Admin/UI generation（§5）
4. Plan / Drift / Migration Safety（§7、v2から継承）
5. AI → Definition Patch → Test → Preview → Deploy（§8）
6. Application-aware plugin system（§6）
7. CLI / scaffolding / conventions
```

---

# 5. Kumi Admin — Product Shell

AshAdminはResource管理・super-admin向け。Kumi Adminの目標は別物：

> **Kumiで作ったCRMの中で、顧客（エンドユーザー）が毎日実際に働けるUI。**

データベース管理器ではなく、完全なSaaS shell：

```text
Sidebar / Navigation / Dashboard
List / Form / Detail / Search / Saved views
Actions / Notifications / Permissions
Theme / Responsive
```

`app`定義の`admin do ... end`ブロックがこのshellを駆動する。
「開けばもう製品」というPayloadの体験を目指す。

**ただしこれは計画中最大の単一コスト項目。** wedge（§9）が採用を証明した後に着手。

---

# 6. Plugin Model

## 存在判定基準（厳格に適用）

Kumi pluginは**Ash packageの薄いwrapperであってはならない**。
「Ash X + 設定10行」ならpackageにせずguide一枚で済ませる。

pluginを名乗る条件：**Application Modelへの全鎖統合**。例：

```elixir
# Kumi.Storage が本物のpluginである理由：
field :avatar, :image
# ↑この一行で以下が全部繋がる
#   upload UI / storage / validation / thumbnail
#   API serialization / permission / cleanup
```

```text
# Kumi.Mail が本物のpluginである理由：
単なるResend wrapperではなく
Template / Campaign / Contact / Delivery / Event
Admin UI / Jobs / Analytics までApplication Modelに統合
```

## 生態の順序

pluginはリストから計画せず、実践から抽出する：

```text
wedge証明 → Ash公式ライブラリでMini CRMを組む guide を書く
         → guideに繰り返し現れる糊コードが最初のpluginの原料
         → 公式plugin → community plugin → 業務plugin（Kumi CRM等）
```

---

# 7. Plan / Drift / Safety（v2から変更なしで継承）

Kumiの技術的wedge。詳細はv2 §2–3の通り：

- Source of Truth：**Code = Desired / PostgreSQL introspection = Actual / Snapshot = Historical Hint**
- `mix kumi.plan`：Desired vs Actual diff + SAFE / REVIEW / DANGEROUS 分類
- `mix kumi.plan --check`：CI統合（REVIEW以上でexit ≠ 0）
- Stage 1 = catalog-based（v0.1）、Stage 2 = data-aware（v0.1.5、本番DB読み取り要件を明示分離）
- ash.codegen（コード履歴ベース）との違い＝実DB照合ベース。手作業driftを検出できる

---

# 8. AI Integration

v2の原則を維持しつつ、対象を**app-level definition**へ拡大：

```text
User: 「営業パイプラインにapproval段階を追加して」
  ↓
AI: Kumi App Definition / Ash Resource へのsource patch
  ↓
mix format / compile / test / ash.codegen / kumi.plan
  ↓
Kumi Report: Source valid / Policy valid / Migration valid / No dangerous op
  → Ready for PR
```

AIはRuntimeに埋め込まない。AIが触るのはSourceのみ。
app-levelのsafety plan（F07、§10のfriction log参照）はAshが提供していない領域。

---

# 9. Roadmap

wedge-first。`kumi.plan`はplan単機能製品としてではなく、**採用ファネル**として先行させる：
最初のユーザーは既存のAsh開発者であり、Ashコミュニティへの配布チャネルになる。

```text
Day 0–3  Spikes（§10）
v0.1     mix kumi.plan + --check（既存Ashアプリに単体で有用）
v0.1.5   Data-aware safety
v0.2     app定義 + compiler（app/navigation/workflow/dashboard → Ash wiring）
         + mix kumi.new / kumi.expand
v0.3     Kumi Admin（product shell）
v0.4     AI patch pipeline（app-level）
v0.5+    Plugin抽出（guideの糊コードから）/ Preview / Deploy
```

---

# 10. Spike Plan（Day 0–3、v2から拡張）

## Day 0 — Spike 0: Ash Baseline + **Friction Log**

Mini CRM（Account / Contact / Deal）を純Ashで実装。AshAdmin / AshJsonApi /
Policies / AshAuthenticationを実際に有効化する。

問いは「Ashは何ができるか」だけでなく「**完全な製品にするために開発者は
あと何をするか**」。摩擦を全部記録する：

```text
Friction Log（このログがKumi DSL / Adminの製品要求文書になる）

F01 Resource作成は簡単か
F02 複数Resourceを一つの完全な製品に組織する作業量
F03 AshAdminはsuper-admin的か、エンドユーザーが使えるか
F04 製品navigationは自前構築が必要か
F05 Dashboardに統一されたapplication definitionはあるか
F06 Workflow / UI / Resourceは同一モデルに載るか
F07 AI変更後のapp-level safety planは存在するか
...
```

想像で「Kumiに必要な機能」を規定しない。
**Ashが既にやること → 残る摩擦 → Kumiがそれを消す**、の順で決める。

## Day 1 — Spike 1: Introspection & Diff

pg_catalog（Actual）× Ash Resource抽出（Desired）の差分表示。
Desired抽出はAshPostgresのResource introspection再利用を最初に検証。

## Day 2 — Spike 2: Diff 5ケース

1. add column
2. remove column（drift検出）
3. nullable → not null
4. type change
5. rename（snapshot-as-hintモデルの検証）

## Day 3 — Spike 3: Safety Classification

SAFE / REVIEW / DANGEROUS + `--check` exit code。

## Go/No-Go（二段構え — 独立した2つの仮説を別々に判定する）

```text
GO-wedge:     planがAshに無く実際に便利 → v0.1をstandalone toolとして出せる
GO-platform:  Friction Logに実質的な残余摩擦がある → v0.2+（app定義/Admin）が正当化される

NO-GO両方:    Ashが全部できる → Ash extensionとして貢献。Spike 0の成果は無駄にならない
```

wedgeだけGOでもplan単体はAshコミュニティ向けツールとして成立する。

### 判定結果（2026-08-26、Spike 0–3実施済み）

- **GO-wedge ✅** — 手動driftを実DBで検出（ash.codegenは原理的に不可視）。clean状態でdesired/actual零diff、64テストgreen。
- **GO-platform ✅** — F03（AshAdminはsuper-admin用途）/ F04（navigation概念なし）/ F05（application定義なし）を実機確認。

---

# 11. Risks（v3版）

## Risk 1 — Ashがapp-level機能を公式実装し、Kumiの層が消える（最大リスク、継続）

対策：friction log駆動で「Ashが埋めない摩擦」だけを製品化。Ash coreとの関係構築。
wedge（plan）はAshの設計思想（コード履歴ベース）と直交するため最も安全な陣地。

## Risk 2 — Kumi Adminのコスト爆発

完全なSaaS shellはそれ自体が一つの製品。対策：v0.3まで着手しない。
着手時もF03/F04（friction log）が示す最小shellから。

## Risk 3 — 二層DSLの混乱（どこまでKumi、どこからAsh）

対策：所有権ルールを文書とコンパイラの両方で強制。
Kumi = app-level + shorthand糖衣、Ash = domain-level。
`mix kumi.expand`で展開を常に可視化（explainable magic）。

## Risk 4 — Ash依存結合

D2で受容済み。Kumi IR / Plan Model / Plugin Model / UI DefinitionをAsh内部詳細から
隔離することが唯一の防御。adapter層は作らない。

具体的な既知依存（Spike実測で確認済み）：

- **snapshot JSON形式**（rename hintが依存）はAshPostgresの未文書化内部実装で、
  後方互換の保証がない（Spike 2 F20）。AshPostgresバージョンアップで壊れる前提を持ち、
  実snapshotを読むテストで破損を即検出できる状態を維持する。
- FK制約名・identity index名の既定命名規則は公開APIに存在せず、
  `migration_generator.ex`のソースから写した（Spike 1 F17）。同上の扱い。

## Risk 5 — Scope explosion（v1の再来）

対策：v0.1は今もplan単体。§9の順序を守る。pluginは実践抽出のみ（§6）。

---

# 12. Open Questions

- [ ] shorthand `resource`のコンパイル方式：マクロ展開（コード非生成）vs コード生成（`kumi.expand`で実体化）
- [ ] `app`定義とAsh Domainの対応関係（1:1か、appが複数domainを束ねるか）
- [ ] Kumi Adminの技術基盤：LiveViewコンポーネント設計、theme機構
- [ ] Workflow実行エンジン：AshStateMachine利用か独自か（Spike 0で評価）
- [ ] License / Hex名 / GitHub org / 商標（v1から未決のまま）

---

# Project North Star（v3・最終）

> **PayloadのようなDXで、CMSに限定されず何でも作れるPhoenix Application Platform。**
> **HumanもAIも、Application Definition（Kumi app-level + Ash domain-level）だけを変更する。**
> **Kumiがそれを完全な製品——Admin・API・Auth・Realtime・安全なMigration——へ変換する。**

```text
Developer / AI
      ↓
Kumi Application Definition（app-level intent）
      ↓
Kumi Compiler / DX
      ↓
本物のAsh Resource（可視・検査可能・直接編集可）
      ↓
Ash ecosystem（Postgres / API / Auth / Jobs / …）
      ↓
Phoenix / PostgreSQL
      ↓
Your SaaS — 顧客が毎日その中で働く製品
```

最初に証明すること（変更なし）：

> **既存のAsh applicationに `mix kumi.plan` を実行すると、
> 本番DBとのdriftと変更の危険度が一目で分かる。**

その次に証明すること（v3で追加）：

> **Friction Logが示す残余摩擦を、`app`定義とKumi Adminが実際に消せる。**
