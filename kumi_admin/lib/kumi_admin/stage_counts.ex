defmodule KumiAdmin.StageCounts do
  @moduledoc """
  Computes a workflow's per-stage record counts via Ash count aggregates,
  scoped to the session actor.

  Returns `{:ok, [{stage, count}]}` (stages in declared order) on success.
  A policy-forbidden read on ANY stage short-circuits the whole workflow to
  `:forbidden` — the caller renders that as "—" per declared stage, never a
  crash (this repo's admin culture: policy-forbidden reads render an
  honest empty state). Any other error is a bug and is raised (fail loud).
  """

  alias Kumi.App.Dsl.Workflow

  @spec fetch(Workflow.t(), term()) :: {:ok, [{atom(), non_neg_integer()}]} | :forbidden
  def fetch(%Workflow{resource: resource, field: field, stages: stages}, actor) do
    # ponytail: N count queries per workflow; single GROUP BY aggregate if it matters
    Enum.reduce_while(stages, {:ok, []}, fn stage, {:ok, acc} ->
      resource
      |> Ash.Query.filter_input(%{field => stage})
      |> Ash.count(actor: actor)
      |> case do
        {:ok, count} -> {:cont, {:ok, [{stage, count} | acc]}}
        {:error, %Ash.Error.Forbidden{}} -> {:halt, :forbidden}
        {:error, error} -> raise error
      end
    end)
    |> case do
      :forbidden -> :forbidden
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
    end
  end
end
