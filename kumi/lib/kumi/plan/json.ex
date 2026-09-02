defmodule Kumi.Plan.Json do
  @moduledoc """
  Machine-readable encoding of a `%Kumi.Plan{}` — the single shape every
  `--json` surface prints for plan state, so `mix kumi.report --json`
  (via `Kumi.Report.Json`) and `mix kumi.describe` can't drift apart.

  ## Schema

      {
        "safe": <int>, "review": <int>, "dangerous": <int>,
        "operations": [
          {"description": "drop_table accounts", "level": "dangerous", "reason": "..."}
          # only REVIEW/DANGEROUS ops — what actually needs a look
        ]
      }

  SAFE operations are counted but not listed: the counts answer "is there
  anything to apply at all", and the listing exists for the operations a
  human still has to decide about.
  """

  alias Kumi.Plan.Format

  @doc """
  Encodes `plan`, or `nil` when the caller had no plan to show (the
  `:plan` step was skipped, the task ran with `--no-plan`).
  """
  @spec to_map(Kumi.Plan.t() | nil) :: map() | nil
  def to_map(nil), do: nil

  def to_map(%Kumi.Plan{} = plan) do
    %{
      safe: plan.safe,
      review: plan.review,
      dangerous: plan.dangerous,
      operations:
        plan.entries
        |> Enum.filter(fn {_op, level, _reason} -> level in [:review, :dangerous] end)
        |> Enum.map(fn {op, level, reason} ->
          %{description: Format.describe(op), level: level, reason: reason}
        end)
    }
  end
end
