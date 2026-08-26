defmodule Kumi.ReportTest do
  # Tests the pure verdict/exit-code derivation `mix kumi.report` relies
  # on, from fake step results — no subprocess, no database. See
  # test/mix/tasks/kumi.report_test.exs for the real end-to-end run.
  use ExUnit.Case, async: true

  alias Kumi.{Plan, Report}
  alias Kumi.Report.Step
  alias Kumi.Schema.{Index, Table}

  defp step(name, status, detail \\ "detail"),
    do: %Step{name: name, status: status, detail: detail}

  defp passing_steps(overrides) do
    for name <- [:format, :compile, :test, :codegen, :plan] do
      Map.get(overrides, name, step(name, :pass))
    end
  end

  test "all steps pass, empty plan -> ready, exit 0 (default and strict)" do
    plan = Plan.build([])
    steps = passing_steps(%{plan: step(:plan, :pass)})
    report = Report.build(steps, plan)

    assert report.verdict == :ready
    assert Report.exit_code(report) == 0
    assert Report.exit_code(report, strict: true) == 0
  end

  test "all steps pass, SAFE-only plan -> ready_with_migration, exit 0 default / 1 strict" do
    plan = Plan.build([{:add_table, %Table{name: "t"}}])
    steps = passing_steps(%{plan: step(:plan, :pass)})
    report = Report.build(steps, plan)

    assert report.verdict == :ready_with_migration
    assert Report.exit_code(report) == 0
    assert Report.exit_code(report, strict: true) == 1
  end

  test "REVIEW/DANGEROUS plan -> blocked, exit 1 even without --strict" do
    idx = %Index{name: "idx", columns: ["x"], unique: true}
    plan = Plan.build([{:add_index, "t", idx}, {:drop_table, %Table{name: "u"}}])
    steps = passing_steps(%{plan: step(:plan, :fail, "blocked")})
    report = Report.build(steps, plan)

    assert report.verdict == :blocked
    assert plan.review == 1
    assert plan.dangerous == 1
    assert Report.exit_code(report) == 1
  end

  test "format failure alone -> failed, even though the plan is clean" do
    plan = Plan.build([])
    steps = passing_steps(%{format: step(:format, :fail, "2 files not formatted")})
    report = Report.build(steps, plan)

    assert report.verdict == :failed
    assert Report.exit_code(report) == 1
  end

  test "compile failure cascades: test/codegen/plan reported skipped, verdict failed" do
    steps = [
      step(:format, :pass),
      step(:compile, :fail, "warning treated as error"),
      step(:test, :skipped, "skipped (compile failed)"),
      step(:codegen, :skipped, "skipped (compile failed)"),
      step(:plan, :skipped, "skipped (compile failed)")
    ]

    report = Report.build(steps, nil)

    assert report.verdict == :failed
    assert Report.exit_code(report) == 1
  end

  test "plan step errors out (no %Kumi.Plan{} produced) -> failed, not blocked" do
    steps = passing_steps(%{plan: step(:plan, :fail, "could not build plan: db down")})
    report = Report.build(steps, nil)

    # Distinguishing failed-to-run from a real REVIEW/DANGEROUS finding
    # matters: an AI agent must not treat "couldn't check" as "found a
    # dangerous op to review".
    assert report.verdict == :failed
    assert Report.exit_code(report) == 1
  end

  test "test failure does not block codegen/plan from running or the plan from deciding the verdict" do
    plan = Plan.build([])
    steps = passing_steps(%{test: step(:test, :fail, "1 tests, 1 failures")})
    report = Report.build(steps, plan)

    # A test failure is still a hard failure overall (verdict :failed) —
    # this only asserts it's *derivable* from a plan that ran fine
    # alongside it, i.e. the orchestrator didn't skip codegen/plan.
    assert report.verdict == :failed
  end
end
