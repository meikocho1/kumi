defmodule Kumi.App.Verifiers.ValidatePrimaryKey do
  @moduledoc """
  Every resource declared under `resources do ... end` must have exactly
  `[:id]` as its primary key.

  This is a deliberate product ceiling, not an oversight: `kumi_admin`
  assumes `record.id` throughout (row links, the show-page header, child
  links, `Ash.Query.sort(:id)`, select option values) rather than deriving
  from `Ash.Resource.Info.primary_key/1`. Supporting composite or renamed
  primary keys is a real feature — a half-measure that derives
  single-column PKs would still break on composite ones — so until that
  feature exists, a resource declaring a different primary key is
  rejected here rather than compiling clean and failing at runtime (an
  invalid sort on the index page, a `KeyError` in the admin's
  `Format.record_label/1`). Such a resource can still be used as plain
  Ash — it just can't be listed under a `Kumi.App`'s `resources`.
  """
  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)

    dsl_state
    |> Verifier.get_entities([:resources])
    |> Enum.find_value(:ok, fn %{resource: resource} ->
      case Ash.Resource.Info.primary_key(resource) do
        [:id] -> nil
        primary_key -> {:error, primary_key_error(module, resource, primary_key)}
      end
    end)
  end

  defp primary_key_error(module, resource, primary_key) do
    DslError.exception(
      module: module,
      path: [:resources, :resource],
      message: """
      #{inspect(resource)} has primary key #{inspect(primary_key)}, but kumi_admin \
      only manages resources whose primary key is exactly `[:id]`.

      A resource with a different primary key cannot be managed by the admin \
      today — it can still be used as plain Ash, just not declared under \
      `resources` in this `Kumi.App`.
      """
    )
  end
end
