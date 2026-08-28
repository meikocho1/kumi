defmodule Kumi.Schema.Ident do
  @moduledoc """
  Quotes a Postgres identifier: wraps it in double quotes, doubling any
  embedded double quote.

  This lives next to `Kumi.Schema.Column`/`Table`/`Index`/`ForeignKey` (not
  under `Kumi.Plan` or `Kumi.Probe`) because it is a property of an
  identifier itself — every module that turns one of those structs' names
  into SQL text needs it, and neither module owning it should have to
  depend on the other. Both do today: `Kumi.Plan.SQL` (whose output
  `Kumi.Apply` EXECUTES) and `Kumi.Probe` (read-only `SELECT count(*)`
  queries) route every table/column/constraint/index name through this
  single implementation, so there is exactly one place that decides how a
  name that needs quoting (mixed case, a reserved word) gets rendered.

  Unquoted, an identifier like `order` (a reserved word) or `myColumn`
  (mixed case) either raises a syntax error or — worse — Postgres folds it
  to lowercase and silently creates a different object than the one
  requested. See `Kumi.Plan.SQL`'s moduledoc for the concrete scenario this
  was written to close (M1).
  """

  @spec quote_ident(String.t()) :: String.t()
  def quote_ident(name), do: "\"" <> String.replace(name, "\"", "\"\"") <> "\""
end
