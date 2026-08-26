defmodule Kumi.PrecisionDriftTest do
  # F18 fix: a precision-only mismatch (e.g. someone hand-ran `ALTER COLUMN
  # ... TYPE timestamp(0)` on a usec column) must be visible as a
  # change_column op — before this fix, both sides' `udt_name` is
  # "timestamp" regardless of precision, so Kumi.Diff was structurally blind
  # to it (see the v0.1 friction log F18). Runs inside the DataCase sandbox
  # transaction, rolled back automatically.
  use Kumi.Test.DataCase, async: false

  alias Kumi.Schema.Column

  test "actual column narrowed to timestamp(0) (Ash expects usec/6): applying the plan would widen it back" do
    Ecto.Adapters.SQL.query!(
      Kumi.Test.Repo,
      "ALTER TABLE kumi_test_accounts ALTER COLUMN inserted_at TYPE timestamp(0)",
      []
    )

    desired = Kumi.Desired.extract([Kumi.Test.Domain, Kumi.Test.ResourceDomain])
    actual = Kumi.Actual.introspect(Kumi.Test.Repo)
    diff = Kumi.Diff.diff(desired, actual)

    assert [{:change_column, "kumi_test_accounts", %Column{name: "inserted_at"}, changes}] = diff
    assert {:datetime_precision, 6, 0} in changes

    assert {:review, reason} = Kumi.Plan.Safety.classify(hd(diff))
    assert reason =~ "widens"
  end

  test "actual column widened to timestamp(6) (Ash expects second/0): applying the plan would narrow it back" do
    Ecto.Adapters.SQL.query!(
      Kumi.Test.Repo,
      "ALTER TABLE kumi_test_deals ALTER COLUMN closed_at TYPE timestamp(6)",
      []
    )

    desired = Kumi.Desired.extract([Kumi.Test.Domain, Kumi.Test.ResourceDomain])
    actual = Kumi.Actual.introspect(Kumi.Test.Repo)
    diff = Kumi.Diff.diff(desired, actual)

    assert [{:change_column, "kumi_test_deals", %Column{name: "closed_at"}, changes}] = diff
    assert {:datetime_precision, 0, 6} in changes

    assert {:review, reason} = Kumi.Plan.Safety.classify(hd(diff))
    assert reason =~ "narrows"
    assert reason =~ "does not fail"
  end
end
