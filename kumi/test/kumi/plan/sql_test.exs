defmodule Kumi.Plan.SQLTest do
  use ExUnit.Case, async: true

  alias Kumi.Plan.SQL
  alias Kumi.Schema.{Column, ForeignKey, Index, Table}

  test "add_column renders ADD COLUMN including NOT NULL" do
    col = %Column{name: "email", type: "text", nullable: false}

    assert SQL.render({:add_column, "crm_accounts", col}) ==
             {:ok, "ALTER TABLE crm_accounts ADD COLUMN email text NOT NULL;"}
  end

  test "add_column renders without NOT NULL when nullable" do
    col = %Column{name: "email", type: "text", nullable: true}

    assert SQL.render({:add_column, "crm_accounts", col}) ==
             {:ok, "ALTER TABLE crm_accounts ADD COLUMN email text;"}
  end

  test "add_fk renders the FOREIGN KEY one-liner" do
    fk = %ForeignKey{
      name: "crm_deals_account_id_fkey",
      column: "account_id",
      references_table: "crm_accounts",
      references_column: "id"
    }

    assert SQL.render({:add_fk, "crm_deals", fk}) ==
             {:ok,
              "ALTER TABLE crm_deals ADD CONSTRAINT crm_deals_account_id_fkey " <>
                "FOREIGN KEY (account_id) REFERENCES crm_accounts (id);"}
  end

  test "add_index renders CREATE UNIQUE INDEX when unique" do
    idx = %Index{name: "crm_accounts_email_index", columns: ["email"], unique: true}

    assert SQL.render({:add_index, "crm_accounts", idx}) ==
             {:ok, "CREATE UNIQUE INDEX crm_accounts_email_index ON crm_accounts (email);"}
  end

  test "add_index renders plain CREATE INDEX when not unique" do
    idx = %Index{name: "crm_accounts_email_index", columns: ["email"], unique: false}

    assert SQL.render({:add_index, "crm_accounts", idx}) ==
             {:ok, "CREATE INDEX crm_accounts_email_index ON crm_accounts (email);"}
  end

  test "change_column: nullable false -> SET NOT NULL" do
    col = %Column{name: "email", type: "text", nullable: false}

    assert SQL.render({:change_column, "t", col, [{:nullable, false, true}]}) ==
             {:ok, "ALTER TABLE t ALTER COLUMN email SET NOT NULL;"}
  end

  test "change_column: nullable true -> DROP NOT NULL" do
    col = %Column{name: "email", type: "text", nullable: true}

    assert SQL.render({:change_column, "t", col, [{:nullable, true, false}]}) ==
             {:ok, "ALTER TABLE t ALTER COLUMN email DROP NOT NULL;"}
  end

  test "change_column: type + nullable join into one comma-separated statement" do
    col = %Column{name: "amount", type: "bigint", nullable: false}

    assert SQL.render(
             {:change_column, "t", col, [{:type, "bigint", "integer"}, {:nullable, false, true}]}
           ) ==
             {:ok,
              "ALTER TABLE t ALTER COLUMN amount TYPE bigint, ALTER COLUMN amount SET NOT NULL;"}
  end

  test "change_column: a default change alone is :unsupported" do
    col = %Column{name: "stage", type: "text", nullable: true}

    assert SQL.render({:change_column, "t", col, [{:default, {:literal, ":lead"}, nil}]}) ==
             :unsupported
  end

  test "change_column: default mixed with a renderable change is :unsupported (all-or-nothing)" do
    col = %Column{name: "amount", type: "bigint", nullable: false}

    changes = [{:type, "bigint", "integer"}, {:default, {:literal, "0"}, nil}]
    assert SQL.render({:change_column, "t", col, changes}) == :unsupported
  end

  test "change_column: a datetime_precision change alone is :unsupported" do
    col = %Column{name: "inserted_at", type: "timestamp", nullable: false}

    assert SQL.render({:change_column, "t", col, [{:datetime_precision, 6, 0}]}) ==
             :unsupported
  end

  test "remove_column, drop_table, remove_fk, remove_index render their DROP SQL" do
    col = %Column{name: "legacy_phone", type: "text", nullable: true}

    assert SQL.render({:remove_column, "crm_accounts", col}) ==
             {:ok, "ALTER TABLE crm_accounts DROP COLUMN legacy_phone;"}

    assert SQL.render({:drop_table, %Table{name: "old_stuff"}}) ==
             {:ok, "DROP TABLE old_stuff;"}

    fk = %ForeignKey{
      name: "t_x_fkey",
      column: "x",
      references_table: "u",
      references_column: "id"
    }

    assert SQL.render({:remove_fk, "t", fk}) == {:ok, "ALTER TABLE t DROP CONSTRAINT t_x_fkey;"}

    idx = %Index{name: "t_x_index", columns: ["x"], unique: false}
    assert SQL.render({:remove_index, "t", idx}) == {:ok, "DROP INDEX t_x_index;"}
  end

  test "possible_rename renders RENAME COLUMN" do
    x = %Column{name: "phone", type: "text", nullable: true}
    y = %Column{name: "phone_number", type: "text", nullable: true}

    assert SQL.render({:possible_rename, "crm_accounts", x, y}) ==
             {:ok, "ALTER TABLE crm_accounts RENAME COLUMN phone TO phone_number;"}
  end

  test "add_table is always :unsupported (no CREATE TABLE reconstruction)" do
    assert SQL.render({:add_table, %Table{name: "crm_deals"}}) == :unsupported
  end
end
