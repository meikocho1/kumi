defmodule KumiAdmin.DashboardLive do
  @moduledoc """
  Dashboard: app title + one titled stat grid per declared `dashboard`
  block, with each metric's live value computed via Ash count/sum
  aggregates against the session actor, plus one grid per declared
  `workflow` block showing its per-stage record counts (read-only — no
  stage transitions). Policy-forbidden reads render "—", never a crash
  (this repo's admin culture). Still not an analytics engine: no ratios,
  no filters, no time windows.

  Metrics and workflow stages share one component because on this page
  they are the same thing: a name and a number. Everything language- or
  format-dependent is resolved here, so `Molecules.stat_grid/1` receives
  pairs of finished strings.
  """

  use Phoenix.LiveView

  alias Kumi.App.Info
  alias KumiAdmin.Components.Molecules
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
        %{app: app, mount_path: mount_path, actor: actor, sign_out_path: sign_out_path} =
          context

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
           text: context.text,
           dashboards: dashboards,
           workflow_counts: workflow_counts
         )}
    end
  end

  def render(assigns) do
    ~H"""
    <Shell.shell
      app={@app}
      text={@text}
      mount_path={@mount_path}
      actor={@actor}
      sign_out_path={@sign_out_path}
    >
      <h1 class="kumi-admin-title">{Info.title(@app) || to_string(Info.name(@app))}</h1>
      <Molecules.stat_grid
        :for={{dashboard, metric_results} <- @dashboards}
        title={KumiAdmin.Text.term(@text, dashboard.name)}
        rows={metric_rows(@text, dashboard, metric_results)}
      />
      <p :if={@dashboards == []} class="kumi-admin-empty">
        {KumiAdmin.Text.string(@text, :no_dashboards)}
      </p>
      <Molecules.stat_grid
        :for={{workflow, result} <- @workflow_counts}
        title={KumiAdmin.Text.term(@text, workflow.name)}
        rows={stage_rows(@text, workflow, result)}
      />
    </Shell.shell>
    """
  end

  defp metric_rows(text, dashboard, metric_results) do
    Enum.map(metric_results, fn {metric, result} ->
      {KumiAdmin.Text.term(text, dashboard.name, metric.name), metric_value(metric, result)}
    end)
  end

  defp metric_value(_metric, :forbidden), do: "—"
  defp metric_value(metric, {:ok, value}), do: Format.cell(metric.name, value)

  # `:forbidden` still lists every declared stage: a dashboard that drops
  # rows when a read is denied reads as "no such stage", not "not allowed".
  defp stage_rows(text, %{name: name, stages: stages}, :forbidden) do
    Enum.map(stages, &{KumiAdmin.Text.term(text, name, &1), "—"})
  end

  defp stage_rows(text, %{name: name}, {:ok, counts}) do
    Enum.map(counts, fn {stage, display} ->
      {KumiAdmin.Text.term(text, name, stage), display}
    end)
  end
end
