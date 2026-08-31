defmodule KumiAdmin.Locale do
  @moduledoc """
  Every fixed string the admin renders, per locale. Data only — the lookup
  lives in `Kumi.Locale`, and `KumiAdmin.Text` is what the LiveViews call.

  Entries are whole phrases with `%{binding}` placeholders, never
  fragments to be concatenated with a label: `"%{name} 一覧へ戻る"` puts
  the noun before the verb where Japanese needs it, which
  `"Back to " <> label` can never do. `KumiAdmin.LocaleTest` asserts that
  `:ja` covers every `:en` key, so a new string can't quietly ship
  English-only.

  Not included, deliberately: error text Ash and AshPhoenix produce
  (`translate_error/1` on a form field), attribute values, and `:select`
  option values — those are the host's or Ash's strings, not the admin's
  chrome.
  """

  @table %{
    en: %{
      # Actions
      new: "New",
      edit: "Edit",
      delete: "Delete",
      save: "Save",
      sign_out: "Sign out",
      prev: "Prev",
      next: "Next",
      confirm_delete: "Are you sure?",
      search_placeholder: "Search…",

      # Section headings
      attributes: "Attributes",
      relations: "Relations",
      back_to: "Back to %{name}",
      current_file: "Current file",

      # Honest empty/blocked states (M3/M4: never claim which one it was)
      no_access: "No access.",
      no_records: "No records visible to you.",
      no_access_or_records: "No access or no records.",
      no_access_or_record: "No access or no record.",
      unknown_resource: "Unknown resource.",
      unsupported_action: "This resource doesn't support that action.",
      and_more: "…and more.",
      no_dashboards: "No dashboards declared.",

      # Flashes
      created: "%{name} created.",
      updated: "%{name} updated.",
      deleted: "Deleted.",
      forbidden: "You don't have permission to do that.",
      fix_errors: "Please fix the errors below.",

      # Uploads
      upload_too_large: "File is too large.",
      upload_too_many_files: "Only one file allowed.",
      upload_not_accepted: "File type not accepted.",
      upload_failed: "Upload error: %{reason}"
    },
    ja: %{
      new: "新規作成",
      edit: "編集",
      delete: "削除",
      save: "保存",
      sign_out: "ログアウト",
      prev: "前へ",
      next: "次へ",
      confirm_delete: "本当に削除しますか？",
      search_placeholder: "検索…",
      attributes: "項目",
      relations: "関連",
      back_to: "%{name}の一覧へ戻る",
      current_file: "現在のファイル",
      no_access: "権限がありません。",
      no_records: "表示できるレコードがありません。",
      no_access_or_records: "権限がないか、レコードがありません。",
      no_access_or_record: "権限がないか、レコードが見つかりません。",
      unknown_resource: "不明なリソースです。",
      unsupported_action: "このリソースはその操作に対応していません。",
      and_more: "…ほかにもあります。",
      no_dashboards: "ダッシュボードが宣言されていません。",
      created: "%{name}を作成しました。",
      updated: "%{name}を更新しました。",
      deleted: "削除しました。",
      forbidden: "その操作の権限がありません。",
      fix_errors: "以下のエラーを修正してください。",
      upload_too_large: "ファイルが大きすぎます。",
      upload_too_many_files: "ファイルは1つだけです。",
      upload_not_accepted: "対応していないファイル形式です。",
      upload_failed: "アップロードに失敗しました: %{reason}"
    }
  }

  @doc "The built-in string table, shaped for `Kumi.Locale.translate/4`."
  @spec table() :: Kumi.Locale.table()
  def table, do: @table
end
