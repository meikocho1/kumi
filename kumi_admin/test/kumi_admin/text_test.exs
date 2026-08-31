defmodule KumiAdmin.TextTest do
  use ExUnit.Case, async: true

  alias KumiAdmin.Test.{Account, App, Contact, JaApp}
  alias KumiAdmin.Text

  describe "an app that declares nothing" do
    test "renders the English chrome and the derived labels — unchanged behaviour" do
      text = Text.new(App)

      assert text.locale == :en
      assert Text.string(text, :new) == "New"
      assert Text.resource(text, Account) == "Accounts"
      assert Text.field(text, Account, :name) == "Name"
      # Bare names, not humanized: this is what the dashboard printed
      # before labels existed, and the default must not move.
      assert Text.term(text, :sales_pipeline) == "sales_pipeline"
      assert Text.term(text, :sales_pipeline, :in_progress) == "in_progress"
    end
  end

  describe "an app that declares locale :ja and labels" do
    test "chrome comes from the declared locale" do
      text = Text.new(JaApp)

      assert Text.string(text, :new) == "新規作成"
      assert Text.string(text, :no_records) == "表示できるレコードがありません。"
    end

    # The reason whole phrases matter: the label sits before the verb in
    # Japanese and after it in English, which a concatenated fragment
    # cannot express.
    test "a phrase with a label puts it where the language wants it" do
      assert Text.string(Text.new(App), :back_to, name: "Accounts") == "Back to Accounts"
      assert Text.string(Text.new(JaApp), :back_to, name: "取引先") == "取引先の一覧へ戻る"
    end

    test "a declared label wins over the derived one" do
      text = Text.new(JaApp)

      assert Text.resource(text, Account) == "取引先"
      assert Text.field(text, Account, :name) == "名称"
    end

    # A declared label is display text the author wrote, so it is used as
    # written — no `s`, no pluralization pass.
    test "a declared label is used verbatim, never pluralized" do
      assert Text.resource(Text.new(JaApp), Contact) == "担当者"
    end

    test "anything without a declared label still falls back to the derived English" do
      text = Text.new(JaApp)

      assert Text.field(text, Account, :inserted_at) == "Inserted at"
      assert Text.term(text, :unlabelled) == "unlabelled"
    end
  end

  describe "host overrides" do
    test "replace individual chrome strings and leave the rest alone" do
      text = Text.new(JaApp, %{ja: %{new: "登録"}})

      assert Text.string(text, :new) == "登録"
      assert Text.string(text, :save) == "保存"
    end

    test "do not touch labels — those come from the app's own DSL" do
      text = Text.new(JaApp, %{ja: %{new: "登録"}})

      assert Text.resource(text, Account) == "取引先"
    end
  end
end
