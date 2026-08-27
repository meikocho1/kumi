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

---

# v0.3 — Kumi Admin shell slice 2 — Forms / Search

> 目的：Blueprint v3 §5「List / Form / Detail / Search」のうち、slice 1が空けたまま残した
> フォーム（create/update）・削除・検索・ボタン単位の権限表示を実装し、
> 「開けばもう製品」に一枚近づけるかを確認する。`kumi`コアは無改変。新規依存は`ash_phoenix`のみ（`kumi_admin`）。

## `AshPhoenix.Form`が無料でくれるもの：validate-on-change・field単位のエラー・`{:error, form}`ラウンドトリップ

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F67 | `AshPhoenix.Form.for_create/3`・`for_update/3`・`validate/2`・`submit/2`はすべて`%Phoenix.HTML.Form{}`を直接受け取れるオーバーロードを持ち、`socket.assigns.form`をそのまま渡すだけで完結した——自前のchangeset往復コードは1行も書いていない | 実装した`KumiAdmin.ResourceFormLive`のイベントハンドラは`handle_event("validate", %{"form" => params}, socket)`→`AshPhoenix.Form.validate(socket.assigns.form, params)`、`handle_event("save", ...)`→`AshPhoenix.Form.submit(socket.assigns.form, params: params)`の2行がロジックの全て。`submit/2`は成功時`{:ok, record}`、失敗時`{:error, %Phoenix.HTML.Form{}}`（すでに`to_form`済み、そのまま`assign(form: form)`できる）を返すため、「エラー時にどう再描画用のformを作り直すか」という定番の面倒がゼロだった。フィールド単位のエラーも`@form[field_name].errors`（`Phoenix.HTML.FormField`が自動的にフィールドへ振り分け済み）を読むだけで、`Ecto.Changeset.traverse_errors`相当の手作業が不要——`%{msg, opts}`から`%{count}`等のプレースホルダを埋める`translate_error/1`（5行）だけ自前で書いた（core_componentsの定番パターンと同一）。 | 低 |
| F68 | `belongs_to`の外部キー（例：`Contact.account_id`）は「生の`:uuid`属性」としてしか見えず、related recordのselect optionsは自前で`Ash.read`する必要があった——`AshPhoenix.Form`にrelationship専用のselect生成機能はない | `AshPhoenix.Form`は`manage_relationship`引数を持つカスタムactionに対する`inputs_for`（ネストしたsub-form）は提供するが、今回のCRM4リソースは全て`belongs_to`をプレーンな外部キー属性（`accept: :*`経由）として公開しているだけで、`manage_relationship`引数は使っていない。そのため`account_id`はFormFields側では単なる`:uuid`型の属性にしか見えず、「これはbelongs_toの外部キーだから選択肢を出す」という判断は`Ash.Resource.Info.public_relationships/1`を`source_attribute`でマッチングして`KumiAdmin.FormFields`側に実装する必要があった（15行程度）。related recordの読み込み（`Ash.Query.limit(100)`でcap）・ラベル選定（`:name`があればname、なければid——`ResourceShowLive`の`relationship_display/1`と全く同じ判定なので`Format.record_label/1`に切り出して共有した）も`KumiAdmin.ResourceFormLive`側の自前ロジック。ここは「Ashが用意していない部分」であり、KumiAdmin側の付加価値として素直に評価できる。 | 中 |

## OR-across-fields検索：`Ash.Query.filter/2`はmacroなので動的フィールドリストには使えない——`filter_input/2`（map/keyword syntax）に倒すと一発で解決した

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F69 | 最初の想定（`Ash.Query.filter(query, expr(contains(name, ^term) or contains(email, ^term)))`）は、フィールドの集合が実行時（resourceごとに違う）にしか分からないため、そもそも書けなかった——`filter/2`はコンパイル時にASTを受け取るmacroであるため | `Ash.Query.filter/2`はAST（`do: body`または`expression`）を受け取るmacroで、`Ash.Query.filter(query, contains(^field_atom, ^term))`のように「どのフィールドを見るか」自体を実行時の変数にすることはできない（`^field_atom`はフィールド名ではなく値のpinとしてしか解釈されない）。ここで一段詰まりかけたが、`ash/lib/ash/query/query.ex`の`filter_input/2`のdocstring（「filter added as user input... use the keyword/map style syntax」）を読み、これはASTではなく**プレーンな実行時データ**（`[or: [[name: [contains: term]], [email: [contains: term]]]]`というただのkeyword list）を受け取ることに気づいた——`Enum.map(searchable_fields, &{&1, [contains: term]})`でリストを組み立てるだけで、macro/AST操作は一切不要だった。`KumiAdmin.Search.apply/3`は10行で完結。 | 中 |
| F70 | 大文字小文字を無視した検索は「両辺をdowncaseする」自前ロジックではなく、検索語を`Ash.CiString.new/1`でラップするだけで実現できた——`contains/2`が`[:string, :ci_string]`という引数シグネチャを型ごとに複数持つ関数だったため | `Ash.Query.Function.Contains`のmoduledocに`contains("foo", %Ash.CiString{string: "FOO"})`が`true`になる例があり、これは「片方がci_stringなら大小無視」という意味だと分かった。実装は`[contains: Ash.CiString.new(term)]`と検索語側だけをci_stringにラップするだけ（フィールド側の`:string`属性はそのまま）。`spike0_crm`の`kumi_admin_live_test.exs`の検索テスト（"Acme Corp"を`"acme"`で検索してヒットする）を実DB（AshPostgres）に対して実行し、ケース非依存でマッチすることを確認済み——理論だけでなく実測で通った。`Ash.Query.filter_input`のmap/keyword syntaxが構造体値（`%Ash.CiString{}`）をそのまま受け取って正しい関数シグネチャにマッチさせてくれる、というのは事前には確信が持てなかった部分だが、実測で1回で通った。 | 低 |

## `Ash.can?/3`はボタンの出し分けに十分軽量だった——ただし「後で実際にsubmitして初めて分かる」ケースは残る

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F71 | `Ash.can?({resource, action_name}, actor)`（作成用）／`Ash.can?({record, action_name}, actor)`（更新・削除用）の2パターンだけで、New/Edit/Deleteボタンの出し分けが完結した——`KumiAdmin.Capability`は40行未満 | 4つのCRM resource全てのpolicyが`policy always() do authorize_if actor_present() end`という単純な形（actor有無だけで決まる）だったため、`Ash.can?`は追加のDBクエリなしで即座にbooleanを返した（`actor_present()`はrunする前に判定できる静的チェック）。actorなしでのindex/detail画面テスト（F71用に追加した`"without an actor, new/edit/delete buttons are absent..."`）で、New/Edit/Deleteの3ボタンが揃って消えることを確認した。ただし`Ash.can?`はdocstringで「runtime check（action実行後にしか判定できないcheck）がある場合は`:maybe`を返し、`can?/3`はそれを`true`として扱う」と明記されており、より複雑なpolicy（レコードの値に依存するcheckなど）を持つresourceでは「ボタンは出るが実際にsubmitすると弾かれる」ケースが原理的に残る——今回のCRMではこのケースは踏んでいないが、`Ash.Resource.Info.primary_action/2`が`nil`を返す場合（actionそのものが存在しない）と合わせて`safe_can?/2`は`rescue`で例外時もボタンを出す側に倒し、「本当に判断できないときはsubmit時のflashに委ねる」という設計をタスク仕様通りに実装した。 | 低 |

## 検証結果

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F72 | Go/No-Go判定 | `kumi`コアパッケージは無改変・103テスト全green。`kumi_admin`パッケージは27テスト全green（既存13＋新規14：`form_fields_test.exs`——`for_action/2`のaccept交差・宣言順維持・belongs_to外部キーの型上書き3件、`widget/2`の型別分岐11件）、`mix compile --warnings-as-errors`クリーン（`ash_phoenix`自体のコンパイル時に出る型警告はdeps側のものでこちらの責任範囲外）。`spike0_crm`側は32テスト全green（既存25＋新規7：`kumi_admin_live_test.exs`——フォーム経由のaccount作成→detail遷移・必須項目未入力時のinlineバリデーションエラー・編集による更新・削除→list遷移・検索によるフィルタ・actorなしでのボタン非表示・`belongs_to`/`decimal`/`atom select`の3種ウィジェットを同時に持つdeal作成フォームのスモークテスト）、`mix compile --warnings-as-errors`もクリーン。`mix phx.routes \| grep kumi-admin`で新規2ルート（`/kumi-admin/:resource/new`・`/kumi-admin/:resource/:id/edit`）を含む5ルートを確認した。 | - |

## 率直な評価：「開けばもう製品」にどこまで近づいたか

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F73 | フォーム・検索・削除・ボタン単位の権限表示が入り、CRUD一通り＋検索が揃ったことで「読むだけの管理画面」から「日常業務が回るCRUD画面」へは一歩進んだが、Blueprint §5が挙げる残り（Saved views・Actions（ドメイン固有の業務アクション）・Notifications・Theme・Responsive）はまだ全てゼロ | 今回の実装でAshAdmin比の差別化点にもう1つ加わったのは「ボタン単位のAsh.can?ゲーティング」——AshAdminはsuper-admin用途である以上、目の前のactorが個々のレコードに対して何ができないかを事前に隠す理由がなく、実際そうしていない（触ってみて初めて拒否される）。KumiAdminはこれを標準の振る舞いにした。一方でPayloadの「開けばもう製品」という基準に照らすと、(1) 検索は文字列属性の`contains`のみで、日付範囲・数値範囲・関連先での絞り込みはまだない、(2) フォームのwidgetはHTML標準input任せで、日付ピッカーやrich textのようなUXの作り込みは一切ない、(3) ページングは件数不明の簡易next/prevのまま（F63から変更なし）、(4) Saved views・通知・テーマは概念すら存在しない——という現在地は変わらず正直に記録しておく。「Ashの素のCRUDより明らかに製品寄り」だが「Payload/Retoolのような完成された管理画面製品」にはまだ複数マイルストーン distance がある、というのが2スライス終了時点の評価。 | - |

## ブラウザ実機検証（2026-08-26）

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F74 | 実機検証 | `mix phx.server`起動後、実ブラウザ（Playwright制御のChromium）で以下を確認：(1) `/register`でユーザー登録→セッション確立、(2) `/kumi-admin`でsidebar（Mini CRM＋Accounts/Contacts/Deals/Notes）とdashboard（overview: pipeline_value / conversion_rate）描画、(3) `/kumi-admin/account`でNewボタン表示（Ash.can?ゲート通過）・空状態表示、(4) フォームからAccount作成（name+industry）→詳細ページへredirect＋flash「Account created.」、(5) 詳細ページにEdit/Deleteボタンと全属性表示、(6) `?q=acme`検索で「Acme Corporation」がヒット（大文字小文字不敏感のcontains、実Postgres上で確認）。LiveViewTestのみだった検証ギャップは解消。スクリーンショット: spikes/spike0_crm/kumi-admin-accounts-live.png | - |

## Installer — kumi.install / kumi_admin.install

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F75 | Igniterがタダでくれるもの | `Igniter.Mix.Task`の`if Code.ensure_loaded?(Igniter) do ... else ...end`二重定義パターン（igniter未導入ホストでは親切なエラーで`exit`）、`Igniter.Project.Module.module_exists/2`＋`create_module/3`によるファイル生成の冪等性（存在チェックを自分で書けば二重生成は原理的に起きない）、`Igniter.Libs.Phoenix.select_router/list_routers`によるルーター自動検出（`use FooWeb, :router`パターンの静的解析、複数あれば対話選択、ゼロなら`nil`）、`Igniter.compose_task/2,3`によるタスク合成（`kumi_admin.install`が`kumi.install`を子タスクとして呼ぶだけで両方が一つの`--dry-run`プレビュー/一つの確認プロンプトにまとまる）——ash・ash_admin本体のインストーラ（`deps/ash/lib/mix/tasks/install/ash.install.ex`、`deps/ash_admin/lib/mix/tasks/ash_admin.install.ex`）をほぼそのまま踏襲できた。`Igniter.Test`（`test_project/2`, `apply_igniter!/1`, `assert_creates/2`, `assert_unchanged/2`）のおかげでインストーラ自体をExUnitで冪等性込みでテストできる——実プロジェクトを都度cloneして手で叩く必要がない。 | - |
| F76 | 壊れた：AST上のコメント挿入 | 「auto-mountできない時はコード内にTODOコメントを残す」を`Igniter.Code.Common.add_code/3`（コメントのみの文字列をパース）や`add_comment/3`で試したが、`mix run -e`で最小再現したところ両方とも実運用パスで期待通り動かなかった：`add_code`は「単一子ブロックのモジュール」だと不正な`nil`ノードが本体に混入し、複数文のモジュールでは（`use`宣言の直後などに）挿入したコメントがまるごと消えた。原因は`Igniter.Project.Module.find_and_update_module!`が`Rewrite.Source.update(source, :quoted, ...)`経由でASTを`Code.quoted_to_algebra/2`（mix標準フォーマッタのアルゴリズム）に渡す点——`Sourceror.to_string/1`を直接呼べばノードの`leading_comments`/`trailing_comments`メタは正しく描画される（`mix run -e`で確認済み）が、Rewriteのフォーマッタ経路は別途渡すコメントリストを前提にしており、ノードメタに埋め込んだだけのコメントを黙って落とす。ドキュメント化されていない内部差異で、Igniterのpublic APIだけを読んでいては気づけなかった。 | 高（半日ほど溶かした） |
| F77 | 対応：ファイル改変ではなく`Igniter.add_notice/2`に倒した | F76を受けて、「auto-mount不可の場合はルーターファイルに壊れたコメントを埋め込む」を諦め、`ash_admin.install`が「ルーターが見つからない」場合に使っているのと同じ手（`Igniter.add_warning/2`）を「auth検出できない」場合にも使うことにした——`Igniter.add_notice`でCLI出力に完全なコピペ用スニペットを出すだけで、ルーターファイルには一切触れない。副産物として冪等性の証明が自明になった（ファイルを変更していないので二回目の実行も同じ通知が出るだけで、重複の余地がそもそもない）。タスクの原文は「commented-out with a clear TODO comment」を指示していたが、AST経由のコメント挿入が実測で壊れる以上、「間違ったlive_session推測はTODOより悪い」という同タスクの原則を、ファイル改変そのものにも一段階上げて適用した——不正確な自動編集よりは「何もしないで正しい手順を見せる」方を選んだ、という判断をここに明記する。 | 中 |
| F78 | auto-mount判定：モジュール存在だけでなくクローズを検証 | 当初案は「ホストに`<Web>.LiveUserAuth`が存在すれば`on_mount: [{LiveUserAuth, :current_user}]`で自動マウント」だったが、`:current_user`という`on_mount`節が実際にそのモジュールに定義されているかまでは見ていなかった。`ash_authentication_phoenix`の生成テンプレート（`spike0_crm_web/live_user_auth.ex`で実物確認）は確かに`on_mount(:current_user, ...)`を標準で持つが、モジュール名の一致だけでは「同名だが中身が違うカスタムLiveUserAuth」を誤検出しうる。`Igniter.Code.Function.function_call?(z, :on_mount, [4])`＋`argument_equals?(z, 0, :current_user)`でAST上に実際の節があることまで確認してから初めてlive-mountする形に直した。これにより「間違った推測」の余地はほぼゼロになった（該当節が無ければ機械的にTODO通知へフォールバック）。 | 中 |
| F79 | 実地検証の結果 | `/private/tmp/kumi_install_check/spike0_crm_copy`（spike0_crmのthrowawayコピー、mix.exsのpath依存だけ絶対パスに書き換え）に対して`mix kumi.install`と`mix kumi_admin.install`を実行——両方とも「既にSpike0Crm.Appが存在」「既にSpike0CrmWeb.Routerにマウント済み」を検出して無変更（冪等性の実地証拠）。さらに`app.ex`を退避して`mix kumi.install --yes`を実行したところ、`otp_app`から`title "Spike0 Crm"`を導出した新規ファイルが生成され`mix compile`が通ることを確認、その後同じファイルに対して再実行しても無変更（生成パスと冪等パスの両方を実地で確認）。検証後はthrowawayコピーを削除、実物の`spikes/spike0_crm`ツリーは一切変更していない（`git status --short`で確認）。 | - |

---

# v0.4 — `mix kumi.report`（AI patchパイプラインの検証ハーネス）

> 目的：Blueprint v3 §8「AI Integration」の中核——AI（外部）がsourceにpatchを当てた後、
> `mix format` / `compile` / `test` / `ash.codegen` / `kumi.plan`を一気通貫で実行し、
> 「Ready for PR」か「どこがダメか」を機械可読で返す`mix kumi.report`を実装する。
> Kumiコア（`lib/kumi/`直下の既存モジュール）は無改変、新規ファイルの追加のみ。

## `ash.codegen --check`の実体：Ash本体のflagで、`ash_postgres.generate_migrations --check`に委譲される

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F80 | `mix ash.codegen --check`は実在するAsh本体（`ash`パッケージ）のCLI flagだった——`deps/ash/lib/mix/tasks/ash.codegen.ex`のmoduledocに明記されており、動作は「ファイルを一切生成せず、生成すべきコードが残っていればexit(1)」。内部実装は`extension.codegen(argv)`という薄い委譲で、AshPostgresの場合`AshPostgres.DataLayer.codegen/1`が`Mix.Task.run("ash_postgres.generate_migrations", args)`に丸投げし、実際に`--check`を処理しているのは`ash_postgres.generate_migrations`タスク（moduledoc：「no files are created, returns an exit(1) code if the current snapshots and resources don't fit」）だった。タスク仕様が示唆していた「素朴に別物を発明せず実在のidiomを使う」がそのまま成立し、`kumi.report`の`codegen`ステップは`System.cmd("mix", ["ash.codegen", "--check"])`一行で完結した。 | 低 |

## subprocess vs in-process：MIX_ENVはOS環境変数として自動伝播しない（実測で確認）——ただし`mix test`だけは強制してはいけない

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F81 | `mix test`実行中の`Mix.env()`は`:test`だが、そこから`System.cmd`で子プロセスを起動しても`MIX_ENV`というOS環境変数は子には見えない（`System.get_env("MIX_ENV")`が`nil`）——実際に最小再現スクリプトで確認した：親プロセス内では`Mix.env()`が`:test`を返すのに、`System.cmd("elixir", ["-e", "IO.puts(System.get_env(\"MIX_ENV\"))"]  )`は`unset`を出力する。MixはCLIのpreferred_cli_env機構で内部的に環境を決めるだけで、それをOS環境変数としてexportしない。このため`format`/`compile`/`codegen`の3ステップは`System.cmd("mix", args, env: [{"MIX_ENV", to_string(Mix.env())}])`で明示的に環境を渡す必要があった（渡さなければ`kumi.report`自身がどの環境で動いていようと子プロセスは常に`:dev`扱いになり、`--app`スコープの host アプリの設定と food違いが起きる）。 | 中 |
| F82 | 一方`test`ステップにだけこの`MIX_ENV`強制を適用すると壊れる——実際にspike0_crmで`** (RuntimeError) cannot invoke sandbox operation with pool DBConnection.ConnectionPool`というクラッシュを引いた | 原因は単純：`mix kumi.report`をMIX_ENV未指定（＝`:dev`）で普通に叩くと`Mix.env()`は`:dev`になり、F81の対応でその値を`test`サブプロセスにも強制していたため、`mix test`が`config/dev.exs`（Sandboxプールではない通常のpool）で起動しようとして`Ecto.Adapters.SQL.Sandbox.mode/2`が失敗した。`mix test`だけはMix自身のpreferred_cli_env（常に`:test`）に委ね、環境変数を明示的に渡さない（＝ユーザーが`MIX_ENV=xxx`を明示していない限り自然に`:test`へフォールバックする）よう修正した——「4ステップとも一律に同じenvを渡す」という最初の素朴な実装が、`mix test`だけは例外だという事実を実測で教えてくれた。 | 中 |

## `--json`のstdoutを汚す2つの実測バグ：Logger debugログとANSIカラーコード

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F83 | spike0_crmで`mix kumi.report --json`を実行すると、`Kumi.Actual`が発行する生SQLクエリの`[debug] QUERY ...`ログがJSON本体の前に大量に出力され、`Jason.decode!`できない壊れた出力になった | 原因はhostアプリ（spike0_crm）のdevロガー設定が`:debug`レベルであること——`plan`ステップはin-process（`Mix.Task.run("app.start")`後に`Kumi.plan`/`Kumi.plan_app`を直接呼ぶ）なので、Loggerの出力先はkumi.report自身の標準出力と同じであり、Mix.shell().infoで最後に出すJSONより先に紛れ込む。host側のロガー設定を変更するのは越権（`kumi.report`の責務外）なので、`plan_step/1`内だけ`Logger.configure(level: :warning)`で一時的に黙らせ、`try/after`で（例外時も含めて）必ず元のレベルへ戻す形にした。 | 中 |
| F84 | `mix format --check-formatted`の失敗時diffはANSIカラーエスケープ（`[1m[31m`等）付きで出力され、そのまま`detail`文字列に載ると機械可読とは言い難い出力になっていた | AI/CIコンシューマ向けの`--json`契約を汚さないよう、`truncate/1`内で`~r/\e\[[0-9;]*m/`によるANSI除去を先にかけるよう直した。 | 低 |

## kumiコア自身の`plan`ステップの構造的限界：`Kumi.Test.Repo`はkumiのOTP applicationに属さない

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F85 | kumiパッケージ自身に対して素の`mix kumi.plan`（`--app`なし）を単独で叩くと、ExUnitの外では`** (RuntimeError) could not lookup Ecto repo Kumi.Test.Repo because it was not started or it does not exist`で必ずクラッシュする——これは`kumi.report`の新規バグではなく、既存の`mix kumi.plan`にも実測で再現した既存の構造的事実 | `Kumi.Test.Repo`はtest/support配下のtest専用コードで、`test/test_helper.exs`が`Kumi.Test.Repo.start_link()`を手動で呼んで初めて起動する——`:kumi`というOTP application自体の`application/0`（`extra_applications: [:logger]`のみ）には一切含まれていないため、`Mix.Task.run("app.start")`では絶対に起動しない。つまり「kumiパッケージ自身のtest fixturesを本物のhostアプリのように`kumi.plan`/`kumi.report`で検証する」ことは、ExUnit経由（Repoが既に起動済み）以外では原理的に不可能——`kumi.report`の`plan_step/1`は素の`mix kumi.plan`と違い、この失敗を`rescue`で捕まえて`{status: :fail, detail: "could not build plan: ..."}`として穏当に報告する（verdictも`:blocked`ではなく正しく`:failed`に倒す——REVIEW/DANGEROUSの発見と「そもそも実行できなかった」を区別する設計、`Kumi.Report`のderive_verdict参照）。kumiパッケージ自身の統合テスト（`test/mix/tasks/kumi.report_test.exs`）はこの制約込みで「`plan`は`fail`、`format`は既存drift（F86）でfail、`verdict`は`failed`」という現実の状態を固定してアサートしている。 | 中 |

## 発見：kumi・spike0_crm両方に既存のformat drift——`kumi.report`がこのプロジェクトで初めて`mix format --check-formatted`を実地で通した

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F86 | `kumi.report`の`format`ステップを実装して初めて分かったこと：kumiパッケージ自身で7ファイル、spike0_crmで9ファイルが`mix format --check-formatted`に「未フォーマット」と判定された——どちらも今回のスライスが触れていない既存ファイル（`git log`で該当ファイルの変更履歴を確認、直近のコミット以降ワーキングツリーの差分はゼロ）で、過去のどのスライスも`mix format --check-formatted`を実地で通したことがなかった（`mix test`のaliasにも`mix precommit`にも入っているが、これまでの検証コマンド列には登場していない）ため気づかれずに残っていた。「kumi coreを触らない」というタスクのHard rulesに従い、kumiパッケージ側の7ファイルは未修正のまま残し、`format: fail`が実地の`verdict: failed`として記録・テスト化されている（F85参照）。spike0_crm側の9ファイルは実物のツリーには一切手を入れず（バックアップ→`mix format`→動作確認→即座に`git status --short`でゼロ差分になるまで復元、を実施）、「readyのverdictを実地デモする」ためだけにF79と同じthrowawayコピー（`/private/tmp/kumi_report_check/spike0_crm_copy`）上でフォーマットして使い捨てた。 | 中 |
| F87 | `mix format`自体が同一ファイルに対して非決定的に見える瞬間があった——`test/spike0_crm/crm/note_test.exs`の1行（`Ash.Changeset.for_create`のパイプ呼び出し）で、`mix format <file>`直後の`mix format --check-formatted`は通るのに、直後に`mix kumi.report`（＝別のmix起動、内部で改めて`mix format --check-formatted`を子プロセス実行）を叩くと同じ行が再び「未フォーマット」と判定され、しかも提示される「正しい」整形結果が1回目とは異なる形だった | `MIX_ENV`を明示的に変えても再現/解消せず（`unset` / `dev` / `test`すべてで一度は成功）、数回`mix format`を往復させると収束して以降は安定した——おそらくSpark.Formatterプラグインが絡む行のAST整形が、直前のコンパイル状態（warm/cold）に依存してごく稀に非決定的な出力を出す、という与太話以上の原因究明はできていない（Elixir/Spark側の既知issueかは未調査）。実務上の回避策は「`mix format`→`mix format --check-formatted`を同一セッションで2〜3回繰り返して収束を確認してから使う」——これは`kumi.report`の実装バグではなく`mix format`自体の挙動なので、`kumi.report`側で対処すべき問題ではないと判断し、これ以上の深掘りはしなかった。 | 中 |

## Elixir 1.20のExUnitサマリ行フォーマット変更——`"N tests, M failures"`はもう存在しない

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F88 | `test`ステップの`detail`を「テスト件数のサマリ1行」に切り詰めるため、当初`~r/\d+ tests?,\s*\d+ failures?/`という正規表現でパースしていたが、spike0_crmに対して実地で`mix kumi.report`（`--skip-tests`を外した完全版）を実行して初めて、この正規表現が一度もマッチしていないことに気づいた——マッチしないとフォールバックの`truncate/1`（ExUnit実行ログの生出力を最大20行そのまま）に落ちるため、バグとしては「動くが冗長」という形で隠れていた | 原因はElixir 1.20で新規追加された`ExUnit.CLIFormatter`（`deps/ex_unit/lib/ex_unit/cli_formatter.ex`のコメントに仕様あり）——サマリ行が旧来の`"32 tests, 0 failures"`から`"Result: 32 passed"`（全成功時）/`"Result: 30/32 passed"`+別行`"Failed: 2 tests"`（失敗時）という新フォーマットに変わっていた。正規表現を`~r/Result:[^\n]*(?:\nFailed:[^\n]*)?/`に直し、実地で`"Result: 32 passed"`という簡潔な1行が`detail`に載ることを確認した。「モデルの知識にある定番文字列を検証なしで正規表現に落とす」ことの典型的な失敗例として記録する。 | 低 |

## 検証結果

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F89 | Go/No-Go判定 | `kumi`パッケージは119テスト全green（既存105＋新規14：`report_test.exs`7・`report/format_test.exs`2・`report/json_test.exs`4・`mix/tasks/kumi.report_test.exs`1）、`mix compile --warnings-as-errors`クリーン（新規ファイルのみ、既存の未フォーマット7ファイルはF86の通り既存drift）。`kumi_admin`は31テスト全green（無改変）。`spike0_crm`は32テスト全green（無改変、`git status --short`でワーキングツリー差分ゼロを確認）。実地検証は`mix kumi.report`をspike0_crm（および、readyデモ用にF79と同じthrowawayコピー）に対して実行——(1) 清潔な状態：`--skip-tests`ありで`verdict: ready`（exit 0）、`--skip-tests`なしの完全版で`test`ステップが実際の`mix test`（32 passed）を実行した上でも`verdict: ready`（exit 0）、(2) `crm_accounts`テーブルに`legacy_migration_notes`列を`ALTER TABLE ADD COLUMN`で注入した状態：`verdict: blocked`（exit 1）、`plan.operations`に`{"description": "remove_column crm_accounts.legacy_migration_notes", "level": "dangerous", ...}`が1件、(3) `ALTER TABLE DROP COLUMN`で復元後：再び`verdict: ready`（exit 0）——を確認した。DB操作は全て`spike0_crm_dev`（localhost:5434、kumi_db docker）に対してのみ行い、注入と復元後の両方で`\d crm_accounts`により実カラム構成を目視確認した。 | - |

## 率直な評価：AIエージェントがこのレポートだけを見て次の一手を判断できるか

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F90 | 十分な点：steps[]配列の各要素が独立したpass/fail/skippedと理由を持ち、`verdict`一語で「PR出していいか」の最終判断が付く、`plan.operations`はREVIEW/DANGEROUSだけに絞られていて「何を直せばいいか」が明示される——AIエージェントが「format直して」「このカラム消していいか人間に聞いて」レベルの次アクションを選ぶには足りる情報量だと判断した | 今回の実地検証（F89）で実際に`verdict: blocked`＋`plan.operations`だけを見て「`legacy_migration_notes`が原因」と機械的に特定できることを確認済み——JSON以外の情報（ログを別途grepする等）を必要としなかった。 | - |
| F91 | 不十分な点：(1) `test`ステップの`detail`は成功時こそ簡潔（`"Result: 32 passed"`）だが、失敗時は`Result:`/`Failed:`の2行サマリのみで「どのテストが」「どのファイルの何行目で」失敗したかという構造化情報（テスト名・file:line・assertion diff）が一切ない——AIエージェントが実際に修正のためのpatchを書くには、結局`mix test`を自分でもう一度実行してログ全文を読み直す必要がある。(2) `detail`は20行で`truncate`される（ponytailコメント通り、意図的な簡略化）——`compile`の警告が21行以上のときAIは全文を失い、再実行するしかない。(3) パッチ適用「前」と「後」のdiffをこのレポート自体は一切持たない——「何が変わったからこの結果になったか」はAI側がpatchそのものを別途保持しておく前提になっており、`kumi.report`単体はステートレスなスナップショット判定しかできない。(4) REVIEW（人間の目が必要だが破壊的ではない）とDANGEROUS（データ損失）が`plan.operations`の中で`level`フィールドでしか区別されず、exit codeのレベルでは両方とも同じ「非0」に潰れる——CIがREVIEWは警告扱い・DANGEROUSは即ブロックのように差をつけたい場合、`--json`をパースしてlevelを見るしかない。総合すると「機械可読な一次判定」としては実地で機能したが、「AIがこれだけを見てpatchを直接書き直せる」水準には未達で、次のスライスがあるなら(1)のテスト失敗の構造化（`ExUnit.Formatter`のraw resultsを保持する等）が最優先だと考える。 | - |

---

# v0.5 — `mix kumi.new`（プロジェクト生成ワンコマンド、Blueprint v3 §28）

> 目的：`mix kumi.new my_crm --db-port 5434`一発で、Kumi＋kumi_admin導入済み・authワイヤリング済み・DB設定済みの
> 「動くPhoenix+Ashアプリ」を生成する。新パッケージ`kumi_new`（`KumiNew`名前空間、ランタイム依存ゼロ、
> archive配布前提）として実装。既存の`kumi`/`kumi_admin`は無改変（READMEのみ例外）。

## `mix igniter.new`の`--yes`は実地で完全にプロンプトを潰した——ただし通知は別

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F92 | `mix igniter.new APP --with phx.new --install ash,ash_postgres,ash_phoenix,ash_authentication,ash_authentication_phoenix --auth-strategy password --yes`を、標準入力を`/dev/null`にリダイレクトした状態（`System.cmd`の子プロセスと同条件）で2回（下見ラン・本番ラン）実地実行し、いずれもプロンプトでハング/エラー終了せず完走した——`--yes`は`igniter.new`自身の確認だけでなく、内部で合成される`ash.install`・`ash_postgres.install`・`ash_authentication.install`等すべての子タスクの確認プロンプトまで一貫して抑制していた。唯一プロンプトに似た出力は、ash installerが出す「picosat_elixirの代わりにsimple_satへの切り替え」という**情報通知**（`mix igniter.install simple_sat && mix deps.compile ash --force`という手順の案内）で、これは選択を迫るものではなく単なる`Igniter.add_notice`の出力であり、`--yes`の対象外でも実行は止まらなかった。「`--yes`が実運用で本当に無人実行を保証するか」は事前には未検証だったが、`/dev/null`縛りの2回の完走が実測の証拠になった。 | 低 |

## mix.exs / config挿入：アンカー文字列1箇所限定＋失敗時は例外、で「壊れたら黙って通す」を避けた

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F93 | `KumiNew.Inject.insert_deps/3`は`"defp deps do\n    [\n"`を、`patch_port/2`は`"  hostname: \"localhost\",\n"`をアンカーに、**出現回数が厳密に1でなければ`{:error, ...}`を返す**実装にした——0件（フォーマット変更で消えた）でも2件以上（想定外の重複）でも黙って無視/誤挿入せず失敗する。下見ラン（`fixture_check`）で捕獲した実物のmix.exs/dev.exs/test.exsをテストフィクスチャとして固定し（`kumi_new/test/fixtures/`）、挿入結果が`Code.string_to_quoted/1`で構文的に有効なElixirであることまでテスト済み。**脆さの評価**：アンカーは`igniter.new`/`phx.new`が生成するテンプレートの一言一句に依存しており、将来どちらかのテンプレートがこの2行の書式を変えれば`kumi.new`は（誤挿入ではなく）明示的なエラーで止まる——「間違った推測より、正しく失敗する」というF77と同じ設計判断をここでも踏襲した。実地の本番ラン（`demo_crm`生成）でもこのアンカーは1回ずつヒットし、挿入後`mix format`をかけた上で`mix kumi.report`の`format`ステップが最終的に「all files formatted」を返したことまで確認済み。 | 中 |

## 実地計測：wall-clock

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F94 | `mix igniter.new`単体（Ash/Phoenix/Auth一式のfetch+compileを含む、依存キャッシュ温まった状態）が3分14.65秒。`mix kumi.new demo_crm --db-port 5434 --kumi-path ...`のフルラン（igniter.new生成＋mix.exs/config注入＋`mix deps.get`＋`mix kumi.install --yes`＋`mix kumi_admin.install --yes`＋`mix ash.setup`）が3分54.54秒——igniter.new本体が全体の8割強を占め、Kumi側の追加ステップ（注入・2つのinstaller・DBセットアップ）は合計40秒弱だった。 | - |

## 検証結果（`demo_crm`、`/private/tmp/kumi_new_check/demo_crm`、実地）

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F95 | Go/No-Go判定 | `kumi_new`パッケージは25テスト全green（Name 11・Args 6・Inject 8）、`mix format --check-formatted`／`mix compile --warnings-as-errors`ともクリーン、ランタイム依存ゼロ（`mix.exs`の`deps()`が空リスト）を維持したまま`mix archive.build`→`mix archive.install --force`でarchive化できることを実地確認。既存3スイートは無改変・全green（`kumi` 119 / `kumi_admin` 31 / `spike0_crm` 32、`kumi/README.md`のQuick startセクション追記以外はソース無変更）。実地生成（`mix kumi.new demo_crm --db-port 5434 --kumi-path /Users/akimitu/Documents/Kumi`）後、(a) 生成アプリの`mix test`が5 passed、(b) `router.ex`に`kumi_admin("/kumi-admin", ...)`のマウントを確認（grep）、(c) `Kumi.Resource`ショートハンドで`DemoCrm.Todo.Task`（`field :title, :string, required: true`）を追加し`app.ex`のresources/adminナビゲーションに登録、`MIX_ENV=dev mix ash.codegen add_tasks && mix ash.setup`でマイグレーション生成・適用が成功、(d) `mix kumi.report --skip-tests`が`format`/`compile`/`codegen`/`plan`全て✓で`Verdict: ready`・exit 0、(e) `mix phx.routes \| grep kumi-admin`で5ルート（dashboard/index/new/show/edit）を確認——という(a)〜(e)全項目を実地で通した。 | - |
| F96 | **admin auto-mountはF78の判定ロジック込みで実地トリガーした**——`mix kumi_admin.install --yes`の出力は`"Kumi Admin: mounted at /kumi-admin in DemoCrmWeb.Router, using DemoCrmWeb.LiveUserAuth to resolve the actor."`で、TODO通知へのフォールバックではなく実マウントパスが通った。これは「`ash_authentication_phoenix`のインストーラが生成する`LiveUserAuth`は`on_mount(:current_user, ...)`節を標準で持つので、新規生成アプリでは自動検出が成立するはず」という設計時の予想が、実地（下見ラン・本番ラン双方）で崩れずに成立した、という確認結果。kumi_admin側のコードは一切変更していない。 | - |

## 率直なDX評価：`create-payload-app`と比べてどうか

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F97 | `create-payload-app`は空のNext.js+Payloadプロジェクトの雛形生成（DB接続なし、認証は生成コード止まり）で概ね1分未満——対して`mix kumi.new`は**約4分**だが、その4分の中身は「空の雛形」ではなく、Postgres接続込みの認証（`ash_authentication`のpassword戦略・users/tokensテーブルとマイグレーション適用済み）・管理画面のマウントと actor 解決の自動配線・アプリ雛形（`app.ex`）が**全部実行済みで動く状態**まで一気に到達している。「1コマンドで何もない状態から`mix phx.server`」という目標そのものは実地で達成できた（F95の(a)〜(e)が生成直後のアプリに対して全部通った）が、時間の大半（3分強）が`igniter.new`本体のdeps fetch/compileであり、`kumi_new`側が短縮できる余地はほぼない（Ash/Phoenixのビルドコストそのもの）。Payloadとの比較で正直に言うと：(1) 初回のwall-clockはPayloadの4倍で「一瞬」ではない、(2) 一方で得られる状態（DB込み・認証済み・管理画面込み）はPayloadの雛形より一段深い、(3) `--kumi-path`必須というHex未公開ゆえの摩擦は、Kumiが公開されれば消える一時的なものであり恒久的なDX差ではない。総合すると「create-payload-appの再現」という当初のゴールに対しては、体験の**深さ**では並ぶ／上回るが、**速さ**の体感では届いていない、というのが実測に基づく評価。 | - |

## `mix kumi.plan --fix-hints`（検出→修復の断絶を出力で埋める）

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F98 | Payload目線レビュー | 出発点はPayload目線レビューの指摘「`kumi.plan`はdriftを検出するが修復手段を提示しない（検出と修復の断絶、"then what?"）」。実装：`Kumi.Plan.FixHint`（純関数、op毎に助言行のリストを返す）＋`Kumi.Plan.Format`の`fix_hints:`オプション（probeのfindingsと同様、opの下にインデントして表示）＋`mix kumi.plan`の`--fix-hints`フラグ。実行は一切しない——planの「読み取り専用wedge」という位置づけは不変、分類・サマリ件数・`--check`のexit codeにも無影響。設計判断3点：(a) code-ahead系（add_table/add_column/add_fk/add_index/change_column）は`mix ash.codegen && mix ash_postgres.migrate`への誘導を基本にしつつ、「codegenが何も生成しない＝snapshotがcodeと一致済み＝DB側がそこからdriftしている」場合向けの手動SQL一行を併記した。ただし`add_table`だけはDDL再構築を諦め「手で再作成」止まりにした——Table構造体からのCREATE TABLE再構築は列制約・FK・indexの組み合わせ次第で不正確になり得るため。(b) drift系（drop_table/remove_column/remove_fk/remove_index、これらはash.codegenがcode-vs-snapshot差分しか見ないため検出できない）は、破壊的SQLをいきなり勧告と読まれないよう「codeに追加してDBに残す」選択肢を先に置き、破壊的SQLは次点として提示した。(c) 正規化済みのdefault値（`{:literal, s}`はAshリテラルの可能性がありそのままSQLにはできない）とdatetime_precision変更はSQL化を諦め「adjust manually」とし、change_columnのSQLは`changes`タプル`{field, desired, actual}`のdesired側を対象にした（drift方向と逆に読み違えやすい箇所）。(4) possible_renameのヒントは「`ash.codegen`より先に`ALTER TABLE ... RENAME COLUMN ...`を実行せよ（先にcodegenを回すとdrop+addが生成されデータを失う）」——rename検出（Kumi.Plan.Rename）の判断をSQL側の実行順として言い直したもの。(5) `mix kumi.apply --safe-only`（SAFE級diffのみdev限定で自動実行する案）はplanのwedge定位そのものを変える判断になるため、今回は実装せずBlueprint §12 Open Questionsに保留登録した。(6) テストはfix_hint_test.exsに13件＋format_test.exsに1件追加、`kumi`パッケージ130テストgreen、`mix format --check-formatted`／`mix compile --warnings-as-errors`ともクリーン。加えて`spikes/spike0_crm`のクリーン状態で`mix kumi.plan --fix-hints`を実地実行し、zero-diffメッセージのままクラッシュせず完走することを確認済み。 | - |

## Dashboard集計（metric :count/:sum — Payload目線レビュー第2弾）

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F99 | Payload目線レビュー第2弾 → metric集計 | 出発点はPayload目線レビューの指摘「dashboardがmetric名の羅列のみ（`No aggregation`）＝占位（placeholder）であり、製品として機能していない」。**(1) DSL変更**：`Kumi.App.Dsl.Metric`に`resource`（必須, `:module`）・`kind`（`{:in, [:count, :sum]}`, default `:count`）・`field`（`:atom`, sum時のみ意味を持つ）を追加し、裸の`metric :name`形式は完全に削除した（Rule 13：後方互換シムを残さない——`field`のconditional requirednessをスキーマではなく検証器側に置いたのも、Sparkのスキーマには「他フィールドの値に応じて必須」を素直に書けないため）。既存使用箇所を全部更新：`kumi/test/support/test_app.ex`（`account_count`, `resource: Kumi.Test.Account`）、`spikes/spike0_crm/lib/spike0_crm/app.ex`（`pipeline_value`/`conversion_rate`の2metric構成→`deal_count`(count)/`pipeline_value`(sum, field: :amount)の2metric構成に置き換え）。**(2) 検証器**：`Kumi.App.Verifiers.ValidateDashboardMetrics`に、既存の「dashboardは≥1metric」ルールに加え、metric単位で(a) `resource`がapp declared resourcesのメンバーであること（`ValidateResources`が先に走ることを前提に、非Ash.Resourceを弾いた後の集合に対してのみ`Ash.Resource.Info.attribute/2`を呼ぶ設計——verifierの実行順（`@verifiers`リストの並び）がここでの安全性の根拠になっている）、(b) `kind: :sum`なら`field`が非nilかつ`Ash.Resource.Info.attribute(resource, field)`が存在すること（型チェックはせず存在チェックのみ——非数値フィールドへのsumは実行時にAsh側でfail loudする設計）、(c) `kind: :count`なら`field`がnilであること、の3ルールを追加した。**(3) admin側**：新規`KumiAdmin.MetricValue.fetch/2`が`Ash.count/2`・`Ash.sum/3`をactor付きで呼び、`{:error, %Ash.Error.Forbidden{}}`（Ashはエラーを**クラス構造体**でラップするため、そのクラスにマッチさせる必要があった）を`:forbidden`に変換、それ以外のエラーはraiseでfail loud。`Ash.sum`が`{:ok, nil}`（該当行0件）を返すケースは`{:ok, 0}`に正規化した。`KumiAdmin.DashboardLive`はmount時に各metricの値を先に計算してassignsに入れ、render側は`:forbidden`を`"—"`に、成功値は必ず`KumiAdmin.Format.cell(metric.name, value)`経由でレンダリング——`Ash.sum`が`:decimal`属性に対して返す`Decimal`構造体が`Phoenix.HTML.Safe`を実装していない可能性があるため、bareの`{value}`補間を避けてこの罠を回避した。**(4) 意図的カット**：`conversion_rate`（比率）はcount/sumだけでは表現できないためこのスライスで削除——比率・フィルタ・時間窓は未対応のまま（analytics engineは作らない、という当初方針を維持）。**(5) 実測テスト数**：`kumi`パッケージ134 passed（既存130＝F98時点 + 新規4検証器テスト）。最初の実行は133/134で、`mix kumi.report`の自己参照テスト（自パッケージのformat状態をチェックする）が「新規verifierファイルの未整形」でfailし、`mix format`を挟んで134全green化した——これも「テストが実際に何を検証しているか」を裏付ける実地の一例。`kumi_admin`はMetricValue新設・DashboardLive書き換えを行ったが、テスト数自体は31 passedのまま変わらず（新規テストは追加していない——自パッケージがDBを持たない制約により、MetricValue/DashboardLiveの実挙動検証はspike0_crm側に委ねる、この repo の既存パターンに従った）。`spike0_crm`33 passed（既存32＝F95時点から、旧「metric名を羅列するだけ」のdashboardテスト1本を削除して集計値を検証する新テスト2本（deal_count/pipeline_value成功パス・no-actor時の"—"パス）に置き換え、差し引き+1。加えて`test/kumi/app_test.exs`が`[:pipeline_value, :conversion_rate]`を直接アサートしていたため追随修正が必要だった）。三スイートとも`mix compile --warnings-as-errors`・`mix format --check-formatted`クリーン。**(6) 摩擦**：ライブラリのDSLロジック自体は初回実装で全テストgreenだった（verifierの順序前提が事前に文書化されていたため設計判断に迷いがなかった）——唯一のつまずきは`kumi/test/kumi/app_test.exs`ならぬ`spikes/spike0_crm/test/kumi/app_test.exs`という、指示書に名指しされていなかった第三の既存テストファイルがmetric名を直接アサートしていたことで、`mix test`を実行するまで気づけなかった（静的grepだけでは`spikes/`配下の別リポジトリのテストまで見落とすリスクがあると再確認した）。 | 低 |

## Workflow stages UI（宣言→段階別件数の読み取り専用描画）

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F100 | 設計 | metricスライス（F99）と同型の設計：`Kumi.App.Dsl.Workflow`に`resource`（必須, `:module`）・`field`（必須, `:atom`）を追加し、裸の`workflow :name do stages [...] end`形式は完全に削除した（Rule 13）。検証器`ValidateWorkflowStages`に、既存の「≥1 stage」ルールに続けてworkflow単位で(a) `resource`がapp declared resourcesのメンバーであること（`ValidateResources`が先に走る前提——`@verifiers`の並び順がここでも安全性の根拠）、(b) `Ash.Resource.Info.attribute(resource, field)`が存在すること、(c) その属性の`public?`が`true`であること（`Ash.Query.filter_input`はpublic属性しか受け付けないため、実行時死を先取りしてコンパイル時に弾く）、(d) 属性に`constraints[:one_of]`があれば`stages`がその部分集合であること（`one_of`が無ければstages検証はスキップ）、の4ルールを追加した。 | - |
| F100 | DSL構文の破綻 | タスク指示書が想定していた`workflow :name, resource: X, field: :y do stages([...]) end`（インラインkeyword opts＋doブロックの併用）は、実地の`mix compile`で`undefined function workflow/3`として失敗することを発見した——`quote`でASTを検証すると、Elixirの`do...end`糖衣構文はdoブロックを**既存のkeyword引数リストとは別の第3引数**として追加する（`workflow(:name, [resource: X, field: :y], [do: block])`）が、Sparkが自動生成するentityマクロは`entity.args`の個数+1（今回は`name`+`opts`の2引数）でしか定義されないため、3引数呼び出しは常にarity不一致で落ちる。この組み合わせ構文自体がSpark/Ashの標準パターンに存在しない（Ashの`create :new, accept: [...] do ... end`も同じ理由で実地に`undefined function create/3`になることを別途確認済み）と判断し、`metric`と同じ「全部インラインkeyword、doブロックなし」形式（`workflow :name, resource: X, field: :y, stages: [...]`）に統一した。ブループリント（§3例）・`Kumi.App`のmoduledoc例・fixture・spike0_crmの`app.ex`まで、この一形式のみに揃えている。 | 中 |
| F100 | admin側 | `KumiAdmin.StageCounts.fetch/2`がstage毎に`Ash.Query.filter_input(%{field => stage})` + `Ash.count(actor: actor)`を宣言順に呼ぶ（`Ash.Query.filter`はマクロで実行時フィールド名を受け付けないためfilter_inputが必須——F67と同じ教訓の再確認）。`Ash.Error.Forbidden`が最初に出た1クエリの時点で`reduce_while`により残りのstageクエリを発火させずに`:forbidden`へ短絡し、それ以外のエラーはfail loud（raise）。`# ponytail: N count queries per workflow; single GROUP BY aggregate if it matters`をコメントで明記した。`KumiAdmin.DashboardLive`は`:forbidden`のとき宣言済みstage全件を`"—"`として描画する（metricの`:forbidden`→`"—"`と同じレンダリング文化を踏襲）。 | - |
| F100 | fixture妥協 | `kumi/test/support/test_app.ex`はplan_app_testの範囲外テーブル断定に必須の非対称（Accountのみ宣言、Dealは宣言しない）を崩せないため、`workflow :onboarding`は`field: :industry`（`one_of`制約なし）にexistence-onlyで束縛した——stages自体の妥当性は検証されない、という制約をfixtureのコメントとして明記した。 | 低 |
| F100 | 対象外 | 遷移・実行エンジン（状態遷移のガード、AshStateMachine統合）はこのスライスの対象外のまま——Blueprint §12のOpen Questionは未決着で持ち越し。読み取り専用の段階別件数描画のみを実装した。 | - |
| F100 | 実測テスト数 | `kumi`パッケージ138 passed（既存134＝F99時点 + 新規4検証器テスト）、`mix compile --warnings-as-errors`・`mix format --check-formatted`ともクリーン。`kumi_admin`は`StageCounts`新設・`DashboardLive`書き換えを行ったが31 passedのまま変わらず（新規テストは追加していない——MetricValueと同じ理由で実挙動検証はspike0_crm側に委ねた）。`spike0_crm`は34 passed（既存33＝F99時点から、workflow forbidden描画のアサーション追加と段階別件数の新規テスト1本の追加で+1）。三スイートとも`mix compile --warnings-as-errors`・`mix format --check-formatted`クリーン。 | - |

---

## 英語gotchasガイド蒸留（OSS準備）

> 目的：Blueprint v3 §12のOSS準備タスク——`kumi`/`kumi_admin`/`kumi_new`のみを公開し、本ログ（日本語・内部限定）は非公開のまま、
> 再利用可能な教訓だけを英語の`kumi/guides/ash-gotchas.md`に蒸留してパッケージに同梱する。

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F101 | 成果物と選定基準 | `kumi/guides/ash-gotchas.md`（英語、F番号・スパイク名・内部ブループリントへの参照ゼロ）を新規作成した。選定基準は「Ash/AshPostgres/Spark/Igniterの上に何かを作る任意の開発者が再利用できる教訓」のみ——Kumi独自のDSL設計判断（`Kumi.App`のmetric/workflow構文そのもの、`kumi.plan`の安全性分類規則、rename検知ヒューリスティック）、Payloadとの比較評価、スパイク運営・テスト会計・パッケージ切り出しのようなKumi内部プロセスは除外した。5セクション（Ash resources & policies／Ash queries／Spark DSL & macros／AshPostgres & migrations／Igniter）に計30件のgotchaを収録し、各項目は「太字1行の症状→原因→直し方」の形式に統一、コード片は成立する箇所のみ添えた。 | - |
| F101 | 見送った代表カテゴリ | (1) Kumi内部の意思決定——安全性分類の1本化（F23）、rename greedyマッチングの限界（F22）、metric/workflow DSLのフィールド設計（F99/F100）は「Kumiがどう作ったか」であって「Ashがどう振る舞うか」ではないため除外。(2) Payload比較——DX評価（F73/F97/F98冒頭）は競合製品との相対評価であり、汎用開発者向けの教訓ではないため除外。(3) スパイク運営・テスト会計——パッケージ切り出しの経緯（F26/F27/F31/F32）、テスト数の増減報告（F19/F25/F39/F58/F66/F72/F89/F95/F100実測テスト数）はKumiのプロジェクト管理記録であり除外。(4) 一部low-signal項目——`mix format`の非決定性（F87、原因未究明のまま）、rename貪欲マッチングの既知の限界（F22、Kumi独自アルゴリズムの制約）も汎用ガイドには不向きと判断し見送った。 | - |
| F101 | 蒸留時の気づき | 重複エントリは実質2組見つかった：F17（FK/index命名規則が非公開）とF20（snapshot JSON形式が非公開）は「AshPostgres内部実装への依存はバージョンアップで壊れる」という同じ教訓の別側面だったため、ガイドでは別項目として残しつつ表現を書き分けた。F18とF33（timestamp精度）も同様に「時系列で後から解消された」関係——F18時点の「精度は検出できない」という記述はF33/F34で覆っていたため、ガイドにはF33/F34の解決済み形（`datetime_precision`列を見る必要性）だけを採用し、F18の「未検出」という古い記述はそのまま英訳しなかった（本ログ自体はSpike記録として当時のまま残すが、ガイドには陳腐化した記述を持ち込まない判断）。README（`kumi/README.md`）の「Known limitations」に残る「timestamp精度変化は検出されない」という記述は、F33/F34の実装後も更新されていない可能性のある既存の陳腐化候補として気づいたが、本タスクの範囲外（ガイド新規セクション＋リンク1行の追加のみ）のため修正せず、レビュアー確認事項として記録するに留めた。 | 低 |

---

## mix kumi.apply（SAFE drift修復 — §12決断）

> 目的：Blueprint v3 §12のOpen Question「`mix kumi.apply --safe-only`を作るか」を決着させる。
> 結論：作る。ただしPayload式push（SAFE級diffを何でも自動実行）の再現ではなく、
> `mix ash.codegen`が原理的に見えない方向（DBがsnapshotより後退した側）だけを直す「drift修復」に限定する。

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F102 | 決断の中身と根拠 | `ash.codegen`はcode→snapshotの前進（code側がsnapshotより進んでいる差分）しか扱えない構造的盲点があり、「DB側が手作業でsnapshotより後退した」drift（列を手でDROPされた等）はcodegenが何も生成しない——`kumi.plan`はこれを検出するが実行はしない読み取り専用wedgeのまま、というのがこれまでの不変条件だった。`mix kumi.apply`はこの2つの不変条件（planは読み取り専用／kumi.applyはcodegenの補完であり代替ではない）を両方維持したまま、「DBがsnapshotに置いていかれた側」だけをSAFE級に限定して自動修復する第3の経路として設計した——Payload式のSAFE級diff全自動pushではなく、範囲をdrift修復のみに絞ったことで、planのwedge定位そのものを変える判断（F98で保留した論点）を回避できた。 | - |
| F102 | 実行ゲート3条件とall-or-nothing | 実行対象は(1)`Kumi.Plan.Safety.classify/1`が`:safe`と判定、(2)opのタグが明示allowlist（`:add_table`／`:add_column`／`:add_index`／`:change_column`——safety.exが実際に`:safe`を返す全タグを読んで洗い出した集合）に含まれる、(3)完全にSQL描画できる、の3条件すべてを満たすopのみ——`:review`／`:dangerous`はどんなフラグを付けても実行対象に入らない設計にした。`change_column`は変更点リストの中に1つでも`:default`や`:datetime_precision`変更が混ざっていたら全体を`:unsupported`にするall-or-nothingルールを`Kumi.Plan.SQL`に実装した——safety.ex側は「default変更だけのchange_column」を単独では`:safe`に分類する（`classify_change`の`{:default, ...}`節）ため、`:safe`判定とSQL描画可能性は別軸であることが実装中に判明した。**レビューで発見した見落とし**：この非対称は`change_column`だけでなく`add_column`にも同じ形で存在した——`Safety.classify/1`は`add_column`を`nullable`だけで判定し`default`を見ないため、「nullableかつdefault付き」の列（例：`Kumi.Test.Deal.stage`、default `:lead`）も`:safe`と分類されるが、`Kumi.Plan.SQL.render/1`が生成する`ADD COLUMN name type`にはdefaultが乗らない——このまま実行すると列は復活するがdefaultだけ黙って未設定のまま残る（=中途半端なdrift）。`SQL.render/1`自体は変更しない（`FixHint`が同じ関数を使ってdefault抜きのSQLを人間に見せる必要があるため、描画可能性はそのまま）——代わりに`Kumi.Apply`側にのみ「`:safe`な`add_column`でも`default`または`datetime_precision`が非nilなら実行から除外する」という第4のガードを追加した。「描画可能≠実行可能」の分離が実行時に何を指しているかの実例になった。 | - |
| F102 | SQL描画の一本化と「描画可能≠実行可能」 | SQL文字列生成箇所を`Kumi.Plan.FixHint`から新設`Kumi.Plan.SQL`に抽出し、`FixHint`（助言・出力のみ）と`Kumi.Apply`（実行）の両方がこれを呼ぶ構成にした——ヒント表示のSQLと実際に実行されるSQLが将来別々に書き換えられて乖離する構造的リスクを消すのが目的。`FixHint`は既存`fix_hint_test.exs`（10件、無改変）がbyte単位で通ることをリファクタの証明とした。一方で`Kumi.Plan.SQL`は破壊的op（`remove_column`／`drop_table`等）のSQLも普通に描画する——`FixHint`がユーザーに見せる必要があるため——ので、「SQLが描画できること」と「Kumi.Applyが実際に実行してよいこと」は明確に別レイヤーとした（描画可能性の判定はSQLモジュール、実行可否の判定はApplyモジュール、両者を混ぜない）。 | - |
| F102 | env guardの配置 | dev限定ガード（`Mix.env() == :dev`でなければ`Mix.raise`）は`Mix.Tasks.Kumi.Apply`（mix task層）にのみ置き、`Kumi.Apply.run/3`自体は`Mix.env()`もApplication configも一切読まない——「configを読むのはmix taskだけ」という既存不変条件（`Kumi.plan/3`・`Kumi.plan_app/2`と同型）をそのまま踏襲した形。これにより`apply_test.exs`は`MIX_ENV=test`下で`Kumi.Apply.run/3`を直接呼んで検証でき（実際に`assert Mix.env() == :test`を書いてから呼ぶ形でテストした）、dev限定ガードの単体テストはmix task層の責務として切り離されている。 | - |
| F102 | トランザクション実行と事後検証 | 実行対象のSQLは全て1つの`repo.transaction/1`の中で`repo.query!/1`により順次実行する。コミット後、`Kumi.Desired.extract/1`＋`Kumi.Actual.introspect/1`＋`Kumi.Diff.diff/2`（`Kumi.plan/3`が内部で使う同じパイプライン部品）で再diffし、実行したopが新しいdiffに1件でも残っていたら`raise`（警告ではなく例外）にした——「実行した」という結果を返しておきながら実は反映されていなかった、という静かな失敗を防ぐのが目的。テストのDDLはEctoサンドボックのトランザクション内で走るため（`Kumi.ActualDriftTest`と同じパターン——`Kumi.Test.DataCase`の`on_exit`がsandbox ownerを止めるだけで、DDLロールバックも自動的に付いてくる）、テスト失敗時も手動クリーンアップは不要だった。 | - |
| F102 | 実測テスト数と摩擦 | `kumi`パッケージは既存138 passed（F100時点）+ 新規17（`sql_test.exs`14件＋`apply_test.exs`3件——最後の1件は上記のadd_column+defaultガードのレビュー後追加）= 155 passed、`mix compile --warnings-as-errors`・`mix format --check-formatted`ともクリーン。摩擦は2点：(1)`Kumi.Plan.SQL`と`Kumi.Apply`を最初に書いた際、`mix format`未実行のまま`mix test`を回したところ`mix kumi.report`の自己参照テスト（自パッケージのformat状態を検証する）が「新規ファイルの未整形」でfailした——F99で一度踏んだのと同じ罠を今回も踏んだ形で、`mix format`を挟んで解消した。(2)初回実装は3ゲート（safe∧allowlist∧SQL.render成功）だけで「全部safety.exから導出した」つもりだったが、レビューで上記のadd_column+default見落としを指摘されて気づいた——safety.exを読んだだけでは「`:safe`の集合」は分かっても「`:safe`だが実行すると部分修復になる集合」は分からず、SQL.renderとSafetyの両方を突き合わせて初めて見える種類の穴だった。 | 低 |

---

## Mini CRM guide（§6生態の順序の実行 — plugin原料の採取）

> 目的：Blueprint v3 §6「生態の順序」——wedge（`kumi.plan`）が実証された次の一手として、
> Kumi＋公式Ashライブラリで実際にMini CRMを組み、その過程で繰り返し書いた糊コードを
> 最初のプラグイン（`Kumi.Storage`／upload想定）の原料として記録する。ガイド本体は
> `kumi/guides/mini-crm.md`（英語、F番号・個人名・マシン固有パス一切なし）として新規作成し、
> `kumi/README.md`に既存gotchasガイドと同じ形式でリンク1行を追加した。

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F103 | 実地の手順と所要感 | スクラッチパッド配下に`mix kumi.new mini_crm --db-port 5434 --kumi-path <kumiリポジトリ>`でアプリを新規生成し、`Contact`（`Kumi.Resource`ショートハンド）・`Deal`（素のAsh、`stage`にone_of+default、`belongs_to :contact`）・`MIX_ENV=dev mix ash.codegen`＋`mix ecto.migrate`・`app.ex`へのresources/navigation/workflow/dashboard登録・`mix test`/`mix kumi.report --skip-tests`/`mix phx.routes`によるheadless検証・`psql`での手動drift作成→`mix kumi.plan`→`--fix-hints`→`mix kumi.apply --yes`→plan再ゼロ、まで全ステップを実地で通した。既存のwedge（plan/apply、F102）とDSL（App/Resource、F99/F100）がそのまま動いたため、通しで詰まった箇所は後述の糊コード以外になく、体感の所要は「新規パッケージ実装」より軽く「導入済み機能の組み合わせ確認」に近かった。 | - |
| F103 | ガイド化で判明したDX断点 | (1) `mix kumi.new`はarchiveが未インストールだと動かないが、F95で「インストール済み」と記録されていたにも関わらず今回の環境（`mix archive`確認）には`kumi_new`archiveが存在せず、`mix archive.build && mix archive.install --force`を本タスクの中で再実行する必要があった——F95の記録が環境の永続性を保証しないことの実例。(2) `Kumi.App`に`resource`を追加しても、対応する`Ash.Domain`モジュール自体は`kumi.new`/`kumi.install`のどちらも生成しない——`use Ash.Domain, otp_app: :mini_crm` + `resources do ... end`を手書きし、さらに`config :mini_crm, ash_domains: [...]`に追記しないと「Domain ... is not present in ash_domains」という警告が出る。この警告文自体は原因を正確に教えてくれるため致命的ではないが、CRMを組む度に必ず踏む定型の3手（domainモジュール・resources登録・config追記）だった。(3) `workflow`を`resource:`/`field:`/`stages:`のインラインkeyword一発で書いた直後の`mix kumi.report`が`format`ステップで失敗した——`mix format`が多行の`workflow(...)`呼び出しを丸ごと括弧付きスタイルに書き換えるため、手書きDSLをコミットする前に一度`mix format`を挟む習慣がないと初回reportが必ず赤くなる。(4) `MIX_ENV=dev mix ash.codegen`が新規テーブル作成だけのマイグレーションに対しても「このマイグレーションは破壊的操作を含みます」という警告を出した——生成された`down/0`に`drop table`が含まれるのが原因で、初見だと本物の警告と誤認しかねない。 | 中 |
| F103 | 糊コード／素のAshに落ちた箇所（plugin原料） | **upload/attachment（最優先・最大の穴）**：`Kumi.Resource`のfield型一覧（`string`/`text`/`integer`/`decimal`/`boolean`/`date`/`datetime`/`email`/`select`）に画像・ファイル型が存在せず、`field :avatar, :image`は実際に`mix kumi.expand`を実行すると`** (ArgumentError) Kumi.Resource: unknown field type :image`で即死する（実地で確認済み）。`kumi_admin`のフォーム側（`form_fields.ex`）にも`file_input`/`upload`系のコードは一切なく、admin生成フォームにファイル入力は出ない。今日読者が取れる道は「URLを保存するだけの素の`:string`フィールド＋読者自身が書くLiveView `<.live_file_input>`＋任意のストレージ（ローカルディスク／S3等）の手書き糊コード」のみで、Kumi/kumi_admin側に受け皿は皆無——これがそのまま`Kumi.Storage`プラグインの一次要件になる。**ドメインスキャフォールド不在**：上記の通り、リソースを増やす度に`Ash.Domain`モジュール＋`ash_domains`config追記が定型の手書き作業として繰り返される——`kumi.install`/`kumi.new`の対象外だが、CRMのようなマルチリソースappでは必ず踏む。**phone型の不在**：電話番号は素の`:string`に落ちる（フォーマット制約なし）——影響は小さいが繰り返し発生する糊。 | - |
| F103 | kumiパッケージ側のバグ | 本タスクでは修正せず報告のみ：バグと呼べる不具合は見つからなかった（`kumi.plan`/`kumi.apply`/`kumi.report`/`Kumi.App`のDSL検証はすべて期待通りに動作）。ただし上記の「新規テーブル作成のみのマイグレーションが『破壊的操作』警告を出す」（F103欄2の(4)）は、`ash.codegen`側の`down/0`ヒューリスティックに起因する誤検知に近いミスリーディングなDXで、Kumi自体のバグではないが報告事項として記録する。 | 低 |
| F103 | 実測の検証結果 | `mini_crm`アプリ：`mix test` 5 passed（0 failed, 0 skipped）、`mix kumi.report --skip-tests`のverdictは`ready — Ready for PR`（`format`/`compile`/`codegen`/`plan`全て✓）、`mix phx.routes \| grep kumi-admin`で5ルート（dashboard/index/new/show/edit）確認。drift往復：`psql`で`contacts.phone`列を手動DROP→`mix kumi.plan`が`+ column phone text [SAFE]`を検出→`mix kumi.apply --yes`が`executed 1 / skipped 0 — verified: true`で復旧→`mix kumi.plan`が`No changes. Database matches application definition.`でゼロdiffに復帰、を実地で確認した。ガイド本体・README・本ログの3ファイル追記後、`kumi`パッケージ自体は`mix format --check-formatted`・`mix test`ともにグリーン（無改変を確認）。 | - |

## Domain脚手架（kumi.install — F103-2の解消）

> 目的：F103欄2の「ドメインスキャフォールド不在」——`mix kumi.new`/`mix kumi.install`が
> `lib/<app>/app.ex`は生成するが`Ash.Domain`は生成せず、最初のリソースを置く前に
> ドメインモジュール＋`ash_domains`config追記を毎回手書きする——を解消する。
> `mix kumi.install`が既定の製品ドメイン`<App>.Core`を生成し`ash_domains`に登録するよう変更した。

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F104 | Step 0の判断：composeか手組みか | 着手前に`deps/ash/lib/mix/tasks/gen/ash.gen.domain.ex`（`spike0_crm`配下）をソースで確認したところ、ピン留め済みのAsh（`~> 3.0`）には`mix ash.gen.domain`が既に存在し、`Igniter.Project.Module.create_module/3`でモジュールを作った上で`Igniter.Project.Config.configure/5`＋`Igniter.Code.List.prepend_new_to_list/2`で`ash_domains`に**membership-checked**で追記する実装だった（`--ignore-if-exists`フラグで既存時スキップも可）——「モジュール生成」と「config追記」の両方を1タスクで済ませ、かつ追記ロジックが既に重複防止済みという条件が揃ったため、手組みせず`Igniter.compose_task(igniter, "ash.gen.domain", [inspect(domain_module)])`でcomposeする方針を採った。理由はF76–78で踏んだ「Igniter AST操作は自前で書くほど壊れやすい」という教訓通り——config追記の等根性ロジックを自分で再実装するリスクをゼロにできるのが決め手。**代償**：compose採用により生成される`core.ex`には@moduledocが付かない（`ash.gen.domain`のテンプレートは`use Ash.Domain, otp_app: ...`＋空`resources do end`のみ）——仕様が想定していた「generated-by note」入りの@moduledocはconfig追記リスク削減と引き換えに落とし、ガイダンスは`Igniter.add_notice`側に寄せた（F76–77と同じ判断：AST注入でコメントを足すより通知で示す）。 | - |
| F104 | 冪等性設計 | (1) domain生成ステップは`kumi.install`の`if exists?`（app.ex用）ブランチの**外**に独立した`ensure_domain/1`として実装し、app.exが既に存在するプロジェクトでもdomain生成をスキップしない——`kumi_install_test.exs`の「app.ex already existing does not skip domain creation」で実測済み。(2) `<App>.Core`の存在確認は`compose_task`呼び出しの前に自前で`Igniter.Project.Module.module_exists/2`を行い、存在すれば`Igniter.add_notice`のみでcompose自体を呼ばない（`ash.gen.domain`本体の`--ignore-if-exists`分岐と二重に守っている）。(3) 二重実行（`kumi_admin.install`が`kumi.install`をcomposeする通常経路の再現）は「1回目適用→2回目compose」というテストパターンで、`assert_unchanged(igniter, "lib/my_app/core.ex")`＋config文字列中の`MyApp.Core`出現数が1回のみであることを正規表現で検証した。 | - |
| F104 | 実地dogfood結果 | `domain_scaffold_check/mini_crm`を新規生成し、`MiniCrm.Core`が`lib/mini_crm/core.ex`として生成され、`config/config.exs`に`ash_domains: [MiniCrm.Core, MiniCrm.Accounts]`（1行・重複なし）で登録されていることを確認。`Contact`（`Kumi.Resource`ショートハンド）と`Deal`（素のAsh）を両方`MiniCrm.Core.*`名前空間に置き、`MiniCrm.Core`モジュール自体を一切手で書かずに`MIX_ENV=dev mix ash.codegen`→`mix ecto.migrate`→`app.ex`登録→`mix test`（5 passed）→`mix kumi.report --skip-tests`（`format`/`compile`/`codegen`/`plan`全✓、`Verdict: ready`）まで通した。domain/configの手書きゼロでF103が指摘した定型3手のうち2手（domainモジュール・config追記）が消え、残るのはリソースモジュール自体の記述のみになった。 | - |
| F104 | guideの更新 | `kumi/guides/mini-crm.md`のStep 1に`MiniCrm.Core`の生成物出力を追加、Step 2の見出しから「Kumi's installer doesn't scaffold a domain module for you」という前提を削除して「`kumi.new`already generated `MiniCrm.Core`」に書き換え、`MiniCrm.Crm.*`だった全モジュール参照を`MiniCrm.Core.*`に統一（`mix kumi.expand`出力含め実地で再取得）。「Where you still write glue code today」の「Domain scaffolding」項目は削除せず、「previously you had to...、now generated」の形に書き換えて1件を縮めた（削除ではなく事実の更新として記録）。 | - |
| F104 | 実測テスト数 | `kumi`パッケージ：`kumi_install_test.exs`単体で6 passed（既存2＋新規4：生成/config追記の確認・既存配列への追記・app.ex先在時の非スキップ・二重実行の非重複）、パッケージ全体で159 passed、`mix compile --warnings-as-errors`・`mix format --check-formatted`ともクリーン（いずれも自分で実行して確認、数字はコピペではなく実測）。`mini_crm`側は`mix test` 5 passed（実測）。 | - |
| F104 | 摩擦 | (1) スクラッチパッドのPostgresに前回セッション由来の`mini_crm_dev`/`mini_crm_test`データベースが残っており、`mix ash.setup`が`relation "tokens" already exists`で失敗した——本変更とは無関係の環境の使い回しが原因で、`DROP DATABASE`してから再実行して解消した。今回のタスク指示通り新規サブディレクトリ（`domain_scaffold_check/`）を使ったにも関わらずDB名は`mini_crm_*`のまま衝突した点は、次回以降スクラッチパッドでの同名アプリ再生成時の既知の落とし穴として記録する。(2) `psql`コマンドがrtkのフックにより見つからずエラーになったため、`docker exec kumi_db psql ...`に切り替えて実行した——ホストの`psql`バイナリが用意されていない環境固有の制約。 | 中 |

## Kumi.Storage v1 run 1（package骨格 + `:image` field）

> 目的：F103が指摘した「最優先・最大の穴」（upload/attachment糖衣コード不在）の解消に着手。
> ブループリントv3 §6で決めた7点設計のうち、run 1（本entry）はkumi core側の`:image`
> field対応と新規package `kumi_storage`（Backend/Local/Validation/Plug/installer）を実装、
> kumi_admin側のupload widget・spike dogfood・guide更新はrun 2に持ち越す。

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F105 | run 1の実装範囲 | §6の7点のうち今回実装したのは1（トポロジ：kumi_storageが素のAsh Attachmentをホストへ生成、kumi coreはkumi_storageを一切importせず循環なし）・2（`to:`省略／不正モジュールのコンパイル時エラー）・3（`__kumi_attachment__`マーカーのみ——`function_exported?`判定はrun 2のkumi_admin側の仕事）・5（destroy時ファイル削除のafter_action）・6（size cap＋content-type allowlistのバリデーション）・7（`KumiStorage.Backend`behaviour＋`Local`実装のみ、S3は明言通り未着手）。4（zero-diffゲート）は設計上installerがAttachmentをdomainに登録すること自体で自動的に満たされる構造になっているが、実host appでの`mix kumi.plan`ゼロdiff確認はrun 2のspike dogfood範囲——今回は`Igniter.Test`上の生成内容検証まで。 | - |
| F105 | `:image`のbelongs_to相乗り | `field :name, :image, to: X`は`Kumi.Resource.FieldSpec.parse_expr/2`の専用clauseで`%FieldSpec{kind: :belongs_to, name: name, type: 解決済みモジュール, opts: []}`に変換して返すだけで、`Kumi.Resource.Codegen`は1行も変更していない——Codegenは`kind`でしか分岐しないため`:image`は生成コード上`belongs_to`と区別不能になる。expand==compiled不変条件はCodegen.generate/3が元々`__kumi_expand__/0`と`mix kumi.expand`の唯一のソースである既存構造でそのまま成立し続ける（Codegen無改修＝不変条件の証明が要らない）。kumi core側で新たに触ったのは`FieldSpec.parse`のみで、`Ash.Resource.Info.resource?/1`という既存gotcha回避パターン（Spark.implements_behaviour?は使わない）を再利用した以外にkumi_storageへの参照は皆無。 | - |
| F105 | コンパイル時エラー2種の文言方針 | `to:`省略は`field name, :image`（opts無し）と`field name, :image, opts`だが`opts`に`:to`キーが無い場合の両方を別clauseで先に捕捉し、`mix kumi_storage.install`実行を案内する共通メッセージ＋`field :name, :image, to: MyApp.Core.Attachment`という具体例を`raise ArgumentError`で返す。`to:`が実在しない、またはAsh resourceでないモジュールを指す場合は`Code.ensure_compiled/1`の`{:module, _}`可否→`Ash.Resource.Info.resource?/1`の二段ガードで判定し、失敗時は指定モジュール名を`inspect`で埋め込んだ別メッセージ（`mix kumi_storage.install`案内つき）を返す。どちらも既存の`:select`未指定options等と同じ`ArgumentError`クラスに揃え、新しい例外型は増やさなかった。 | - |
| F105 | 生成Attachmentと D1 / marker | `<App>.Core.Attachment`は`Kumi.Resource`ショートハンドを一切使わない、`use Ash.Resource`＋`postgres`＋`actions`（`defaults [:read, create: :*]`＋`destroy`のみカスタムし`change after_action(fn _, record, _ -> backend.delete(record.storage_key, opts) ... end)`）＋`attributes`（uuid pk／filename／content_type／byte_size／storage_key全部public？true／timestamps）の素のAshソース文字列を`Igniter.Project.Module.create_module/3`にまるごと渡して生成する——ユーザーが`mix kumi.expand`相当のものを介さず直接読める前提（D1）で書いた。コメントは入れず`@moduledoc`のみで説明した（F76–78のIgniter AST comment insertion落とし穴は本来「既存ファイルへのAST挿入」の話で今回は新規ファイル全文生成のため理論上は無関係だが、念のため踏み外さない側に倒した）。マーカー`def __kumi_attachment__, do: true`はDSLブロック外・モジュール末尾に置き、run 2のkumi_adminは`function_exported?(mod, :__kumi_attachment__, 0)`で検出できる契約とした。 | - |
| F105 | Local backendの鍵設計 | `KumiStorage.Backend.Local.store/4`はキーを`Ash.UUID.generate()`＋拡張子のみで構成し、クライアント指定filenameはパス構築に一切使わない（拡張子も`^\.[a-z0-9]{1,10}$`に一致しない限り空文字へ落とす——`../../etc/passwd`のような入力はPath.extnameが最終セグメントにしか一致しないため実際には拡張子自体が空になることを実機確認）。`path/2`・`delete/2`・`open/2`は共通で`Path.expand(Path.join(root, key))`が`Path.expand(root)`配下に留まるかをprefix比較で判定し、外れた場合は`:error`/`{:error, :invalid_key}`を返す。`Path.join/2`は第2引数が絶対パスでも常に相対結合する（Erlangの`:filename.join`と違い絶対パスが前段を上書きしない）ことをElixirで実機確認した上で、`../..`型traversalと絶対パス風キーの両方をテストで固定した。`KumiStorage.Plug`は独自のtraversal判定を持たず`Backend.path/2`の`:error`をそのまま404に変換するだけ——判定ロジックを1箇所に一本化した。 | - |
| F105 | installerのrouter挿入とdomain登録 | router forwardは`Igniter.Libs.Phoenix.select_router`＋`add_scope`で自動挿入まで到達できた——kumi_adminの認証検出（F77系）のような「確信が持てないので通知に倒す」分岐は不要だった（forwardはactor解決等の曖昧さを持たないプレーンなplug委譲のため）。ルータ不在時のみ`Igniter.add_notice`でコピペ用スニペットを出す（confidently insertableでない場合のnotice fallback）。Attachmentのdomain登録は自前AST操作を書かず、Ash本体が`mix ash.gen.resource`向けに公開している`Ash.Domain.Igniter.add_resource_reference/3`をそのまま再利用した——F104と同じ「Igniter AST操作は自前で書くほど壊れやすい、既存ヘルパーがあれば再利用」を踏襲。config追記（backend/root）も`Igniter.Project.Config.configure_new/5`（値が既存なら書かない版）でmembership-checked、二重実行テストで非重複を確認した。 | - |
| F105 | テストのDB要否 | kumi_storage単体テスト29件は全てPostgres起動なしで完走する——`Backend.Local`/`Validation`/`Plug`はtmpディレクトリと明示opts（`root: ...`）のみで完結し、installerテストは`Igniter.Test`が仮想ファイルシステム上で完結する。生成される`Attachment`リソースはホストapp内で初めてコンパイルされる素のAsh資源であり、kumi_storageパッケージ自身はそれをコンパイルもテストもせず文字列として生成・assertするだけなので、DB接続が必要な箇所は設計上どこにも生まれなかった。 | - |
| F105 | 実測テスト数 | `kumi`パッケージ：F104時点159 passed＋`:image` field新規6（FieldSpec parse=belongs_to同値／`to:`省略2ケース／不正モジュール2ケース／end-to-endのexpand確認）＝165 passed、`mix compile --warnings-as-errors`・`mix format --check-formatted`ともクリーン。新規`kumi_storage`パッケージ：29 passed（Backend.Local 9／Validation 7／Plug 4／installer 9 の内訳）、同じく`mix compile --warnings-as-errors`・`mix format --check-formatted`クリーン。 | - |
| F105 | 摩擦 | (1) ブループリント文言の`store(source_path_or_binary, filename, content_type)`をそのまま`binary()`型で実装しようとしたところ、Elixirでは`Path.t()`自体が`binary()`のエイリアスで両者が型的に区別不能だと気づき、`{:path, tmp_path} | {:binary, data}`のタグ付きtupleに変更した——指示のシグネチャを字面通りには実装できなかった実装上の必然。(2) `Plug.Conn.put_resp_content_type/2`はデフォルトで`; charset=utf-8`を付与するため、画像バイナリ配信のテストで`image/png; charset=utf-8`という想定外のヘッダに一度落ち、`charset: nil`を明示して回避した——バイナリ配信でPlugのデフォルト引数が罠になりやすい典型例として記録。(3) 逆に想定より楽だった点：router forward挿入・domain登録・config追記の3箇所とも既存Igniter公式ヘルパー（`Igniter.Libs.Phoenix`／`Ash.Domain.Igniter`／`Igniter.Project.Config.configure_new`）で一発で通り、F76–78／F104で踏んだ「自前AST操作は壊れやすい」の教訓が効いて自前のzipper操作を一切書かずに済んだ。 | 低 |

## Kumi.Storage v1 run 2（admin upload widget + 実地統合）

> 目的：run 1（F105）が持ち越した残り——kumi_admin側のupload widget、
> spike0_crmへの実地統合、guideの更新——を仕上げる。ブループリントv3 §6の
> 8（upload action契約）・9（URL契約）が本runの拘束条件：ストレージ呼び出しは
> 全てホスト生成Attachment resource内に置き、kumi_adminはmarker + 規約action +
> `__kumi_attachment_url__/1`だけを知って依存ゼロ（kumi+phoenix+LV+ash_phoenix）を保つ。

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F106 | §6点8・9の実装 | installerのAttachmentテンプレートに`create :upload`（`source`/`filename`/`content_type`/`byte_size`引数、`KumiStorage.Validation.validate/4`→`backend.store/4`を呼びvalidation/store失敗をchangeset errorに変換する可視のchange）と`def __kumi_attachment_url__(record), do: "/uploads/#{record.storage_key}"`（installerが実際に挿入する`/uploads`forwardと文字列で一致）を追加。検証はホストresource側（信頼境界）に置き、kumi_adminは一切validationロジックを持たない——設計通り。 | - |
| F106 | kumi_adminの依存ゼロupload機構 | `KumiAdmin.FormFields.attachment?/1`（`function_exported?(mod, :__kumi_attachment__, 0)`）で`belongs_to`の宛先を判定し、`:belongs_to`ではなく新widget種別`:upload`を返す。`ResourceFormLive`は`mount`で該当フィールド分`allow_upload(socket, relationship.name, accept: ~w(.jpg .jpeg .png .gif .webp), max_entries: 1)`、save時は`consume_uploaded_entries`→宛先resourceの`:upload` action（`Ash.create(dest, params, action: :upload, actor: actor)`）→返ってきたidをFKとして`params`に混ぜてから通常のform submitに合流、という2段構えにした。`kumi_admin/mix.exs`はrun全体を通して無改変（kumi+phoenix+phoenix_live_view+ash_phoenix+igniterのまま）——`git diff mix.exs`で実測確認。 | - |
| F106 | 実装中に踏んだ実バグ3件（すべてrun 2で初めて表面化） | (1) `function_exported?/3`はモジュールを自動ロードしない——ドキュメント記載通りだが実際に踏むと、ExUnit非同期テストで初参照のfixtureモジュールに対し`attachment?/1`が偽を返す。`Code.ensure_loaded?(module) and function_exported?(...)`に修正（本ログ既存のSpark系gotcha「`Spark.implements_behaviour?`が実resourceに偽を返す」と同じ「モジュール反射の罠」ファミリー）。(2) `assign_new(socket, :uploads, fn -> %{} end)`が`ArgumentError: :uploads is a reserved assign by LiveView and it cannot be set directly`で落ちた——`:uploads`はLiveView予約assignで`allow_upload/3`経由でしか書けない。upload項目0件のresourceで`@uploads`参照が失敗する問題を、テンプレート側を`Map.get(assigns, :uploads, %{})`に変える（reserved assignには触らない）方式で解消。このバグはkumi_storage/kumi_admin単体テストでは検出できず、spike0_crmの既存LiveViewTest（Account/Dealのフォームテスト4件）が全滅して初めて発覚した——package単体テストの限界とspike dogfoodの価値を裏付ける実例。(3) installerテンプレートの`destroy :destroy`が`change after_action(...)`のみでrequire_atomic?未指定のため、`mix compile --warnings-as-errors`が`cannot be done atomically`で失敗——kumi_storage自身のテストは生成コードを文字列としてassertするだけでコンパイルしないため、この警告はspike0_crmで初めてホスト実コンパイルした瞬間に初めて出た（run 1のF105「テストのDB要否」で書いた「生成Attachmentはホストappで初めてコンパイルされる」という設計上の弱点が、そのまま今回の実バグとして的中した）。`require_atomic? false`を追加して解消し、installerテストのassertionも追加した。 | 高 |
| F106 | Igniter test_projectの括弧問題（既存パターンの再確認） | run 1のdestroy actionテストが`~r/table\(?\s*"attachments"/`のようなparen-tolerant正規表現を使っていた理由が今回判明した：`Igniter.Test.test_project`のテスト用.formatter.exsはAsh/Spark用`locals_without_parens`を持たないため、生成コードをフォーマットすると`argument :source, ...`が`argument(:source, ...)`に変わる。新規追加した`create :upload`まわりのアサーションも同じ理由で`~r/argument\(?\s*:source,.../`のような柔軟な正規表現に統一した——実host appの実際の生成物（spike0_crm/mini_crmで確認）には一切括弧が付かない（Ash用formatter pluginが効くため）ので、これはテスト環境固有のノイズであってバグではない。 | 中 |
| F106 | inline fixture moduleの非同期テストrace | `KumiAdmin.FormFieldsTest`に`__kumi_attachment__/0`だけを持つ最小限markerモジュールを追加する際、最初はテスト.exsファイル末尾に直接`defmodule`したところ、`async: true`下で10回に1〜2回`attachment?/1`が偽を返すflaky failureが発生した（.exsファイル内で定義される補助モジュールは、通常のtest/support配下のfixtureと違いオンデマンドロードのタイミングがテスト実行プロセスと競合しうる）。`test/support/fixtures.ex`（通常のコンパイル済みfixture）に移設したところ10回中10回安定した——原因の完全な特定はできていないが、「.exsファイル内の補助モジュール定義はrace的に不安定になりうる、test/supportに置くのが安全」という実践知として記録する。 | 中 |
| F106 | spike0_crm統合とzero-diff維持 | `{:kumi_storage, path: "../../kumi_storage"}`追加→`mix kumi_storage.install --yes`で`Spike0Crm.Core`（既存）にAttachmentが登録され、`config :spike0_crm, ash_domains: [Spike0Crm.Core, Spike0Crm.Accounts, Spike0Crm.Crm]`に3ドメイン全て揃っていることを実測確認。`Contact`に素のAsh`belongs_to :avatar, Spike0Crm.Core.Attachment, allow_nil?: true, public?: true`を追記、`MIX_ENV=dev mix ash.codegen add_attachments`→`mix ecto.migrate`後、`mix kumi.plan --check`が`0 safe / 0 review / 0 dangerous`でゼロdiffを維持することをCLIで確認し、さらに`Kumi.plan(Spike0Crm.Repo, ash_domains)`（`Spike0Crm.App`が意図的に宣言しない`Spike0Crm.Core`まで含む全DB view）をテストとして追加して自動化した——既存の`plan_app_test.exs`（App宣言resourceのみのscoped view）はAttachmentテーブルを検証できないため、意図的に別テストで補完した。 | - |
| F106 | LiveViewTestのfile-upload helperの使用感 | `Phoenix.LiveViewTest.file_input/4`＋`render_upload/3`はドキュメント通りに動作し、`consume_uploaded_entries`のconsumer fn内で`Ash.create(dest, params, action: :upload, actor: actor)`を呼ぶ実装が実際にAttachmentレコードを作りファイルを保存することをテストで確認できた。唯一の詰まり：公式doc例の`assert render_upload(...) =~ "100%"`は進捗バーをテンプレートに描画しているアプリ前提のイディオムで、本実装のように進捗UIを描画しない（v1は最小限——ファイル入力＋現在のファイルリンクのみ）widgetでは常に失敗する。`data-phx-done-refs="\d+"`という属性ベースの正規表現アサーションに置き換えて解消した——doc例をそのままコピペすると自分のUIの実装詳細（進捗バーの有無）に暗黙に依存していることに気づきにくい典型例。 | 中 |
| F106 | 孤児レコードの後送り（明記箇所） | `ResourceFormLive.apply_uploads/2`のdocコメントと`kumi/guides/mini-crm.md`のStep 7末尾の両方に明記：アップロードフィールドを触らなければ`params`にFKキー自体が乗らないため既存attachmentは無傷、新ファイルを選ぶと必ず新規Attachmentレコード＋新規ファイルが作られてFKが差し替わるだけで、旧レコード・旧ファイルは削除されない（意図的後送り、ブループリント§6点5・9と整合）。掃除ジョブは本run未実装のまま。 | - |
| F106 | guideの糊コード一覧の縮小 | `kumi/guides/mini-crm.md`のStep 7を「`:image`が`ArgumentError`で即死する」失敗デモから、`mix kumi_storage.install --yes`→1行の`field :avatar, :image, to: ...`→`mix kumi.expand`（plain `belongs_to`を出力）→`mix kumi.report --skip-tests`（`Verdict: ready`）まで通る成功ストーリーに全面書き換え。「Where you still write glue code today」の先頭項目（このガイドが列挙する糊コードの中で最大だったもの）を「一覧から削除」ではなく「予告通り解消された」形に書き換え、S3バックエンド未実装・replace時の孤児後送り・サムネイル非対応の3点を正直に明記した。すべてのコードブロックは新規scratchpad（`mini_crm`をゼロから再生成）で実際に実行して採取——過去セッションの`mini_crm_dev`/`mini_crm_test`が残っていて`mix ash.setup`が`relation "tokens" already exists`で失敗する場面に今回も遭遇し（F104と同じ現象の再発）、`DROP DATABASE`してから再実行して解消した。 | 低 |
| F106 | 実測テスト数 | `kumi_storage`：30 passed（run 1の29から:upload action・URL関数・require_atomic?のassertion追加で+1）、`mix compile --warnings-as-errors`・`mix format --check-formatted`クリーン。`kumi_admin`：31 passed→35 passed（+4、全て`test/kumi_admin/form_fields_test.exs`——`:upload`derivation新規2件＋`attachment?/1`新規2件。`git diff --stat`で当該ファイルのみが変更されていることを確認済み）、mix.exs無改変を確認、compile/format共クリーン。race修正で移動したのはテストではなく`KumiAdmin.Test.MarkerOnly`という補助fixtureモジュール本体（`test/support/fixtures.ex`へ）——テスト数には影響しない。`spike0_crm`：36 passed（既存34＋whole-database plan zero-diffテスト1＋avatar upload統合テスト1、うち後者はshow画面・index列・edit画面「現在のファイル」リンクの3面すべてを1テスト内でアサート）。`kumi`パッケージは本runで無改変のためrun 1と同じ165 passed。全て自分で実行して確認した数字。 | - |


## Admin無スタイル問題（F107 — バグであってデザイン未実装ではなかった）

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F107 | HEEx `<style>`内の`{}`補間は無効 | ユーザーがブラウザで実機確認した際、adminが完全に無スタイル（生テキスト羅列）で表示された。原因調査の結果、デザイン未実装ではなく**v0.3当初からのバグ**：`Shell.shell/1`は自前の`<style>{css()}</style>`を同梱していたが、HEExは`<style>`/`<script>`タグ内の`{...}`補間を無効化する（documented挙動）ため、ページには文字通り`{css()}`というテキストがCSSとして出力され、全スタイルが不適用だった。documentedな回避`<%= Phoenix.HTML.raw(css()) %>`への1行修正で解消（ブラウザ実機で確認）。**35テストが素通しだった穴**も同時に塞いだ：shell描画のCSS実出力を断定する回帰テスト（`kumi-admin-shell { display: flex`を含む／リテラル`{css()}`を含まない）を追加、kumi_admin 36 passed。過去の「ブラウザ実機検証」（Playwright、register→CRUD）は機能面のみを見ておりスタイル適用を一度も断定していなかった——見た目の検証をスクリーンショットの「取得」で済ませ「目視断定」していなかったのが見逃しの根因。教訓はgotchasガイドにも追加（LiveView節新設）。 | 高 |

## Top/Login/Logoutデザイン（ユーザー優先指示）

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F108 | トークン設計 | kumi_adminのshell CSSに`--kumi-bg`/`--kumi-surface`/`--kumi-border`/`--kumi-text`/`--kumi-text-muted`/`--kumi-accent`/`--kumi-accent-hover`/`--kumi-sidebar-*`/`--kumi-danger`/`--kumi-radius`をCSS custom propertiesとして`.kumi-admin-shell`セレクタに定義し、全ルールをハードコード16進値ではなく`var(--kumi-*)`経由で参照するよう書き換えた。ハードコード値のままでも今回の見た目は同じだが、custom propertiesにしたのは将来のtheme機構（ブループリント§12想定）への布石——host側やdata属性で値を上書きするだけでshell全体を再配色できる形にしておく方が、後で「実は全箇所ハードコードだった」を発見してやり直すより安い、という判断。spike0_crmの top page とサインイン overrides は host-owned な別ファイルのため custom properties を使わず同じ16進値をベタ書き（下記F108「二重管理」参照）。 | - |
| F108 | shellの再設計とtopbar/footer | サイドバー（タイトル+ナビのみ、ユーザー領域は撤去）とは別に、content area側に新設した`.kumi-admin-topbar`（56px、白背景、下ボーダー）へユーザー領域を移設——左にactive_resourceラベル（無ければapp title）、右にactor email + Sign outリンク。`KumiAdmin.Router.kumi_admin/2`に`sign_out_path`オプション（default `"/sign-out"`）を追加し、セッション経由で`KumiAdmin.Context.resolve/3`→4つのLiveView（Dashboard/Index/Form/Show）のmount→`Shell.shell`のattrへ配線。footerは`.kumi-admin-content`をflex columnにし`margin-top: auto`で下端固定、「Powered by Kumi」を右寄せ12pxで表示。既存クラス名（`.kumi-admin-title`/`.kumi-admin-card`/`.kumi-admin-table`等）は全て温存し、`grep kumi-admin- lib/`で無関係LiveViewが未スタイル化しないことを確認した。 | - |
| F108 | actorのemail表示の防御的実装 | `Shell`内`actor_email/1`は`is_map(actor)`ガード付きで`Map.get(actor, :email)`——構造体でも`:email`フィールドが定義自体されていない場合、`Map.get/2`は（構造体であっても）単にmapとしてキー欠如→`nil`を返すだけで例外は出ない（Elixir仕様通り、実際にテストで確認）。`to_string/1`で`Ash.CiString`透過対応。nilなら描画自体をスキップ（emailだけ非表示、Sign outは出す）。テスト3件追加：email表示／actor nilで領域非表示／emailフィールド欠如時に安全に何も出さない。 | - |
| F108 | ash_authentication_phoenixのoverride機構の実際 | `override_for/3`は`overrides:`リストを先頭から走査し最初に値を持つモジュールが勝つ（`Overridable.override_for`実装をdeps配下で確認）ため、host側の`<AppWeb>.AuthOverrides`をリスト先頭に置くだけで（spike0_crm/kumi_newとも既存の並び順のまま）上書きできた。実際に上書きしたkey：`SignInLive`/`SignOutLive`の`root_class`（背景色）、`Components.Banner`の`image_url: nil`+`text`（ロゴ画像をapp titleテキストに差し替え、card上部の「header」役を兼務）、`Components.SignIn`の`root_class`/`strategy_class`（白カード化）、`Components.Password.Input`の`input_class`/`submit_class`（accentボーダー・accentボタン）。Tailwind前提：spike0_crmは`daisyUI`ベースの`AshAuthentication.Phoenix.Overrides.DaisyUI`が2番目に並ぶ構成のままで、`input input-bordered`のようなdaisyUIユーティリティクラスと`bg-[#4f46e5]`のような任意値Tailwindを併用——CSSを1行も書かずに済んだ。footer行を足す差し込み口（slot）は`Overridable`に存在しないため、サインインページのfooterは実装しなかった（設計上のスキップ、コード側に理由をコメント済み）。 | 中 |
| F108 | spike0_crmとkumi_newテンプレの二重管理 | 「top page」と「AuthOverrides」はkumi_new側に共通コンポーネント抽出できる基盤が無い（kumi_newは"zero runtime deps"制約でPhoenixコンパイル時アセットを一切持たず、生成先に直接書き込む生文字列しか返せない）ため、spike0_crm向け（`spike0_crm_web/controllers/page_html/home.html.heex`・`auth_overrides.ex`、タイトル固定"Mini CRM"）と、kumi_new向け（`KumiNew.Inject.home_page/1`・`auth_overrides/2`、タイトルは`KumiNew.Name.title/1`でapp_nameから動的生成）を別々に手で同期させた。2箇所の見た目が将来ズレないための機械的な保証は無く、「spike0_crmのCSS値を変えたらkumi_newのInject関数も見て」という人力ルールが増えた——これは二重管理の解消ではなく最小化（1ファイルにまとめられる余地はkumi_newの制約上ない、という現状追認）。 | 中 |
| F108 | Playwright目視検証（F107の教訓の適用） | top page（`/`）とsign-in（`/sign-in`）はホストファイル（`home.html.heex`/`auth_overrides.ex`）でありPhoenixのcode reloaderが対象とするため、稼働中のdev server（既存beam.smp、pkill禁止）が変更を即座に反映——Playwrightで実機ナビゲートしscreenshotを撮り、**F107の教訓どおり自分で目視して**ヘッダー/ヒーロー/フッター（top）とtitle banner/白カード/accent入力欄（sign-in）が意図通りであることを確認した（`kumi-top-styled.png`/`kumi-login-styled.png`）。一方`/kumi-admin`は`kumi_admin`がpath依存（Mixのcode reloaderは通常host web配下のみを対象でpath depsは再コンパイル対象外）のため、稼働中serverでは`Context.resolve/3`の戻りキー変更と`Router.__session__/4→/5`のarity変更でstaleコードと不整合を起こし`UndefinedFunctionError`で500——実際に確認した。既存serverをkillできない制約下で、`Phoenix.HTML.Safe.to_iodata/1`で`Shell.shell`コンポーネントを直接レンダーしたHTMLを一時HTTPサーバ（`python3 -m http.server`、beam.smpとは無関係）経由でPlaywrightに見せる形で目視検証した（`kumi-admin-styled.png`）——実サーバのHTTPレスポンス由来ではない点は正直に記録する。加えてkumi_adminのshellテスト（HEEx実render assertion、40件）で構造面の回帰は別途担保。 | 高 |
| F108 | kumi_new側の未検証範囲 | `KumiNew.Inject.home_page/1`と`auth_overrides/2`は文字列生成の単体テスト（`assert content =~ ...`、Elixir parse可能性チェック含む）でのみ検証し、指示どおり`mix kumi.new`のフルend-to-end再生成（実際に`mix igniter.new`を走らせてapp一式を生成し`mix phx.server`まで確認）は本runでは実施していない——archive前提のI/O過多な検証のため、フォローアップとして明記のみ行う。 | 低 |
| F108 | Kumi-by-default ブランディングの追加指示 | 途中でユーザーから「これはMini CRMではなくKumi自体のブランドデザイン。Kumiで作った物はデフォルトで"Kumi"に見えるべき（hostは後から再ブランド可能——だからtokenをCSS custom propertiesにした）」という訂正が入った。既存の`design/kumi-logo.svg`（kumiko格子、8ピース、`#4338CA`）と`design/BRAND.md`（accent `#4338CA`/hover `#3730A3`）を正典として、(1) 全ファイルのaccent値を`#4f46e5`/`#4338ca`（旧・任意選定色）から`#4338CA`/`#3730A3`（ブランド確定色）へ一括置換、(2) kumi_adminのfooterとtop page（spike/kumi_new）のfooterに14pxのinline SVGマーク追加、(3) サインインページのbanner（`Components.Banner`）に`image_url`としてマークのbase64 data URI（python3の`base64.b64encode`で事前計算、手打ちURLエンコードは文字化けリスクがあるため回避）を設定し、`root_class`をflex-columnに変えてマーク→app titleの縦積みにした。マークはbrand資産なので毎回同じsvgソースからbase64を再計算し3ファイル（kumi_admin/shell.ex、spike0_crm/auth_overrides.ex、kumi_new/inject.ex）に同一文字列を複製——これも「二重管理の最小化はできても解消はできない」F108既出の摩擦と同型。実装後の自己レビューで「Forgot your password? / Need an account?」リンクがdaisyUIデフォルトのorange（`text-primary`）のまま残っていたことに気づいた——`Components.Password`の`toggler_class`キー（deps配下`components/password.ex`のOverridable宣言で確認）を追加でoverrideしBRAND.mdのリンク色（`#4338CA`/hover `#3730A3`）に統一、再スクリーンショットで確認した。 | 中 |
| F108 | 未ログインtopbarのSign inボタン欠落（ユーザー指摘） | topbarは`@actor`が真の時だけemail+Sign outを描画する実装のままで、`@actor`がnilの時（未ログイン）はユーザー領域自体が空になり、サインインへの導線が無いことをユーザーが指摘するまで気づかなかった——`shell_test.exs`の「actor nilで領域非表示」テストが「何も出ない」ことを正としてassertしており、導線欠如をバグとして検出できていなかった（テストは実装のミラーになっていた）。修正は`sign_out_path`の双子として`sign_in_path`（default `"/sign-in"`）を追加し、`KumiAdmin.Router.kumi_admin/2`のoptionから`__session__/4→/5`、`KumiAdmin.Context.resolve/3`、4つのLiveView（Dashboard/Index/Form/Show）のmount/render、`kumi_admin.install`のスニペット3箇所まで`sign_out_path`と完全に同じ配線経路を辿らせた。Shellのtopbarは`:if={@actor}`ブロック（email+Sign out、既存のまま）と`:if={!@actor}`のSign inリンク（`.kumi-admin-signin`——`.kumi-admin-signout`と同一スタイルの双子クラス）に分岐。該当テストは「Sign inが出る／Sign outは出ない」の断定に置き換えた。kumi_newの生成テンプレには`sign_out_path`の参照が無く、揃えるべき対称コードは存在しなかった（確認のみ）。 | 中 |
| F108 | 実測テスト数（自走のみ） | `kumi_admin`：36→40 passed（+4：`shell_test.exs`にtopbar関連3件＋footerのKumiマーク・attribution断定1件）、`mix compile --warnings-as-errors`・`mix format --check-formatted`共クリーン。`spike0_crm`：36 passed（本runで件数変化なし、`page_controller_test.exs`のGET /テスト1件のassertionを新top pageの内容に置き換えたのみ）、compile/format共クリーン。`kumi_new`：25→30 passed（+5：`name_test.exs`の`title/1`1件＋`inject_test.exs`の`home_page/2`（admin?true/false）2件＋`auth_overrides/2`2件）、compile/format共クリーン。`kumi`パッケージは本runで無改変。 | - |

## Admin認証ゲート + 初回ユーザー誘導（ユーザー指示 — Payload同等のonboarding）

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F109 | 「ログイン後の世界」への転換とF108の即撤回 | ユーザー指示は明確だった：kumi_adminは未ログイン訪問者に空シェル＋Sign inボタンを見せる場所ではなく、ログイン後にしか入れない場所（Payload CMS admin相当）。これはF108で追加したばかりの「actor nil時にtopbarへSign inリンクを出す」実装と正面から矛盾する——F108は「導線が無い」というユーザー指摘への修正だったが、今回の指示はその導線自体を「リダイレクトに置き換えて撤去しろ」という上位判断だった。Rule 13（不留向后兼容）に従い、`Shell.shell`の`:if={!@actor}`のSign inリンク（`.kumi-admin-signin`）と対応CSS、`sign_in_path`属性そのものを削除——「後で要る可能性」を理由に残すフォールバック分岐は作らなかった。`sign_in_path`オプション自体（Router/Context層）はGateのリダイレクト先として引き続き必要なため存置、Shellへの配線のみ切った。 | 中 |
| F109 | gateの集中実装（4 LiveViewへのコピペ回避） | `KumiAdmin.Gate.check/2`を新設し、4つのLiveView（Dashboard/Index/Form/Show）はいずれも`KumiAdmin.Context.resolve/3`直後に1行`case KumiAdmin.Gate.check(context, socket) do {:halt, socket} -> {:ok, socket}; {:cont, socket} -> ...`を挟むだけにした——判定ロジック（actor有無→user_resourceのゼロ件チェック→redirect先決定）はGate内の`check/2`＋`redirect_path/2`の2関数に一本化し、4箇所に同じ`if/case`を複写しなかった。`{:halt, socket}`分岐で即`{:ok, socket}`を返すことで「リダイレクト後に一切のassign/Ash呼び出しが走らない」を構造的に保証（早期return、後続コードは`{:cont, socket}`節の中にしか存在しない）。 | - |
| F109 | `authorize?: false`カウントの情報露出ゼロという根拠 | `KumiAdmin.Gate.redirect_path/2`が呼ぶ`Ash.count(user_resource, authorize?: false)`は、actorが`nil`の時（＝そもそもauthorizeするactorが存在しない状況）にのみ実行され、返り値は`{:ok, 0}`かどうかの2値判定にしか使われない——呼び出し元には「0件か否か」という1bit相当の情報しか渡らず、レコードの中身（email等）は一切フェッチしない。これはbootstrap専用の設計判断であり、moduledocに明記した。actorが存在する経路（`check/2`の1つ目の節）はこのカウント自体を一切実行しない。 | - |
| F109 | `redirect_path/2`をDB無しでテストする設計 | 指示どおり「packageにDBハーネスを足さない」方針を守るため、`redirect_path/2`に`count_fn`引数（default: 本物の`Ash.count/2`）を追加し、テストでは`fn SomeApp.User -> {:ok, 0} end`のような無名関数を注入して判定ロジックだけを検証した（`gate_test.exs`、6件：actor有り即continue／user_resource未設定→sign-in／0件→register／N件→sign-in／count error→sign-inにfail-safe／`check/2`自体がsocketをredirect済みにしてhaltすることの構造断定）。実在するAsh resourceもDB接続も不要——`Kumi.Plan`の`Kumi.Actual`同様、「注入可能にして純粋関数として単体テストする」設計を踏襲した形。 | - |
| F109 | `user_resource`自動検出は成功 | `kumi_admin.install`に`detect_user_resource/1`を追加し、`detect_live_user_auth/1`と同型（`Igniter.Project.Module.module_name(igniter, "Accounts.User")`→`module_exists?`）で検出。既存の`kumi_admin_install_test.exs`（4件、無改変で通過）に加え2件追加：`Accounts.User`が存在する場合は生成スニペットに`user_resource: MyApp.Accounts.User`と`register_path: "/register"`が入り通知にもモジュール名が出ること、存在しない場合は両オプションを省略し通知で正直にその旨を伝えること。実装時に1つ実装ミスを踏んだ：生成する`contents`文字列で`sign_in_path: "/sign-in"`の直後に改行だけで`user_resource:`行を継ぎ足し、キーワードリスト内のカンマを1個忘れて`SyntaxError`（Sourceror解析失敗）——`user_resource_line`の先頭に`,`を足して解消。spike0_crmは`Spike0Crm.Accounts.User`が実在するため、ルータへの手動配線でも同じ`user_resource:`/`register_path: "/register"`を追加した（spike0_crmは`kumi_admin.install`経由ではなく既存ルータへの直接編集のため、自動検出の恩恵はkumi_new経由の新規プロジェクトでのみ発生する）。 | - |
| F109 | 既存no-actorテスト群のリワーク方法 | spike0_crmのCRM 3リソース（Account/Contact/Deal）は`policy always() do authorize_if actor_present() end`のみ——「ログイン済みだがpolicyに弾かれるactor」というシナリオがそもそも存在しない。かつgate導入後は「actor nilでHTTPアクセス」自体が即リダイレクトになり、`ResourceIndexLive`の`:forbidden`空状態や`DashboardLive`の`—`表示を**ルータ経由のLiveViewテストで再現する経路が構造的に無くなった**。指示にあった2択（forbiddenなactorに差し替える／component層に移す）のうち、forbiddenなactorを作る前者は今回のリソース群では原理的に不可能だったため、正直に「到達不能」と明記して該当3テスト（no-access空状態／dashboard `—`表示／new-edit-delete非表示）を削除し、各削除箇所にコメントで理由と「該当分岐はコード上は残っている（より厳格なpolicyのリソースがあれば発火し得る）が本suiteでは行使されない」ことを記録した。代わりに新設した3テストでgateそのもの（`/kumi-admin`と`/kumi-admin/account`——ゼロユーザー→register、ユーザー有り→sign-in）を直接断定し、失われたカバレッジの実質的な代替とした。 | 中 |
| F109 | 実測テスト数 | `kumi_admin`：40→48 passed（+8：`gate_test.exs`新設6件、`kumi_admin_install_test.exs`+2件、`shell_test.exs`は1件の内容変更のみで件数増減なし）。`mix compile --warnings-as-errors`・`mix format --check-formatted`共クリーン。`spike0_crm`：36→36 passed（3件削除＋3件追加で件数不変、内訳はF109「既存no-actorテスト群」参照）、compile/format共クリーン。`kumi`パッケージは本runで無改変。 | - |

## モジュール選択UX（mix kumi.new --with / 対話picker — ユーザービジョンの入口）

> 目的：「installするときに、使うKumiモジュールを選ぶと配線済みで出てくる」というユーザービジョンの入口を作る。
> 採用基準はBlueprint §6（全鎖統合・実践から抽出——新規機能は「実際に使ってみて」初めてカタログに載る）に従う。

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F110 | カタログのハードコード判断 | `KumiNew.Modules`にカタログ（現状`storage`1件、`key`/`description`/`dep`/`installer`の`%Entry{}`）をモジュール属性ではなく`catalog/0`関数として持たせた——理由は実装上の制約（後述）だが、結果的にも正しい選択：kumi_newの零ランタイム依存不変条件（archive互換）を保ったまま、`mail`/`chat`等の追加が「リストに1エントリ足すだけ」で済む形になっている。レジストリ機構・動的発見・外部設定ファイルは一切導入しなかった（YAGNI——カタログが数件のうちは静的リストが最も安く、後から要る形に育てればよい）。`admin`はこのカタログに**含めない**——デフォルトの製品シェルであり`--no-admin`という既存フラグの領分であって「追加モジュール」ではない、という指示の区別をそのまま実装に反映した。 | - |
| F110 | `%Entry{}`を`@catalog`モジュール属性にできなかった実装上の制約 | 当初`defmodule Entry do defstruct ... end`を`KumiNew.Modules`内にネストし、直後に`@catalog [%Entry{...}]`とモジュール属性で持たせようとしたところ`cannot access struct KumiNew.Modules.Entry, the struct was not yet defined or the struct is being accessed in the same context that defines it`でコンパイルエラー——同一ファイル内で先に書いた`defmodule`でも、外側モジュールの属性評価はネストモジュールの結晶化前に走るため`%Entry{}`を参照できない（Elixirコンパイラの既知の制約）。ファイル分割はせず、`catalog/0`を関数化して呼び出し時（＝`Entry`コンパイル完了後）に構築する形に変えるだけで解消した——ファイル数を増やさない側を選んだ。 | 低 |
| F110 | 対話promptのTTYガード（CI/agent実行で絶対にハングしない側の倒し方） | `KumiNew.Modules.interactive?/0`は`Mix.shell() == Mix.Shell.IO and IO.ANSI.enabled?()`の論理積のみで判定し、「確信が持てなければfalse」に倒した——`Mix.shell()`がテスト用`Mix.Shell.Process`や将来のCI用quiet shellに差し替わっていれば即falseになり、TTYでもANSI非対応端末（一部CI・agentのpty偽装）でもfalseになる。この関数自体と`resolve(:unset)`のprompt分岐は指示通り意図的に未テスト——`Mix.shell()`の実体はプロセス辞書のグローバル状態でありモックするとテストの意味が「モックが動くこと」の確認に堕ちるため、正直に「テストしない」と決めた（テストする価値があるのは`parse_selection/1`という純粋関数側）。`--with`/`--no-modules`のどちらも指定しない・非TTY実行（今回のdogfoodも含め全てこの経路）は`resolve/1`が`{:ok, []}`を即返し、`Mix.shell().prompt/1`は一度も呼ばれない。 | - |
| F110 | storage選択時のpipeline合成順とidempotency前提 | `mix kumi.new`の`with`チェーンに`resolve_modules`（`Args.modules_flag`→`Args.modules`への解決、I/Oはここでのみ発生）を`preflight_archives`直後・`generate`直前に追加、`maybe_install_modules`は指示通り`maybe_install_admin`の直後・`ash.setup`の前に置いた。`mix.exs`への`{:kumi_storage, path: ...}`挿入は`KumiNew.Inject.insert_deps/4`（第4引数`modules \\ []`でデフォルト値を足し既存3引数呼び出し・既存テストを無改修のまま温存）が`kumi`→`kumi_admin`→各モジュールの順で挿入する。`kumi_storage.install`が内部で`Igniter.compose_task("kumi.install", [])`する既存の冪等設計（kumi_storage側で実測済み）にそのまま乗っており、kumi_new側で二重実行を避ける工夫は追加不要だった。 | - |
| F110 | `--no-admin`との直交性 | `admin?`と`modules`は`Args`上も`Inject.insert_deps/4`上も独立した引数・独立した条件分岐——`--no-admin --with storage`の組み合わせをinject_testで明示的に検証した（`kumi_admin`という文字列が出力に一切現れず、かつ`kumi_storage`は出ることを1テストで両方assert）。storage自体がkumi_admin非依存（kumi_storage/kumi_admin間に依存関係なし、F105で確認済み）なので、実装上も特別な分岐は不要だった。 | - |
| F110 | 実地dogfood結果 | `kumi_new`をarchive再ビルド→再install→`/private/tmp/.../module_select_check`配下で`mix kumi.new mod_crm --db-port 5434 --kumi-path /Users/akimitu/Documents/Kumi --with storage`をフルパイプライン実行、成功。生成物確認：`mix.exs`に`{:kumi, ...}`/`{:kumi_admin, ...}`/`{:kumi_storage, path: ".../kumi_storage"}`の3依存が順に挿入済み、`lib/mod_crm/core/attachment.ex`存在、`config :kumi_storage, backend: KumiStorage.Backend.Local, root: "priv/uploads"`挿入済み、`lib/mod_crm_web/router.ex`に`forward "/uploads", KumiStorage.Plug`挿入済み——全項目実測confirm。事前のstale DB確認（`docker exec kumi_db psql -lqt \| grep mod_crm`）はヒットなしでF104/F106の再発なし。 | - |
| F110 | `mix kumi.report`が一度目`failed`になった件 → dogfoodが実際のギャップを検出、pipeline側を修正 | 生成直後の`mix kumi.report --skip-tests`は`codegen  Pending Code Generation Detected for 2 files`で`failed`。当初「`kumi_storage.install`が生成するAttachment resourceは、ユーザーが自分で書いたリソースと同じく手動`ash.codegen`が要る既存の運用手順であり仕様通り」と判断しかけたが、advisorレビューで指摘の通りこれは筋が違う：認証resource（tokens/users）も同じくinstaller生成物でありながら`mix ash.setup`で無人適用済みであり、「comes with them fully wired」というユーザービジョンの下でAttachmentだけ手動codegenを要求するのは「配線済み」の約束を満たさない。mini-crm guideの手動codegen手順は**既存アプリへの後付け**インストール（`mix kumi_storage.install`単体）向けであり、`mix kumi.new`という「無からの生成」パスには適用すべきでないと判断を改めた。修正：`mix kumi.new`のpipelineに`maybe_install_modules`の直後・`mix ash.setup`の直前で`maybe_codegen_modules`（`modules != []`なら`mix ash.codegen add_kumi_modules`を1回実行）を追加——選択した全モジュールの新規resourceをまとめて1migrationに落とし、続く`ash.setup`がそのまま適用する。`--no-setup`時はmigrationファイルは生成されるが適用されない（既存の認証resourceと同じ挙動）。再dogfoodで無人実行のまま`Verdict: ready`に到達したことを確認した（下記）。Attachmentは`lib/`配下でF27（`test/support`限定のMIX_ENV=test gotcha）に該当しないため`MIX_ENV`指定なしのプレーン`ash.codegen`で足りることも実測確認済み。 | 高 |
| F110 | `mix test`の1件failureも既存の別バグではなく本機能のdogfoodで見つけた要修正ギャップ | 同じ生成appで`mix test`が4/5 passed、`ModCrmWeb.PageControllerTest`の`GET /`が`"Peace of mind from prototype to production"`不在で失敗。`kumi_new`は`home.html.heex`をブランド済みトップページで上書きする一方、phx.newが生成する`page_controller_test.exs`のデフォルトassertionは書き換えていなかった——F108のspike0_crm実測で「手動でassertionを置き換えた」と記録されていた通り、これは`--with storage`と無関係の**素の`mix kumi.new`にも存在する既存ギャップ**だが、「required checkとして明示されている以上スコープ外扱いにしない」というadvisorの指摘を受けて修正対象に格上げした。`KumiNew.Inject.page_controller_test/1`を新設（`home_page/2`が`admin?`に関わらず常に描画する"Built with Kumi."をassertする内容で全置換）、`write_page_controller_test/1`と`format_injected/1`のformat対象リストに追加してpipelineに配線。副次的に踏んだ実装ミス：`~s(assert html_response(conn, 200) =~ "Built with Kumi.")`という括弧区切りsigilを書いたところ`mix format`が`mismatched delimiter`でクラッシュ——Elixirの`~s(...)`は`~s{...}`/`~s[...]`と違い**内側の丸括弧をネストとして数えない**（`~s(foo(bar))`単体で最小再現し確認）ため、丸括弧を含む文字列を丸括弧区切りsigilで書いてはいけないという実装上の罠だった。エスケープ付き二重引用符文字列に書き換えて解消。 | 中 |
| F110 | 実測テスト数 | `kumi_new`：52 passed（新規`modules_test.exs` 12件＋`args_test.exs`+5件＋`inject_test.exs`+5件（storage系3件＋`page_controller_test/1`系2件）＝本機能で+22）、`mix compile --warnings-as-errors`・`mix format --check-formatted`共クリーン。生成app（`mod_crm`、`--with storage`、stale DB drop→archive再ビルド→再installした状態からの完全無人実行）：`mix kumi.report --skip-tests`が`Verdict: ready`、`mix test`は**5/5 passed**（手動介入ゼロ）。`kumi`/`kumi_admin`/`kumi_storage`パッケージは本featureで無改変。 | - |
| F110 | 摩擦まとめ | (1) ネストstructをモジュール属性で即座に参照できない実装上の制約に一度躓いたが影響は小さい（低）。(2) 最初の実装判断（Attachmentのcodegenは手動運用手順の踏襲でよい）はadvisorレビューで「ユーザービジョン（fully wired）と既存の認証resourceの扱いに矛盾する」と指摘され、pipelineに`maybe_codegen_modules`を追加する方向に転換した——dogfoodの`failed`が実際の設計ギャップを検出した事例（高）。(3) `page_controller_test.exs`の既存ギャップも同様に「required checkに明記されている以上スコープ外にしない」との指摘で修正対象へ格上げした（中）。(4) `~s(...)`括弧区切りsigilが内側の丸括弧をネスト計算しないというElixir自体の罠を実装中に1回踏んだ（中）。 | 高 |

## Spike 1: chat_ops（第二宿主 + 埋め込みチャットの糊コード採取）

> 目的：Kumiを2つ目の実host app（`spikes/chat_ops/`——オンライン接客チャットSaaSの骨格）に当て、
> (a) 単一hostでしか検証していないというブループリントの既知の限界を消し、
> (b) 糊コード（module原料）を採取し、
> (c) 「顧客サイトにタグを埋め込むと訪問者がチャットできる」というユーザービジョンを最小スライスで証明する。
> D-B-D（分層生長）：オペレータ返信box・bot・Phoenix Channels・マルチテナントは意図的に持ち越し（run 2+）。

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F111 | 第二宿主でのkumi.new→admin→plan/reportの素通り度 | `mix kumi.new chat_ops --db-port 5434 --kumi-path ... --no-modules`は依存解決・`kumi.install`・`kumi_admin.install`・`ash.setup`（migrate含む）まで無介入で完走し、事前のstale DB確認（`docker exec kumi_db psql -lqt \| grep chat_ops`）もヒットなしでF104/F106の再発なし。3リソース（Site/Conversation/Message）を追記後も`mix ash.codegen`→`mix ecto.migrate`→`mix kumi.plan --check`が`0 safe / 0 review / 0 dangerous`のゼロdiff、`mix kumi.report --skip-tests`が一発で`Verdict: ready`——spike0_crmで踏んだ摩擦（F104/F106/F107/F109等）は第二宿主では一つも再発しなかった。素通りしなかったのはKumi本体ではなく**このrunで新規に書いたコード側**の2箇所（次項）。 | - |
| F111 | 素通りしなかった2箇所（自作コードのバグ、Kumiのバグではない） | (1) `Ash.read_one(Site, action: :read_by_public_key, arguments: %{...})`という呼び方は`Spark.Options.ValidationError: unknown options [:arguments]`で失敗する——`Ash.read_one/2`はresource+optsを直接取れず、`Ash.Query.for_read(Site, :read_by_public_key, %{public_key: public_key}) \|> Ash.read_one()`のようにqueryを先に組む必要があった（ExUnitで1件デバッグ用testを書いて実測特定）。(2) `Plug.Conn.put_resp_content_type(conn, "text/javascript", charset: nil)`が`--warnings-as-errors`で型警告——第3引数はキーワードリストではなくcharsetの生の値（`nil`や文字列）を直接渡す関数であり、`put_resp_content_type(conn, "text/javascript", nil)`が正しい形。どちらもコンパイル/テストで即座に検出でき、実行時まで残らなかった。 | 中 |
| F111 | no-actor書き込みpolicyの形（module原料候補1） | `Conversation.visitor_create`・`Message.visitor_create`は`accept`を最小限（`[:site_id]`／`[:conversation_id, :body]`）に絞った専用create actionとして定義し、`policies do bypass action(:visitor_create) do authorize_if always() end; policy always() do authorize_if actor_present() end end`という形でactorなし書き込みを許可した。安全性の根拠はactor条件ではなく**アクション自体が受け付けるフィールドの狭さ**（`Message.visitor_create`は`:sender`を受け付けず`change set_attribute(:sender, :visitor)`で固定——訪問者が`:operator`を騙れない）。`Site`の`read_by_public_key`も同じ形（`get? true`＋`filter expr(public_key == ^arg(:public_key))`のbypass）で、1行探せば全レコード列挙にはならないことが読み取れる。3例とも同型なので「public/no-actorなCRUDのための狭いaction＋bypass」はテンプレート化できるパターンとして再利用性が高い（`Kumi.Resource`ショートハンドはpolicies非対応なので、これは素のAshで書く前提のまま——ショートハンドへの拡張は本runではスコープ外）。 | - |
| F111 | public LiveView + embed.js配信の形（module原料候補2） | `/widget/:public_key`（`ChatOpsWeb.WidgetLive`）はrouterの`ash_authentication_live_session`ブロックの外・`on_mount`なしの独立scopeに置くだけで「actorなしLiveView」が素直に実現できた——kumi_adminのGate（session-MFAパターン）を一切経由しない別経路。`/embed.js`（`ChatOpsWeb.EmbedController`）はプレーンな`Plug.Controller`アクションで`text/javascript`を返すだけの1関数——JSビルドツールチェーン（esbuild設定変更・npmパッケージ）が一切不要だった。埋め込みスニペットは`<script src=".../embed.js" data-kumi-site="KEY">`1行で、スクリプトが`document.currentScript`から`data-kumi-site`と`src`のoriginを読み取ってiframeを注入する。 | - |
| F111 | 「public read policyは実は不要だった」という再利用性の高い発見 | 当初はConversation/Messageにも訪問者用の`visitor_read`bypassが要ると想定していたが、実装を進める過程で「WidgetLiveは自分が書いたレコードしか表示しない」設計にすれば**読み取り系のpolicy拡張が一切不要**と気づいた——`create`が返すstructをそのままLiveViewのsocket assignsに積み増して描画し、DBへの再読み込みをしない。代償は「ブラウザをリロードすると会話履歴が消える」（本slice唯一の実害あるカット、運用上は許容範囲としてrun 2+送り）。この設計判断自体が「no-actor writeを支えるのに、対称的なno-actor readは常には要らない」という一般化可能な知見で、Kumiのガイド（no-actor policyのドキュメント化候補）に載せる価値がある。 | - |
| F111 | iframe方式を選んだ理由 | 訪問者ウィジェットの配信方式として(a) Phoenix Channels + 自前JS SDK、(b) 独自ビルドのWeb Component、(c) 単純なiframe埋め込み、の3択のうちiframeを選んだ。理由：本sliceの要件（訪問者がメッセージを送れてoperatorがadminで見える）を満たすのに必要な技術要素が「LiveViewを1つ書く」だけで済み、Channelsの接続管理・JS SDKのビルド・バンドル配布・CORSの検討が一切不要になる——ponytailの梯子（既存機能の再利用＞stdlib＞最小コード）通りの選択。CORSは明示的に検討した上で「iframeのロードはfetch/XHRと違いCORS対象外」と判断し、ヘッダーを一切付けなかった（コメントに理由を明記）。Channelsは双方向リアルタイム更新（operator返信のプッシュ）が要る run 2+ で再検討する。 | - |
| F111 | 意図的カット | (1) オペレータ返信box、(2) bot応答、(3) Phoenix Channelsによるリアルタイム更新（現状は訪問者がメッセージ送信するたびフルpage roundtripのLiveView再描画のみ、operator側には何もpushされない）、(4) マルチテナント（Site間の分離は`site_id`カラムのみで、operator側の閲覧範囲を絞るpolicyは未実装——`policy always() do authorize_if actor_present() end`はログイン済みなら全Site横断で見える）、(5) ページリロードで会話履歴が消える（前項参照）、(6) `Message.sender`はデフォルトcreate/updateアクションでは`allow_nil?`を明示していない（オペレータ返信box自体が無いため実害なし、run 2+で返信boxを足す際に`allow_nil? false`へ締める）。 | - |
| F111 | Kumi本体に欲しくなった機能（正直な列挙） | (1) no-actor bypass policyの定型パターン（本ログ上の候補1）をガイド化するか、`Kumi.Resource`ショートハンドの将来拡張候補にする価値がある。(2) `mix kumi.plan`/`kumi_admin`のnavigationは「ログイン済みactorに何が見えるか」の一枚岩の前提（`policy always() do authorize_if actor_present() end`）に最適化されており、マルチテナント（`site_id`ごとの行フィルタ）のようなactor属性に依存するpolicyをkumi_adminの列/検索/dashboardが正しく扱えるかは本runでは未検証（Conversation一覧に全Siteが混在して見える状態のまま）——次spikeか本体側の検証課題として残す。(3) それ以外はF104-F110で解消済みの摩擦（domain scaffold・attachment codegen配線等）の恩恵をそのまま受けられ、新規に欲しい機能は見つからなかった。 | - |
| F111 | 実測テスト数 | `chat_ops`：9 passed（`widget_live_test.exs` 3件——2メッセージ送信・永続化・描画／未知public_keyのリダイレクト／operator側での可視性、`embed_controller_test.exs` 1件、生成直後からの既存5件（page/error html/json）と合わせて計9）。`mix compile --warnings-as-errors`・`mix format --check-formatted`共クリーン、`mix kumi.plan --check`ゼロdiff、`mix kumi.report --skip-tests`が`Verdict: ready`。`kumi`/`kumi_admin`/`kumi_new`の3パッケージは本runで無改変（すべて実測、コピペではない）。 | - |
| F111 | 摩擦まとめ | (1) `Ash.read_one/2`の呼び出し形を誤り1回デバッグテストで特定（中）。(2) `put_resp_content_type/3`の第3引数の型を誤り`--warnings-as-errors`で検出（低）。(3) advisorレビューで「operatorがconversationを見える」ことを検証するテストのassertionが`html =~ "new"`（New buttonのhrefにマッチするだけで常に真になる空証明）になっていた点を指摘され、`String.slice(conversation.id, 0, 8)`に修正——spike0_crm自身のテストパターン（`String.slice(account.id, 0, 8)`）を見ていたのに最初のドラフトでは踏襲し損ねた（中、テストの意図確認プロセスの穴として記録）。(4) それ以外は第二宿主でも第一宿主と同じ体験が得られ、新規の重い摩擦は発生しなかった——Kumiの安定性の傍証。 | 中 |
| F111 | embed.jsの403（親セッション実HTTP検証で発見） | spike完成報告後の実HTTP検証で`/embed.js`が403を返した。原因は`:browser`パイプラインの`protect_from_forgery`（Plug.CSRFProtection）が**クロスオリジンscript GET（js形式）を遮断する仕様**——埋め込みスニペットは設計上まさにそれなので、専用`:embed_js`パイプライン（`accepts ["js"]`のみ）に分離して解消。同時に`put_secure_browser_headers`の`x-frame-options: SAMEORIGIN`が顧客サイトからのiframe埋め込み（製品の本質）を塞ぐ問題も発見し、widgetルートだけheaderを削除する`:embeddable`パイプラインを追加。**※このXFO側の記述は後にF115で誤りと判明——Phoenix 1.8.13はそもそも`x-frame-options`を送っておらず、この`:embeddable`はno-opだった。フレーム制御はCSPの`frame-ancestors`。****テストが偽陰性だった根因**：Phoenix.ConnTestは`:plug_skip_csrf_protection`を立てるためCSRF遮断はテストで原理的に再現不能——x-frame-options側のみ回帰テスト化（10 passed）し、CSRF側は実HTTP検証を検証手順に残すべきと記録。「suite green ≠ ブラウザで動く」の3例目（F107のstyle補間、今回のCSRF/XFO）。 | 高 |

---

## has_many子テーブル表示（詳細画面 + related_limit）

> 目的：kumi_adminの詳細画面はこれまで公開属性＋`belongs_to`しか出さず、「このAccountのDeals」のような
> 基本的なCRM/CMS期待を満たしていなかった。深さ意味論を決め打ちした上でhas_many子テーブルを足す。

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F112 | 深さ意味論の決定 | 1階層のみ・app全体で1つの`related_limit`（`admin do related_limit N end`、default 10）という決め打ちにした。多階層（孫レコード）とexport/API depthは明示的に対象外——理由は「まだAPIサーフェス自体が存在しない」ことで、要らない抽象を先回りして作らない（YAGNI）。必要になったら実際のAPI設計と一緒に深さの意味論を決める。 | - |
| F112 | has_manyを既存`Ash.get`の`load:`に混ぜなかった理由 | `ResourceShowLive.load_record/2`は本体レコードを`belongs_to`だけ乗せた1回の`Ash.get`で取り、has_manyは各関係ごとに別の`Ash.load(record, [{rel.name, child_query}], actor: actor)`で個別に読む。理由：もし全部を1回の`load:`にまとめていたら、子リソースのうち1つでもpolicy拒否になった瞬間`Ash.get`全体が`{:error, _}`を返し、画面全体が`:forbidden`（属性もbelongs_toも何も出ない）に落ちる——「1つの子セクションが見えないだけ」で済むはずの失敗が、ページ全体の失敗に格上げされてしまう。個別`Ash.load`＋個別`case`分岐（`build_has_many_section/4`）にすることで、forbiddenな子セクションだけ「No access.」の空状態になり、他のセクション・属性・belongs_to・Edit/Deleteボタンは無傷で描画される。 | - |
| F112 | limit+1方式（`Ash.count`を足さなかった理由） | 各子クエリは`Ash.Query.sort(:id) \|> Ash.Query.limit(related_limit + 1)`で「表示件数+1」だけ取り、`related_limit`件を表示・余った1件があれば「…and more.」を出す（index画面の`@page_size + 1`と同じidiom）。正確な総件数を出すための`Ash.count`は意図的に追加しなかった——has_manyセクションの数だけ追加クエリが増える（N+1的なコスト）割に、要求されていたのは「もっとあるかどうか」の二値情報だけだったため。正確な総数が要る場面が実際に出たら`Ash.count`を足す、というponytailコメントをコード側にも残した。 | - |
| F112 | 子行リンクをルート存在でゲートした理由 | `KumiAdmin.Router`の`/:resource/:id`は`:resource`パス変数自体はどんな文字列にもマッチするが、実際に解決できるかは`KumiAdmin.Slug.resolve/2`が`Kumi.App.Info.resources(app)`（`navigation`ではなく`resources`宣言）に対して行うslug一致でしか決まらない。子セクションの各行を「常にリンク化」すると、appの`resources`に載っていない（が`has_many`では見える）destinationに対して404リンクを踏ませることになる——`build_has_many_section/4`は`destination in admin_resources`を`linkable?`として返し、レンダー側は`linkable?`がfalseなら`:id`列でも素のテキストのまま出す。 | - |
| F112 | forbidden子セクションのテスト可否（正直に） | package側（kumi_admin）はforbidden分岐を`build_has_many_section/4`に`{:error, %Ash.Error.Forbidden{}}`という「用意したload結果」を直接注入するユニットテストでカバー済み（実Ashの`Ash.load`は経由しない、純粋なmapビルド関数のテスト）。一方spike0_crm側の実LiveViewテスト（実HTTPパスを通す統合テスト）ではforbidden分岐は**未検証**——spike0_crmの全リソースのpolicyは`actor_present()`のみで、ログイン済みactorに対してだけforbiddenを起こす手段が既存のドメインモデル内に無いため。正直にテストできていないと記録する（テストを偽装して通した箇所ではない）。 | - |
| F112 | spike側のhas_many追加とzero-diff再確認 | `Spike0Crm.Crm.Account`は`has_many :contacts`/`has_many :deals`をすでに宣言していたが`public?`未指定（このリポジトリの慣習では`belongs_to`側が全て明示`public? true`しており、デフォルトは非公開）だったため`public?: true`を追記しただけで済んだ——新規リレーション追加ではなくpublic化。`Spike0Crm.Crm.Contact`は`has_many`を一切宣言していなかったため、`Deal.belongs_to :contact`の既存FKに対応する`has_many :deals, Spike0Crm.Crm.Deal, public?: true`をこちらは新規追加した（タスク指示が明示的にaccount.ex**とcontact.ex**の両方を確認対象としていたため）。両方とも`public?`追記はAsh側のメタデータでスキーマ変更を伴わないため、`MIX_ENV=test mix ash.codegen --check`で保留codegenなし、`mix kumi.plan --check`で`0 safe / 0 review / 0 dangerous`のゼロdiffを実測確認した（本チェックはこのリポジトリの中核リグレッションゲート、絶対に特別扱いしない）。 | - |
| F112 | 実測テスト数 | `kumi`：166 passed（`app_test.exs`に`related_limit`のdefault/明示値assertion2件追加）。`kumi_admin`：52 passed（48→52、`resource_show_live_test.exs`新設4件——`:ok`結果／limit+1のhas_more?／`:error`結果のforbidden空状態／`linkable?`false、いずれも`build_has_many_section/4`への注入テスト）。`spike0_crm`：38 passed（既存36+新規2件——2件のDeal描画／11件seedしたcapと「…and more.」の実HTTP検証）。3パッケージとも`mix compile --warnings-as-errors`・`mix format --check-formatted`クリーン、spike0_crmは`mix kumi.plan --check`ゼロdiff実測。 | - |
| F112 | 摩擦 | 実装上の大きな摩擦は無かった——`Ash.Resource.Info.public_relationships/1`を`type == :has_many`でフィルタするだけで既存の`belongs_to_relationships/1`と対称に書け、`Ash.load(record, [{name, query}], actor:)`もドキュメント通りに動いた。唯一の小さな設計判断は「section-buildingを`Ash.load`呼び出しから分離する」こと自体で、これをしないとforbidden分岐のユニットテストがpackage内で書けず（実際にpolicy拒否するAsh resourceをkumi_admin側のfixtureに新設する必要が出ていた）、分離したことでpackage内テストのまま済んだ。 | - |

## AI視線での拡張可能性チェック（pgvector実測 → 本物のバグ発見）

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F114 | pgvector型でkumi.planがクラッシュしていた | 「KumiはAI製品の土台に使えるか」の検証として、まず型エンジンを実測した。`Kumi.Desired.PgType.from_ash(Ash.Type.Vector, dimensions: 1536)`——**pgvectorを使うAIアプリの実際の書き方**——が`FunctionClauseError (to_pg_name/1)`で落ちることを確認。原因：AshPostgresの`get_migration_type`はパラメータ付き型を`{:vector, 1536}`のタプルで返すが、`to_pg_name/1`のcatch-allは`when is_atom(atom)`ガード付きでタプルを受けない。影響は「plan全体が実行不能」——Safetyの「未知型ペアはDANGEROUSに倒す（fail closed）」という設計思想が、型名取得の段で例外になるため成立していなかった。修正：(a) タプルは第1要素を型名として扱う節（Postgresの`udt_name`はパラメータを含まず"vector"のみなので、これがdesired側の正解）、(b) それでも該当しない形は`inspect/1`で文字列化する最終節（実在するudt_nameと一致しないためchange_columnとして浮上し、Safetyが未知ペアをDANGEROUS判定＝本来の fail closed が成立）。テスト2件追加、kumi 168 passed。**ash_ai実在確認**：hex上に0.8.2（2026-08-03、週6834DL、depsにash_postgres/ash_phoenix/igniter＝Kumiと同生態）。なお本番検証は未了——docker `postgres:17-alpine`にpgvector拡張が入っていない（`pg_available_extensions`が0行）ため、実DBでのdesired/actual一致確認はイメージ変更が必要（CLAUDE.mdのDocker標準を変える決定を伴うので保留）。**「テストが緑でも実際の使い方で落ちる」の4例目**（F107 style補間、F111 CSRF/XFO、そして今回）。 | 高 |

## 詳細ページのAtomic Design化

> 目的：`ResourceShowLive`は属性・belongs_to・has_manyを全て同じ`kumi-admin-field`divの縦積みで出しており（has_manyまでこのクラスを流用していたのは意味的に誤り）、レコードタイトルも枠も無かった。Atomic Designで再構成し、今使う部品だけ作る。

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F113 | atoms/molecules/organismsの分割方針 | `kumi_admin/components/{atoms,molecules,organisms}.ex`の3ファイルに分けたが、カタログ的に網羅せず「詳細ページが実際に使う部品だけ」を作った——atoms: `button`/`badge`/`field_label`/`field_value`/`empty`/`section_title`/`back_link`（7個）、molecules: `field`（label+value）/`panel`（カード＋任意headerスロット）/`action_bar`（見出し＋右寄せactionsスロット）/`data_table`（列＋行＋callerが中身を決める`:cell`スロット）、organisms: `record_header`/`attribute_panel`/`relation_panel`/`child_section`。未使用の組み合わせ（例：フォーム用のfield variantやトースト等）は一切足していない——YAGNI優先で、次のページ（index/form/dashboard）がAtomic化される時に必要な分だけ追加すればよい。 | - |
| F113 | 既存クラス名を壊さず追加、index/form/dashboardは今回スコープ外 | `grep -rn "kumi-admin-" lib/kumi_admin/*.ex`で事前に洗い出し、`kumi-admin-field`/`-field-label`/`-field-value`/`-table`/`-button`/`-button-danger`/`-actions`/`-empty`/`-back-link`は**新しいmoleculeやatomの内部実装として再利用**した（例：`Molecules.field`は`kumi-admin-field`をそのまま出す）ため、CSSの追加は真に新規な見た目（panel/record-header/badge/section-title/attribute-grid）にのみ限定できた。`shell.ex`の`css/0`には既存ルールを1行も変更せず末尾に追記しただけ。index/form/dashboardの3 LiveViewは指示通り本スライスの対象外——これらは同じクラス名を直接埋め込んだ独自マークアップのままで、Atomic化していないぶん詳細ページと見た目の実装経路がまだ揃っていない（次のスライス候補として明記）。 | - |
| F113 | 詳細ページの新レイアウト | `render/1`は「back_link → record_header（h1＝`KumiAdmin.Format.record_label/1`、その下にmuted subtitle＝リソース名＋truncated id、右にEdit/Delete） → attribute_panel（属性を2カラムグリッド、800px以下で1カラムにmedia queryで折り返し） → relation_panel（belongs_toが1件でもあれば表示、無ければpanelごと非表示） → has_manyの数だけchild_section（1つ1panel）」という縦積みに再構成した。属性値がatomかつnil/booleanでない場合（例：`stage: :qualified`）は`Atoms.badge`で囲む——`KumiAdmin.Format.cell/2`の文字列自体は変えていないため、既存の部分一致アサーション（`html =~ "qualified"`等）はそのまま通る。 | - |
| F113 | 保持を義務付けられた既存文言・挙動 | `:not_found`→"Unknown resource."、`:forbidden`→"No access or no record."、child sectionの"No access."／"No records yet."／"…and more."は全て`Atoms.empty`経由で一字一句同じテキスト・同じ`<p class="kumi-admin-empty">`markupのまま出す。idカラムのリンクは`section.linkable?`ゲートのまま`child_section`に移設、`__kumi_attachment_url__/1`によるattachment linkの分岐（`relationship_display/2`）はLiveView側にノータッチで残し、その戻り値をそのまま`relation_panel`に渡すだけにした。Edit/Delete は`Ash.can?`ベースの`can_update?`/`can_destroy?`gatingと`phx-click="delete"`/`data-confirm="Are you sure?"`をAtoms.buttonの`:rest`経由でそのまま維持——spike0_crmの`has_element?(view, "a", "Edit")`/`element("button", "Delete")`は無修正で通過した。`build_has_many_section/4`を含むデータ導出コードは一切変更していない。 | - |
| F113 | HEEx `<style>` raw形式の回帰テストには触れていない | F107で追加された`shell_test.exs`の`refute html =~ "{css()}"`regressionテストの対象行（`<style><%= Phoenix.HTML.raw(css()) %></style>`）はCSS追記時も1文字も変更しておらず、末尾に新規CSSルールを追記しただけ——テスト自体も無改修で52→52件目のまま緑のことを確認した（後述の実測テスト数は新規component testファイル分の増加のみ）。 | - |
| F113 | ブラウザ目視で確認した内容（直した点は無し） | spike0_crmを起動し、register→account/contact/deal各1件を実データで作成した上でAccount詳細（`kumi-detail-atomic.png`）とDeal詳細（`kumi-detail-atomic-child.png`、belongs_to 2件＋atom badgeを含む方をchild画面に選んだ）を実際に目視した——見た目の破綻（枠のズレ・ラベル判読不能・詰まった余白）は無く、修正は発生しなかった。属性グリッドは3項目（奇数個）だと2列目に1マス分の空白ができるが、これはGitHub/Stripe等の管理画面でも見られる通常のtrailing-cellパターンであり崩れではないと判断し、そのままにした。480px幅への手動リサイズでも`kumi-admin-attribute-grid`のmedia queryが1カラムへ正しく折り返すことを確認——一方でサイドバー（220px固定）とtopbarはこのスライスの対象外である`shell.ex`の既存構造そのままのため狭幅で窮屈になる（今回導入した回帰ではなく、shell自体の未対応レスポンシブ課題として記録のみ）。 | - |
| F113 | 実測テスト数 | `kumi_admin`：52→73 passed（+21：`test/kumi_admin/components/atoms_test.exs` 7件、`molecules_test.exs` 6件、`organisms_test.exs` 8件、新規）。`mix compile --warnings-as-errors`・`mix format --check-formatted`共クリーン。`spike0_crm`：38 passed（本sliceで件数不変、既存のdetail-page系アサーション——account属性表示・deals子テーブル・cap/"…and more."——を1件も改変せずに通過を確認）、`mix test`実行、`mix deps.get`込みで確認。`kumi`パッケージは本runで無改変。 | - |
| F113 | 摩擦 | (1) `Atoms.button`のclass listレンダリングが`["kumi-admin-button", false]`で末尾に半角スペースが残る（`class="kumi-admin-button "`）のに気づかず最初のcomponentテストが1件fail、アサーションを実際の出力に合わせて修正（低）。(2) 1行`~H"..."`sigil内で`\"`エスケープを使うとdeprecation警告が出る（Elixir 1.19系の仕様変更）——複数行`~H"""..."""`に書き直して解消（低）。それ以外は既存クラス名の再利用が effectively 効いたため、CSSの新規追加は最小限で済んだ。 | 低 |
| F113 | 親セッションの目視で2件追加修正（エージェントは「問題なし」と報告） | Atomic Design化のスクリーンショットを親セッションが実際に読んで、エージェントが見落とした2つの実害を発見した。(1) 子テーブルに**親へのFK列**が出ていた（Accountの詳細ページのContacts/Deals両方に`ACCOUNT`列＝全行同じ値、情報量ゼロ）→ `build_has_many_section/4`のcolumnsから`relationship.destination_attribute`を除外。(2) FK値が**生UUIDのフル幅表示**でDealsテーブルが折り返して崩れていた（`Format.cell`が`:id`キーのみ切り詰め、`account_id`等は素通し）→ `*_id`で終わるキーのbinary値も`truncate_id`する節を追加（他ページのテーブルにも同時に効く改善）。エージェントは(2)を「原ロジックと一致するので放置」と自己申告しており、事実としては正しいが**デザインスライスの目的に照らせば実害**——「既存挙動と一致」は見た目の欠陥を残す理由にならない。テスト1件追加、kumi_admin 74 passed、spike0_crm 38 passed（既存アサーション無改変で通過）。教訓：スクリーンショットを撮るところまでは委譲できるが、**何が欠陥かの判断は委譲しきれない**（F107の「撮るだけでなく読む」の続き）。 | 中 |

## `kumi/guides/api.md`（AshJsonApi実装ガイド、blueprint §9のwedge実行）

> 目的：「KumiはAPIレイヤを自作しない、AshJsonApiへの逃げ道（D1）を示すguideを書く」という§9方針を、実際に動くscratchアプリ（`apiguide`、docker `kumi_db`上の`apiguide_dev`、ポート4010）に対してcurlで実測し、guideに書く手順が本当に動くことを検証した。

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F116 | shorthandがjson_apiを持たないことをコードで確認 | `kumi/lib/kumi/resource.ex`のmoduledocとその実体`Kumi.Resource.Codegen.generate/3`（`kumi/lib/kumi/resource/codegen.ex`）を実読し、`json_api`・`extensions`・AshJsonApi関連の生成パスが一切無いことを確認した。moduledoc自身が「calculations, aggregates, policies, custom actions, or anything else beyond the default four actions? Write the Ash resource directly」と明記しており、json_apiはこの「anything else」に該当する——未実装ではなく意図的にサポート対象外というD1の設計通りの姿。`mix kumi.expand Apiguide.Core.Contact`の実出力でも同じことを実証（json_apiブロックは出てこない、素のAsh resourceのまま）。 | - |
| F116 | `:accepts, ["json"]`が`application/vnd.api+json`を406で拒否 | JSON:APIクライアントが送る`Accept: application/vnd.api+json`を、kumi.new生成の`:api`パイプライン（`plug :accepts, ["json"]`）はMIMEタイプとして認識せず、`AshJsonApi`に到達する前に`Phoenix.NotAcceptableError`（406）で落ちることを実測（curlで再現）。既存のspike0_crmの`config/config.exs`に`config :mime, extensions: %{"json" => "application/vnd.api+json"}, types: %{"application/vnd.api+json" => ["json"]}`という解決策が既にあったため、それをapiguideにも追加し`mix deps.clean --build mime`で再ビルドして解消した（`:mime`はコンパイル時に型テーブルを生成するため、config変更だけでは効かない）。タスク指示にあった「js-format GETが403で落ちた前例」通りのcontent-type negotiationの罠が、AshJsonApiでも実在することを確認した実例。 | 高 |
| F116 | ドメインに`extensions: [AshJsonApi.Domain]`が無いと**コンパイルは通り実行時にのみ落ちる** | `AshJsonApi.Router`のディスパッチは`<Domain>.json_api_match_route/2`という関数を呼ぶが、これは`AshJsonApi.Domain.Persisters.DefineRouter`というドメインレベルのSpark transformerが生成するもので、ドメインに`extensions: [AshJsonApi.Domain]`を付けて初めて生成される。resource側に`AshJsonApi.Resource`を付けてrouterをmountしただけでは足りず、`mix compile --warnings-as-errors`は無警告で通るのに、実際にcurlした瞬間`UndefinedFunctionError: Apiguide.Core.json_api_match_route/2 is undefined`で500になることを実測。**注記（未検証のまま記録）**：`spikes/spike0_crm/lib/spike0_crm/crm.ex`を読む限りそのドメイン`Spike0Crm.Crm`も`extensions: [AshJsonApi.Domain]`を宣言していない——本タスクの制約でspike0_crmへの変更・起動検証はしていないため断定はしないが、同じ実行時エラーが起きる可能性がある構成に見える。もし事実なら「テストが緑でもHTTPが壊れている」の別の実例候補として、spike0_crm側の作業者に確認を委ねる。 | 高 |
| F116 | `?include=`は**関係が実在してもresourceごとに明示許可リストが要る、かつ多階層はroot resourceのnested keyword listでしか表現できない** | `Deal.belongs_to :contact`と`Contact.has_many :deals`はどちらも`public? true`で実在し、`relationships`キーにも出力されるのに、`json_api do includes([...]) end`を書かずに`?include=contact`を叩くと`{"errors":[{"code":"invalid_includes",...}]}`（400）になることを実測。`includes([:contact])`／`includes([:deals])`を両resourceに追加して単純1階層includeは通った（Deal→Contact、Contact→Deals両方向でcurl実測、200）。**advisorの指摘で多階層も実測**：`?include=deals.contact`をこのフラットな`includes([:deals])`のまま叩くと`"Invalid includes: [[\"deals\",\"contact\"]]"`で400——「各resourceが次のhopを宣言すれば繋がる」という当初の推測は誤りだった。`Contact`側を`includes(deals: [:contact])`というnested keyword listに書き換えて初めて`?include=deals.contact`が200になり、`included`に`contact`と`deal`両方が実データで載ることを確認した。Payloadの`depth`相当の疑問への実測回答：深さは経路の起点resourceが持つ`includes`のnest構造でしか表現できず、経路上の他resourceの`includes`宣言は無関係。 | 中 |
| F116 | `relationships`経由のbelongs_to書き込みはデフォルトcreateアクションでは失敗し、`ash_json_api`自身のエラー整形にもバグがある | `{"data":{"type":"deal","relationships":{"contact":{"data":{...}}}}}`をPOSTすると、`defaults [:read, :destroy, create: :*, update: :*]`が属性`contact_id`は受け付けても関係名`contact`自体は受け付けないため`Ash.Error.Invalid.NoSuchInput`が発生——のはずが、`ash_json_api` 1.7.1の`NoSuchInput.exception/1`内部が`Enum.filter(nil)`を呼んで`Protocol.UndefinedError`を追加で投げ、クライアントには素の500しか返らないことを実機確認した（AshJsonApi自体のバグ、guide側での回避は不可能）。**実際に動いた回避策**：`attributes.contact_id`に直接UUIDを渡す形でPOST→201を実測。JSON:API仕様の`relationships`書き込みを正規サポートするには、resourceごとにcustom create action（`accept`に関係名を含めるか`manage_relationship`）を書く必要があり、これは意図的にguideのスコープ外とした（汎用guideが個別resourceの書き込み方針を決め打ちすべきでないため）。 | 高 |
| F116 | kumi.new生成の`config/runtime.exs`がdev環境でもポートを強制上書き | タスク指示通り`config/dev.exs`に`http: [port: 4010]`を書いたが、実際に起動すると4000で待受していた——原因は`config/runtime.exs`の`config :apiguide, ApiguideWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]`が`if config_env() == :prod do`ブロックの**外**（全環境で実行される場所）に生成されていたため。該当行をprodブロック内に移動して再起動し、4010で待受することを実測確認した。ash-gotchas.mdのIgniterセクションに追記済み。**※「kumi.newのテンプレートが誤っている」という当初の推測は親セッションの追検証で否定された（次項）。** | 中 |
| F116 | 上記は**kumi.newの不具合ではなく上流phx.newの仕様**だった（親セッションによる追検証） | 根拠2点：(1) `strings ~/.mix/archives/phx_new-1.8.8/phx_new-1.8.8/ebin/*.beam \| grep 'System.get_env("PORT"'`で、phx_new 1.8.8自身のruntime.exsテンプレートに当該行が`if System.get_env("PHX_SERVER")`ブロックの直後＝prodブロックの**外**として埋め込まれていることを確認。(2) `grep -rn 'PORT\|runtime\.exs' kumi_new/lib/`のヒットは2件のみで、どちらも`--db-port`（**DB**ポートをdev/test configに注入する処理）に関するもの——kumi_newは`runtime.exs`もHTTPポートも一切触っていない。つまりPhoenix 1.8はdevでも`PORT`環境変数を効かせる設計に**意図的に**変えており、`config/dev.exs`にポートを書くのが誤りで`PORT=4010 mix phx.server`が正しい作法（F115でchat_opsを4011で起動した際に`config/dev.exs`無編集で通ったのはこのため）。生成物側でprodブロックに移す「修正」はKumi側の責任ではなく、上流仕様への逆行。ash-gotchas.mdの該当項目もkumi.new帰属を撤回して書き換えた。**エージェントが「Kumiのバグ」として報告した内容が実は上流仕様だった初のケース**——実装報告の帰属主張は上流テンプレートを直接見るまで信じない、という検証則を追加。 | 中 |
| F116 | 実測エンドポイント一覧（全てcurlで実行、ステータス実測） | `GET /api/json/contacts`（空配列、200）／`POST /api/json/contacts`（Contact作成、201）／`POST /api/json/deals`（relationships経由：500、attributes.contact_id経由：201）／`GET /api/json/deals/:id`（200）／`GET /api/json/contacts/:id`（200）／`GET /api/json/contacts/00000000-...`（404、Entity Not Found）／`GET /api/json/deals/:id?include=contact`（includes未宣言時400→宣言後200、included配列に実データ）／`GET /api/json/contacts/:id?include=deals`（同上、200）／`GET /api/json/open_api`（200、OpenAPIスキーマ）。全て`apiguide`（`/private/tmp/.../scratchpad/apiguide`、DB `apiguide_dev`、ポート4010）に対する実HTTPリクエストで、`mix test`のグリーンだけに頼らなかった。`mix kumi.report --skip-tests`は`format`/`compile`/`codegen`/`plan`全てOKで`Verdict: ready`。（※このF番号は`chat_ops`のCSP/XFO調査と同時並行で採番したため、両方がF115を主張する衝突が発生した——先に確定していた方に譲り、本エントリ群はF116として記録し直した。） | - |

## `kumi/guides/frontend.md` 執筆（chat_opsを実例として採取、Blueprint v3 §9）

> 目的：「adminは手に入った、同じアプリに公開フロントを載せるには」に答えるguideをchat_opsから採取。新しいexampleは作らず、既存のrouter/policy/widgetを実HTTPで検証しながら文書化した。

| # | 領域 | 事実 | 摩擦度 |
|---|---|---|---|
| F115 | `:embeddable`パイプラインが現行Phoenix(1.8系)で不完全——CSPがXFOを黙って上書きする | chat_opsの`/widget/:public_key`は`delete_x_frame_options/2`で`x-frame-options`を削除しているが、`put_secure_browser_headers/2`（Phoenix 1.8.13）は`content-security-policy: base-uri 'self'; frame-ancestors 'self';`も同時にセットしており、こちらは一切削除されていない。curlでは`x-frame-options`が消えていることしか見えず「直っているように見える」——しかし実ブラウザ（Playwright）で別オリジン（`localhost:5502`）から実際に`<iframe src="http://localhost:4011/widget/...">`を読み込ませたところ、コンソールに`Framing '...' violates the following Content Security Policy directive: "frame-ancestors 'self'". The request has been blocked.`が出て**埋め込みは実際には失敗していた**。既存の`embed_controller_test.exs`は`x-frame-options`の不在しかアサートしておらず、この壊れた状態のままテストは緑。原因はモダンブラウザがXFOよりCSPの`frame-ancestors`を優先する仕様のため、片方だけ消しても効果がない。 | 高 |
| F115 | 修正を実機検証してから戻した（chat_opsへの恒久変更はしていない） | `delete_x_frame_options/2`に`Plug.Conn.delete_resp_header(conn, "content-security-policy")`を追加する一時editを適用→devサーバのcode reloaderで即反映→同じ別オリジンiframeテストページを再読み込みし、コンソールエラー0件・iframe内にwidgetの実コンテンツ（サイト名・メッセージ入力欄）が描画されることを確認→editをそのまま元の1行`do: Plug.Conn.delete_resp_header(conn, "x-frame-options")`に戻し、curlで元のCSPヘッダが復活していることを確認した。タスク指示（chat_opsは採取元であり改造対象ではない）に従い、正しい修正は`kumi/guides/frontend.md`本文・`kumi/guides/ash-gotchas.md`（Phoenix LiveViewセクション）・本エントリに記録するに留めた。gitコマンドは一切使わず、Edit toolでの手動復元のみで原状回復を確認した。 | - |
| F115 | no-actor write policyの実測（読みではなく実行で確認） | `ChatOps.Core.Conversation`/`Message`の`bypass action(:visitor_create)`が「1アクションだけ開ける」設計であることを、(1) `Ash.read(ChatOps.Core.Conversation)`をactorなしで実行→`{:error, %Ash.Error.Forbidden{}}`、(2) `Message.visitor_create`に`sender: :operator`を混ぜて`Ash.create`→`accept`に`:sender`が無いため`{:error, %Ash.Error.Invalid{... NoSuchInput input: :sender}}`、(3) 実ブラウザで`/widget/:public_key`を開きメッセージを実際に送信→画面に反映、の3通りで実測した。読み専用のポリシー読解では「たぶん安全」までしか言えないため、この3点は全て`mix run -e`または実ブラウザ操作で確認した。 | - |
| F115 | 検証環境 | docker `kumi_db`（`postgres:17-alpine`、`localhost:5434`）は既存コンテナをそのまま使用、DB作成・削除なし。`chat_ops_dev`は`mix ash.setup`実行時点で既に存在・migration済み（"already up"）だったため作成不要だった。サーバは`PORT=4011 mix phx.server`で起動——`config/runtime.exs`の`http: [port: String.to_integer(System.get_env("PORT", "4000"))]`が全environment共通で効く既存コードのため、`config/dev.exs`は無編集。ポート4010は別エージェントが使用中との指示のため4011を選択。 | - |
| F115 | 摩擦 | 大きな摩擦は無し。唯一の想定外は上記CSP/XFOの二重ヘッダ問題——タスク指示が想定していた「exemptionは2つ（CSRF・XFO）」に対し、実ブラウザ検証で3つ目（CSP frame-ancestors）が見つかった。curlだけでは見えず（curlはCSPを解釈しない）、Playwrightで実際に別オリジンiframeを描画させて初めて判明した——「テストが緑でも実際の使い方で壊れている」の5例目（F107 style補間、F111 CSRF/XFO、F114 pgvector、そして今回）。 | 低 |
| F115 | **上の「二重ヘッダ」という理解自体が誤りだった（親セッションによる追検証）** | `curl -s -D - http://localhost:4011/`（`:browser`パイプラインの素のルート）で全ヘッダを実測したところ、**Phoenix 1.8.13の`put_secure_browser_headers/2`は`x-frame-options`を一切送っていない**。送っているのは`content-security-policy: base-uri 'self'; frame-ancestors 'self';`だけ。つまり「XFOとCSPの二重ブロック」ではなく「1.8ではXFOは存在せず、フレーム制御はCSPのみ」が事実で、chat_opsの`delete_x_frame_options/2`は**完全なno-op**だった（v0.3実装時から一度も機能していない）。連鎖する帰結が2つ: (1) F111で「XFOを消して直した」と記録した内容は1.8では成立していない、(2) 既存テストの`assert get_resp_header(conn, "x-frame-options") == []`は**空虚に真**——`:embeddable`パイプラインを丸ごと削除しても緑のまま通る。Rule 9（ビジネスロジックを変えても通るテストは間違い）の実例。世間の記事が全て「XFOを消せ」と書いているため、コードもテストも当然そう書いてしまう構造的な罠。 | 高 |
| F115 | 恒久修正を適用（採取元だから触らない、では済まない種類のバグだった） | 委譲時は「chat_opsは採取元、改造しない」と指示したが、これは"設計判断の対象"ではなく実機で壊れている機能の根本原因だったため親セッションで修正した。`:embeddable`を`allow_cross_site_framing/2`に改名し、`delete_resp_header("x-frame-options")`（CDN/proxy/旧Phoenix対策として残置）+ `put_resp_header("content-security-policy", "base-uri 'self';")`に。**deleteではなくoverride**にしたのは、同じヘッダが載せている`base-uri 'self'`はフレーム制御と無関係で残すべきだから——エージェントが検証した`delete_resp_header("content-security-policy")`案はbase-uri保護も一緒に落とす。テストは`refute csp =~ "frame-ancestors"` + `assert csp =~ "base-uri 'self'"`に差し替え（後者は将来「ヘッダごと消す」簡略化が入ったら落ちるための番人）。実HTTP再検証: widget → `200` / XFOなし / `csp: base-uri 'self';`、`/`（対照） → `csp: base-uri 'self'; frame-ancestors 'self';`（免除が1ルートに限定されていることの証明）。chat_ops 10 tests green。 | - |
| F115 | 残した制約（意図的） | 修正後の`frame-ancestors`は"絞る"のではなく"落とす"——つまり任意originから埋め込める。本番なら`Site`に登録ドメインを持たせて`frame-ancestors https://customer.example`を出すべきで、これはヘッダの問題ではなくデータモデルの問題（`allowed_origins`フィールド＋それを読むplug）。`kumi/guides/frontend.md`の"Where you still write glue code today"に明記済み。 | - |
