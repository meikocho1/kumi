defmodule Kumi.Report.FormatTest do
  use ExUnit.Case, async: true

  alias Kumi.{Plan, Report}
  alias Kumi.Report.{Format, Step}
  alias Kumi.Schema.Table

  defp step(name, status, detail), do: %Step{name: name, status: status, detail: detail}

  test "renders one line per step, with icons, and the verdict" do
    plan = Plan.build([])

    steps = [
      step(:format, :pass, "all files formatted"),
      step(:compile, :pass, "compiled cleanly (no warnings)"),
      step(:test, :skipped, "skipped (by flag)"),
      step(:codegen, :pass, "up to date (no pending migrations)"),
      step(:plan, :pass, "clean — database matches application definition")
    ]

    text = Format.format(Report.build(steps, plan))

    assert text =~ "✓ format"
    assert text =~ "✓ compile"
    assert text =~ "○ test"
    assert text =~ "skipped (by flag)"
    assert text =~ "✓ codegen"
    assert text =~ "✓ plan"
    assert text =~ "Verdict: ready — Ready for PR"
  end

  test "blocked plan lists the REVIEW/DANGEROUS operations" do
    plan = Plan.build([{:drop_table, %Table{name: "accounts"}}])

    steps = [
      step(:format, :pass, "all files formatted"),
      step(:compile, :pass, "compiled cleanly (no warnings)"),
      step(:test, :pass, "10 tests, 0 failures"),
      step(:codegen, :pass, "up to date (no pending migrations)"),
      step(:plan, :fail, "blocked: 0 safe / 0 review / 1 dangerous")
    ]

    text = Format.format(Report.build(steps, plan))

    assert text =~ "✗ plan"
    assert text =~ "drop_table accounts"
    assert text =~ "DANGEROUS"
    assert text =~ "Verdict: blocked"
  end

  test "H3: change_primary_key/change_fk/change_index each describe without crashing" do
    alias Kumi.Schema.{ForeignKey, Index}

    fk = %ForeignKey{name: "fk", column: "a", references_table: "b", references_column: "id"}
    idx = %Index{name: "idx", columns: ["a"], unique: true}

    plan =
      Plan.build([
        {:change_primary_key, "t", ["id"], []},
        {:change_fk, "t", fk, %{fk | references_table: "c"}},
        {:change_index, "t", idx, %{idx | columns: ["b"]}}
      ])

    steps = [step(:plan, :fail, "blocked: 0 safe / 3 review / 0 dangerous")]
    text = Format.format(Report.build(steps, plan))

    assert text =~ "change_primary_key t"
    assert text =~ "change_fk t.a"
    assert text =~ "change_index t.idx"
  end
end
