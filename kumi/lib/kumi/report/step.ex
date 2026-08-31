defmodule Kumi.Report.Step do
  @moduledoc """
  One step's outcome in a `Kumi.Report` (`mix kumi.report`): `:name` is the
  fixed step identifier (`:format`, `:compile`, `:test`, `:codegen`,
  `:plan`, always in that order), `:status` is `:pass` | `:fail` |
  `:skipped`, and `:detail` is a short human-readable explanation (the
  offending files, the failure count, why the step was skipped, ...).

  `:detail` is always English — `mix kumi.report --json` is not localized,
  and that is the string it emits. `:detail_key` carries what that English
  sentence *was*, as `{key, bindings}` into `Kumi.Plan.Locale`, so the
  human-readable formatter can re-render it in another locale. It is `nil`
  for a detail that is not a sentence Kumi wrote — a captured compiler
  diagnostic, `mix test`'s own summary line — because there is nothing to
  translate and guessing would mangle the output being reported.
  """

  @enforce_keys [:name, :status, :detail]
  defstruct [:name, :status, :detail, detail_key: nil]

  @type name :: :format | :compile | :test | :codegen | :plan
  @type status :: :pass | :fail | :skipped

  @type t :: %__MODULE__{
          name: name(),
          status: status(),
          detail: String.t(),
          detail_key: {atom(), keyword()} | nil
        }
end
