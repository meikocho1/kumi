defmodule Kumi.Desired.PgTypeTest do
  use ExUnit.Case, async: true

  alias Kumi.Desired.PgType
  alias Kumi.Plan.Safety
  alias Kumi.Schema.Column

  defmodule WeirdAshType do
    @moduledoc false
    # A stand-in for a custom Ash type. `migration_type/1` is an AshPostgres
    # extension point (checked via `function_exported?/3`, not part of
    # `Ash.Type`'s own behaviour — see `AshPostgres.MigrationGenerator.
    # migration_type/2`'s generic clause) that a user's own type module can
    # define to return anything at all. This one returns a map: neither an
    # atom nor a tuple, so it is the one shape that genuinely reaches
    # `Kumi.Desired.PgType.to_pg_name/1`'s `inspect/1` last resort. No real
    # Ash builtin type takes this path — it exists to prove the fail-closed
    # branch is reachable, not just asserted.
    def migration_type(_constraints), do: %{weird: true}
  end

  describe "from_ash/2" do
    test "uuid" do
      assert PgType.from_ash(Ash.Type.UUID, []) == "uuid"
    end

    test "string -> text" do
      assert PgType.from_ash(Ash.Type.String, trim?: true, allow_empty?: false) == "text"
    end

    test "ci_string -> citext" do
      assert PgType.from_ash(Ash.Type.CiString, []) == "citext"
    end

    test "decimal -> numeric" do
      assert PgType.from_ash(Ash.Type.Decimal, precision: :arbitrary, scale: :arbitrary) ==
               "numeric"
    end

    test "atom -> text (stored as string, not the atom name)" do
      assert PgType.from_ash(Ash.Type.Atom, one_of: [:lead, :won]) == "text"
    end

    test "utc_datetime_usec -> timestamp (constraints must carry precision, or this collapses to :utc_datetime)" do
      constraints = [precision: :microsecond, cast_dates_as: :start_of_day, timezone: :utc]
      assert PgType.from_ash(Ash.Type.UtcDatetimeUsec, constraints) == "timestamp"
    end

    test "utc_datetime -> timestamp" do
      constraints = [precision: :second, cast_dates_as: :start_of_day, timezone: :utc]
      assert PgType.from_ash(Ash.Type.UtcDatetime, constraints) == "timestamp"
    end

    test "map -> jsonb" do
      assert PgType.from_ash(Ash.Type.Map, []) == "jsonb"
    end

    test "date -> date (H4)" do
      assert PgType.from_ash(Ash.Type.Date, []) == "date"
    end

    test "duration -> interval, not the atom name \"duration\" (H4)" do
      # Empirically verified: Ecto.Adapters.Postgres.Connection.ecto_to_db/1
      # maps the :duration migration type to "interval". The generic atom
      # fallback used to return "duration", which never equals a real
      # udt_name — a permanent phantom type-change diff.
      assert PgType.from_ash(Ash.Type.Duration, []) == "interval"
    end
  end

  describe "precision_from_ash/2 (empirically verified against the real spike DB, see moduledoc)" do
    test "utc_datetime -> precision 0" do
      constraints = [precision: :second, cast_dates_as: :start_of_day, timezone: :utc]
      assert PgType.precision_from_ash(Ash.Type.UtcDatetime, constraints) == 0
    end

    test "utc_datetime_usec -> precision 6" do
      constraints = [precision: :microsecond, cast_dates_as: :start_of_day, timezone: :utc]
      assert PgType.precision_from_ash(Ash.Type.UtcDatetimeUsec, constraints) == 6
    end

    test "naive_datetime -> precision 0" do
      assert PgType.precision_from_ash(Ash.Type.NaiveDatetime, precision: :second) == 0
    end

    test "non-datetime types -> nil (nothing to compare)" do
      assert PgType.precision_from_ash(Ash.Type.UUID, []) == nil
      assert PgType.precision_from_ash(Ash.Type.String, trim?: true, allow_empty?: false) == nil
    end

    test "date -> precision 0, NOT nil (H4 — the actual bug: date is precision-bearing)" do
      assert PgType.precision_from_ash(Ash.Type.Date, []) == 0
    end

    test "duration -> precision 6, matching a bare `interval` column's Postgres default (H4)" do
      assert PgType.precision_from_ash(Ash.Type.Duration, []) == 6
    end
  end

  describe "parameterized and unmapped types never crash the plan" do
    # pgvector columns (an AI app's embedding storage) hit this: AshPostgres
    # returns {:vector, dimensions}, and Postgres reports udt_name "vector".
    test "Ash.Type.Vector with dimensions -> vector, matching udt_name" do
      assert PgType.from_ash(Ash.Type.Vector, dimensions: 1536) == "vector"
      assert PgType.from_ash(Ash.Type.Vector, []) == "vector"
    end

    test "a Vector with any dimensions clause still yields \"vector\" — dimension drift is invisible" do
      # The tuple clause (`to_pg_name/1`'s `{:vector, dimensions}` -> "vector")
      # intercepts EVERY shape here, including a malformed `dimensions`
      # value, before the `inspect/1` last-resort fallback is ever reached.
      # So this does NOT exercise the fail-closed path the old comment
      # claimed: it returns the concrete, real udt_name "vector", same as
      # any other Vector column. See the note on `to_pg_name/1` in
      # pg_type.ex: a 768 -> 1536 dimension change is structurally
      # invisible to Kumi, because both sides report "vector" regardless of
      # dimensions.
      assert PgType.from_ash(Ash.Type.Vector, dimensions: {:weird, %{}}) == "vector"
    end
  end

  describe "the inspect/1 last-resort fallback IS reachable (L1)" do
    test "a custom type's non-atom, non-tuple migration_type/1 reaches inspect/1" do
      assert PgType.from_ash(WeirdAshType, []) == "%{weird: true}"
    end

    test "...and that inspected value fails closed to DANGEROUS end to end" do
      # A real udt_name is always a bare word (see pg_catalog); it can never
      # equal an `inspect/1`-rendered Elixir term, so this classification
      # is not a coincidence of the test fixture — it holds for any input
      # that reaches this branch.
      weird_name = PgType.from_ash(WeirdAshType, [])
      col = %Column{name: "x", type: weird_name, nullable: true}

      assert {:dangerous, _reason} =
               Safety.classify({:change_column, "t", col, [{:type, weird_name, "text"}]})
    end
  end
end
