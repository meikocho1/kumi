defmodule KumiAdmin.JapaneseRenderTest do
  @moduledoc """
  End of the chain: an app declaring `locale :ja` and labels actually
  renders a Japanese page. `render/1` is a function component underneath,
  so this needs no mount and no database — the same trick
  `KumiAdmin.ResourceIndexLiveTest` uses.
  """

  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias KumiAdmin.ResourceIndexLive
  alias KumiAdmin.Test.{Account, App, JaApp}

  defp assigns_for(app) do
    %{
      app: app,
      resource: Account,
      mount_path: "/admin",
      # An actor is what makes the topbar render its sign-out link at all.
      actor: %{email: "person@example.com"},
      sign_out_path: "/sign-out",
      can_create?: true,
      search: "",
      error: nil,
      records: [],
      columns: [:id, :name],
      offset: 0,
      has_more?: false,
      attachment_relationships: %{},
      foreign_keys: [],
      text: KumiAdmin.Text.new(app)
    }
  end

  test "chrome and the resource heading render in Japanese" do
    html = render_component(&ResourceIndexLive.render/1, assigns_for(JaApp))

    # Chrome from KumiAdmin.Locale
    assert html =~ "新規作成"
    assert html =~ "検索…"
    assert html =~ "表示できるレコードがありません。"
    assert html =~ "ログアウト"

    # Labels from the app's own `admin do labels %{...} end`
    assert html =~ "取引先"

    # And nothing English leaks back in for the parts that were declared
    refute html =~ ">New<"
    refute html =~ "No records visible to you."
  end

  test "a labelled column header renders in Japanese, an unlabelled one falls back" do
    assigns =
      Map.put(assigns_for(JaApp), :records, [
        %Account{id: "11111111-2222-3333-4444-555555555555", name: "Acme"}
      ])

    html = render_component(&ResourceIndexLive.render/1, assigns)

    assert html =~ "名称"
    refute html =~ "Name"
    # `:id` has no declared label, so it still humanizes.
    assert html =~ "Id"
  end

  # The acceptance bar for the whole feature: an app that declares neither
  # a locale nor labels renders exactly what it rendered before any of this
  # existed.
  test "an app declaring nothing still renders the English page" do
    html = render_component(&ResourceIndexLive.render/1, assigns_for(App))

    assert html =~ "New"
    assert html =~ "Search…"
    assert html =~ "No records visible to you."
    assert html =~ "Accounts"
    refute html =~ "新規作成"
  end
end
