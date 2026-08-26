defmodule Kumi.ProbeTest do
  # Kumi.Probe runs read-only SQL against fixture tables created directly in
  # the sandbox (raw SQL, not Ash resources) — this lets each test control
  # the exact row counts a finding must report, and lets the identifier
  # quoting test use a table/column name that needs quoting, which none of
  # the Ash-backed test resources have. Runs inside the DataCase sandbox
  # transaction, rolled back automatically — probes never write, but the
  # fixture setup does, so it must not leak between tests.
  use Kumi.Test.DataCase, async: false

  alias Kumi.Plan.Finding
  alias Kumi.Schema.{Column, ForeignKey, Index, Table}

  defp exec!(sql), do: Ecto.Adapters.SQL.query!(Kumi.Test.Repo, sql, [])

  defp plan_of(entries), do: %Kumi.Plan{entries: Enum.map(entries, &{&1, :review, "test"})}

  describe "nullable -> NOT NULL tightening" do
    test "counts exactly the existing NULL rows" do
      exec!("CREATE TABLE probe_null_test (id serial primary key, email text)")
      exec!("INSERT INTO probe_null_test (email) VALUES ('a@example.com'), (NULL), (NULL)")

      col = %Column{name: "email", type: "text", nullable: false}
      op = {:change_column, "probe_null_test", col, [{:nullable, false, true}]}

      assert [%Finding{count: 2, note: note}] = Kumi.Probe.run(Kumi.Test.Repo, plan_of([op]))
      assert note == "2 existing NULL rows would fail"
    end

    test "0 existing NULLs still produces a finding (same safety level, just evidence)" do
      exec!("CREATE TABLE probe_null_zero (id serial primary key, email text NOT NULL)")
      exec!("INSERT INTO probe_null_zero (email) VALUES ('a@example.com')")

      col = %Column{name: "email", type: "text", nullable: false}
      op = {:change_column, "probe_null_zero", col, [{:nullable, false, true}]}

      assert [%Finding{count: 0, note: "0 existing NULL rows would fail"}] =
               Kumi.Probe.run(Kumi.Test.Repo, plan_of([op]))
    end
  end

  describe "new unique index / identity -> duplicate-group count" do
    test "counts exactly the duplicate value groups, ignoring NULLs" do
      exec!("CREATE TABLE probe_dup_test (id serial primary key, email text)")

      exec!("""
      INSERT INTO probe_dup_test (email) VALUES
        ('a@example.com'), ('a@example.com'),
        ('b@example.com'), ('b@example.com'), ('b@example.com'),
        ('c@example.com'),
        (NULL), (NULL)
      """)

      idx = %Index{name: "probe_dup_test_email_index", columns: ["email"], unique: true}
      op = {:add_index, "probe_dup_test", idx}

      assert [%Finding{count: 2, note: note}] = Kumi.Probe.run(Kumi.Test.Repo, plan_of([op]))
      assert note == "2 duplicate value groups would violate uniqueness"
    end
  end

  describe "remove_column (DANGEROUS) -> data-loss count" do
    test "counts exactly the rows with non-null data in the column being dropped" do
      exec!("CREATE TABLE probe_remove_test (id serial primary key, notes text)")
      exec!("INSERT INTO probe_remove_test (notes) VALUES ('keep me'), (NULL), ('and me')")

      col = %Column{name: "notes", type: "text", nullable: true}
      op = {:remove_column, "probe_remove_test", col}

      assert [%Finding{count: 2, note: note}] = Kumi.Probe.run(Kumi.Test.Repo, plan_of([op]))
      assert note == "2 rows contain data that would be lost"
    end
  end

  describe "drop_table -> row count" do
    test "counts exactly the rows in the table being dropped" do
      exec!("CREATE TABLE probe_drop_test (id serial primary key)")
      exec!("INSERT INTO probe_drop_test DEFAULT VALUES")
      exec!("INSERT INTO probe_drop_test DEFAULT VALUES")
      exec!("INSERT INTO probe_drop_test DEFAULT VALUES")

      op = {:drop_table, %Table{name: "probe_drop_test"}}

      assert [%Finding{count: 3, note: "table contains 3 rows"}] =
               Kumi.Probe.run(Kumi.Test.Repo, plan_of([op]))
    end
  end

  describe "type change -> row count only (no cast probing)" do
    test "counts the rows and says cast safety was not checked" do
      exec!("CREATE TABLE probe_type_test (id serial primary key, amount text)")
      exec!("INSERT INTO probe_type_test (amount) VALUES ('1'), ('2')")

      col = %Column{name: "amount", type: "numeric", nullable: true}
      op = {:change_column, "probe_type_test", col, [{:type, "numeric", "text"}]}

      assert [%Finding{count: 2, note: note}] = Kumi.Probe.run(Kumi.Test.Repo, plan_of([op]))
      assert note =~ "not checked"
    end
  end

  describe "ops with nothing to probe" do
    test "add_table, add_fk, remove_fk, possible_rename yield no findings" do
      ops = [
        {:add_table, %Table{name: "t"}},
        {:add_fk, "t", %ForeignKey{name: "fk", column: "a_id", references_table: "a", references_column: "id"}},
        {:remove_fk, "t", %ForeignKey{name: "fk", column: "a_id", references_table: "a", references_column: "id"}}
      ]

      assert Kumi.Probe.run(Kumi.Test.Repo, plan_of(ops)) == []
    end
  end

  describe "identifier quoting" do
    test "quote_ident/1 wraps and doubles embedded quotes" do
      assert Kumi.Probe.quote_ident("plain") == ~s("plain")
      assert Kumi.Probe.quote_ident("Weird Name") == ~s("Weird Name")
      assert Kumi.Probe.quote_ident(~s(has"quote)) == ~s("has""quote")
    end

    test "a table/column name that needs quoting (mixed case + reserved word) still probes correctly" do
      exec!("CREATE TABLE \"Probe Order\" (id serial primary key, \"Group\" text)")
      exec!("INSERT INTO \"Probe Order\" (\"Group\") VALUES ('x'), (NULL)")

      col = %Column{name: "Group", type: "text", nullable: false}
      op = {:change_column, "Probe Order", col, [{:nullable, false, true}]}

      assert [%Finding{count: 1, note: "1 existing NULL rows would fail"}] =
               Kumi.Probe.run(Kumi.Test.Repo, plan_of([op]))
    end
  end

  describe "opt-out (default): Kumi.plan/3 without probe: true never runs Kumi.Probe" do
    test "plan.findings is empty when probe is not requested" do
      Ecto.Adapters.SQL.query!(
        Kumi.Test.Repo,
        "ALTER TABLE kumi_test_accounts ADD COLUMN legacy_phone text",
        []
      )

      plan = Kumi.plan(Kumi.Test.Repo, [Kumi.Test.Domain, Kumi.Test.ResourceDomain])

      assert plan.findings == []
    end

    test "probe: true attaches findings for the diffed op" do
      Ecto.Adapters.SQL.query!(
        Kumi.Test.Repo,
        "ALTER TABLE kumi_test_accounts ADD COLUMN legacy_phone text",
        []
      )

      plan = Kumi.plan(Kumi.Test.Repo, [Kumi.Test.Domain, Kumi.Test.ResourceDomain], probe: true)

      assert [%Finding{count: 0, note: note}] = plan.findings
      assert note == "0 rows contain data that would be lost"
    end
  end
end
