defmodule Kumi.Plan do
  @moduledoc """
  A diff (with renames already resolved by `Kumi.Plan.Rename`), where every
  operation has been classified by `Kumi.Plan.Safety` and rolled up into
  summary counts. This is what `mix kumi.plan` renders and what
  `--check` inspects to decide its exit code.
  """

  alias Kumi.Plan.Safety

  @enforce_keys [:entries]
  defstruct [:entries, safe: 0, review: 0, dangerous: 0]

  @type entry :: {term(), Safety.level(), Safety.reason()}

  @type t :: %__MODULE__{
          entries: [entry()],
          safe: non_neg_integer(),
          review: non_neg_integer(),
          dangerous: non_neg_integer()
        }

  @spec build([term()]) :: t()
  def build(ops) do
    entries =
      Enum.map(ops, fn op ->
        {level, reason} = Safety.classify(op)
        {op, level, reason}
      end)

    counts = Enum.frequencies_by(entries, fn {_op, level, _reason} -> level end)

    %__MODULE__{
      entries: entries,
      safe: Map.get(counts, :safe, 0),
      review: Map.get(counts, :review, 0),
      dangerous: Map.get(counts, :dangerous, 0)
    }
  end

  @doc "Whether the plan contains anything a human should look at before applying."
  @spec needs_check?(t()) :: boolean()
  def needs_check?(%__MODULE__{review: review, dangerous: dangerous}),
    do: review > 0 or dangerous > 0

  @doc "Process exit code for `mix kumi.plan --check`: 1 if `needs_check?/1`, else 0."
  @spec exit_code(t()) :: 0 | 1
  def exit_code(plan), do: if(needs_check?(plan), do: 1, else: 0)

  @doc "Machine-friendly one-line summary, e.g. \"2 safe / 1 review / 0 dangerous\"."
  @spec summary_line(t()) :: String.t()
  def summary_line(%__MODULE__{safe: safe, review: review, dangerous: dangerous}),
    do: "#{safe} safe / #{review} review / #{dangerous} dangerous"
end
