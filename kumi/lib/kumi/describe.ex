defmodule Kumi.Describe do
  @moduledoc """
  The machine-readable model of a `Kumi.App` — what `mix kumi.describe`
  prints (blueprint §8: Kumi supplies the app-level model and leaves the
  reasoning to an external agent; it never generates patches itself).

  This is an **index, not a second source of truth**. It names what
  exists — resources, navigation, workflows, dashboards, detected
  plugins — plus the plan state around it. `mix kumi.expand` stays the
  authority on what a resource actually compiles to (D1), so nothing
  here restates the Ash source and the two can't drift.

  ## Schema (`schema_version` 1)

      {
        "schema_version": 1,
        "app": {"module": "MyApp.App", "name": "my_app",
                "title": "My App", "locale": "en"},
        "resources": [
          {"module": "MyApp.Core.Account", "table": "accounts",
           "domain": "MyApp.Core", "in_navigation": true}
        ],
        "admin": {"navigation": ["MyApp.Core.Account"], "related_limit": 10},
        "workflows": [
          {"name": "pipeline", "resource": "MyApp.Core.Deal",
           "field": "stage", "stages": ["lead", "won"]}
        ],
        "dashboards": [
          {"name": "overview",
           "metrics": [{"name": "deal_count", "kind": "count",
                        "resource": "MyApp.Core.Deal", "field": null}]}
        ],
        "plugins": [
          {"name": "storage", "marker": "__kumi_attachment__/0",
           "resources": ["MyApp.Core.Attachment"],
           "attached_via": [{"resource": "MyApp.Core.Contact",
                             "relationship": "avatar"}]}
        ],
        "plan": null | {...}   # `Kumi.Plan.Json`'s schema
      }

  `schema_version` is the promise this output makes: a breaking change to
  the shape raises it, and no shim keeps the old version alive (Rule 13).
  It exists because AshPostgres' undocumented snapshot format is the trap
  this project already pays for (Risk 4 / F17 / F20) — Kumi doesn't hand
  its own consumers the same problem.

  Deliberately absent: admin `labels` (display copy, not structure) and
  any per-attribute detail (that's `mix kumi.expand`).
  """

  alias Kumi.App.Info

  @schema_version 1

  @doc """
  The model of `app`, with `plan` folded in (or `nil` when there is no
  plan to show — `mix kumi.describe --no-plan`, which needs no database).
  """
  @spec to_map(module(), Kumi.Plan.t() | nil) :: map()
  def to_map(app, plan \\ nil) do
    resources = Info.resources(app)
    navigation = Info.navigation(app)

    %{
      schema_version: @schema_version,
      app: %{
        module: inspect(app),
        name: Info.name(app),
        title: Info.title(app),
        locale: Info.locale(app)
      },
      resources: Enum.map(resources, &resource_map(&1, navigation)),
      admin: %{
        navigation: Enum.map(navigation, &inspect/1),
        related_limit: Info.related_limit(app)
      },
      workflows: Enum.map(Info.workflows(app), &workflow_map/1),
      dashboards: Enum.map(Info.dashboards(app), &dashboard_map/1),
      plugins: plugins(resources),
      plan: Kumi.Plan.Json.to_map(plan)
    }
  end

  @doc """
  `to_map/2`, pretty-printed with keys in a stable (alphabetical) order.

  Erlang's own map order is neither alphabetical nor guaranteed across
  builds, and the whole point of this output is that a human can diff two
  of them — a reshuffle that isn't a real change would defeat it.
  """
  @spec encode(module(), Kumi.Plan.t() | nil) :: String.t()
  def encode(app, plan \\ nil),
    do: app |> to_map(plan) |> ordered() |> Jason.encode!(pretty: true)

  defp ordered(map) when is_map(map) and not is_struct(map) do
    %Jason.OrderedObject{
      values:
        map
        |> Enum.sort_by(&to_string(elem(&1, 0)))
        |> Enum.map(&{to_string(elem(&1, 0)), ordered(elem(&1, 1))})
    }
  end

  defp ordered(list) when is_list(list), do: Enum.map(list, &ordered/1)
  defp ordered(other), do: other

  defp resource_map(resource, navigation) do
    %{
      module: inspect(resource),
      table: table(resource),
      domain: inspect(Ash.Resource.Info.domain(resource)),
      in_navigation: resource in navigation
    }
  end

  # D2 says AshPostgres, but a declared resource can still sit on another
  # data layer — `null` says "no table" rather than raising on the way to
  # a read-only description.
  defp table(resource) do
    if Ash.Resource.Info.data_layer(resource) == AshPostgres.DataLayer,
      do: AshPostgres.DataLayer.Info.table(resource)
  end

  defp workflow_map(%{name: name, resource: resource, field: field, stages: stages}),
    do: %{name: name, resource: inspect(resource), field: field, stages: stages}

  defp dashboard_map(%{name: name, metrics: metrics}),
    do: %{name: name, metrics: Enum.map(metrics, &metric_map/1)}

  defp metric_map(%{name: name, kind: kind, resource: resource, field: field}),
    do: %{name: name, kind: kind, resource: inspect(resource), field: field}

  # Storage is detected exactly the way `KumiAdmin.FormFields` detects it
  # — by the `__kumi_attachment__/0` marker on a `belongs_to` destination
  # (blueprint §6 point 3), never by depending on `kumi_storage`. The
  # generated Attachment resource is a plain-Ash support resource and is
  # deliberately *not* in the app's own `resources` block, so walking
  # relationships is the only place it surfaces.
  defp plugins(resources) do
    attached =
      for resource <- resources,
          %Ash.Resource.Relationships.BelongsTo{} = rel <-
            Ash.Resource.Info.relationships(resource),
          attachment?(rel.destination),
          do: {rel.destination, resource, rel.name}

    if attached == [], do: [], else: [storage_map(attached)]
  end

  defp storage_map(attached) do
    %{
      name: :storage,
      marker: "__kumi_attachment__/0",
      resources: attached |> Enum.map(fn {dest, _, _} -> inspect(dest) end) |> Enum.uniq(),
      attached_via:
        Enum.map(attached, fn {_dest, resource, field} ->
          %{resource: inspect(resource), relationship: field}
        end)
    }
  end

  defp attachment?(module),
    do: Code.ensure_loaded?(module) and function_exported?(module, :__kumi_attachment__, 0)
end
