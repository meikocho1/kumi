defmodule KumiAdmin.DashboardLive do
  @moduledoc """
  Slice-1 dashboard: app title + one card per declared `dashboard` block,
  listing its metric names. No aggregation — this proves the app
  definition drives UI (blueprint F05), it does not invent an analytics
  engine.
  """

  use Phoenix.LiveView

  alias Kumi.App.Info
  alias KumiAdmin.Components.Shell

  def mount(_params, session, socket) do
    %{app: app, mount_path: mount_path} = KumiAdmin.Context.resolve(session, %{}, socket)
    {:ok, assign(socket, app: app, mount_path: mount_path)}
  end

  def render(assigns) do
    ~H"""
    <Shell.shell app={@app} mount_path={@mount_path}>
      <h1 class="kumi-admin-title">{Info.title(@app) || to_string(Info.name(@app))}</h1>
      <div :for={dashboard <- Info.dashboards(@app)} class="kumi-admin-card">
        <h2>{dashboard.name}</h2>
        <ul>
          <li :for={metric <- dashboard.metrics}>{metric.name}</li>
        </ul>
      </div>
      <p :if={Info.dashboards(@app) == []} class="kumi-admin-empty">
        No dashboards declared.
      </p>
    </Shell.shell>
    """
  end
end
