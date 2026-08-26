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
end
