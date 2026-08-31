defmodule Kumi.Plan.Locale do
  @moduledoc """
  Every sentence `mix kumi.plan` and `mix kumi.report` print, per locale.
  Data only — `Kumi.Locale` does the lookup.

  ## What is and isn't in here

  The operation lines themselves are *not* translated:
  `~ fk account_id on_delete :nothing -> :delete` is table names, column
  names, Postgres types and arrows. Translating `column` to `列` would
  make the line harder to match against the database, not easier to read.
  What's in here is the prose around them: the safety reason, the fix
  hint, the drift parenthetical, the summary line.

  `SAFE` / `REVIEW` / `DANGEROUS` also stay as they are. They're the
  classification's names — the same tokens `Kumi.Plan.Safety` returns as
  atoms and the guides document — not a sentence.

  `--json` output is locale-independent and always English: a consumer
  parsing it must not have its keys or values change because someone set
  `locale :ja` in their app.

  ## The `:en` entries are load-bearing

  They reproduce the exact strings `Kumi.Plan.Safety` and
  `Kumi.Plan.FixHint` produced before this table existed, character for
  character. The existing `safety_test.exs` / `fix_hint_test.exs`
  assertions are what keeps them honest — an accidental reword shows up
  as a failing test, not as a silently changed CLI.
  """

  @codegen "mix ash.codegen <name> && mix ash_postgres.migrate"

  @doc "The command every code-ahead fix hint points at."
  @spec codegen_command() :: String.t()
  def codegen_command, do: @codegen

  @table %{
    en: %{
      # ---- Kumi.Plan.Format frame ----
      no_changes: "No changes. Database matches application definition.",
      summary: "%{safe} safe / %{review} review / %{dangerous} dangerous",
      drift_in_db_not_code: "  (in DB, not in code — drift)",
      drift: "  (drift)",
      via_snapshot: "      via: %{file}",
      via_no_snapshot: "      via: no matching snapshot file under %{dir}",
      via_catalog:
        "      via: pg_catalog (Kumi.Actual) vs Ash resource introspection (Kumi.Desired)",
      finding: "      finding: %{note}  (%{query})",
      verdict_ready: "Verdict: ready — Ready for PR",
      verdict_ready_with_migration:
        "Verdict: ready_with_migration — Ready for PR (apply the SAFE migration)",
      verdict_blocked: "Verdict: blocked — NOT ready, see above",
      verdict_failed: "Verdict: failed — NOT ready, see above",

      # ---- mix kumi.report step details ----
      step_format_pass: "all files formatted",
      step_compile_pass: "compiled cleanly (no warnings)",
      step_codegen_pass: "up to date (no pending migrations)",
      step_skipped: "skipped (compile failed)",
      step_plan_clean: "clean — database matches application definition",
      step_plan_safe: "%{count} SAFE operation(s) — acceptable with migration",
      step_plan_blocked: "blocked: %{summary}",
      step_plan_error: "could not build plan: %{message}",

      # ---- Kumi.Plan.Safety reasons ----
      safety_add_table: "creates new table %{table}",
      safety_drop_table: "drops table %{table} and all its data",
      safety_add_column_nullable: "adds nullable column %{column}",
      safety_add_column_not_null:
        "adds NOT NULL column %{column} — existing rows need a default/backfill",
      safety_remove_column:
        "drops column %{column} — in the DB, not in code, not matched as a rename: data loss",
      safety_add_fk: "adds FK %{column} on an existing table",
      safety_remove_fk: "removes FK %{column} from an existing table",
      safety_add_index_unique: "adds UNIQUE index %{index}",
      safety_add_index: "adds index %{index} — use CREATE INDEX CONCURRENTLY in production",
      safety_remove_index: "removes index %{index} — only ever drift, not requested by code",
      safety_change_primary_key:
        "primary key changed %{actual} -> %{desired} — needs DROP CONSTRAINT + ADD CONSTRAINT, verify manually",
      safety_change_fk: "FK %{column} target changed %{actual} -> %{desired}",
      safety_change_fk_on_delete:
        "FK %{column} on_delete changed %{actual} -> %{desired} — needs DROP CONSTRAINT + ADD CONSTRAINT, verify deletes still behave as intended",
      safety_change_index:
        "index %{index} definition changed — columns %{actual_columns} -> %{desired_columns}, unique %{actual_unique} -> %{desired_unique}",
      safety_possible_rename:
        "possible rename %{from} -> %{to} (heuristic guess from snapshot history, verify before applying)",
      safety_widen_type: "widens %{column} type %{actual} -> %{desired}",
      safety_change_type:
        "narrows or changes %{column} type %{actual} -> %{desired} (default: unsafe)",
      safety_tighten_not_null: "tightens %{column} to NOT NULL — existing NULLs would fail",
      safety_relax_null: "relaxes %{column} to allow NULL",
      safety_change_default: "changes %{column} default %{actual} -> %{desired}",
      safety_widen_precision: "widens %{column} timestamp precision %{actual} -> %{desired}",
      safety_narrow_precision:
        "narrows %{column} timestamp precision %{actual} -> %{desired} (rounds sub-second values, does not fail)",
      safety_change_timestampness:
        "%{column} timestamp-ness changed (precision %{actual} -> %{desired}) — verify manually",

      # ---- Kumi.Plan.FixHint lines ----
      hint_codegen: "fix: %{codegen}  (code ahead of DB)",
      hint_add_table:
        "if codegen emits nothing, table %{table} was dropped manually — recreate it by hand",
      hint_keep_resource:
        "fix: to keep it, define it as an Ash resource (ash.codegen cannot see this drift)",
      hint_keep_attribute:
        "fix: to keep it, add the attribute to your Ash resource (ash.codegen cannot see this drift)",
      hint_keep_relationship:
        "fix: to keep it, add the relationship to your Ash resource (ash.codegen cannot see this drift)",
      hint_keep_identity:
        "fix: to keep it, add the identity/index to your Ash resource (ash.codegen cannot see this drift)",
      hint_remove_sql: "to remove it: %{sql}",
      hint_rename_first:
        "fix: if this is a rename, run BEFORE ash.codegen (codegen would emit drop+add and lose data):",
      hint_code_ahead_sql: "if codegen emits nothing, the DB drifted — apply manually: %{sql}",
      hint_code_ahead_manual:
        "if codegen emits nothing, the DB drifted — adjust manually (default/precision changes have no single SQL form)",
      hint_primary_key_drift:
        "if codegen emits nothing, primary key drifted (DB: %{actual}, code: %{desired}) — changing it needs DROP CONSTRAINT <table>_pkey + ADD CONSTRAINT ... PRIMARY KEY (...); apply manually, verify data implications first",
      hint_fk_drift:
        "if codegen emits nothing, FK %{column} target drifted (DB: %{actual}, code: %{desired}) — needs DROP CONSTRAINT %{constraint} + ADD CONSTRAINT pointing at the new target; apply manually",
      hint_fk_on_delete_drift:
        "if codegen emits nothing, FK %{column} on_delete drifted (DB: %{actual}, code: %{desired}) — needs DROP CONSTRAINT %{constraint} + ADD CONSTRAINT ... ON DELETE ...; apply manually",
      hint_index_drift:
        "if codegen emits nothing, index %{index} definition drifted (DB: columns %{actual_columns}, unique %{actual_unique}; code: columns %{desired_columns}, unique %{desired_unique}) — needs DROP INDEX + CREATE INDEX; apply manually"
    },
    ja: %{
      no_changes: "差分はありません。データベースはアプリケーションの定義と一致しています。",
      summary: "安全 %{safe} 件 / 確認 %{review} 件 / 危険 %{dangerous} 件",
      drift_in_db_not_code: "  （DB にあってコードに無い — ドリフト）",
      drift: "  （ドリフト）",
      via_snapshot: "      根拠: %{file}",
      via_no_snapshot: "      根拠: %{dir}/ 以下に一致するスナップショットがありません",
      via_catalog: "      根拠: pg_catalog（Kumi.Actual）と Ash resource の内省（Kumi.Desired）の比較",
      finding: "      調査結果: %{note}  (%{query})",
      verdict_ready: "判定: ready — PR を出せます",
      verdict_ready_with_migration:
        "判定: ready_with_migration — PR を出せます（SAFE なマイグレーションを適用してください）",
      verdict_blocked: "判定: blocked — まだ出せません。上の内容を確認してください",
      verdict_failed: "判定: failed — まだ出せません。上の内容を確認してください",
      step_format_pass: "すべて整形済み",
      step_compile_pass: "警告なしでコンパイルできました",
      step_codegen_pass: "未適用のマイグレーションはありません",
      step_skipped: "実行していません（コンパイルが失敗）",
      step_plan_clean: "ズレなし — DB とアプリの定義が一致しています",
      step_plan_safe: "SAFE な操作が %{count} 件 — マイグレーションを当てれば進めます",
      step_plan_blocked: "止まっています: %{summary}",
      step_plan_error: "plan を作れませんでした: %{message}",
      safety_add_table: "テーブル %{table} を新規作成します",
      safety_drop_table: "テーブル %{table} とその全データを削除します",
      safety_add_column_nullable: "NULL 可の列 %{column} を追加します",
      safety_add_column_not_null: "NOT NULL の列 %{column} を追加します — 既存行には default か backfill が必要です",
      safety_remove_column: "列 %{column} を削除します — DB にあってコードに無く、リネームとしても一致しません: データが失われます",
      safety_add_fk: "既存テーブルに外部キー %{column} を追加します",
      safety_remove_fk: "既存テーブルから外部キー %{column} を削除します",
      safety_add_index_unique: "UNIQUE インデックス %{index} を追加します",
      safety_add_index: "インデックス %{index} を追加します — 本番では CREATE INDEX CONCURRENTLY を使ってください",
      safety_remove_index: "インデックス %{index} を削除します — コードが要求したものではなく、常にドリフトです",
      safety_change_primary_key:
        "主キーが %{actual} から %{desired} に変わっています — DROP CONSTRAINT と ADD CONSTRAINT が必要です。手で確認してください",
      safety_change_fk: "外部キー %{column} の参照先が %{actual} から %{desired} に変わっています",
      safety_change_fk_on_delete:
        "外部キー %{column} の on_delete が %{actual} から %{desired} に変わっています — DROP CONSTRAINT と ADD CONSTRAINT が必要です。削除の挙動が意図どおりか確認してください",
      safety_change_index:
        "インデックス %{index} の定義が変わっています — 列 %{actual_columns} → %{desired_columns}、unique %{actual_unique} → %{desired_unique}",
      safety_possible_rename: "%{from} から %{to} へのリネームの可能性があります（スナップショット履歴からの推測です。適用前に確認してください）",
      safety_widen_type: "列 %{column} の型を %{actual} から %{desired} に拡張します",
      safety_change_type: "列 %{column} の型を %{actual} から %{desired} に変更します（縮小の可能性あり。既定で危険とみなします）",
      safety_tighten_not_null: "列 %{column} を NOT NULL に厳しくします — 既存の NULL があれば失敗します",
      safety_relax_null: "列 %{column} の NULL を許可します",
      safety_change_default: "列 %{column} の default を %{actual} から %{desired} に変更します",
      safety_widen_precision: "列 %{column} のタイムスタンプ精度を %{actual} から %{desired} に拡張します",
      safety_narrow_precision:
        "列 %{column} のタイムスタンプ精度を %{actual} から %{desired} に縮小します（秒未満は丸められます。失敗はしません）",
      safety_change_timestampness:
        "列 %{column} のタイムスタンプ性が変わっています（精度 %{actual} → %{desired}）— 手で確認してください",
      hint_codegen: "対処: %{codegen}  （コードが DB より進んでいます）",
      hint_add_table: "codegen が何も出さない場合、テーブル %{table} は手で削除されています — 手で作り直してください",
      hint_keep_resource: "対処: 残すなら Ash resource として定義してください（このドリフトは ash.codegen には見えません）",
      hint_keep_attribute:
        "対処: 残すなら Ash resource に attribute を追加してください（このドリフトは ash.codegen には見えません）",
      hint_keep_relationship:
        "対処: 残すなら Ash resource に relationship を追加してください（このドリフトは ash.codegen には見えません）",
      hint_keep_identity:
        "対処: 残すなら Ash resource に identity か index を追加してください（このドリフトは ash.codegen には見えません）",
      hint_remove_sql: "削除するなら: %{sql}",
      hint_rename_first:
        "対処: リネームであれば ash.codegen より先に実行してください（codegen は drop と add を出してデータを失います）:",
      hint_code_ahead_sql: "codegen が何も出さない場合、DB がドリフトしています — 手で適用してください: %{sql}",
      hint_code_ahead_manual:
        "codegen が何も出さない場合、DB がドリフトしています — 手で調整してください（default と精度の変更に単一の SQL 形はありません）",
      hint_primary_key_drift:
        "codegen が何も出さない場合、主キーがドリフトしています（DB: %{actual}、コード: %{desired}）— 変更には DROP CONSTRAINT <table>_pkey と ADD CONSTRAINT ... PRIMARY KEY (...) が必要です。データへの影響を確かめてから手で適用してください",
      hint_fk_drift:
        "codegen が何も出さない場合、外部キー %{column} の参照先がドリフトしています（DB: %{actual}、コード: %{desired}）— DROP CONSTRAINT %{constraint} と、新しい参照先を指す ADD CONSTRAINT が必要です。手で適用してください",
      hint_fk_on_delete_drift:
        "codegen が何も出さない場合、外部キー %{column} の on_delete がドリフトしています（DB: %{actual}、コード: %{desired}）— DROP CONSTRAINT %{constraint} と ADD CONSTRAINT ... ON DELETE ... が必要です。手で適用してください",
      hint_index_drift:
        "codegen が何も出さない場合、インデックス %{index} の定義がドリフトしています（DB: 列 %{actual_columns}、unique %{actual_unique}／コード: 列 %{desired_columns}、unique %{desired_unique}）— DROP INDEX と CREATE INDEX が必要です。手で適用してください"
    }
  }

  @doc "The plan/report string table, shaped for `Kumi.Locale.translate/4`."
  @spec table() :: Kumi.Locale.table()
  def table, do: @table

  @doc "`Kumi.Locale.translate/4` against this table — the only table plan/report prose lives in."
  @spec translate(Kumi.Locale.locale(), atom(), keyword() | map()) :: String.t()
  def translate(locale, key, bindings \\ []),
    do: Kumi.Locale.translate(@table, locale, key, bindings)
end
