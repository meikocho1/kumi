defmodule KumiAdmin.DashboardLiveTest do
  @moduledoc """
  The dashboard's own rendering, which had no test until the metrics
  stopped being a bulleted list. `render/1` is a function component
  underneath, so this needs no mount and no database — the same trick
  `KumiAdmin.ResourceIndexLiveTest` uses.
  """

  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Kumi.App.Info
  alias KumiAdmin.DashboardLive
  alias KumiAdmin.Test.{App, JaApp}

  defp assigns_for(app, opts \\ []) do
    result = Keyword.get(opts, :result, {:ok, 7})

    dashboards =
      Enum.map(Info.dashboards(app), fn dashboard ->
        {dashboard, Enum.map(dashboard.metrics, &{&1, result})}
      end)

    %{
      app: app,
      mount_path: "/admin",
      actor: %{email: "person@example.com"},
      sign_out_path: "/sign-out",
      text: KumiAdmin.Text.new(app),
      dashboards: dashboards,
      workflow_counts: []
    }
  end

  test "a metric is a labelled number in the grid, not a `key: value` line" do
    html = render_component(&DashboardLive.render/1, assigns_for(App))

    assert html =~ "kumi-admin-stat-grid"
    assert html =~ ~s(<span class="kumi-admin-stat-label">account_count</span>)
    assert html =~ ~s(<span class="kumi-admin-stat-value">7</span>)

    # The old shape put both halves in one text node. Nothing should be
    # assembling "name: value" any more — the grid separates them so each
    # can be styled, and so a Japanese label isn't glued to a colon.
    refute html =~ "account_count: 7"
  end

  test "declared labels name the dashboard and its metrics" do
    html = render_component(&DashboardLive.render/1, assigns_for(JaApp))

    assert html =~ "概要"
    assert html =~ "取引先数"
    refute html =~ "account_count"
  end

  test "a policy-forbidden read renders an em dash, and still renders the metric" do
    html = render_component(&DashboardLive.render/1, assigns_for(App, result: :forbidden))

    assert html =~ ~s(<span class="kumi-admin-stat-label">account_count</span>)
    assert html =~ ~s(<span class="kumi-admin-stat-value">—</span>)
  end

  test "a workflow's stages render in the same grid as metrics" do
    workflow = %{name: :pipeline, stages: [:lead, :won]}

    assigns =
      App
      |> assigns_for()
      |> Map.put(:workflow_counts, [{workflow, {:ok, [{:lead, 3}, {:won, 1}]}}])

    html = render_component(&DashboardLive.render/1, assigns)

    assert html =~ "pipeline"
    assert html =~ ~s(<span class="kumi-admin-stat-label">lead</span>)
    assert html =~ ~s(<span class="kumi-admin-stat-value">3</span>)
  end

  test "a forbidden workflow read keeps every declared stage" do
    workflow = %{name: :pipeline, stages: [:lead, :won]}

    assigns =
      App
      |> assigns_for()
      |> Map.put(:workflow_counts, [{workflow, :forbidden}])

    html = render_component(&DashboardLive.render/1, assigns)

    # Dropping the rows would read as "no such stage" rather than "not allowed".
    assert html =~ ~s(<span class="kumi-admin-stat-label">lead</span>)
    assert html =~ ~s(<span class="kumi-admin-stat-label">won</span>)
  end
end
