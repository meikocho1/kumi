defmodule Kumi.DiffFkOnDeleteTest do
  # Friction log P16/P17: a real host application shipped a foreign key with no
  # ON DELETE and only found out when a user could not delete their account.
  # The plan had every ingredient to catch it — both sides model foreign keys —
  # but on_delete was not part of the model, so nothing compared it.
  use ExUnit.Case, async: true

  alias Kumi.Schema.{Column, ForeignKey, Table}

  @col %Column{name: "id", type: "uuid", nullable: false, default: nil, datetime_precision: nil}

  defp fk(on_delete) do
    %ForeignKey{
      name: "promises_created_by_id_fkey",
      column: "created_by_id",
      references_table: "accounts",
      references_column: "id",
      on_delete: on_delete
    }
  end

  defp tables(fk), do: [%Table{name: "promises", columns: [@col], foreign_keys: [fk]}]

  test "on_delete defaults to :nothing, matching Postgres' NO ACTION" do
    bare = %ForeignKey{
      name: "t_a_fkey",
      column: "account_id",
      references_table: "accounts",
      references_column: "id"
    }

    assert bare.on_delete == :nothing
  end

  test "a drifted on_delete produces its own op, not change_fk" do
    desired = fk(:delete)
    actual = fk(:nothing)

    assert Kumi.Diff.diff(tables(desired), tables(actual)) ==
             [{:change_fk_on_delete, "promises", desired, actual}]
  end

  test "the same on_delete on both sides produces no ops" do
    assert Kumi.Diff.diff(tables(fk(:delete)), tables(fk(:delete))) == []
  end

  test "a changed target is reported once, as change_fk, not twice" do
    desired = fk(:delete)
    actual = %{fk(:nothing) | references_table: "legacy_accounts"}

    # When the target itself moved, only that operation is reported. Emitting
    # both would turn one constraint replacement into two items of homework.
    assert Kumi.Diff.diff(tables(desired), tables(actual)) ==
             [{:change_fk, "promises", desired, actual}]
  end

  test "the op is REVIEW — never SAFE, in either direction" do
    assert {:review, message} =
             Kumi.Plan.Safety.classify(
               {:change_fk_on_delete, "promises", fk(:delete), fk(:nothing)}
             )

    assert message =~ "on_delete"

    assert {:review, _} =
             Kumi.Plan.Safety.classify(
               {:change_fk_on_delete, "promises", fk(:nothing), fk(:delete)}
             )
  end

  test "no SQL is rendered for it — DROP + ADD is not something to run unattended" do
    assert Kumi.Plan.SQL.render({:change_fk_on_delete, "promises", fk(:delete), fk(:nothing)}) ==
             :unsupported
  end

  test "the fix hint names the constraint and both sides" do
    lines = Kumi.Plan.FixHint.lines({:change_fk_on_delete, "promises", fk(:delete), fk(:nothing)})
    text = Enum.join(lines, "\n")

    assert text =~ "promises_created_by_id_fkey"
    assert text =~ ":nothing"
    assert text =~ ":delete"
  end
end
