# Kumi Project Blueprint v2

> **Kumi — Safe Application-as-Code for Phoenix and Ash**
>
> Application変更を、レビュー可能・テスト可能・デプロイ可能なPlanへ変換するレイヤー。

---

## 0. v1からの変更点

v1（`KUMI_PROJECT_BLUEPRINT.md`）は「Phoenix上にApplication Frameworkを自作する」設計だった。
v2はAsh評価の結果を反映し、前提を反転する。

| | v1 | v2 |
|---|---|---|
| 土台 | Phoenix + Ecto（Ashは最後に比較） | **Phoenix + Ash**（Ash比較を最初に実施） |
| Kumiの範囲 | DSL / IR / CRUD / Admin / API / Auth 全部 | **Plan / Drift / Safety / AI Patch / CI** のみ |
| 最初の実装 | Kumi独自DSL → IR | **Ash製Mini CRM → `mix kumi.plan`** |
| 競合姿勢 | Ashと並走 | **Ashと戦わない。Ashの上の空きレイヤーを取る** |
| v0.1サイズ | 数ヶ月 | **数日〜数週間で検証可能** |

理由：現行のAshは既に「Resource宣言から周辺機能を派生させる」Application Frameworkであり、
AshPostgres（`mix ash.codegen`によるsnapshot比較migration生成）、AshAdmin、AshJsonApi、
Policy、Multitenancy、PubSub Notifier、AshOban、AshAIまでエコシステムが揃っている。
v1のMVPリストの大半は、Ashの再実装になる。

v1は歴史的文書として残す。本ファイルが新しい **Project Source of Truth**。

---

# 1. Vision

## 1.1 一言で言うと

Kumiは、**Applicationの変更を、検証済みのPlanとして扱えるようにするレイヤー**。

```text
Terraform → Infrastructure as Code
Kumi      → Application as Code
```

## 1.2 レイヤー構造

```text
                    Kumi

             Application as Code
                     │
       ┌─────────────┼─────────────┐
       │             │             │
      Plan          AI            DX
       │             │             │
  DB Drift      Source Patch    Preview
  Safety        Validation      CI / Deploy
       │             │             │
       └─────────────┼─────────────┘
                     │
                    Ash
                     │
        ┌────────────┼─────────────┐
        ↓            ↓             ↓
    Resources      Policies      Actions
        ↓            ↓             ↓
   AshPostgres   AshAdmin     AshJsonApi
        │
     PostgreSQL
```

Ashが解いている問題をKumiは作らない。

| v1でKumiが作る予定だったもの | v2での担当 |
|---|---|
| Resource DSL / IR | Ash Resource |
| Generic CRUD Engine | Ash Actions / Changesets / Queries |
| REST API | AshJsonApi |
| Admin UI | AshAdmin |
| Permission / RBAC | Ash Policies |
| Realtime | Ash.Notifier.PubSub + Phoenix.PubSub |
| Background Jobs | AshOban |
| Migration生成（通常パス） | `mix ash.codegen` |

Kumiに残る問題：

```text
1. Desired（コード）vs Actual（本番DB）の drift 検出
2. Schema変更の安全性分類（SAFE / REVIEW / DANGEROUS）
3. AIによるSource変更の検証パイプライン
4. Plan → CI → PR → Preview のワークフロー
```

---

# 2. Source of Truth モデル

v1 §9の未決問題（DB introspection vs metadata、どちらが真か）をここで確定する。

```text
             Source of Truth
                  ↓
               CODE（Git上のAsh Resource定義）
                  ↓
             Desired State
                  ↓
             Kumi Planner
              ↙       ↘
   DB introspection   Previous snapshot
    = Actual State     = Historical Hint
```

- **Desired State** … Git上のApplication Definition（Ash Resource）。真実はここ。
- **Actual State** … PostgreSQL introspection（pg_catalog）。DBに何が実在するかはこちらを信じる。
- **Snapshot** … AshPostgresのsnapshot等。歴史情報。`rename`か`drop+add`かの判別など、
  DesiredとActualだけでは決められない曖昧さを解くヒントとしてのみ使う。

3つの役割が重ならないので矛盾しない。

### AshPostgresとの違い（Kumiの核心）

```text
ash.codegen:   Current Resource  vs  Previous Snapshot   （コード履歴ベース）
kumi.plan:     Desired Resource  vs  Actual PostgreSQL   （実DB照合ベース）
```

ash.codegenは「コードがどう変わったか」から migration を作る。
Kumiは「本番DBが今どうなっているか」と照合する。だから手作業で追加されたカラムを検出できる：

```text
Code                      Actual DB
customers                 customers
├ id                      ├ id
├ name                    ├ name
└ email                   ├ email
                          └ legacy_phone   ← 手作業追加

KUMI PLAN
~ customers
  - legacy_phone
    DRIFT DETECTED
    Safety: REVIEW
```

---

# 3. Kumi Plan Engine

## 3.1 Input / Output

```text
Input:
  Ash Resource定義（Desired）
+ PostgreSQL introspection（Actual）
+ AshPostgres snapshot（Hint）

Output:
  Kumi Plan
  = 差分操作リスト + 安全性分類 + 説明
```

## 3.2 UX

```bash
mix kumi.plan
```

```text
Kumi Plan

Customer
─────────────────────────────
+ add column status varchar
  SAFE

~ email nullable → not null
  REVIEW

- legacy_code
  DANGEROUS

+ index customers_status_idx
  SAFE
─────────────────────────────
2 safe / 1 review / 1 dangerous
```

CI用：

```bash
mix kumi.plan --check
# REVIEW以上が含まれる場合 exit code ≠ 0
```

## 3.3 安全性分類

### SAFE

- nullable column追加
- index追加（※本番はCONCURRENTLY前提。将来の注記対象）
- enum option追加

### REVIEW

- NOT NULL化
- unique制約追加
- rename
- relation変更
- drift（コードに無いDBオブジェクト）

### DANGEROUS

- column / table削除
- 非互換type change
- destructive relation change

DANGEROUSは自動適用しない。常に人間のレビューを要求する。

## 3.4 分類の2段階（実装上の重要な区別）

```text
Stage 1 — Catalog-based（v0.1）
  pg_catalogだけで判定できる分類。
  DBへの接続はread-only introspectionのみ。

Stage 2 — Data-aware（v0.1.5以降）
  「email NOT NULL化 → 現在143行がNULL」
  「legacy_code削除 → 28,392行に値が存在」
  のような実データ検査。実DBへのSELECTが必要になるため、
  権限・実行コスト・本番接続ポリシーを整理してから追加する。
```

v0.1はStage 1のみ。Stage 2はスコープを明示的に分ける（黙って本番DB読み取り要件を増やさない）。

---

# 4. AI Integration（v0.2）

AIをRuntimeに埋め込まない。AIの役割は**Sourceへのpatch提案**のみ。この原則はv1から変更なし。

```text
User: 「Customerにstatusを追加。lead/active/lost。営業担当だけ更新可能。」
  ↓
AI: Ash Resourceへのsource patch
  attributes do
+   attribute :status, :atom do
+     constraints one_of: [:lead, :active, :lost]
+   end
  end
  ↓
mix format
mix compile
mix test
mix ash.codegen
mix kumi.plan
  ↓
Kumi Report:
  ✓ Source valid
  ✓ Policy valid
  ✓ Migration valid
  ✓ No dangerous operation
  Ready for PR
```

AshAIはStructured Outputs / MCP / Vectorization等を提供するが、
「AIにApplication Sourceを安全に変更させ、DB差分・migration・CIまで検証する」役割は担っていない。
ここがKumi最大の価値になる可能性がある。

---

# 5. v0.1 Scope

```text
1. 既存のAsh Application（Kumi無しで動くもの）を前提にする
2. mix kumi.plan
   - PostgreSQL introspection
   - Ash Resourceからdesired schema抽出
   - Desired vs Actual diff
   - SAFE / REVIEW / DANGEROUS 分類（Stage 1）
   - Migration proposal（ash.codegen / Ecto migrationへの橋渡し）
3. mix kumi.plan --check（CI）
```

これだけ。DSLなし、Adminなし、CRUDなし、REST APIなし、Authなし。
すべてAshが提供済みだから。

### 実装ノート

- Desired schema抽出は、AshPostgresが持つResource/DataLayer introspection
  （table名、attributes、identities、custom_indexes等）を再利用できる可能性が高い。
  ゼロから抽出器を書く前にSpike 0で確認する。

## Explicitly NOT in v0.1

- Kumi独自DSL（作らない。恒久的に不要な可能性が高い）
- Generic CRUD Engine（Ashに委譲）
- Admin / REST / Auth / Permission（Ashに委譲）
- Data-aware safety（v0.1.5）
- AI patch pipeline（v0.2）
- GUI / Cloud / Marketplace（変更なし、遠い将来）

---

# 6. Spike Plan（Go/No-Go）

v1のSpike A〜Fを置き換える。**Spike 0（旧Spike F）が最初**。

## Day 0 — Spike 0: Ash Baseline

- Mini CRM（Account / Contact / Deal）をAshだけで実装
- AshAdmin / AshJsonApi / Policiesを実際に有効化
- 「Ashがどこまでやるか」を記録（推測ではなく実測）
- AshPostgresのsnapshot形式とResource introspection APIを確認

## Day 1 — Spike 1: Introspection & Diff

- pg_catalogからActual Schemaを取得
- Ash ResourceからDesired Schemaを抽出
- 差分を表示

## Day 2 — Spike 2: Diff Cases

以下5ケースを検証：

1. add column
2. remove column（drift検出を含む）
3. nullable → not null
4. type change
5. **rename**（snapshot-as-hintモデルの検証。DesiredとActualだけでは
   `drop+add`と区別できないケースをsnapshotで解けるか）

## Day 3 — Spike 3: Safety Classification

- SAFE / REVIEW / DANGEROUS の分類実装
- `--check` のexit code

## Go/No-Go判定

```text
GO:     上記がAshで提供されておらず、かつ実際に便利
NO-GO:  Ashが既に全部できる → Kumiを独自packageにせずAsh extensionとして提案
```

どちらに転んでも失敗ではない。NO-GOでもSpike 0の成果物（Ash製Mini CRM）は
そのまま次のプロジェクトの土台になる。

---

# 7. Risks（v2版）

## Risk 1 — Ashがdrift検出をネイティブに実装し、Kumiが「機能」で終わる

最大のリスク。diff単体はコピー可能。

対策：

- **Productはplan/CI/AI-patchパイプライン全体**であり、drift diffはその入口（wedge）と位置付ける
- 将来 `kumi.plan` をAsh無しの素のEcto appでも動くようにすれば市場が広がる
  （open question。v0.1ではコミットしない）
- Ash coreチームとの関係構築。extension化への転換も常に選択肢に残す

## Risk 2 — Ashへの依存結合

Ashのbreaking change / 内部API変更に引きずられる。

対策：Desired抽出を薄いadapter層に隔離。pg_catalog側はAsh非依存に保つ。

## Risk 3 — Desired schema抽出の忠実度

Ash Resourceの表現（calculated attributes、embedded resources等）と
物理schemaの対応が1:1でないケースがある。

対策：v0.1は対応可能なサブセットを明示的に定義し、対象外は「Kumi管理外」として
planから除外表示する（黙って無視しない）。

## Risk 4 — Framework magic（v1 Risk 6を継承）

対策：`mix kumi.plan`自体が「何が起きるか見える化」の道具。
planの根拠（どのcatalog行、どのsnapshot entryから判定したか）を`--verbose`で説明可能にする。

---

# 8. Positioning

旧：~~Phoenix版Payload~~（弱い）
旧：~~Application Framework for the AI era~~（Ashと重なる）

現：

> **Kumi — Safe Application-as-Code for Phoenix and Ash.**

または：

> **Kumi turns application changes into reviewable, testable and deployable plans.**

概念上の参照点はTerraform。CMSでもAdmin generatorでもない。

---

# 9. v1から引き継ぐもの（変更なし）

- **P3. Safe change over instant change** — Kumiの存在理由そのもの
- **P4. PostgreSQL first**
- **P6. One-person maintainable** — v2で初めて現実的になった
- **Source-first原則**（§2で精密化） — GUI/AIはSource of Truthではなく、Definitionへの入力
- Security Baseline（v1 §41） — 特にidentifier sanitization、migration privilege separation
- ADR運用（v1 §46）。ADR-008として「Kumi builds on Ash, not beside it」を追加
- AGENTS.md / ARCHITECTURE.mdによるAI開発ルール（v1 §47）
- Semantic Versioning方針（v1 §48）

---

# 10. Roadmap

```text
v0.1   mix kumi.plan（catalog-based）+ --check
v0.1.5 Data-aware safety
v0.2   AI source patch pipeline（validate → plan → report → PR-ready）
v0.3   Preview environment統合 / migration実行ワークフロー
v0.4+  非Ash Ecto app対応の検討 / GUI → Definition Change
```

---

# 11. Open Questions

- [ ] Ash extension vs 独立package（Spike 0後に判断）
- [ ] `kumi.plan`のmigration proposal出力形式：ash.codegen呼び出し / 素のEcto migration / 両方
- [ ] snapshot形式：AshPostgres snapshotをそのまま使うか、Kumi独自snapshotを持つか
- [ ] 非Ash Ecto appサポートの是非（市場 vs 複雑性）
- [ ] License（Apache-2.0第一候補、v1から変更なし）
- [ ] Hex package名 / GitHub org / 商標（v1から変更なし）

---

# Project North Star（v2）

> **HumanもAIも、Application Source（Ash Resource）だけを変更する。**
> **Kumiが、その変更を検証済み・分類済み・レビュー可能なPlanへ変換し、**
> **本番DBとの整合性を担保する。**

```text
Human Developer ─┐
                 │
AI Agent ────────┼──→ Ash Resource (Source)
                 │          ↓
GUI (future) ────┘        Git / PR
                            ↓
                    mix kumi.plan
                    ├ Desired（Code）
                    ├ Actual（PostgreSQL）
                    └ Hint（Snapshot）
                            ↓
                  SAFE / REVIEW / DANGEROUS
                            ↓
                    CI → Migration → Runtime
```

最初に証明すること：

> **既存のAsh applicationに対して `mix kumi.plan` を実行すると、
> 本番DBとのdriftと変更の危険度が一目で分かる。**

これが成立し、Ashが提供しておらず、実際に便利なら、Kumi GO。
