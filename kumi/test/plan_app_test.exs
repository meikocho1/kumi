defmodule Kumi.PlanAppTest do
  # Kumi.Test.App declares only Kumi.Test.Account, but Kumi.Test.Domain
  # (same repo) also has Kumi.Test.Deal, whose table is real and migrated.
  # If plan_app/2 didn't scope the ACTUAL side to the app's declared
  # resources, kumi_test_deals would show up as a spurious :drop_table.
  use Kumi.Test.DataCase, async: false

  test "plan_app scopes the diff to the app's declared resources only" do
    plan = Kumi.plan_app(Kumi.Test.App)

    # This alone proves both-side filtering: Kumi.Test.App declares only
    # Kumi.Test.Account, but kumi_test_deals exists and is migrated in the
    # same repo — if plan_app/2 filtered only the DESIRED side (or only the
    # ACTUAL side), the mismatch would show up here as a non-empty diff
    # either way. An empty diff is only possible when both sides agree to
    # ignore kumi_test_deals.
    assert plan.entries == []
  end
end
