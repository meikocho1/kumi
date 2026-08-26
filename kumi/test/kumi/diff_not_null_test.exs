defmodule Kumi.DiffNotNullTest do
  # Canonical diff case 3: nullable -> not null. Pure struct manipulation,
  # no database needed — Kumi.Diff only ever compares in-memory Table
  # structs, so we can build both sides by hand.
  use ExUnit.Case, async: true

  alias Kumi.Schema.{Column, Table}

  test "actual column is nullable, desired requires NOT NULL -> change_column reports the tightening" do
    desired = [
      %Table{name: "t", columns: [%Column{name: "email", type: "text", nullable: false}]}
    ]

    actual = [%Table{name: "t", columns: [%Column{name: "email", type: "text", nullable: true}]}]

    assert [{:change_column, "t", %Column{name: "email"}, changes}] =
             Kumi.Diff.diff(desired, actual)

    assert {:nullable, false, true} in changes
  end
end
