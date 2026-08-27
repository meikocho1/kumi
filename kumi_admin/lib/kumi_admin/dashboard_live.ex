defmodule KumiAdmin.DashboardLive do
  @moduledoc """
  Dashboard: app title + one card per declared `dashboard` block, with
  each metric's live value computed via Ash count/sum aggregates against
  the session actor, plus one card per declared `workflow` block showing
  its per-stage record counts (read-only — no stage transitions). Policy-
  forbidden reads render "—", never a crash (this repo's admin culture).
  Still not an analytics engine: no ratios, no filters, no time windows.
  """

  use Phoenix.LiveView

  alias Kumi.App.Info
  alias KumiAdmin.Components.Shell
  alias KumiAdmin.Format
  alias KumiAdmin.MetricValue
  alias KumiAdmin.StageCounts

  def mount(_params, session, socket) do
    context = KumiAdmin.Context.resolve(session, %{}, socket)

    case KumiAdmin.Gate.check(context, socket) do
      {:halt, socket} ->
        {:ok, socket}

      {:cont, socket} ->
        %{app: app, mount_path: mount_path, actor: actor, sign_out_path: sign_out_path} = context

        dashboards =
          Enum.map(Info.dashboards(app), fn dashboard ->
            metric_results = Enum.map(dashboard.metrics, &{&1, MetricValue.fetch(&1, actor)})
            {dashboard, metric_results}
          end)

        workflow_counts =
          Enum.map(Info.workflows(app), fn workflow ->
            {workflow, StageCounts.fetch(workflow, actor)}
          end)

        {:ok,
         assign(socket,
           app: app,
           mount_path: mount_path,
           actor: actor,
           sign_out_path: sign_out_path,
           dashboards: dashboards,
           workflow_counts: workflow_counts
         )}
    end
  end

  def render(assigns) do
    ~H"""
    <Shell.shell app={@app} mount_path={@mount_path} actor={@actor} sign_out_path={@sign_out_path}>
      <h1 class="kumi-admin-title">{Info.title(@app) || to_string(Info.name(@app))}</h1>
      <div :for={{dashboard, metric_results} <- @dashboards} class="kumi-admin-card">
        <h2>{dashboard.name}</h2>
        <ul>
          <li :for={{metric, result} <- metric_results}>
            {metric.name}: {metric_value_display(metric, result)}
          </li>
        </ul>
      </div>
      <p :if={@dashboards == []} class="kumi-admin-empty">
        No dashboards declared.
      </p>
      <div :for={{workflow, result} <- @workflow_counts} class="kumi-admin-card">
        <h2>{workflow.name}</h2>
        <ul>
          <li :for={{stage, display} <- stage_rows(workflow, result)}>
            {stage}: {display}
          </li>
        </ul>
      </div>
    </Shell.shell>
    """
  end

  defp metric_value_display(_metric, :forbidden), do: "—"
  defp metric_value_display(metric, {:ok, value}), do: Format.cell(metric.name, value)

  defp stage_rows(%{stages: stages}, :forbidden), do: Enum.map(stages, &{&1, "—"})
  defp stage_rows(_workflow, {:ok, counts}), do: counts
end
