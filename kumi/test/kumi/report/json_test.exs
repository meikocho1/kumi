defmodule Kumi.Report.JsonTest do
  use ExUnit.Case, async: true

  alias Kumi.{Plan, Report}
  alias Kumi.Report.{Json, Step}
  alias Kumi.Schema.Table

  defp step(name, status, detail), do: %Step{name: name, status: status, detail: detail}

  defp steps(plan_step) do
    [
      step(:format, :pass, "all files formatted"),
      step(:compile, :pass, "compiled cleanly (no warnings)"),
      step(:test, :pass, "10 tests, 0 failures"),
      step(:codegen, :pass, "up to date (no pending migrations)"),
      plan_step
    ]
  end

  test "to_map schema: 5 steps in order, verdict, plan summary + operations" do
    plan = Plan.build([{:drop_table, %Table{name: "accounts"}}])
    plan_step = step(:plan, :fail, "blocked")

    report = Report.build(steps(plan_step), plan)
    map = Json.to_map(report)

    assert Enum.map(map.steps, & &1.name) == [:format, :compile, :test, :codegen, :plan]
    assert map.verdict == :blocked
    assert map.plan.safe == 0
    assert map.plan.dangerous == 1
    assert [%{description: "drop_table accounts", level: :dangerous}] = map.plan.operations
  end

  test "clean plan -> plan.operations is empty, verdict ready" do
    plan = Plan.build([])
    report = Report.build(steps(step(:plan, :pass, "clean")), plan)
    map = Json.to_map(report)

    assert map.verdict == :ready
    assert map.plan.operations == []
  end

  test "plan step that could not run -> plan is null" do
    report = Report.build(steps(step(:plan, :fail, "could not build plan: db down")), nil)
    map = Json.to_map(report)

    assert map.verdict == :failed
    assert map.plan == nil
  end

  test "encode/1 produces valid, round-trippable JSON" do
    plan = Plan.build([])
    report = Report.build(steps(step(:plan, :pass, "clean")), plan)

    json = Json.encode(report)
    decoded = Jason.decode!(json)

    assert decoded["verdict"] == "ready"
    assert length(decoded["steps"]) == 5
    assert decoded["plan"]["safe"] == 0
  end
end
