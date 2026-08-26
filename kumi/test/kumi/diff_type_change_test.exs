defmodule Kumi.DiffTypeChangeTest do
  # Canonical diff case 4: type change (e.g. text -> numeric). Pure struct
  # manipulation, no database needed.
  use ExUnit.Case, async: true

  alias Kumi.Schema.{Column, Table}

  test "actual column is text, desired column is numeric -> change_column reports the type change" do
    desired = [%Table{name: "t", columns: [%Column{name: "amount", type: "numeric", nullable: true}]}]
    actual = [%Table{name: "t", columns: [%Column{name: "amount", type: "text", nullable: true}]}]

    assert [{:change_column, "t", %Column{name: "amount"}, changes}] = Kumi.Diff.diff(desired, actual)
    assert {:type, "numeric", "text"} in changes
  end
end
