# Spike 0 — Friction Log

> 目的：純AshでMini CRM（Account / Contact / Deal）を作り、
> 「完全な製品にするために開発者はあと何をするか」を記録する。
> このログがKumi DSL / Kumi Adminの製品要求文書になる（Blueprint v3 §10）。

記録ルール：

- F番号 / 領域 / 事実（何をした・何行書いた・何を調べた）/ 摩擦度（低・中・高）
- 「Ashができない」ではなく「開発者の手作業がどれだけ残るか」を書く
- 良かった点も記録する（Kumiが再発明してはいけない部分の証拠）

---

## Setup

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F00 | scaffold | igniter installer (`ash,ash_postgres,ash_phoenix,ash_json_api,ash_admin,ash_authentication,ash_authentication_phoenix`) は auth resource（`Accounts.User`/`Accounts.Token`）と初回migration2本、`config.exs`の`ash_domains: [Spike0Crm.Accounts]`、`/admin`ルート、`ash_json_api_router.ex`（`domains: []`の空箱）、`router.ex`の`:api`パイプラインまで自動生成済みだった。Repoの接続先（port 5434）だけは環境固有なので`dev.exs`/`test.exs`に1行追加が必要だった。 | 低 |

## Resource定義

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F01 | resource作成量 | Account/Contact/Dealの3リソースはそれぞれ59/61/72行。内訳は`postgres`（table+repo）、`json_api`（type+routes、8行程度）、`actions`（`defaults [:read, :destroy, create: :*, update: :*]`の1行）、`policies`（3行）、`attributes`、`relationships`の6ブロック。1リソースにつき「DBテーブル定義」「REST API」「ポリシー」「Admin表示」の4関心事が1ファイルに同居する。ドメインへの登録は`resources do resource X end`の1行、`config.exs`の`ash_domains`への追加も1行で済み、この部分は軽量だった。 | 中 |
| F02 | accept制御 | `create: :*, update: :*`という省略記法で全public属性・引数を受け付けられる。`belongs_to`が生成する外部キー属性（`account_id`等）は`public? true`を明示しないとAdmin/JSON:APIで見えない・書けない状態になる。関連の必須/任意は`allow_nil?`で表現でき、DDL上のNOT NULLまで自動で伝播した（後述F09）。 | 低 |

## 製品への組み立て（navigation / UI / dashboard）

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F04 | navigation | 3リソースを`Spike0Crm.Crm`ドメインに登録しても、Phoenix側には`/admin`と`/api/json/*`以外のルートは一切増えない。一覧画面・詳細画面・「Account一覧からContact/Dealへ辿る」ような業務ナビゲーションはAshが提供する概念に存在せず、LiveView/Controllerを人間が別途書く前提。Ash＝データ層+API層+ポリシー層であり、"製品の顔"はゼロから作る必要があると実機で確認した。 | 高 |
| F05 | dashboard | 同様に、複数リソースを跨ぐ集計ダッシュボードや「アプリ全体の定義（このアプリにはこの3リソースがあり、こう繋がっている）」を表現する統一的なDSL/画面はAsh本体にはない。`ash_domains`は起動時に読み込むドメインのリストであって、UI上のapplication定義ではない。AshAdminがその代替になり得るか、という点はF03で検証。 | 高 |

## Admin（AshAdminはエンドユーザーに使えるか）

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F03 | AshAdmin本質 | `ash_admin`のREADME自身が "a super-admin UI dashboard for Ash Framework applications" と明記している（`deps/ash_admin/README.md:18`）。ドメイン側は`admin do show? true end`を明示しないと管理画面に一切出てこない（`AshAdmin.Domain`の`show?`はデフォルト`false`）。リソース側は追加の`admin do ... end`ブロックを書かずに済み、`show_resources: :*`のデフォルトのおかげで3リソースとも自動で表示された。つまり「オンにする1行」は必要だが「各リソースの個別設定」は不要だった。用途は開発者/運用者向けの生CRUDテーブル+アクション実行画面であり、エンドユーザー（営業担当など）に見せる製品UIとしては流用不可、という当初仮説を裏付けた。 | 中 |

## API（AshJsonApi）

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F06 | JSON:API配線 | ルートをドメイン側ではなくリソース側の`json_api do type "..." routes do get/index/post/patch/delete end end`で定義する方式を選択（ドメインに書く方式より1箇所で完結し単純）。`ash_json_api_router.ex`の`domains: []`を`[Spike0Crm.Crm]`に変えるだけで、`mix phx.routes`に3リソース×5エンドポイント＝15ルートが即座に反映された（`/api/json/accounts`等）。コントローラーコードは1行も書いていない。 | 低 |

## Auth / Policy

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F07 | policy既定動作の非対称性 | `policy always() do authorize_if actor_present() end`だけでは、`create`/`update`/`destroy`はactor無しで`Ash.Error.Forbidden`を投げるが、`read`はエラーを投げずに**黒く空リストを返す**（`Ash.Policy.Authorizer`の`access_type`既定値が`:filter`のため）。これはテストで実際に失敗して発覚した（`Expected exception Ash.Error.Forbidden but nothing was raised`）。テストが「例外を検証する」だけだと気づかず、権限漏れのないアプリだと誤認しかねない。回避には各resourceの`policies`ブロックに`default_access_type :strict`を追加する必要があった。 | 高 |
| F08 | policy DSLのコスト | 最終的な記述は3行（`default_access_type :strict` + `policy always() do authorize_if actor_present() end`）で全アクションを保護できた。ただしF07のような既定動作の違いを知らないと「ログを書いたのに本番でCRUDだけ守られ一覧は空で返るだけ」という気づきにくいバグを埋め込む。 | 中 |

## Migration（ash.codegen の挙動、snapshotの形式）

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F09 | codegen品質 | `mix ash.codegen add_crm_resources`は1個のmigrationファイル（92行）と3個のsnapshot（`priv/resource_snapshots/repo/crm_accounts|crm_contacts|crm_deals/*.json`）を生成。FK制約は名前付き（`crm_contacts_account_id_fkey`等）で自動生成、`allow_nil? false`の属性は正しく`null: false`に変換、`down/0`はテーブル削除とFK制約の逆順dropまで自動で書かれていた。実行前に「破壊的操作を含む」という警告が出るが、内容は純粋な追加（`down`にdropがあるだけ）であり、警告文自体は定型文で毎回出る点は注意が必要。 | 低 |
| F10 | enumの実装 | `attribute :stage, :atom do constraints one_of: [...] end`は、DB上は素の`text`カラム（`default: "lead"`）として生成され、PostgresのネイティブENUM型やCHECK制約は一切生成されなかった。つまり`one_of`制約はAshアプリ経由のバリデーションのみで保証され、Ash層を経由しない直接SQL操作では不正な値を挿入できる。DBレベルでの整合性保証をKumiが必要とするなら、Ash側でのCHECK制約生成、または生成物へのpost-migration手動追加が必要。 | 中 |

## その他

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F11 | 再発明してはいけない部分 | (1) resource属性のconstraintsからmigrationのカラム型・NOT NULL・FK名までの自動導出は正確で速い。(2) `json_api`ブロックの数行からPhoenixルーティングまで一貫して繋がり、コントローラー層が消える。(3) `load: [:contacts, :deals]`のような関連ロードはhas_many/belongs_toどちら向きでも1行で書け、N+1を手で気にしなくてよい。(4) ポリシーDSLは書く分量自体は最小（3行）。これらはKumiが独自に再実装すべきではなく、そのまま使うべき層である。 | - |

---

## 検証チェックリスト（Blueprint v3 §10 F01–F07に対応）

- [x] F01 Resource作成は簡単か → 1ファイル59〜72行で属性/関連/アクション/ポリシー/API/Admin表示まで完結。DSL自体は軽量（本ログF01/F02）。
- [x] F02 複数Resourceを一つの完全な製品に組織する作業量 → ドメイン登録1行×3、config 1行だが、navigation/dashboard/画面遷移は完全にゼロから（本ログF04/F05）。
- [x] F03 AshAdminはsuper-admin的か、エンドユーザーが使えるか → README自身が"super-admin UI"と明記。生CRUDテーブルであり製品UIには使えない（本ログF03）。
- [x] F04 製品navigationは自前構築が必要か → Yes。Ashはnavigationという概念自体を持たない（本ログF04）。
- [x] F05 Dashboardに統一されたapplication definitionはあるか → No。`ash_domains`は起動時ロード対象のリストに過ぎない（本ログF05）。
- [ ] F06 Workflow / UI / Resourceは同一モデルに載るか → 本スパイクの範囲外（workflow機能を使っていないため未検証）。
- [ ] F07 AI変更後のapp-level safety planは存在するか → 本スパイクの範囲外（未検証）。

---

# Spike 1 — Desired/Actual抽出

> 目的：pg_catalog（Actual）× Ash Resource抽出（Desired）の差分を作り、
> 「Desired抽出はAshPostgresのResource introspection再利用で足りるか」を検証する
> （Blueprint v3 §10 Day 1）。実装は`spike0_crm`内`lib/kumi/`、`Kumi.*`名前空間。

## Desired抽出（Ash/AshPostgres introspectionの再利用範囲）

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F12 | Info関数だけで足りた範囲 | `Ash.Domain.Info.resources/1`・`Ash.Resource.Info.attributes/relationships/identities/primary_key/1`・`AshPostgres.DataLayer.Info.table/repo/1`の組み合わせだけで、テーブル名・カラム名・NULL可否・PK・identity一覧まで手で1行もパースせずに取れた。`belongs_to :account`が生成する外部キー属性（`account_id`）は`Ash.Resource.Info.attributes/1`の戻り値に最初から**通常の属性として**含まれており、「FK用に別枠で拾う」処理は不要だった。Desired抽出の8割程度はここに集約される。 | 低 |
| F13 | defaultは意味論が違うので文字列比較できない | `attribute.default`はAsh側では「関数」（例：`&Ash.UUID.generate/0`、`&DateTime.utc_now/0`）または生の値（`:lead`）だが、DB側の実際のdefault式（`gen_random_uuid()`、`(now() AT TIME ZONE 'utc'::text)`）はAshPostgresのmigration generatorが**別途決めた**SQL式であり、Ash側の関数と一対一で対応しない。テキスト同値比較をすると誤ってdrift扱いになる。`Kumi.Schema.Default`で「関数/DB生成式なら`:generated`、リテラル値なら`{:literal, ...}`、なければ`nil`」という3値に正規化し、生成式の中身までは比較しないことでクリーン状態の diff=[] を成立させた。Stage 2（data-aware）で式の意味まで比較するなら、ここは別途作り直しが要る。 | 高 |

## 型マッピング（AshPostgresの内部関数は公開・純粋だが、pg型名への変換は自作）

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F14 | `AshPostgres.MigrationGenerator.get_migration_type/2`が使えた | Ash型→Ecto migration型（`:uuid`, `:text`, `{:decimal, _, _}`, `:utc_datetime_usec`等）の変換は、AshPostgres自身がmigration生成に使っている関数`get_migration_type/2`が`def`（public）かつ副作用なしで、そのまま呼べた。ここを独自に再実装せずに済んだのは想定通りの「再利用できる」ケース。 | 低 |
| F15 | constraintsを丸ごと渡さないと精度情報が消える | `get_migration_type(Ash.Type.UtcDatetimeUsec, [])`（空constraints）は`:utc_datetime`を返し、`UtcDatetime`と区別できなくなる。実際のattributeが持つ`constraints`（`precision: :microsecond`等）を丸ごと渡してはじめて`:utc_datetime_usec`が返る。型だけ見て「constraintsは後で」と後回しにすると、usec/秒単位の型が黒く同一視されるバグを埋め込む——実際にこの実装中に一度踏んだ。 | 中 |
| F16 | Ecto migration型 → pg実型名の変換は自作（約15行） | `get_migration_type/2`が返すのはEcto migrationの型（DSLの型）であり、pg_catalogが返す実際の型名（`udt_name`）とは別物（例：`:map`→DB上は`jsonb`、`:utc_datetime`/`:utc_datetime_usec`→どちらもDB上は`timestamp`、`{:decimal, _, _}`→`numeric`）。この対応表はEctoの`Ecto.Adapters.Postgres.Connection.ecto_to_db/1`（private関数）をソースを読んで手で写す形になった（`Kumi.Desired.PgType`、約15行）。 | 中 |

## pg_catalog介入（FK/index命名規則、精度の扱い）

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F17 | FK制約名・identity index名の既定命名規則はInfo関数に出ていない | `AshPostgres.DataLayer.Info`には`foreign_key_names/1`・`identity_index_names/1`があるが、これらは**上書き設定を取得するだけ**で、上書きしていない場合の既定命名規則（`"#{table}_#{attribute}_fkey"`、`"#{table}_#{identity.name}_index"`）はどこにも公開関数として出ていない。`ash_postgres`の`migration_generator.ex`のソースを読んで既定値の組み立て式を探し出す必要があった。Desired側でこの規則通りに名前を組み立てないと、実DBのFK制約名・unique index名と一致せず、クリーン状態でも`add_fk`/`remove_fk`の偽陽性が出る。 | 高 |
| F18 | timestamp精度は意図的に追跡していない（既知の限界） | `tokens.expires_at`（`:utc_datetime`、精度0）と`inserted_at`/`updated_at`（`:utc_datetime_usec`、精度6）は、pg_catalogの`udt_name`ではどちらも`"timestamp"`で区別できない（`information_schema.columns.datetime_precision`を見れば区別できるが今回は未使用）。今回の型比較は`udt_name`のみで行っており、精度違いの`type change`はSpike 1では検出できない。Stage 2以降で`datetime_precision`列を追加すれば拾えるようになる、という前提を明示しておく。 | 中 |

## 検証結果

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F19 | Go/No-Go判定 | マイグレーション済みの`spike0_crm_dev`に対し`Kumi.Diff.diff(Kumi.Desired.extract(), Kumi.Actual.introspect())`が`[]`になることを確認（テスト`Kumi.DiffCleanStateTest`）。さらに`ALTER TABLE crm_accounts ADD COLUMN legacy_phone text`をsandboxトランザクション内で実行し、`remove_column`（DB内・コード外＝drift）として正しく検出されることも確認した（`Kumi.ActualDriftTest`）。`mix ash.codegen`が見えない手動drift をKumiが見えることを実機で示せたため、Spike 1は**GO**。 | - |

---

# Spike 2+3 — Rename / Safety

> 目的：5つの典型的なdiffケース（列追加・列削除・NOT NULL化・型変更・rename）を検証し、
> 「snapshotは歴史的ヒントとして使えるか」（rename検知）と
> 「安全性分類は1本の一貫した規則で説明できるか」を検証する（Blueprint v3 §10 Day 2–3）。
> 実装は`Kumi.Plan.Rename`・`Kumi.Plan.Safety`・`Kumi.Plan`・`Kumi.Plan.Format`。

## Spike 2 — Rename検知（snapshot = 歴史的ヒントモデルの検証）

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F20 | snapshot JSONのフォーマット品質 | `priv/resource_snapshots/repo/<table>/<timestamp>.json`は`mix ash.codegen`が書き出す内部フォーマットで、公式スキーマドキュメントは見当たらなかった（ソースコードから逆算する必要があった）。ただし実際に読んだ範囲（`attributes[].source`＝カラム名、`attributes[].type`＝Ash型、`table`＝テーブル名、`hash`）は素直な構造で、パースは`Jason.decode!/1`と`Map.get/2`だけで完結した。ファイル名がタイムスタンプ（`20260826021129.json`のような形式）である点も、ソート可能で「新しいものほど大きい文字列」という素朴な期待通りに機能する。**構造は安定しているが「AshPostgres内部実装の詳細」であり後方互換の保証はどこにも書かれていないため、これに依存するコードはAshPostgresのバージョンアップで壊れる前提を持つべき**——今回はこの1点のみが不安要素。 | 中 |
| F21 | rename検知ヒューリスティックの信頼性 | 「同テーブル・同型のremove_column+add_columnペアで、旧名がsnapshot履歴にあり新名がどのsnapshotにも出てこない」という条件は、今回作った`full_name`/`name`のシナリオ（`Kumi.Plan.RenameTest`）では正しく`possible_rename`に昇格した。一方で、この判定は**構造的（列名の集合演算）**であり、意味を全く見ていない——たまたま同型・同テーブルで「削除された無関係な列」と「追加された無関係な列」が揃うと、誤ってrename候補にされるリスクが原理的に残る（今回のCRMのように列数が少ないうちは低リスクだが、列が多いテーブルでは要注意）。曖昧な場合（同型候補が複数）は昇格させない、という「疑わしきは何もしない」方針にしたことで、少なくとも**過検知（false positive）より過少検知（false negative）に倒す**設計にはできた。あくまでrenameは人間が確認すべき「ヒント」であり、事実（fact）ではないという位置づけを`possible_rename`という名前自体と、Safetyでの分類（REVIEW固定）の両方で表現した。 | 中 |
| F22 | greedyマッチングの既知の限界 | 1つのremove_columnに対し同型のadd_column候補が複数あれば「昇格しない」で正しく処理できるが、逆に「2つのremoveが、消費前は両方とも同じ1つのaddだけを候補として持つ」ケースでは、リストの先頭から順に貪欲にマッチさせるため、2番目のremoveは必ず候補を失って昇格しないという副作用がある（`Kumi.Plan.Rename`のmoduledocに明記）。今回のCRM規模（1テーブルあたり数列）では実害が出るケースを作れなかったため、Spike 2の範囲では「既知の限界として記録し、深追いしない」判断をした。 | 低 |

## Spike 3 — 安全性分類

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F23 | 「1本の一貫した規則」に落とし込む際の衝突 | タスク仕様には「`remove_column`はdrift由来ならREVIEW、実際のDROPはDANGEROUS」という2段階の書き方があったが、これは`Kumi.Diff`が生成する`remove_column`という1種類のopに対して2つの安全度を要求しており、そのままでは矛盾する。**「データを削除する提案はすべてDANGEROUS」という1本の規則に統一し、rename候補として拾われなかった`remove_column`は例外なくDANGEROUSとする**ことで解消した——rename昇格が先に走る前提（`Kumi.Plan.Rename.detect/1`を`Safety.classify/1`より先に呼ぶ）がこの規則の成立条件になっている点は、`Kumi.Plan.Safety`のmoduledocに明記した。 | 中 |
| F24 | 型変更の互換表はどこまで書くべきか | 「wideningはREVIEW、それ以外はDANGEROUS」という規則自体はシンプルだが、widening pairのリスト（`varchar→text`, `int2→int4`, `int4→int8`, `float4→float8`）は網羅的な検証をしておらず、Kumi独自の判断で組んだ小さな対照表にすぎない。未知の型ペアはデフォルトDANGEROUS（fail closed）にしたので、判断を誤って安全側に倒すリスクは低いが、逆に「本来REVIEWで済むはずの型変更」を過剰にDANGEROUS扱いしてしまう偽陽性は普通に起こりうる——widening表を運用で育てていく前提の設計である。 | 中 |
| F25 | 検証結果 | `mix kumi.plan --verbose`を実DB（`spike0_crm_dev`、ローカルdocker `kumi_db`）に対して実行し、一時的に(1) `crm_accounts`にAshコード側で`notes`（nullable）属性を追加（未migrate）、(2) `industry`属性を`allow_nil? false`に変更（未migrate）、(3) DBに直接`legacy_notes`列を追加、という3つの改変を同時に行ったところ、`1 safe / 1 review / 1 dangerous`が1回のdiffで出力され、SAFE（列追加）・REVIEW（NOT NULL化）・DANGEROUS（drift列のDROP）の3段階が同時に確認できた。`mix kumi.plan --check`の終了コードもこの状態で`1`になることを確認済み。検証後、コード変更とDB変更はすべて元に戻した。 | - |

---

# v0.1抽出 — spike0_crmからスタンドアロンパッケージへ

> 目的：`spike0_crm/lib/kumi/`にあるプロトタイプを`/Users/akimitu/Documents/Kumi/kumi/`という
> 独立したmixパッケージに切り出し、`mix kumi.plan`が任意の既存Ashアプリにインストールできる状態にする
> （Blueprint v3 §7 wedge、§9 roadmap）。

## Spike0Crm依存の実際の深さ

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F26 | 汎用化が必要だった箇所は実質2箇所だけ | `Kumi.Diff`・`Kumi.Plan`・`Kumi.Plan.Safety`・`Kumi.Plan.Format`・`Kumi.Plan.Rename`・`Kumi.Schema.*`・`Kumi.Desired.PgType`はSpike 1〜3の時点ですでに「引数を受け取って値を返すだけ」の純粋な形で書かれており、`Spike0Crm`名前空間への参照が最初から一切なかった。Spike0Crm固有の仮定が残っていたのは`Kumi.Actual.introspect(repo \\ Spike0Crm.Repo)`のデフォルト引数と、`Kumi.Desired.extract(domains \\ Application.get_env(:spike0_crm, :ash_domains, []))`のデフォルト引数の2箇所のみで、どちらも`\\ ...`を消すだけで済んだ。「引数を明示的に取る」という設計をSpike立ち上げ時点から徹底していたことが、切り出しコストをほぼゼロにした——後から汎用化するより、最初から`Application.get_env`を呼ぶのをmix taskの層だけに限定しておく方が安い、という確認が取れた。 | 低 |
| F27 | 便利層（mix task）と純粋層（`Kumi.plan/3`）の境界を新たに引く必要があった | プロトタイプには`Kumi.plan/3`のようなトップレベルAPIがなく、`mix kumi.plan`タスク自身が`Kumi.Desired.extract()` → `Kumi.Diff.diff(...)` → `Kumi.Plan.Rename.detect(...)` → `Kumi.Plan.build(...)`を直接呼んでいた。パッケージ化にあたり、この4行を`Kumi.plan(repo, domains, opts \\ [])`という明示引数のAPIとして`lib/kumi.ex`に新設し、mix task側は「ホストアプリの`:ash_domains`設定を読み、`AshPostgres.DataLayer.Info.repo/1`でリポジトリを解決し、`Kumi.plan/3`を呼ぶ」という薄い変換層に書き直した。`Application.get_env`を呼ぶコードがmix taskの中だけに閉じたのはこの書き直しの結果であり、既存コードの移植だけでは自動的には達成されなかった。 | 中 |

## ash-extension流テストハーネスを立てるコスト

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F28 | 「アプリなしライブラリ」は素のASH機能に足りないものが2つある | 独立mixパッケージには`Application`ビヘイビア（supervisor）が存在しないため、(1) テスト用Repoは`test_helper.exs`で`Kumi.Test.Repo.start_link()`を手動で呼ばないと`Ecto.Adapters.SQL.Sandbox.mode/2`が「repoが起動していない」で落ちる。(2) `mix ash.codegen`はデフォルト（`MIX_ENV=dev`）で実行すると、テスト専用ドメイン（`test/support/`、`elixirc_paths(:test)`のみでコンパイル対象）が見えず「対象0件」で何も生成せず終わる——`MIX_ENV=test mix ash.codegen initial`と環境を明示するのが唯一の回避策で、エラーメッセージも出ないため気づきにくい罠だった。 | 中 |
| F29 | ポリシー（`Ash.Policy.Authorizer`）はテストハーネスから外す判断をした | Spike0Crmの実resourceは`authorizers: [Ash.Policy.Authorizer]`と`policies`ブロックを持つが、これをそのままテスト用resourceにコピーすると`picosat_elixir`（SATソルバー）への依存が発生する。パッケージのmix.exsは`ash`・`ash_postgres`・`jason`・`ecto_sql`・`postgrex`のみに固定する縛りがあるため、テスト用resource（`Kumi.Test.Account`・`Kumi.Test.Deal`）からは`authorizers`・`policies`・`json_api`を落とし、Kumiの対象範囲であるカラム/FK/index/identity導入だけに絞った。プロトタイプのresourceをそのまま複製できなかった、という点は「テストハーネスを立てる」作業の見えないコストの一つ。 | 中 |
| F30 | `ash-functions` Postgres拡張の警告 | `installed_extensions/0`を空`[]`にすると、コンパイル時に`AshPostgres: You have not installed the "ash-functions" extension`という警告が出る（atomics・`string_trim`・`||`/`&&`演算子が使えなくなる旨の警告）。テスト用resourceはこれらの機能を使わないため実害はないが、`mix compile --warnings-as-errors`をパッケージ自身のコードだけでなく依存全体に厳格適用するなら拾ってしまう警告だった。`use AshPostgres.Repo, warn_on_missing_ash_functions?: false`で明示的に黙らせる必要があった——ash-extensionを書く側は最小限のテストharnessでもこの選択を迫られる、という記録。 | 低 |

## F20カナリアの移植で失ったカバレッジ

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F31 | 「実resource→実diff→実snapshot」の全経路を独立パッケージでは再現できない | spike0_crmの`Kumi.Plan.RenameRealSnapshotsTest`は`Kumi.Desired.extract()`（実resourceの`crm_accounts`、`name`属性）を起点に、実際に`Kumi.Diff.diff/2`でoperationを生成してから`Rename.detect/2`に渡していた。パッケージには`crm_accounts`という実resourceが存在しないため、この起点を再現できず、パッケージ版では`{:remove_column, ...}`/`{:add_column, ...}`のoperationペアを手で組み立てて`Rename.detect/2`に直接渡す形に簡略化した。これにより検証範囲は「本物のAshPostgres snapshot JSONフォーマットを`load_history`が正しくパースできるか」に絞られ、「実resourceの属性抽出からdiff生成までが正しくrenameペアの形になるか」の経路はパッケージのテストではカバーされなくなった——ただしこの経路自体はspike0_crm側に**同名のまま統合テストとして残した**（`Application.fetch_env!(:spike0_crm, :ash_domains)`を明示引数化しただけ）ため、全体としては経路が失われたわけではなく、2つのテストが担当を分担する形になった。 | 中 |

## テスト数の会計

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F32 | 移動・残留・重複の内訳 | 切り出し前のspike0_crm全体は64テスト、うち`test/kumi/`配下が52・非kumi（web/crm resource等）が12。パッケージ側は53テスト全green（移植52＋新規1：新設した公開API `Kumi.plan/3` を直接叩くテストを`diff_clean_state_test.exs`に追加——移植元には`Kumi.plan/3`自体が存在しなかったため純粋な移植ではなく新規追加）。内訳は純粋48＋DB連携4をテストハーネスに適応＋`Kumi.plan/3`直接テスト1。spike0_crm側は`test/kumi/`から4つのDB連携テスト（clean-state・missing-column・drift・rename-real-snapshots）を明示引数化して**統合テストとして残し**、残り48は削除（パッケージに移動済みのため）。spike0_crm全体のテスト数は64→16（残留4＋非kumi12）に減ったが、消えたわけではなく48はパッケージ側に、4は両側に存在する形になった。件数の合計だけを見ると「64が16に減った」ように見えるため、変更点として明示しておく。 | - |

---

# v0.1.5 — Data-aware / Precision

> 目的：F18（timestamp精度の盲点）を解消し、`Kumi.Probe`でdata-aware safety probe（read-onlyクエリで
> N件のNULL/重複/データ喪失を報告するfinding）を追加する（Blueprint v3 §7 Stage 2、§3.4 opt-in原則）。
> 実装は`kumi`パッケージ本体（`Kumi.Actual`・`Kumi.Desired.PgType`・`Kumi.Diff`・`Kumi.Plan.Safety`・
> 新設`Kumi.Probe`・`Kumi.Plan.Finding`）。CRITICAL REGRESSION GATE（パッケージ／spike0_crm双方の
> clean-state diff=[]）は全工程を通じて維持した。

## F18解消 — timestamp精度

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F33 | `information_schema.columns.datetime_precision`は素直に取れたが、値の意味はEcto側のハードコードを読まないと分からなかった | `datetime_precision`列は非timestamp型では`NULL`、timestamp系では整数（0〜6）を返す——ここまでは仕様通り単純だった。しかし「Ash側の`:utc_datetime`/`:utc_datetime_usec`はDB上何precisionになるのか」はAsh/AshPostgres側のどこにも明記されておらず、`Ecto.Adapters.Postgres.Connection`のprivate関数`column_type_name/2`を読んで初めて分かった：`:utc_datetime`/`:naive_datetime`/`:time`は`timestamp(0)`に**ハードコード固定**（precisionオプション自体が存在しない）、`_usec`系は明示的な`precision:`オプションが渡らない限り無指定の`timestamp`型になり、Postgresのデフォルトprecisionである6が採用される。AshPostgresのmigration generatorはこの`precision:`オプションをdatetime系attributeに対して渡していないため、実質「_usecは常に6、非usecは常に0」という2値だけが実際に起こりうる。実DB（`spike0_crm_dev`）で`tokens.expires_at`（`:utc_datetime`）＝0、`users.confirmed_at`（`:utc_datetime_usec`）＝6、`timestamps()`マクロが生成する`inserted_at`/`updated_at`（既定で`:utc_datetime_usec`）＝6であることを実測して裏付けた。 | 中 |
| F34 | 精度の狭小化（narrowing）は「失敗する」という予断を実測で覆した | タスク仕様は「6→0への狭小化はDANGEROUS（truncateする？）、rounding して失敗しないと確認できればREVIEWに倒してよい」という条件付きの指示だった。`kumi_db`のdocker実DBで直接検証：`timestamp(6)`列に`12:00:00.123999`を入れて`ALTER COLUMN ... TYPE timestamp(0)`すると`12:00:00`（切り捨てではなく四捨五入で同じ秒に丸まる）、`12:00:00.900001`を入れると`12:00:01`（次の秒に繰り上がる四捨五入）になり、どちらもエラーなく成功した。truncateではなくroundingであり、失敗もしないことを実測で確認できたため、狭小化・拡大化どちらもREVIEW（DANGEROUSにしない）という1本の規則に統一した——DANGEROUSはあくまで「データが失われる/操作が失敗する」ケース用に予約する、というSafetyモジュールの既存方針（F23参照）と整合させた判断。 | 中 |
| F35 | `Ash.Type.NaiveDatetimeUsec`は存在しない——`utc_datetime`系と非対称 | `:utc_datetime`/`:utc_datetime_usec`はAsh側で別々の型モジュール（`Ash.Type.UtcDatetime`/`Ash.Type.UtcDatetimeUsec`、`Ash.Type.NewType`のconstraints違いのラッパー）として実装されているが、`Ash.Type.NaiveDatetime`にはusecバリアントの型モジュールが存在せず、`storage_type/1`が常に`:naive_datetime`を返す（constraintsを見ない）。したがってAshPostgresの`migration_type/2`もconstraints次第で`:naive_datetime_usec`を返す経路を持たない——`Kumi.Desired.PgType`（既存コード）にあった`to_pg_name(:naive_datetime_usec)`ケースは現行Ashバージョンでは到達不能なデッドコードだった（今回追加した`precision_from_ash/2`も対称性のため同じ枝を残したが、同じ理由で到達不能）。テストでは実際に呼べる`Ash.Type.NaiveDatetimeUsec`が存在しないため、そのケースのテストは書かずに諦めた。 | 低 |

## `Kumi.Probe` — read-only SQL識別子クオートのコスト

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F36 | 識別子クオート自体は1関数（3行）で済んだが、「どこに要るか」の洗い出しが本体だった | `quote_ident/1`（`"` + `String.replace(name, "\"", "\"\"")` + `"`）という実装自体は3行で終わったが、Kumiのpg_catalog/Ash由来の名前（テーブル名・カラム名・identityの列リスト）は「信頼できるが空白や予約語を含みうる」——実際にテストで`"Probe Order"`テーブル・`"Group"`列（予約語）を使い、クオートなしでは構文エラーになることを確認した。5種類の probe SQL（NULL count・重複count・data-loss count・drop_table count・type change count）すべてで個別に組み立てず、`quote_ident/1`を1箇所に集約して全SQL生成が経由する形にした——モジュールごとに散らばらせていたら、いずれか1つで生クオート忘れが起きるリスクがあった。 | 低 |
| F37 | UNIQUE制約とNULLの扱いの違いをGROUP BYクエリに反映する必要があった | 重複グループ数の検出を素朴に`GROUP BY col HAVING count(*) > 1`だけで書くと、複数のNULL行が「NULL同士の重複グループ」として誤ってカウントされる。しかしPostgresのUNIQUE制約はNULLを「区別可能な値」として扱い、NULL同士は重複とみなさない（複数NULL行があってもUNIQUE制約には抵触しない）。実際に検証用テストで`(a, a, b, b, b, c, NULL, NULL)`という値を入れ、`WHERE col IS NOT NULL`を`GROUP BY`の前に挟まないと期待の2件（aのペア・bの3件グループ）ではなく3件（NULLペアも含む）を返すことを確認し、`not_null_clause`を全indexed columnに対して`AND`で連結する形で対処した。 | 中 |
| F38 | probeクエリのパフォーマンス上限は今回未対応・既知の天井として明記 | 全probe（NULL count・重複count・data-loss count・drop_table count・type change count）は`count(*)`（または`GROUP BY ... HAVING`の上に`count(*)`）で、`LIMIT`もサンプリングも一切していない。数百万行規模のテーブルに対しては単純なsequential scanコストが乗る——今回は意図的にサンプリングを実装せず、`Kumi.Probe`のmoduledocに「既知の天井」として明記するだけに留めた（`--probe`自体がopt-inなので、大規模テーブルを持つ利用者は明示的に選んで実行することになる、という設計上の逃げ道はある）。 | 低（対応せず） |

## 検証結果

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F39 | Go/No-Go判定 | パッケージ側73テスト全green（既存53＋新規20：精度関連8＝`pg_type_test.exs`4＋`safety_test.exs`2＋`precision_drift_test.exs`2、probe関連11＝`probe_test.exs`、findings表示1＝`format_test.exs`）。spike0_crm側16テスト全green、`mix kumi.plan`は変更後も`No changes. Database matches application definition.`のまま（CRITICAL REGRESSION GATE維持）。`spike0_crm_dev`に`ALTER TABLE crm_accounts ADD COLUMN legacy_notes text`を一時的に投入して`mix kumi.plan --probe`を実行し、`DANGEROUS`分類の`remove_column`の下に`finding: 0 rows contain data that would be lost`が正しくインデントされて表示されることを確認、検証後は`DROP COLUMN`で元に戻し、`mix kumi.plan`が再び`No changes.`に戻ることも確認した。 | - |

---

# v0.2 — Kumi.App DSL

> 目的：Kumi v0.2マイルストーンの最初の一枚、application-level DSL `Kumi.App`
> （Blueprint v3 §3「二層のDSL所有権」、§3.1の`app :sales do ... end`例）を実装する。
> Ash自体が使っているSpark 2.xを直接dependencyに追加して`use Spark.Dsl`で書き、
> Info module・verifierによる「explainable magic」（宣言した内容が必ず読み戻せる）
> を成立させ、`Kumi.plan_app/2`でwedge（`Kumi.plan/3`）と接続する。

## Sparkがタダでくれたもの

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F40 | section/entity宣言だけでパーサ・バリデータ・マクロ展開が全部ついてきた | `Kumi.App.Dsl`は`%Spark.Dsl.Section{}`5個（`app`・`resources`・`admin`・`workflows`・`dashboards`）と`%Spark.Dsl.Entity{}`4個（`resource`・`workflow`・`dashboard`・`metric`）の宣言（データ）だけで、`app do name :crm end`のようなブロック構文・`resource Foo`のような引数構文・ネストしたentity（`dashboard`の中の`metric`）が全部動いた。手書きしたのは構造体定義とverifier 5個のみで、パーサやマクロ展開のコードは1行も書いていない——AshのDomain DSL（`deps/ash/lib/ash/domain/dsl.ex`）をほぼそのまま踏襲する形で書けたのが大きい。 | 低 |
| F41 | `top_level?: true`一つで「ラップ不要の繰り返しentity」が実現できた | Blueprintの例は`workflow :sales_pipeline do ... end`と`dashboard :overview do ... end`が`app`モジュール直下に（`workflows do ... end`のようなラップなしで）複数回書ける形を要求していた。Spark標準は「sectionは`section_name do ... end`で包む」がデフォルトだが、`%Spark.Dsl.Section{top_level?: true}`を立てるだけでその制約が外れ、section名（`:workflows`）と中のentity名（`:workflow`）を別にしておけば、Info側は`workflows/1`のまま、DSL表記は`workflow :x do ... end`のまま、両方が両立した。 | 低 |
| F42 | Verifier / Info moduleの「型」がそのまま設計の型になった | `Spark.Dsl.Verifier`は`verify(dsl_state) :: :ok \| {:error, term} \| {:warn, ...}`という契約だけを課してくる——`Ash.Resource.Verifiers.NoReservedFieldNames`を読み写経する形で5個のverifier（resourceがAsh.Resourceか／navigationがresourcesの部分集合か／workflowのstagesが空でないか／dashboardのmetricsが空でないか／resource・workflow・dashboardの重複名）を1ファイル20〜35行で書けた。Info moduleも同様に、`Ash.Domain.Info`が`Spark.Dsl.Extension.get_entities/2`・`get_opt/3`を素で呼んでいるのを見て、`Spark.InfoGenerator`を使わず同じ書き方をした（理由はF44参照）。 | 低 |
| F43 | `Spark.Test`の`assert_dsl_error`/`refute_dsl_errors`で「コンパイルが落ちることをテストする」が素直に書けた | verifierのエラーは`@after_verify`フック内で発生し、通常の`assert_raise`では拾えない（Spark側はデフォルトでstderr警告に変換して握りつぶす）。`Spark.Test.assert_dsl_error(%Spark.Error.DslError{path: [...]}) do defmodule Elixir.Foo do ... end end`という形でdo-block内に「壊れたDSLモジュール」をその場でdefmoduleし、収集されたエラーをパターンマッチで検証する専用ハーネスが用意されていた——8個の異常系テスト（`app_verifiers_test.exs`）を自前の`try/rescue`やプロセス間通信なしで書けた。 | 低 |

## つまずいた点

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F44 | Info moduleの関数名をBlueprintの表面（`name/1`・`title/1`・`navigation/1`）に固定したかったため`Spark.InfoGenerator`を使わなかった | `Spark.InfoGenerator`はoption用の関数名をsectionパスから機械的に生成する（例：`app`section内の`name`optionは`app_name/1`、`admin`section内の`navigation`optionは`admin_navigation/1`になる）。タスク仕様が`Kumi.App.Info.name/1`・`title/1`・`navigation/1`という非プレフィックスの名前を明示していたため、InfoGeneratorの命名規則と衝突した。回避策は`Ash.Domain.Info`が実際にやっている書き方——`Spark.Dsl.Extension.get_opt/get_entities`を直接呼ぶ6行のInfo moduleを手書きする——を採用しただけで、実害はなかった（InfoGeneratorは「命名規則に従える場合」限定の時短ツールという理解に落ち着いた）。 | 低 |
| F45 | resourceが本物の`Ash.Resource`かどうかの正しい判定関数は`Spark.implements_behaviour?/2`ではなかった | タスク仕様のヒント通り最初`Spark.implements_behaviour?(module, Ash.Resource)`を使ったところ、`use Ash.Resource`した実resource（`Kumi.Test.Account`）に対してすら`false`が返り、happy-pathのテストが誤って落ちた。`Ash.Resource`は古典的な`@behaviour`ではなく`Spark.Dsl`拡張として実装されており、正しい判定は`Ash.Resource.Info.resource?/1`（内部は`Spark.Dsl.is?/2`）だった——Ash自身のソース（`ash/lib/ash/resource/info.ex`）を読んで気づいた。verifierを直すだけで済み、テストが「間違った判定基準で誤検知していた」ことをすぐ検出できたのは収穫だった。 | 中 |
| F46 | Entity構造体に`__spark_metadata__`フィールドが要ることを警告駆動で知った | `%Spark.Dsl.Entity{target: MyStruct}`の`MyStruct`が`__spark_metadata__`フィールドを持たないと、`mix compile --warnings-as-errors`が「Entity without __spark_metadata__ field is deprecated」で4entity分（`Resource`・`Workflow`・`Dashboard`・`Metric`）落ちた。ドキュメントを読む前にコンパイラ警告で気づけたため、`defstruct`に1フィールド足すだけで解決——Spark 2.7系での新しい規約（source annotation対応）であり、Ash本体の`deps/ash`側entityは既にこのフィールドを持っていた。 | 低 |

## 汎用パイプラインの再利用で新規コードを最小化できた箇所

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F47 | `plan_app/2`のスコープ規則は「両側を同じtable名集合でフィルタする」1行で表現できた | `Kumi.plan_app/2`は`Kumi.plan/3`の中身（`Desired.extract` → `Diff.diff` → `Rename.detect` → `Plan.build`）を一切変更せず、`AshPostgres.DataLayer.Info.table/1`から作った宣言済resourceのtable名集合で、DESIRED側・ACTUAL側の両方を`Enum.filter`で絞ってから同じパイプラインに渡すだけで実装できた。「appが宣言していないresourceのtableは、DESIREDに出てこない（＝dropとして検出される）せいでdrift扱いになる」という罠を、ACTUAL側も同じ集合で絞ることで対称的に潰した——`spike0_crm`側で`Spike0Crm.App`が`Spike0Crm.Crm`のみ宣言し`Spike0Crm.Accounts`（users/tokensテーブル）を宣言しない状態で`plan_app_test.exs`を実測し、`plan.entries == []`（driftなし）を確認して裏付けた。 | 低 |

## 率直な評価：app-level DSLは「実質価値」か「儀式」か

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F48 | 現時点（v0.2スライス1枚目）では「読み戻せる宣言的データ」以上の価値はまだ実証されていない | 今回実装した`Kumi.App`は、navigation・workflow・dashboardを構造化データとして宣言し、Info moduleで100%読み戻せる（`mix kumi.plan --app`もこのデータから repo/domain を導出する）ところまでは動いた——これ自体はBlueprint §3の「explainable magic」を満たしている。しかし現状これらのデータを**消費する側**（Admin UI生成・workflow実行エンジン・dashboard集計）はまだ存在しないため、「宣言した」以上のことはまだ何もしていない。「二層のDSL所有権」という設計判断（Ash DSLを換皮しない）自体は`resources do resource Foo end`のように実resourceモジュールをそのまま指すだけで一切重複がなく筋が良いと感じたが、価値が実証されるのは§4の優先順位2（Payload級Product DX）・3（Admin UI生成）がこのデータを実際に使い始めてから、というのが率直な現在地。 | - |

---

# v0.2 — Kumi.Resource shorthand / kumi.expand

> 目的：Blueprint v3 §3.2「Shorthand（入門モード）」・§0 D1「Show Ash」を実装する。
> `use Kumi.Resource` + `fields do ... end`が本物のAsh Resourceへコンパイルされ、
> `mix kumi.expand`がその展開結果をそのまま印字することを保証する
> （両者が同じ純粋関数`Kumi.Resource.Codegen.generate/3`から生成される、という一点鎖で担保）。

## 設計の分岐点：standalone-moduleフォームを採用（inline-in-appフォームは見送り）

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F49 | Blueprintの`resource Customer do ... end`（`Kumi.App`本体にネストして書く）フォームは今回実装していない | タスク仕様が最初から明示していた通り、今回実装したのは`defmodule MyApp.Customer do use Kumi.Resource, domain: ..., repo: ..., table: ... fields do ... end end`という**standalone-moduleフォーム**のみ。Blueprintの例（`app`ブロックの中に`resource Customer do field :name, :string end`と書く形）は、`Kumi.App`（Sparkの`%Spark.Dsl.Entity{}`ベース）の枠組みの中にAsh Resourceの動的コンパイルという別種の仕組みをネストさせる必要があり、Spark entityの引数パース（`resource Customer do ... end`のブロックをKumi.App.Dslのentityとして受け取りつつ、その中身をAsh Resourceソースへ変換して**別モジュール**として動的生成する）は今回のスコープでは着手しなかった——「決めた設計を実装する、再設計しない」という制約の下、まずstandalone-moduleフォーム一枚を「Show Ash」の骨格として固めることを優先した。inline-in-appフォームが要るなら、Kumi.App.Dslのentity機構とKumi.Resource.Codegenを接続する追加レイヤーが要る、という宿題として残る。 | - |

## macro実装のつまずき：`@before_compile`ネストは「見た目動くが危険」

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F50 | 最初の実装（`use Ash.Resource`を含む生成ソース全体を自前の`@before_compile`から一括注入）は、単体では正しくコンパイルされるのに、他モジュールから参照されると偽陽性エラーを出した | 最初のアプローチは「`fields do ... end`で集めたフィールド仕様を`@before_compile Kumi.Resource`まで貯めておき、そこで`use Ash.Resource, ...`を含む生成ソース全体を一括で`Code.string_to_quoted!`→spliceする」というものだった。単体で`mix run -e`から`Ash.Resource.Info.resource?/1`を呼ぶと`true`が返り、一見正しく動いているように見えた。しかし`mix compile --warnings-as-errors`をパッケージ全体に対して実行すると、このshorthand resourceを`belongs_to`で参照する別モジュールや、`resources do resource ... end`で列挙するAsh Domainが、`Exception while verifying ...: ArgumentError: ... is not a Spark DSL module`という警告付きで失敗した（`Module.ParallelChecker`が実行する`__verify_spark_dsl__/1`という、Ash自身が生成するクロスモジュール検証フック内）。原因は「`use Ash.Resource`を自前の`@before_compile`から遅延実行すると、素朴なhand-writtenリソースと違って、そのモジュールが『Ash Resourceとして認識される』タイミングが極端に遅くなり、他モジュールの検証フックとの間に競合が起きる」ことだった——最終コンパイル成果物としては正しい（`Ash.Resource.Info.resource?`は最終的に`true`）が、コンパイル**過程**の形が違うだけで、`--warnings-as-errors`環境では実害のあるエラーになる、という「動いているように見えて実は壊れやすい」実装だった。 | 高 |
| F51 | 解決：`use Ash.Resource`は`__using__`で即時実行し、`fields do ... end`が集めたフィールド仕様だけをその場（`fields`マクロの呼び出し位置）でsplice——`@before_compile`には「fieldsブロックを書き忘れていないか」を確認するガードだけを残した | 修正版は、`domain:`だけを`__using__`から即座に`use Ash.Resource, domain: ..., data_layer: AshPostgres.DataLayer`として展開し（hand-writtenリソースと全く同じ位置・同じタイミング）、`postgres`/`actions`/`attributes`/`relationships`の4ブロックだけを`fields do ... end`マクロの展開結果としてその場に差し込む形にした。これにより「Ashリソースとして認識される瞬間」が通常のhand-writtenリソースと完全に同じタイミングになり、F50のクロスモジュール検証エラーは`mix compile --warnings-as-errors`をゼロから再実行しても再現しなくなった（Ecdo側の付随警告——`belongs_to`先を「Ectoスキーマではない」と誤検知する警告——も同時に消えたことから、根本原因が同一だったことを確認できた）。`fields do ... end`ブロックを書き忘れた場合に単に「空のAsh Resourceが黙って生成される」という劣化を防ぐため、`@before_compile Kumi.Resource`は残し、`fields`が一度も呼ばれなかった場合にのみ`CompileError`で落とす5行のガードとして再利用した。 | 中 |
| F52 | もう一段深い罠：モジュール属性は「後続の`@attr value`という**コード**として埋め込む」のと「マクロ展開中に`Module.put_attribute/3`を直接呼ぶ」のとで、同一モジュール内の**別マクロ**からの可視性が違う | F51の修正を実装する過程で、`use Kumi.Resource, opts`の`opts`（`domain:`/`repo:`/`table:`）を`fields do ... end`マクロから読み戻す必要が生じたが、素朴に`quote do @kumi_resource_opts unquote(opts) end`という形で埋め込むと、後続の`fields/1`マクロが**展開されている最中**（`Module.get_attribute/2`を直接呼ぶ場所）ではまだ`nil`しか読めない、という現象に遭遇した——同じ内容を`@before_compile`（モジュール末尾の確定タイミング）から読めば正しく取れることは既存コードで確認済みだったため、「モジュール属性は設定した瞬間から即座に読める」という前提そのものが崩れる場面がある、というのが新しい発見だった。5行の最小再現スクリプトで検証した結果、`Module.put_attribute(caller_module, :key, value)`をマクロの**Elixirコードとして**（quoteの外で、展開時に）直接呼び出せば、同一モジュール内の後続マクロ展開時点で`Module.get_attribute`が正しく値を返すことを確認し、この形に変更して解消した——「モジュール属性への書き込みが、生成されたコードとして後で評価されるのか、マクロ展開時点で即座に副作用として実行されるのかで、可視性のタイミングが変わる」という、Elixirマクロの合成（マクロがマクロを呼ぶ）に特有の罠だった。 | 高 |

## Shorthandが実際に何行節約するか（正直な集計）

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F53 | spike0_crmに追加した実例（`Spike0Crm.Crm.Note`）で、shorthandは10行、展開後のAsh Resourceは32行——約3.2倍の圧縮 | `fields do ... end`本体を含むshorthand側のコード行数（moduledocを除く、`use Kumi.Resource, ...`から`end`まで）は10行。`mix kumi.expand Spike0Crm.Crm.Note`が印字する展開後のAsh Resourceソース（`Code.format_string!`でフォーマット済み）は32行。ただしこの比較はNoteが「属性1つ＋belongs_to 1つ、policy/json_api/custom action一切なし」という最小構成だから成立する比率であり、Blueprintの`Customer`例（属性3つ＋belongs_to＋has_many）で同様の比率になるかは属性数に比例して両側とも伸びるため、「shorthandは概ねAsh定型部分（`uuid_primary_key`・`timestamps()`・`actions do defaults [...] end`・`postgres do ... end`のボイラープレート約12〜15行）をゼロにし、フィールド1個あたり1行で書ける」というのが実態に近い評価。既存のhand-writtenリソース（`Contact`、61行）との比較は`policies`/`json_api`ブロック分（約25行）が乗っているため対等な比較にならず、意図的に比較対象から外した。 | - |

## Sugarが漏れる場所

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F54 | `authorizers`/`policies`/`json_api`/カスタムaction/calculation/aggregateは一切表現できない——これは意図した設計（moduledocの「escape hatch」） | `Kumi.Resource`が生成するのは常に「`uuid_primary_key`＋timestamps＋public属性＋`actions do defaults [:read, :destroy, create: :*, update: :*] end`＋`postgres`＋`relationships`」の固定形のみで、Spike0Crmの実resource（`Account`/`Contact`/`Deal`）が持つ`authorizers: [Ash.Policy.Authorizer]`・`policies do ... end`・`extensions: [AshJsonApi.Resource]`・`json_api do ... end`は一切生成できない。これはタスク仕様が最初から明示していた設計（「calculations / aggregates / custom actions / 複雑なpolicyが必要になったら、Ashを直接書く」）であり、漏れというより意図的な線引きだが、実務上は「shorthandで書けるresourceは`policies`が要らない社内ツール的なものに限られる」ことを意味する——`Spike0Crm.Crm.Note`のCRUDテストで`actor:`を渡しているのは既存resourceとの見た目の一貫性のためであり、Noteの`create`は`authorizers`がないためactorなしでも実際には通る（他resourceとの対比で明示的に確認した）。 | - |
| F55 | `belongs_to`/`has_many`には`required:`や`destination_attribute:`などの調整オプションが存在せず、`allow_nil?`はAshのデフォルト（`true`）のまま——外部キーを必須にしたい場合はshorthandを出て手で書く必要がある | フィールドDSLの`field`には`required:`/`default:`があるが、`belongs_to`/`has_many`にはオプションを一切取らない設計にした（タスク仕様の例が`belongs_to :account, MyApp.Account`という素の形だったため）。結果として、FKを`allow_nil? false`にしたい（例えば`Kumi.Test.Resource.Deal`の`belongs_to :customer`を必須にしたいケース）場合、shorthandでは表現できず、そのフィールドだけhand-writtenへ逃げる必要がある——今回のテスト資源で唯一「FKをNOT NULLにしたい」需要があった`Deal.belongs_to :customer`は、意図的にhand-writtenリソース側（shorthandの対象外）に置くことでこの制約を回避した。 | 中 |
| F56 | `:text`は`:string`と全く同じAshコードを生成する——Ashに「長文用の別型」が存在しないため | Ash自体に`:string`と区別される「長文（text）」専用の型は存在しない（Ecto/Ashの型システムでは両方とも`:string`型で表現され、Postgres上のカラム型（`text` vs `varchar(n)`）は`constraints`の`max_length`有無で決まる）。そのためshorthandの`:text`は単に`:string`のsugarとして実装した——`field :body, :text`と`field :body, :string`は生成されるAshコードが1バイトも変わらない。これは「型名として直感的だから残した」だけで、Ash側に対応する意味論の差は存在しない、という点はmoduledocに明記した。 | 低 |

## `:email`セマンティック型は価値に見合うか

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F57 | 生成されるのは`:string`属性＋`constraints match: ~r/.../`の1行だけだが、「メールらしきものを弾く」という頻出要件をフィールド定義1行に圧縮できる点は実測でも確認できた | `field :email, :email`は`attribute :email, :string do public? true; constraints match: ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/ end`という4〜5行のAshコードに展開される。実DBに対する`Ash.create`テスト（`test/kumi/resource_semantic_types_test.exs`）で、`"not-an-email"`が`{:error, %Ash.Error.Invalid{}}`で弾かれ、`"jane@example.com"`が通ることを確認した。正規表現自体は「妥当だが網羅的ではない」単純なもの（RFC 5322準拠ではない）で、hand-writtenで書いても4〜5行程度の差にしかならないため、行数削減効果としては小さい。それでも「メールらしきものを検証する」という定型パターンを`:email`という1語で毎回思い出さずに済む、という点で、shorthandの型システムに載せる価値はある（`:select`の`one_of`も同様の理由）と評価した——ただし「セマンティック型」と呼ぶには正規表現1本のみで、Kumi.Storage（Blueprint §6）のような「upload UI/thumbnail/permissionまで繋がる」本物のpluginとは全く別の重みであることは明記しておく。 | 低 |

## 検証結果

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F58 | Go/No-Go判定 | パッケージ側は103テスト全green（既存83＋新規20：`resource_test.exs`14＋`resource_semantic_types_test.exs`6——後者は`:integer`/`:decimal`/`:boolean`/`:date`/`:datetime`のCodegen型マッピングを実DBなしで直接検証する2テストを追加した分を含む）、`mix compile --warnings-as-errors`もクリーン。既存83テストのうち6件（`diff_clean_state_test.exs`・`actual_drift_test.exs`・`precision_drift_test.exs`・`probe_test.exs`）は、新domain（`Kumi.Test.ResourceDomain`）のテーブルが同一のPostgres DB（`kumi_test`、既存`Kumi.Test.Domain`と同じrepo）に追加されたことで、DB全体を走査するテストの対象domainリストに新domainを加えないと誤ってdrift扱いされる状態になったため、該当4ファイルの`Kumi.Desired.extract`/`Kumi.plan`呼び出しに`Kumi.Test.ResourceDomain`を追記する形で修正した（`Kumi.Test.Domain`自体・`Kumi.Test.Account`/`Deal`は無改変）。spike0_crm側は20テスト全green（既存18＋新規2：`note_test.exs`）、`mix kumi.expand Spike0Crm.Crm.Note`の出力を確認、`mix ash.codegen add_notes`→`mix ecto.migrate`後に`mix kumi.plan`が`No changes. Database matches application definition.`に戻ることを確認した。Info moduleのテスト（`test/kumi/app_test.exs`）もNote追加後の`resources`/`navigation`リストに合わせて更新した。 | - |

---

# v0.3 — Kumi Admin shell slice 1

> 目的：Blueprint v3 §5「Kumi Admin — Product Shell」の最初の一枚。
> `Kumi.App`定義（`Kumi.App.Info.{name,title,resources,navigation,workflows,dashboards}`）を
> **消費するだけ**の新規パッケージ`kumi_admin`（read-only shell：sidebar/nav・resource一覧・detail・dashboard stub）を作り、
> Spike 0が記録したF03（AshAdminはsuper-admin専用）・F04（navigation概念なし）・F05（application定義がUIを駆動しない）
> の3つの摩擦が、`app`定義とKumi Adminの組み合わせで実際に消えるかを確認する。

## ルータマクロの実装コスト：`private:`は使えず、ash_admin流の`session:` MFAに落ち着いた

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F59 | ash_adminのroute `private:`オプションは静的（dead render）にしか効かず、`kumi_admin`が渡したいapp module／actor解決関数をLiveViewの`mount/3`に確実に届ける経路にはならなかった | `Phoenix.LiveView.Router`の`live/4`が持つ`:private`オプションは「`conn.private`に入る」ものであり（`phoenix_live_view/lib/phoenix_live_view/router.ex`のdocstringで確認）、`socket.private`に汎用データとして安定的に載る保証はない——最初の実装案（ash_adminがCSP nonce keyを`private:`で運んでいるのを見て真似た形）は、実際にはコンパイル確認までしか進めず採用を見送った。代わりに`ash_authentication_phoenix`（`ash_authentication_phoenix/lib/ash_authentication_phoenix/live_session.ex`）と`ash_admin`（`ash_admin/lib/ash_admin/router.ex`の`__session__/2`）が共通して使っている「`live_session`の`session:`オプションに`{Module, :function, args}`のMFAを渡し、関数内で`Plug.Conn.get_session/1`（Plugセッション全体）を取ってから独自キーを`Map.put`で足す」という形に合わせた。これにより`KumiAdmin.Router.__session__/4`が`kumi_admin_app`・`kumi_admin_path`・`kumi_admin_actor`の3キーを足しつつ、host側の`on_mount`フック（`ash_authentication_phoenix`の`user_token`読み取りなど）が必要とする既存のPlugセッションキーをすべて素通りさせられる——「独自データを運ぶ」と「hostの認証セッションを壊さない」が両立する形は、既存2パッケージのソースを読まずには見つけられなかった。 | 中 |
| F60 | `scope "/", HostWeb do ... end`（moduleエイリアス付き）の中で`kumi_admin/2`を呼ぶと、Phoenixのscopeエイリアス連結が`KumiAdmin.DashboardLive`のような**フル修飾**モジュール名にまで`HostWeb.`を前置してしまい、存在しないモジュール`Spike0CrmWeb.KumiAdmin.DashboardLive`への参照で`mix compile --warnings-as-errors`が落ちた | `ash_admin`の使用例が`scope "/" do`（エイリアスなし）で`ash_admin "/admin"`を呼ぶ形になっている理由がこの実装で初めて腑に落ちた——Phoenixの`live/get/post`系マクロは、渡されたモジュール名がすでに複数セグメントの完全修飾名であってもscopeのエイリアスを無条件に連結する（`Module.concat(alias, given)`相当）。`spike0_crm`側のrouter.exでは他のブロックが`scope "/", Spike0CrmWeb do`という形を使っていたため、最初そこに倣って`kumi_admin`呼び出しも同じブロックに入れてしまい、警告で気づいた。修正は`scope "/" do`（エイリアスなし）に切り出すだけで済んだが、「サードパーティのrouterマクロは常にエイリアスなしscopeに置く」という規約を明示的に書き残す価値があると判断した。 | 低 |

## Actor handoffの設計：KumiAdminは誰も認証しない、`socket.assigns`から読むだけ

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F61 | 採用した設計は「`kumi_admin/2`に渡した`on_mount:`フックが`socket.assigns`に何か（既定`:current_user`）を詰め、KumiAdminはそれを読むだけ」——`KumiAdmin.Actor.resolve/2`と`{Module, :function}`のオーバーライドで完結させた | `spike0_crm`側の配線は`on_mount: [{Spike0CrmWeb.LiveUserAuth, :current_user}]`の1行——このフックは既存コード（`live_user_auth.ex`）に元からあったもの（`AshAuthentication.Phoenix.LiveSession.assign_new_resources/2`を呼ぶだけ）で、KumiAdmin用に新規に書いた行は0。KumiAdmin側の既定値`{KumiAdmin.Actor, :from_current_user}`は`socket.assigns[:current_user]`を読むだけの1行関数。actorが`nil`のままでも例外にはならず、ポリシー保護されたリソースは`Ash.read`が`{:error, Forbidden}`を返すだけなので、それを`:forbidden`として拾って「No access or no records.」を描画する分岐に流すだけで済んだ——「認証はhostの責務、KumiAdminはactorの取り出し方だけを知っている」という線引きが、実装コード量としては非常に軽かった（`actor.ex`+`context.ex`で40行未満）。 | 低 |
| F62 | テスト側でこの設計の裏を取るために実際のsign-in経路を通す必要があり、`AshAuthentication.Checks.AshAuthenticationInteraction`という別のpolicy bypassの存在を知らずに最初のテストが全滅した | LiveViewTestで「ログイン済みユーザーとしてshellにアクセスする」を検証するには、`Spike0Crm.Accounts.User`の`register_with_password`アクションを直接`Ash.create!`で叩いて得たJWTを`Plug.Conn.put_session("user_token", token)`でconnに積む、という素朴な方法を最初に試したが、`Ash.Error.Forbidden`（`unknown actor` / 「No policy conditions applied」）で落ちた。原因は`User`リソースの`policies do bypass AshAuthentication.Checks.AshAuthenticationInteraction do ... end end`——このcheckは`changeset.context.private.ash_authentication?`が`true`の場合のみ通過するもので、`ash_authentication`パッケージ内部のコード経由（`AshAuthentication.Strategy.action/4`など）でしか自然には立たないフラグだった。`ash_authentication/lib/ash_authentication/checks/ash_authentication_interaction.ex`のソースを読み、`Ash.Changeset.for_create(:register_with_password, attrs, context: %{private: %{ash_authentication?: true}})`と明示的にcontextを渡すことで解消——「テストで認証済みユーザーを用意する」という一見単純な作業が、hostアプリ側のセキュリティ設計（bypassの存在理由）を理解しないと通らない、という発見だった。 | 中 |

## ページング：Ashの`page:`オプションは「宣言していないと使えない」——kumi coreに触れずQuery側のlimit/offsetに倒した

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F63 | タスク仕様が例示した`Ash.read(resource, page: [limit: 25, offset: N])`は、4つのCRM resourceのどれも`:read`アクションに`pagination ...`を宣言していないため、そのままでは`{:error, %Ash.Error.Invalid.PaginationRequired{}}`になる——`ash/lib/ash/actions/read/read.ex`で確認した | 素朴な回避策（Account/Contact/Dealの`:read`アクションに`pagination offset?: true`を足す）は不可能ではなかったが、4つ目の`Note`は`Kumi.Resource`（kumi core側のcodegen）が生成する固定形（`defaults [:read, :destroy, create: :*, update: :*]`）で、pagination付きの`read`を個別宣言する余地がない——kumi coreを触らない縛り（タスクのHard rules）の中でNoteだけ挙動が変わる非対称な実装は避けたかった。代わりに`Ash.Query.sort(:id) |> Ash.Query.limit(26) |> Ash.Query.offset(N)`（`page:`宣言を必要としない、任意のread actionで動くquery-level limit/offset）で26件（page_size+1）取得し、26件目が来たら「次がある」と判定して先頭25件だけ描画する、という形にした。4リソースとも無改変・kumi core無改変で「簡易next/prev」は成立したが、Ashが公式に提供する`Ash.Page.Offset`（`count`・`more?`をサーバ側で持つ構造体）は使っていない——正確な総件数は取得していない、という制約は`KumiAdmin.ResourceIndexLive`のmoduledocに明記した。 | 中 |

## `Ash.Resource.Info`はgeneric table描画にどこまで効くか

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F64 | 列選択・detail描画は`Ash.Resource.Info.public_attributes/1`・`public_relationships/1`だけで、host側の設定・アノテーション追加が一切不要だった | `KumiAdmin.Columns.for_resource/1`は`public_attributes/1`を先頭6件に切るだけの1関数、detailページの`belongs_to`検出も`public_relationships/1`を`type == :belongs_to`でfilterするだけで、Account/Contact/Deal/Noteの4リソースに対してKumiAdmin側に一切の個別設定なしで動いた——host側が変更したのはrouter.exへの5行の追加のみ。唯一「推測」が入ったのは関連レコードの表示ラベル（`relationship_display/1`：`Map.has_key?(related, :name)`があれば`name`、なければid）で、これはAshのメタデータからは導出できない「名前っぽい属性はどれか」という判断——今回のCRMでは`Account`・`Contact`とも`:name`属性を持つため偶然当たったが、`:name`が存在しないリソースでは常にidにfallbackする、という素朴な取り決めであることは明記が必要。 | 低 |

## 率直な評価：AshAdminとの違いはもう感じられるか

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F65 | 「navigationがapp定義から出る」「actorなし／forbiddenでもクラッシュせず正直な状態を描く」の2点はF04・F03への具体的な回答になったが、「開けばもう製品」（Blueprint §5）にはまだ遠い | AshAdminとの体感差として今回実測できたのは：(1) サイドバーのリンク・ラベルが`Spike0Crm.App`の`admin do navigation [...] end`から100%生成され、host側にnav用のLiveViewコードが1行もない（F04への回答）、(2) actorなし／policy forbiddenのケースで例外画面ではなく「No access or no records.」という文言を描画する（AshAdminはsuper-admin用途である以上、この種の「エンドユーザーが権限を持たない」状態を一級の状態として扱う理由がない——F03への回答）。一方で、slice 1は意図的にread-onlyであり、フォーム・検索・saved views・通知・権限UI・テーマ（Blueprint §5の枠組み）はゼロ、ページングも件数不明の簡易next/prevに留まる（F63）。「Ashの素のCRUD画面ではなくKumiのapp定義が実際に効いている」ことは確認できたが、「顧客が毎日働けるUI」の体感には、フォーム（slice 2予定）が入るまでは到達しないというのが率直な現在地——AshAdminとの機能面の差は今回まだ「劣化版」に近く、差別化点は今のところ「navigationとforbidden状態の描き方」の2点に限られる。 | - |

## 検証結果

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F66 | Go/No-Go判定 | 新規`kumi_admin`パッケージは13テスト全green（`slug_test.exs`3・`label_test.exs`4・`columns_test.exs`2・`format_test.exs`4）、`mix compile --warnings-as-errors`クリーン（upstream依存の警告を除く）。`kumi`コアパッケージは無改変・103テスト全green。`spike0_crm`側は25テスト全green（既存20＋新規5：`kumi_admin_live_test.exs`——sidebar/nav描画・actor付きaccount一覧・actorなしでの`No access or no records.`描画・detail画面の属性描画・dashboard画面のmetric名描画）、`mix compile --warnings-as-errors`もクリーン。`mix phx.routes \| grep kumi-admin`で`/kumi-admin`（dashboard）・`/kumi-admin/:resource`（index）・`/kumi-admin/:resource/:id`（show）の3ルートがマウント済みであることを確認した。 | - |
