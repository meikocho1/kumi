defmodule Kumi.PlanTest do
  # Tests the underlying, pure functions that `mix kumi.plan --check`
  # relies on for its exit code, rather than spawning the mix task itself.
  use ExUnit.Case, async: true

  alias Kumi.Plan
  alias Kumi.Schema.Table

  test "no ops -> zero counts, no check needed, exit code 0" do
    plan = Plan.build([])

    assert plan.safe == 0
    assert plan.review == 0
    assert plan.dangerous == 0
    refute Plan.needs_check?(plan)
    assert Plan.exit_code(plan) == 0
  end

  test "only safe ops -> no check needed, exit code 0" do
    plan = Plan.build([{:add_table, %Table{name: "t"}}])

    assert plan.safe == 1
    refute Plan.needs_check?(plan)
    assert Plan.exit_code(plan) == 0
  end

  test "a review op needs check and exits non-zero" do
    idx = %Kumi.Schema.Index{name: "idx", columns: ["x"], unique: true}
    plan = Plan.build([{:add_index, "t", idx}])

    assert plan.review == 1
    assert Plan.needs_check?(plan)
    assert Plan.exit_code(plan) == 1
  end

  test "a dangerous op needs check and exits non-zero" do
    plan = Plan.build([{:drop_table, %Table{name: "t"}}])

    assert plan.dangerous == 1
    assert Plan.needs_check?(plan)
    assert Plan.exit_code(plan) == 1
  end

  test "summary_line renders machine-friendly counts" do
    plan =
      Plan.build([
        {:add_table, %Table{name: "t"}},
        {:drop_table, %Table{name: "u"}}
      ])

    assert Plan.summary_line(plan) == "1 safe / 0 review / 1 dangerous"
  end
end
