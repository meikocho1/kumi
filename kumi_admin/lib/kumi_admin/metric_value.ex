defmodule KumiAdmin.MetricValue do
  @moduledoc """
  Computes a dashboard metric's live value via Ash count/sum aggregates,
  scoped to the session actor.

  Returns `{:ok, number}` on success. A policy-forbidden read returns
  `:forbidden` — the caller renders that as "—", never a crash (this
  repo's admin culture: policy-forbidden reads render an honest empty
  state). Any other error is a bug and is raised (fail loud).
  """

  alias Kumi.App.Dsl.Metric

  @spec fetch(Metric.t(), term()) :: {:ok, number()} | :forbidden
  def fetch(%Metric{kind: :count, resource: resource}, actor) do
    case Ash.count(resource, actor: actor) do
      {:ok, count} -> {:ok, count}
      {:error, %Ash.Error.Forbidden{}} -> :forbidden
      {:error, error} -> raise error
    end
  end

  def fetch(%Metric{kind: :sum, resource: resource, field: field}, actor) do
    case Ash.sum(resource, field, actor: actor) do
      {:ok, nil} -> {:ok, 0}
      {:ok, sum} -> {:ok, sum}
      {:error, %Ash.Error.Forbidden{}} -> :forbidden
      {:error, error} -> raise error
    end
  end
end
