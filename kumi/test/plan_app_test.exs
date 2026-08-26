defmodule Kumi.PlanAppTest do
  # Kumi.Test.App declares only Kumi.Test.Account, but Kumi.Test.Domain
  # (same repo) also has Kumi.Test.Deal, whose table is real and migrated.
  # If plan_app/2 didn't scope the ACTUAL side to the app's declared
  # resources, kumi_test_deals would show up as a spurious :drop_table.
  use Kumi.Test.DataCase, async: false

  test "plan_app scopes the diff to the app's declared resources only" do
    plan = Kumi.plan_app(Kumi.Test.App)

    assert plan.entries == []

    refute Enum.any?(plan.entries, fn {op, _, _} ->
             match?({:drop_table, %{name: "kumi_test_deals"}}, op)
           end)
  end
end
