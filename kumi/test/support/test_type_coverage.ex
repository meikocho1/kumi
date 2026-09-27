defmodule Kumi.Test.TypeCoverage do
  @moduledoc false
  # Clean-state coverage (Kumi.DiffCleanStateTest) for column shapes that
  # used to read as permanent drift on a freshly migrated database:
  # storage types whose udt_name is not the migration type's own name
  # (:float -> float8, :binary -> bytea, :time_usec -> time), and literal
  # defaults Kumi.Schema.Default could not read back (`%{}` crashed the
  # plan, `'it''s'::text` was compared with its quotes still doubled).
  # A table of its own so none of the other fixtures' op counts move.

  use Ash.Resource,
    domain: Kumi.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "kumi_test_type_coverage"
    repo Kumi.Test.Repo
  end

  actions do
    defaults [:read]
  end

  attributes do
    uuid_primary_key :id

    attribute :ratio, :float
    attribute :payload, :binary
    attribute :blob, :term

    attribute :starts_at, :time do
      constraints precision: :microsecond
    end

    attribute :settings, :map, default: %{}
    attribute :note, :string, default: "it's"
  end
end
