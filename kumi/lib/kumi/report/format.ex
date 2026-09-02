defmodule Kumi.Report.Format do
  @moduledoc """
  Renders a `Kumi.Report` as the human-readable checklist `mix kumi.report`
  prints by default (blueprint §8): one line per step (`✓`/`✗`/`○` +
  detail), the blocking operations when the plan is `:blocked`, and a
  final verdict line.

  The step names, the operation descriptions and the `SAFE`/`REVIEW`/
  `DANGEROUS` labels are identifiers, not prose, and stay as they are in
  every locale. What `:locale` changes is every sentence: the safety
  reason, the verdict, and each step's detail — a report that says
  `判定: ready` under `all files formatted` is half a translation.
  A detail Kumi didn't write (a captured compiler diagnostic, `mix test`'s
  own summary) has no key and is printed as captured.
  `Kumi.Report.Json` is never localized.
  """

  alias Kumi.Report.Step

  @spec format(Kumi.Report.t(), keyword()) :: String.t()
  def format(report, opts \\ [])

  def format(%Kumi.Report{steps: steps, plan: plan, verdict: verdict}, opts) do
    locale = Keyword.get(opts, :locale, Kumi.Locale.base_locale())
    step_lines = Enum.map_join(steps, "\n", &step_line(&1, locale))
    ops = blocked_ops_lines(plan, locale)

    step_lines <> "\n" <> ops <> "\n" <> verdict_line(verdict, locale)
  end

  defp step_line(%Step{name: name, status: status} = step, locale) do
    "#{icon(status)} #{pad(name)} #{step_detail(step, locale)}"
  end

  # The stored `detail` is already the base-locale string, so returning it
  # verbatim there keeps `--json` and the printed report byte-identical.
  defp step_detail(%Step{detail: detail, detail_key: nil}, _locale), do: detail

  defp step_detail(%Step{detail: detail, detail_key: {key, bindings}}, locale) do
    if locale == Kumi.Locale.base_locale() do
      detail
    else
      Kumi.Plan.Locale.translate(locale, key, bindings)
    end
  end

  defp icon(:pass), do: "✓"
  defp icon(:fail), do: "✗"
  defp icon(:skipped), do: "○"

  defp pad(name), do: name |> to_string() |> String.pad_trailing(8)

  defp blocked_ops_lines(nil, _locale), do: ""

  defp blocked_ops_lines(plan, locale) do
    plan.entries
    |> Enum.filter(fn {_op, level, _reason} -> level in [:review, :dangerous] end)
    |> Enum.map_join("", fn {op, level, reason} ->
      # The stored reason is the canonical English one (that is what
      # `--json` serializes); re-render it from the op for any other locale.
      reason = if locale == Kumi.Locale.base_locale(), do: reason, else: localized(op, locale)

      "    - #{Kumi.Plan.Format.describe(op)}  [#{String.upcase(to_string(level))}: #{reason}]\n"
    end)
  end

  defp localized(op, locale) do
    {_level, reason} = Kumi.Plan.Safety.classify(op, locale)
    reason
  end

  defp verdict_line(verdict, locale) do
    "\n" <> Kumi.Plan.Locale.translate(locale, :"verdict_#{verdict}")
  end
end
