<p align="center">
  <img src="design/kumi-logo.svg" alt="Kumi" width="88" height="88">
</p>

<h1 align="center">Kumi</h1>

<p align="center">
  <strong>Ash はアプリケーションのモデリングを助ける。Kumi はそれを製品として出すところを助ける。</strong>
</p>

<p align="center">
  <a href="https://github.com/meikocho1/kumi/actions/workflows/ci.yml"><img src="https://github.com/meikocho1/kumi/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT"></a>
  <img src="https://img.shields.io/badge/elixir-~%3E%201.20-purple.svg" alt="Elixir">
</p>

<p align="center">
  <a href="README.md">English</a> · 日本語
</p>

先に結論だけ書きます。

> `mix ash.codegen` は、コードと「自分が書いたスナップショット」を比べています。データベースは一度も見ていません。だからマイグレーション以外の経路でスキーマが変わった瞬間から、履歴は現実の説明をやめる。しかも、誰も教えてくれない。

`mix kumi.plan` は `pg_catalog` を直接読んで、Ash のリソース定義と突き合わせます。

```text
crm_accounts:
  + column notes text  [SAFE: adds nullable column notes]
  ~ column industry (nullable: true -> false)  [REVIEW: tightens industry to NOT NULL — existing NULLs would fail]
  - column legacy_notes text  (in DB, not in code — drift)  [DANGEROUS: drops column legacy_notes — data loss]

1 safe / 1 review / 1 dangerous
```

作ったきっかけは、自分のプロジェクトで実際にドリフトを踏んだことです。踏むまで、この盲点があること自体を知りませんでした。

## 差分そのものは、たいした話ではない

`pg_catalog` を読めば誰でも出せます。そこは本体ではありません。

意味があるのは、**その差分を埋める操作がデータを消しうるかどうかを機械が判定している**ところです。

SAFE は純粋な追加。REVIEW は制約の厳格化と、Kumi が推測している箇所（rename らしき drop + add など）。DANGEROUS はデータが消えるもの全部。

そして型変更は **fail closed** にしてあります。広がる変換だと証明できない型の組み合わせは、全部 DANGEROUS に倒す。

これは確実に誤検知を出します。出すつもりで作りました。偽の DANGEROUS は「もう一度見る」コストで済みますが、見逃した DANGEROUS はカラムが消えます。この取引が設計の全部です。ここは反対されうると思っているので、違うと思ったら issue が一番助かります。

## 分類はデータを見ない

`--probe` を付けると read-only のカウントが走り、「NOT NULL にしようとしているそのカラム、NULL が 4,102 件あります」と注釈が付きます。

ただし **probe の結果は分類を変えません**。注釈するだけです。

意図的にそうしています。`mix kumi.plan --check` を CI に置いたとき、exit code が「どの DB に向けて実行したか」で変わってはいけないからです。変わるなら CI に置く意味がない。

```bash
mix kumi.plan            # 差分
mix kumi.plan --check    # REVIEW か DANGEROUS があれば exit 1
mix kumi.apply           # dev 限定、SAFE の部分だけ
```

`ash.codegen` の代わりではありません。問いが違うので、両方走らせています。

## リソースを宣言してあるので、管理画面は勝手に出てくる

<p align="center">
  <img src="design/screenshots/kumi-detail-atomic-child.png" alt="Kumi の管理画面。属性・enum のバッジ・解決済みの belongs_to 関連が並んでいる" width="860">
</p>

一覧、フォーム、検索、`belongs_to` のセレクト、子テーブル、ダッシュボードの指標、ワークフローのステージ。**リソースごとのコードはゼロです。**

認証は持っていません。あなたが既に使っているものの後ろにマウントします。`mix kumi.gen.auth google` を叩けば、`ash_authentication` にインストーラが無い OAuth2 プロバイダの配線も生成します。

ただしこの部分は plan エンジンより若くて、それは見れば分かります。先に plan エンジンを見てください。

## `ash_admin` との違い

競合していません。

`ash_admin` は開発者がデータを覗くための道具です。汎用なのは意図的で、dev でリソースをつつくならあれが正解。

`kumi_admin` が狙っているのは、**開発者でない人に渡す画面**です。ナビゲーション・ダッシュボードの指標・ワークフローのステージを、アプリのレベルで自分で宣言します。データを見たいだけなら `ash_admin` を使ってください。

## やらないと決めた3つ

穴ではなく決定です。コードの中で蒸し返しません。

**Ash を隠さない。** Kumi の DSL は全部ふつうの Ash リソースにコンパイルされ、`mix kumi.expand` が「実際に何になるか」をそのまま印字します。印字したソースとコンパイル結果が一致することをテストで固定してあるので、この主張が静かに腐ることはありません。素の Ash に降りるのは想定された経路であって、Kumi が壊れたときの避難先ではない。`kumi.expand` で往復できない機能は、shorthand に入れません。

**データ層を抽象化しない。** AshPostgres だけ。Ecto アダプタは作りません。私は書きたくないし、あなたも依存したくないはずです。

**`ash.codegen` を置き換えない。** codegen はコードの履歴を見て、Kumi はデータベースを見る。両方走らせる価値があるし、実際そうしています。

## 使ってみる

Hex には出していないので、`mix kumi.new` はローカルビルドの archive から入れて、`--kumi-path` にこのチェックアウトを渡します。**クローンの1つ上のディレクトリ**で実行してください。

```bash
mix archive.install hex igniter_new
mix archive.install hex phx_new
(cd Kumi/kumi_new && mix archive.build && mix archive.install)  # [Yn] を聞かれます

# 何もない状態から動くアプリまで: Ash, Phoenix, 認証, 管理画面, DB
mix kumi.new my_crm --kumi-path Kumi --db-port 5434
```

`--kumi-path` には**実パス**を渡してください。symlink を渡すと `the dependency kumi in mix.exs is overriding a child dependency` で生成プロジェクトが Mix に拒否されます。`mix.exs` に書き込まれる絶対パスと、`kumi_admin` が宣言している `../kumi` の解決結果が一致しなくなるためです。上の手順を symlink 付きのチェックアウトで実行して踏みました。

既存アプリに入れる場合は [`kumi/README.md`](kumi/README.md#existing-app) を見てください。

## パッケージ構成

| パッケージ | 中身 |
|---|---|
| [`kumi/`](kumi/) | `mix kumi.plan`（コード vs 実 DB の差分と安全性分類）、`mix kumi.apply`、`mix kumi.gen.auth`、アプリレベル DSL、リソース shorthand |
| [`kumi_admin/`](kumi_admin/) | リソースから導出される LiveView 管理画面。リソースごとのコード無し、認証は持たない |
| [`kumi_storage/`](kumi_storage/) | ファイル/画像アップロード。素の Ash リソースを生成し、管理画面が自動で拾う |
| [`kumi_new/`](kumi_new/) | `mix kumi.new my_app`。1コマンドで動くアプリまで |

## ドキュメント

- [`kumi/README.md`](kumi/README.md) — インストール、plan エンジン、DSL、全 mix タスク
- [`kumi_admin/README.md`](kumi_admin/README.md) — マウント方法、router のオプション、新規の人が必ず踏む2点（認証を持たないこと／管理対象は `:id` 単一主キー必須）
- [`kumi_storage/README.md`](kumi_storage/README.md) — アップロード、`:image` フィールド、バックエンド契約
- [`kumi/guides/mini-crm.md`](kumi/guides/mini-crm.md) — 小さな CRM を最後まで作る。**全スニペット実行済み**
- [`kumi/guides/auth.md`](kumi/guides/auth.md) — サインイン方式、Google/GitHub/OIDC の生成、2要素認証がどこから来るべきか
- [`kumi/guides/api.md`](kumi/guides/api.md) — JSON:API が必要になったとき
- [`kumi/guides/frontend.md`](kumi/guides/frontend.md) — 公開フロントを管理画面と同じ Phoenix アプリに載せる
- [`kumi/guides/ash-gotchas.md`](kumi/guides/ash-gotchas.md) — Ash / Spark / AshPostgres / Igniter で実際にデバッグ時間を溶かした挙動

## どこまで本気にしていいか

個人プロジェクトです。自分の Ash アプリで使っていますが、**本番トラフィックと呼べるものには当てていません。** あなたの本番に向ける前に、そこを勘定に入れてください。

MIT、テスト430本、Hex 未公開。Hex に出していないのは面倒だからではなく、**分類ルールが間違っているなら誰かが依存する前に知りたい**からです。判定に納得できないケースがあったら、それが一番ありがたい issue です。

## 動作環境

Elixir と OTP は [`.tool-versions`](.tool-versions) のピン留めどおり。PostgreSQL 17。

## コントリビュート

バグ報告・機能・PR 歓迎です。セットアップ、CI が回すチェック、レビューで見ている点は [`CONTRIBUTING.md`](CONTRIBUTING.md)（英語）に書いてあります。セキュリティの問題は公開の issue ではなく [`SECURITY.md`](SECURITY.md) の私的報告を使ってください。

## ライセンス

MIT。[`LICENSE`](LICENSE) を参照。
