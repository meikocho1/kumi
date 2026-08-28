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
    # Something actually executed and the post-commit re-diff found no
    # residual drift — the honest "checked, and it held" state (not the
    # boolean this used to be, which couldn't distinguish this from a
    # zero-execution run — see the two tests below).
    assert result.verified == :ok

    assert [{{:add_column, "kumi_test_accounts", %Column{name: "industry"}}, sql}] =
             result.executed

    assert sql == ~s(ALTER TABLE "kumi_test_accounts" ADD COLUMN "industry" text;)

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
    # Nothing ran, so nothing was checked either — :not_run, not the old
    # boolean `true` (which lied: "verified" implies something was
    # actually re-diffed, and here nothing was).
    assert result.verified == :not_run

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
    # Same reasoning as the :dangerous test above: skipped, not executed —
    # :not_run, never a claimed :ok.
    assert result.verified == :not_run

    assert [{{:add_column, "kumi_test_deals", %Column{name: "stage"}}, reason}] = result.skipped
    assert reason =~ "default"

    # untouched: stage is still missing from the DB.
    actual = Kumi.Actual.introspect(Kumi.Test.Repo)
    table = Enum.find(actual, &(&1.name == "kumi_test_deals"))
    refute Enum.any?(table.columns, &(&1.name == "stage"))
  end

  # verify!/3's raise is the real protection here (the report's real
  # danger: `verified` used to be a boolean that could never be `false`),
  # but every genuine :safe+allowlisted+renderable op that Kumi.Apply's own
  # three gates let through is, by construction, one that actually resolves
  # its drift — that's the whole point of those gates. So there is no
  # naturally-occurring plan whose execution leaves the same op behind for
  # this check to catch. `check_verification!/2` is split out of `verify!/3`
  # precisely so the raise path can still be exercised directly, with a
  # fabricated "op we claim we ran" / "ops still in a fresh diff" pair, with
  # no database and no dependency on lib/kumi/plan/** or lib/kumi/diff.ex
  # (both owned by another agent this run).
  test "H3: change_primary_key/change_fk/change_index (all :review) land in skipped, never executed — pure, no DB" do
    alias Kumi.Schema.{ForeignKey, Index}

    pk_op = {:change_primary_key, "t", ["id"], []}

    fk_op =
      {:change_fk, "t",
       %ForeignKey{name: "fk", column: "a", references_table: "b", references_column: "id"},
       %ForeignKey{name: "fk", column: "a", references_table: "c", references_column: "id"}}

    idx_op =
      {:change_index, "t", %Index{name: "idx", columns: ["a"], unique: true},
       %Index{name: "idx", columns: ["b"], unique: false}}

    entries =
      Enum.map([pk_op, fk_op, idx_op], fn op ->
        {level, reason} = Kumi.Plan.Safety.classify(op)
        {op, level, reason}
      end)

    {to_execute, skipped} = Kumi.Apply.preview(entries)

    assert to_execute == []
    assert Enum.map(skipped, &elem(&1, 0)) == [pk_op, fk_op, idx_op]
    assert Enum.all?(skipped, fn {_op, reason} -> reason =~ "not :safe (review)" end)
  end

  test "check_verification!/2 raises when an executed op is still present in the fresh diff" do
    op =
      {:add_column, "kumi_test_accounts", %Column{name: "industry", type: "text", nullable: true}}

    assert_raise RuntimeError, ~r/verification failed.*1 executed op/, fn ->
      Kumi.Apply.check_verification!([{op, "ALTER TABLE ... ADD COLUMN ..."}], [op])
    end
  end

  test "check_verification!/2 returns :ok when no executed op remains in the fresh diff" do
    op =
      {:add_column, "kumi_test_accounts", %Column{name: "industry", type: "text", nullable: true}}

    assert Kumi.Apply.check_verification!([{op, "ALTER TABLE ... ADD COLUMN ..."}], []) == :ok
  end
end
