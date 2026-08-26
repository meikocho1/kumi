defmodule Kumi.Report.Json do
  @moduledoc """
  Machine-readable encoding of a `Kumi.Report` for `mix kumi.report --json`
  — what an AI agent or CI parses to decide whether to open the PR.

  ## Schema

      {
        "steps": [
          {"name": "format", "status": "pass" | "fail" | "skipped", "detail": "..."}
          # ... "compile", "test", "codegen", "plan", always in this order
        ],
        "verdict": "ready" | "ready_with_migration" | "blocked" | "failed",
        "plan": null | {
          "safe": <int>, "review": <int>, "dangerous": <int>,
          "operations": [
            {"description": "drop_table accounts", "level": "dangerous", "reason": "..."}
            # only REVIEW/DANGEROUS ops — what actually needs a look
          ]
        }
      }

  `plan` is `null` when the `:plan` step didn't run (skipped or errored) —
  see `Kumi.Report`'s moduledoc for when that happens.
  """

  alias Kumi.Report.{Format, Step}

  @spec to_map(Kumi.Report.t()) :: map()
  def to_map(%Kumi.Report{steps: steps, verdict: verdict, plan: plan}) do
    %{
      steps: Enum.map(steps, &step_map/1),
      verdict: verdict,
      plan: plan_map(plan)
    }
  end

  @spec encode(Kumi.Report.t()) :: String.t()
  def encode(report), do: report |> to_map() |> Jason.encode!(pretty: true)

  defp step_map(%Step{name: name, status: status, detail: detail}),
    do: %{name: name, status: status, detail: detail}

  defp plan_map(nil), do: nil

  defp plan_map(plan) do
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
