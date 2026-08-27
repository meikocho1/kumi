defmodule Kumi.ApplyTest do
  # Mirrors Kumi.ActualDriftTest's drift-induction/cleanup pattern: DDL runs
  # inside the DataCase sandbox transaction, so it (and anything Kumi.Apply
  # does on top of it) is rolled back automatically at the end of the test —
  # even if a test fails mid-way, nothing here needs a manual on_exit.
  use Kumi.Test.DataCase, async: false

  alias Kumi.Schema.Column

  @domains [Kumi.Test.Domain, Kumi.Test.ResourceDomain]

  test "repairs additive drift (a manually-dropped nullable column), and a fresh plan is clean" do
    # Kumi.Apply itself takes no Mix/env stance (the dev-only guard lives in
    # Mix.Tasks.Kumi.Apply) — running it here under MIX_ENV=test proves that.
    assert Mix.env() == :test

    Ecto.Adapters.SQL.query!(
      Kumi.Test.Repo,
      "ALTER TABLE kumi_test_accounts DROP COLUMN industry",
      []
    )

    plan = Kumi.plan(Kumi.Test.Repo, @domains)

    assert [{{:add_column, "kumi_test_accounts", %Column{name: "industry"}}, :safe, _reason}] =
             plan.entries

    result = Kumi.Apply.run(Kumi.Test.Repo, plan, domains: @domains)

    assert result.skipped == []
    assert result.verified

    assert [{{:add_column, "kumi_test_accounts", %Column{name: "industry"}}, sql}] =
             result.executed

    assert sql == "ALTER TABLE kumi_test_accounts ADD COLUMN industry text;"

    fresh_plan = Kumi.plan(Kumi.Test.Repo, @domains)
    assert fresh_plan.entries == []
  end

  test "a :dangerous op (drifted extra column) is skipped, never executed" do
    Ecto.Adapters.SQL.query!(
      Kumi.Test.Repo,
      "ALTER TABLE kumi_test_accounts ADD COLUMN legacy_phone text",
      []
    )

    plan = Kumi.plan(Kumi.Test.Repo, @domains)

    assert [
             {{:remove_column, "kumi_test_accounts", %Column{name: "legacy_phone"}}, :dangerous,
              _reason}
           ] = plan.entries

    result = Kumi.Apply.run(Kumi.Test.Repo, plan, domains: @domains)

    assert result.executed == []
    assert result.verified

    assert [{{:remove_column, "kumi_test_accounts", %Column{name: "legacy_phone"}}, reason}] =
             result.skipped

    assert reason =~ "not :safe (dangerous)"

    # the drifted state is untouched: legacy_phone is still there.
    actual = Kumi.Actual.introspect(Kumi.Test.Repo)
    table = Enum.find(actual, &(&1.name == "kumi_test_accounts"))
    assert Enum.any?(table.columns, &(&1.name == "legacy_phone"))
  end

  test "a :safe add_column with a default is skipped (ADD COLUMN can't set it — partial-repair guard)" do
    # `stage` is nullable with a literal default (:lead) — Safety.classify/1
    # only looks at `nullable`, so this is still classified :safe; Apply
    # must catch the default itself, or ADD COLUMN would come back with the
    # column present but its default silently unset (residual drift).
    Ecto.Adapters.SQL.query!(
      Kumi.Test.Repo,
      "ALTER TABLE kumi_test_deals DROP COLUMN stage",
      []
    )

    plan = Kumi.plan(Kumi.Test.Repo, @domains)

    assert [
             {{:add_column, "kumi_test_deals", %Column{name: "stage", default: default}}, :safe,
              _reason}
           ] = plan.entries

    refute is_nil(default)

    result = Kumi.Apply.run(Kumi.Test.Repo, plan, domains: @domains)

    assert result.executed == []
    assert result.verified

    assert [{{:add_column, "kumi_test_deals", %Column{name: "stage"}}, reason}] = result.skipped
    assert reason =~ "default"

    # untouched: stage is still missing from the DB.
    actual = Kumi.Actual.introspect(Kumi.Test.Repo)
    table = Enum.find(actual, &(&1.name == "kumi_test_deals"))
    refute Enum.any?(table.columns, &(&1.name == "stage"))
  end
end
