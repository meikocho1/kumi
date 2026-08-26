defmodule Kumi.Report do
  @moduledoc """
  A verdict for `mix kumi.report` (blueprint §8: the AI patch pipeline's
  verification harness — "AI patches source → `mix kumi.report` runs the
  full validation chain and emits a machine-readable verdict").

  This module holds only the pure derivation: given the five steps'
  already-computed outcomes (`Kumi.Report.Step`, in fixed order `:format`,
  `:compile`, `:test`, `:codegen`, `:plan`) and the `%Kumi.Plan{}` the
  `:plan` step produced (or `nil` if it didn't run), `build/2` derives the
  overall `:verdict` and `exit_code/2` derives the process exit code.
  `Mix.Tasks.Kumi.Report` (the actual mix task) does the orchestration —
  shelling out to `mix format`/`mix compile`/`mix test`/`mix ash.codegen`
  and calling `Kumi.plan`/`Kumi.plan_app` in-process — and hands its
  results here so the verdict logic itself stays testable without ever
  spawning a subprocess or touching a database.

  ## Verdict semantics

    * `:failed` — `:format`, `:compile`, `:test`, or `:codegen` failed
      (or was skipped as a result — e.g. a compile failure skips
      `:test`/`:codegen`/`:plan`), or the `:plan` step could not be
      computed at all (no `%Kumi.Plan{}` to show).
    * `:blocked` — every other step passed, but the plan has at least one
      REVIEW or DANGEROUS operation.
    * `:ready_with_migration` — every step passed and the plan is
      SAFE-only (non-zero `safe`, zero `review`/`dangerous`).
    * `:ready` — every step passed and the plan is empty (zero ops).
  """

  alias Kumi.Report.Step

  @enforce_keys [:steps, :verdict]
  defstruct [:steps, :verdict, plan: nil]

  @type verdict :: :ready | :ready_with_migration | :blocked | :failed

  @type t :: %__MODULE__{
          steps: [Step.t()],
          verdict: verdict(),
          plan: Kumi.Plan.t() | nil
        }

  @doc """
  Builds a `%Kumi.Report{}` from the five steps' outcomes (in order) and
  the plan they produced (`nil` if the `:plan` step didn't run or errored).
  """
  @spec build([Step.t()], Kumi.Plan.t() | nil) :: t()
  def build(steps, plan \\ nil) do
    %__MODULE__{steps: steps, plan: plan, verdict: derive_verdict(steps, plan)}
  end

  @doc """
  Process exit code: 0 for `:ready`/`:ready_with_migration`, 1 otherwise.
  With `strict: true`, only `:ready` exits 0.
  """
  @spec exit_code(t(), keyword()) :: 0 | 1
  def exit_code(%__MODULE__{verdict: verdict}, opts \\ []) do
    strict? = Keyword.get(opts, :strict, false)

    case verdict do
      :ready -> 0
      :ready_with_migration -> if strict?, do: 1, else: 0
      _ -> 1
    end
  end

  defp derive_verdict(steps, plan) do
    plan_step = Enum.find(steps, &(&1.name == :plan))

    cond do
      Enum.any?(steps, &(&1.name != :plan and &1.status == :fail)) ->
        :failed

      plan_step == nil or plan_step.status != :pass or plan == nil ->
        failed_or_blocked(plan_step, plan)

      plan.safe > 0 ->
        :ready_with_migration

      true ->
        :ready
    end
  end

  defp failed_or_blocked(%Step{status: :fail}, plan) when not is_nil(plan), do: :blocked
  defp failed_or_blocked(_plan_step, _plan), do: :failed
end
