defmodule Kumi.Plan.FormatTest do
  use ExUnit.Case, async: true

  alias Kumi.Plan.Format
  alias Kumi.Schema.Column

  test "no ops renders the go/no-drift message" do
    assert Format.format([]) == "No changes. Database matches application definition.\n"
  end

  test "a drifted column renders as a '-' line marked drift, under its table" do
    col = %Column{name: "legacy_phone", type: "text", nullable: true, default: nil}
    output = Format.format([{:remove_column, "crm_accounts", col}])

    assert output =~ "crm_accounts:"
    assert output =~ "- column legacy_phone text  (in DB, not in code — drift)"
    assert output =~ "[DANGEROUS:"
  end

  test "safe, review, and dangerous ops each render their safety label" do
    safe_op = {:add_table, %Kumi.Schema.Table{name: "new_table"}}

    review_op =
      {:change_column, "t", %Column{name: "x", type: "text", nullable: false},
       [{:nullable, false, true}]}

    dangerous_op = {:drop_table, %Kumi.Schema.Table{name: "old_table"}}

    output = Format.format([safe_op, review_op, dangerous_op])

    assert output =~ "[SAFE:"
    assert output =~ "[REVIEW:"
    assert output =~ "[DANGEROUS:"
  end

  test "summary line reports safe/review/dangerous counts" do
    output = Format.format([{:add_table, %Kumi.Schema.Table{name: "t"}}])

    assert output =~ "1 safe / 0 review / 0 dangerous"
  end

  test "verbose mode adds a provenance line under each op" do
    output = Format.format([{:add_table, %Kumi.Schema.Table{name: "t"}}], verbose: true)

    assert output =~ "via: pg_catalog"
  end
end
