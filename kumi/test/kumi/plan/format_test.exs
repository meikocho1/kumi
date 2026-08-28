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

  test "fix_hints: true adds indented fix lines under each op; absent by default" do
    col = %Column{name: "email", type: "text", nullable: false, default: nil}
    ops = [{:add_column, "crm_accounts", col}]

    with_hints = Format.format(ops, fix_hints: true)
    without_hints = Format.format(ops)

    assert with_hints =~ "\n      fix: mix ash.codegen"
    assert with_hints =~ ~s(ALTER TABLE "crm_accounts" ADD COLUMN "email" text NOT NULL;)
    refute without_hints =~ "fix:"
  end

  test "verbose mode adds a provenance line under each op" do
    output = Format.format([{:add_table, %Kumi.Schema.Table{name: "t"}}], verbose: true)

    assert output =~ "via: pg_catalog"
  end

  test "findings are rendered indented under their matching op, not under unrelated ops" do
    op = {:remove_column, "t", %Column{name: "notes", type: "text", nullable: true}}
    other_op = {:add_table, %Kumi.Schema.Table{name: "u"}}

    finding = %Kumi.Plan.Finding{
      op: op,
      query_description: "count(*) FROM t WHERE notes IS NOT NULL",
      count: 3,
      note: "3 rows contain data that would be lost"
    }

    output = Format.format([op, other_op], findings: [finding])

    lines = String.split(output, "\n")
    op_index = Enum.find_index(lines, &(&1 =~ "notes"))
    finding_index = Enum.find_index(lines, &(&1 =~ "finding:"))

    assert output =~ "finding: 3 rows contain data that would be lost"
    assert finding_index == op_index + 1
  end

  test "H3: change_primary_key/change_fk/change_index render end-to-end (format_op, classify, fix hints) without crashing" do
    alias Kumi.Schema.{ForeignKey, Index}

    pk_op = {:change_primary_key, "t", ["id"], []}

    fk_op =
      {:change_fk, "t",
       %ForeignKey{
         name: "fk",
         column: "account_id",
         references_table: "b",
         references_column: "id"
       },
       %ForeignKey{
         name: "fk",
         column: "account_id",
         references_table: "c",
         references_column: "id"
       }}

    idx_op =
      {:change_index, "t", %Index{name: "idx", columns: ["a"], unique: true},
       %Index{name: "idx", columns: ["b"], unique: false}}

    output = Format.format([pk_op, fk_op, idx_op], verbose: true, fix_hints: true)

    assert output =~ "primary key"
    assert output =~ "fk account_id"
    assert output =~ "index idx"
    assert output =~ "[REVIEW:"
    assert output =~ "fix: mix ash.codegen"
    assert output =~ "0 safe / 3 review / 0 dangerous"
  end
end
