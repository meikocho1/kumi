defmodule Kumi.Report.Step do
  @moduledoc """
  One step's outcome in a `Kumi.Report` (`mix kumi.report`): `:name` is the
  fixed step identifier (`:format`, `:compile`, `:test`, `:codegen`,
  `:plan`, always in that order), `:status` is `:pass` | `:fail` |
  `:skipped`, and `:detail` is a short human-readable explanation (the
  offending files, the failure count, why the step was skipped, ...).
  """

  @enforce_keys [:name, :status, :detail]
  defstruct [:name, :status, :detail]

  @type name :: :format | :compile | :test | :codegen | :plan
  @type status :: :pass | :fail | :skipped

  @type t :: %__MODULE__{
          name: name(),
          status: status(),
          detail: String.t()
        }
end
