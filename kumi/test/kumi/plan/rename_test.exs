defmodule Kumi.Plan.RenameTest do
  # Canonical diff case 5: rename detection via snapshot-as-hint. Simulates
  # a developer renaming an attribute in code while the DB still has the
  # old column: desired has the new name, actual has the old name, and an
  # on-disk snapshot fixture records the old name (never the new one) —
  # exactly what `Kumi.Plan.Rename` needs to upgrade the remove+add pair.
  #
  # Fixtures live under test/fixtures (inside the project, not /tmp) and
  # are removed in on_exit.
  use ExUnit.Case, async: true

  alias Kumi.Plan.Rename
  alias Kumi.Schema.Column

  @fixtures_root Path.join([File.cwd!(), "test", "fixtures", "rename_snapshots"])

  setup do
    dir = Path.join(@fixtures_root, "case_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  defp write_snapshot(dir, table, filename, sources) do
    table_dir = Path.join(dir, table)
    File.mkdir_p!(table_dir)

    attributes = Enum.map(sources, fn source -> %{"source" => source, "type" => "text"} end)
    File.write!(Path.join(table_dir, filename), Jason.encode!(%{"attributes" => attributes}))
  end

  test "same table, same type, old name in history, new name never seen -> possible_rename", %{
    dir: dir
  } do
    write_snapshot(dir, "crm_accounts", "20260101000000.json", ["id", "name", "industry"])

    old = %Column{name: "name", type: "text", nullable: false}
    new = %Column{name: "full_name", type: "text", nullable: false}

    ops = [{:remove_column, "crm_accounts", old}, {:add_column, "crm_accounts", new}]

    assert Rename.detect(ops, dir) == [{:possible_rename, "crm_accounts", old, new}]
  end

  test "no snapshot mentions the old name -> left as plain remove + add", %{dir: dir} do
    write_snapshot(dir, "crm_accounts", "20260101000000.json", ["id", "industry"])

    old = %Column{name: "name", type: "text", nullable: false}
    new = %Column{name: "full_name", type: "text", nullable: false}

    ops = [{:remove_column, "crm_accounts", old}, {:add_column, "crm_accounts", new}]

    assert Rename.detect(ops, dir) == ops
  end

  test "multiple same-type candidates are ambiguous -> left as plain remove + add", %{dir: dir} do
    write_snapshot(dir, "crm_accounts", "20260101000000.json", ["id", "a", "b"])

    a = %Column{name: "a", type: "text", nullable: true}
    b = %Column{name: "b", type: "text", nullable: true}
    c = %Column{name: "c", type: "text", nullable: true}
    d = %Column{name: "d", type: "text", nullable: true}

    ops = [
      {:remove_column, "crm_accounts", a},
      {:remove_column, "crm_accounts", b},
      {:add_column, "crm_accounts", c},
      {:add_column, "crm_accounts", d}
    ]

    assert Enum.sort(Rename.detect(ops, dir)) == Enum.sort(ops)
  end

  test "different types are never matched as a rename", %{dir: dir} do
    write_snapshot(dir, "crm_accounts", "20260101000000.json", ["id", "name"])

    old = %Column{name: "name", type: "text", nullable: false}
    new = %Column{name: "name_count", type: "numeric", nullable: false}

    ops = [{:remove_column, "crm_accounts", old}, {:add_column, "crm_accounts", new}]

    assert Rename.detect(ops, dir) == ops
  end

  test "provenance/3 reports the newest snapshot file mentioning a column", %{dir: dir} do
    write_snapshot(dir, "crm_accounts", "20260101000000.json", ["id", "name"])
    write_snapshot(dir, "crm_accounts", "20260201000000.json", ["id", "name", "industry"])

    assert Rename.provenance("crm_accounts", "industry", dir) == "20260201000000.json"
    assert Rename.provenance("crm_accounts", "nope", dir) == nil
  end
end
