defmodule Kumi.Desired.PgTypeTest do
  use ExUnit.Case, async: true

  alias Kumi.Desired.PgType

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
  end

  describe "parameterized and unmapped types never crash the plan" do
    # pgvector columns (an AI app's embedding storage) hit this: AshPostgres
    # returns {:vector, dimensions}, and Postgres reports udt_name "vector".
    test "Ash.Type.Vector with dimensions -> vector, matching udt_name" do
      assert PgType.from_ash(Ash.Type.Vector, dimensions: 1536) == "vector"
      assert PgType.from_ash(Ash.Type.Vector, []) == "vector"
    end

    test "an unrecognized shape yields a non-matching name instead of raising" do
      # Fails closed: whatever comes back cannot equal a real udt_name, so the
      # column surfaces as a change and Safety classifies the unknown pair
      # DANGEROUS — a plan that still runs beats one that crashes.
      assert is_binary(PgType.from_ash(Ash.Type.Vector, dimensions: {:weird, %{}}))
    end
  end
end
