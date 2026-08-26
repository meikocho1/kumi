defmodule Kumi.DiffCleanStateTest do
  # This is Spike 1's Go/No-Go signal: on a freshly migrated database,
  # what Kumi.Desired extracts from the Ash domains and what Kumi.Actual
  # introspects from pg_catalog must describe the exact same schema.
  use Kumi.Test.DataCase, async: false

  test "desired vs actual diff is empty on a clean, fully-migrated database" do
    desired = Kumi.Desired.extract([Kumi.Test.Domain, Kumi.Test.ResourceDomain])
    actual = Kumi.Actual.introspect(Kumi.Test.Repo)

    assert Kumi.Diff.diff(desired, actual) == []
  end

  test "Kumi.plan/3 (the public API) reports no changes on a clean database" do
    plan = Kumi.plan(Kumi.Test.Repo, [Kumi.Test.Domain, Kumi.Test.ResourceDomain])

    assert plan.entries == []
    assert Kumi.Plan.exit_code(plan) == 0
  end
end
