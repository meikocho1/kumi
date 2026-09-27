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
  # four gates let through is, by construction, one that actually resolves
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

  # Gate 2 is independent of the stored level by design, so it has to be
  # exercised with entries Safety would never produce: every op below is
  # forged as :safe. With the old tag-level allowlist the change_column
  # type change ran `ALTER COLUMN ... TYPE` and verified :ok.
  test "gate 2: a :safe entry whose op shape isn't executable is skipped — pure, no DB" do
    alias Kumi.Schema.{Index, Table}

    col = %Column{name: "c", type: "text", nullable: true}

    ops = [
      {:drop_table, %Table{name: "t"}},
      {:add_table, %Table{name: "t2"}},
      {:remove_column, "t", col},
      {:add_column, "t", %Column{col | nullable: false}},
      {:add_index, "t", %Index{name: "t_c_index", columns: ["c"], unique: true}},
      {:change_column, "t", col, [{:type, "int8", "int4"}]},
      {:change_column, "t", col, [{:nullable, true, false}, {:nullable, false, true}]},
      {:change_column, "t", col, []}
    ]

    {to_execute, skipped} = Kumi.Apply.preview(Enum.map(ops, &{&1, :safe, "forged"}))

    assert to_execute == []
    assert Enum.map(skipped, &elem(&1, 0)) == ops
    assert Enum.all?(skipped, fn {_op, reason} -> reason =~ "not on the executable allowlist" end)
  end

  test "gate 2 still lets the three executable shapes through — pure, no DB" do
    alias Kumi.Schema.Index

    col = %Column{name: "c", type: "text", nullable: true}

    ops = [
      {:add_column, "t", col},
      {:add_index, "t", %Index{name: "t_c_index", columns: ["c"], unique: false}},
      {:change_column, "t", col, [{:nullable, true, false}]}
    ]

    {to_execute, skipped} = Kumi.Apply.preview(Enum.map(ops, &{&1, :safe, "safe"}))

    assert skipped == []

    assert Enum.map(to_execute, &elem(&1, 1)) == [
             ~s(ALTER TABLE "t" ADD COLUMN "c" text;),
             ~s[CREATE INDEX "t_c_index" ON "t" ("c");],
             ~s(ALTER TABLE "t" ALTER COLUMN "c" DROP NOT NULL;)
           ]
  end

  test "a :safe add_column with a fixed datetime precision is skipped — pure, no DB" do
    op =
      {:add_column, "t",
       %Column{name: "at", type: "timestamp", nullable: true, datetime_precision: 0}}

    assert {[], [{^op, reason}]} = Kumi.Apply.preview([{op, :safe, "x"}])
    assert reason =~ "datetime precision"
  end

  # numeric(10,2) and vector(1536) compare as "numeric" and "vector", so
  # ADD COLUMN would build a different column than codegen did and the
  # post-commit re-diff could not tell.
  test "a :safe add_column whose type isn't exact is skipped — pure, no DB" do
    op =
      {:add_column, "t",
       %Column{name: "price", type: "numeric", nullable: true, exact_type?: false}}

    assert {[], [{^op, reason}]} = Kumi.Apply.preview([{op, :safe, "x"}])
    assert reason =~ "type carries modifiers"
  end

  # Postgres drops an index with a column it covers, so a hand-dropped
  # column comes back as its add_column plus an add_index. With the
  # add_column skipped, CREATE INDEX raised on the missing column and
  # rolled back every other repair in the run.
  test "an add_index on a column this run won't add is skipped with it — pure, no DB" do
    alias Kumi.Schema.Index

    price = %Column{name: "price", type: "numeric", nullable: true, exact_type?: false}
    code = %Column{name: "code", type: "text", nullable: true}
    index = &%Index{name: &1, columns: &2, unique: false}

    ops = [
      price_col = {:add_column, "t", price},
      code_col = {:add_column, "t", code},
      rename = {:possible_rename, "t", %{code | name: "old"}, %{code | name: "new"}},
      price_idx = {:add_index, "t", index.("t_price_index", ["price"])},
      pair_idx = {:add_index, "t", index.("t_code_price_index", ["code", "price"])},
      renamed_idx = {:add_index, "t", index.("t_new_index", ["new"])},
      code_idx = {:add_index, "t", index.("t_code_index", ["code"])},
      other_idx = {:add_index, "other", index.("other_price_index", ["price"])}
    ]

    entries =
      Enum.map(ops, fn op ->
        {level, reason} = Kumi.Plan.Safety.classify(op)
        {op, level, reason}
      end)

    {to_execute, skipped} = Kumi.Apply.preview(entries)

    assert Enum.map(to_execute, &elem(&1, 0)) == [code_col, code_idx, other_idx]

    assert Enum.map(skipped, &elem(&1, 0)) == [
             price_col,
             rename,
             price_idx,
             pair_idx,
             renamed_idx
           ]

    reasons = Map.new(skipped)
    assert reasons[price_col] =~ "type carries modifiers"
    assert reasons[price_idx] =~ "covers column price, which this run does not add"
    assert reasons[pair_idx] =~ "covers column price"
    assert reasons[renamed_idx] =~ "covers column new"
  end

  test "a :safe add_index that isn't exact is skipped — pure, no DB" do
    alias Kumi.Schema.Index

    op =
      {:add_index, "t",
       %Index{name: "t_partial_index", columns: ["c"], unique: false, exact?: false}}

    assert {[], [{^op, reason}]} = Kumi.Apply.preview([{op, :safe, "x"}])
    assert reason =~ "where/using/include/expression"
  end

  test "repairs a manually-dropped plain custom index, and a fresh plan is clean" do
    Ecto.Adapters.SQL.query!(Kumi.Test.Repo, "DROP INDEX kumi_test_deals_amount_index", [])

    plan = Kumi.plan(Kumi.Test.Repo, @domains)

    assert [{{:add_index, "kumi_test_deals", %{exact?: true}}, :safe, _reason}] = plan.entries

    result = Kumi.Apply.run(Kumi.Test.Repo, plan, domains: @domains)

    assert result.skipped == []
    assert result.verified == :ok

    assert [{_op, sql}] = result.executed
    assert sql == ~s[CREATE INDEX "kumi_test_deals_amount_index" ON "kumi_test_deals" ("amount");]

    assert Kumi.plan(Kumi.Test.Repo, @domains).entries == []
  end

  test "a hand-dropped indexed column comes back with its index, and a fresh plan is clean" do
    # DROP COLUMN takes kumi_test_deals_amount_index with it.
    Ecto.Adapters.SQL.query!(Kumi.Test.Repo, "ALTER TABLE kumi_test_deals DROP COLUMN amount", [])

    plan = Kumi.plan(Kumi.Test.Repo, @domains)

    assert [
             {{:add_column, "kumi_test_deals", %Column{name: "amount"}}, :safe, _},
             {{:add_index, "kumi_test_deals", %{name: "kumi_test_deals_amount_index"}}, :safe, _}
           ] = plan.entries

    result = Kumi.Apply.run(Kumi.Test.Repo, plan, domains: @domains)

    assert result.skipped == []
    assert length(result.executed) == 2
    assert result.verified == :ok
    assert Kumi.plan(Kumi.Test.Repo, @domains).entries == []
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
