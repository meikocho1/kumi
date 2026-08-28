defmodule KumiAdmin.ResourceIndexLiveTest do
  @moduledoc """
  Unit test for the empty-state wording (M4). `render/1` is a plain
  function component under the hood, so it can be rendered directly with
  hand-built assigns — no LiveView mount, no database.
  """

  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias KumiAdmin.ResourceIndexLive

  test "no records and no error renders wording that can't be misread as 'this table is empty' (M4)" do
    assigns = %{
      app: KumiAdmin.Test.App,
      resource: KumiAdmin.Test.Account,
      mount_path: "/admin",
      actor: nil,
      sign_out_path: "/sign-out",
      can_create?: false,
      search: "",
      error: nil,
      records: [],
      columns: [:id, :name],
      offset: 0,
      has_more?: false,
      attachment_relationships: %{}
    }

    html = render_component(&ResourceIndexLive.render/1, assigns)

    # A policy-filtered-to-nothing read returns `{:ok, []}`, indistinguishable
    # from a genuinely empty table — the wording must not claim either.
    assert html =~ "No records visible to you."
    refute html =~ "No records yet."
  end
end
