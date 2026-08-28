defmodule Kumi.Plan.FixHintTest do
  use ExUnit.Case, async: true

  alias Kumi.Plan.FixHint
  alias Kumi.Schema.{Column, ForeignKey, Index, Table}

  describe "code-ahead ops point to ash.codegen, with manual SQL fallback" do
    test "add_column renders the exact ADD COLUMN statement including NOT NULL" do
      col = %Column{name: "email", type: "text", nullable: false, default: nil}
      [codegen, fallback] = FixHint.lines({:add_column, "crm_accounts", col})

      assert codegen =~ "mix ash.codegen"
      assert fallback =~ ~s(ALTER TABLE "crm_accounts" ADD COLUMN "email" text NOT NULL;)
    end

    test "add_table has no reconstructed DDL — recreate by hand" do
      [codegen, fallback] = FixHint.lines({:add_table, %Table{name: "crm_deals"}})

      assert codegen =~ "mix ash.codegen"
      assert fallback =~ "recreate it by hand"
      refute fallback =~ "CREATE TABLE"
    end

    test "add_fk and add_index render complete one-liners" do
      fk = %ForeignKey{
        name: "crm_deals_account_id_fkey",
        column: "account_id",
        references_table: "crm_accounts",
        references_column: "id"
      }

      idx = %Index{name: "crm_accounts_email_index", columns: ["email"], unique: true}

      [_, fk_sql] = FixHint.lines({:add_fk, "crm_deals", fk})
      [_, idx_sql] = FixHint.lines({:add_index, "crm_accounts", idx})

      assert fk_sql =~
               ~s(ALTER TABLE "crm_deals" ADD CONSTRAINT "crm_deals_account_id_fkey" ) <>
                 ~s{FOREIGN KEY ("account_id") REFERENCES "crm_accounts" ("id");}

      assert idx_sql =~
               ~s{CREATE UNIQUE INDEX "crm_accounts_email_index" ON "crm_accounts" ("email");}
    end
  end

  describe "change_column SQL targets the DESIRED value ({field, desired, actual})" do
    test "desired nullable: false becomes SET NOT NULL" do
      col = %Column{name: "email", type: "text", nullable: false, default: nil}
      [_, sql] = FixHint.lines({:change_column, "t", col, [{:nullable, false, true}]})

      assert sql =~ ~s(ALTER TABLE "t" ALTER COLUMN "email" SET NOT NULL;)
    end

    test "desired nullable: true becomes DROP NOT NULL" do
      col = %Column{name: "email", type: "text", nullable: true, default: nil}
      [_, sql] = FixHint.lines({:change_column, "t", col, [{:nullable, true, false}]})

      assert sql =~ ~s(ALTER TABLE "t" ALTER COLUMN "email" DROP NOT NULL;)
    end

    test "type change targets desired type; multiple actions join in one statement" do
      col = %Column{name: "amount", type: "bigint", nullable: false, default: nil}

      [_, sql] =
        FixHint.lines(
          {:change_column, "t", col, [{:type, "bigint", "integer"}, {:nullable, false, true}]}
        )

      assert sql =~
               ~s(ALTER TABLE "t" ALTER COLUMN "amount" TYPE bigint, ) <>
                 ~s(ALTER COLUMN "amount" SET NOT NULL;)
    end

    test "default-only change gets no SQL (normalized defaults are not SQL)" do
      col = %Column{name: "stage", type: "text", nullable: true, default: {:literal, ":lead"}}

      [_, sql] =
        FixHint.lines({:change_column, "t", col, [{:default, {:literal, ":lead"}, nil}]})

      assert sql =~ "adjust manually"
      refute sql =~ "ALTER TABLE"
    end
  end

  describe "drift ops list the keep-it option before the destructive SQL" do
    test "remove_column: add-to-code first, DROP COLUMN second" do
      col = %Column{name: "legacy_phone", type: "text", nullable: true, default: nil}
      [keep, remove] = FixHint.lines({:remove_column, "crm_accounts", col})

      assert keep =~ "add the attribute to your Ash resource"
      assert keep =~ "cannot see this drift"
      assert remove =~ ~s(ALTER TABLE "crm_accounts" DROP COLUMN "legacy_phone";)
    end

    test "drop_table, remove_fk, remove_index each render their removal SQL" do
      fk = %ForeignKey{
        name: "t_x_fkey",
        column: "x",
        references_table: "u",
        references_column: "id"
      }

      idx = %Index{name: "t_x_index", columns: ["x"], unique: false}

      assert [_, ~s(to remove it: DROP TABLE "old_stuff";)] =
               FixHint.lines({:drop_table, %Table{name: "old_stuff"}})

      assert [_, ~s(to remove it: ALTER TABLE "t" DROP CONSTRAINT "t_x_fkey";)] =
               FixHint.lines({:remove_fk, "t", fk})

      assert [_, ~s(to remove it: DROP INDEX "t_x_index";)] =
               FixHint.lines({:remove_index, "t", idx})
    end

    test "drop_table's SQL comes from Kumi.Plan.SQL, not a hardcoded literal (L3)" do
      # Regression for L3: this used to build "DROP TABLE #{table.name};" by
      # hand instead of going through SQL.render/1 like every other
      # destructive op — this test pins that the two can't diverge again by
      # asserting the SQL module's own render call produces the same text.
      table = %Table{name: "old_stuff"}
      [_, hint_sql] = FixHint.lines({:drop_table, table})

      assert {:ok, rendered} = Kumi.Plan.SQL.render({:drop_table, table})
      assert hint_sql == "to remove it: " <> rendered
    end
  end

  describe "H3: change_primary_key/change_fk/change_index get advisory prose, no literal SQL" do
    test "change_primary_key names both column lists, no SQL" do
      [codegen, fallback] = FixHint.lines({:change_primary_key, "t", ["id"], []})

      assert codegen =~ "mix ash.codegen"
      assert fallback =~ "[]"
      assert fallback =~ "[\"id\"]"
      refute fallback =~ "ALTER TABLE"
    end

    test "change_fk names both targets, no SQL" do
      fk = %ForeignKey{
        name: "t_a_fkey",
        column: "account_id",
        references_table: "accounts",
        references_column: "id"
      }

      changed_fk = %{fk | references_table: "legacy_accounts"}
      [_, fallback] = FixHint.lines({:change_fk, "t", fk, changed_fk})

      assert fallback =~ "accounts.id"
      assert fallback =~ "legacy_accounts.id"
      refute fallback =~ "ALTER TABLE"
    end

    test "change_index names both definitions, no SQL" do
      idx = %Index{name: "t_email_index", columns: ["email"], unique: true}
      changed_idx = %{idx | columns: ["username"], unique: false}
      [_, fallback] = FixHint.lines({:change_index, "t", idx, changed_idx})

      assert fallback =~ "email"
      assert fallback =~ "username"
      refute fallback =~ ~s(INDEX "t_email_index" ON)
    end
  end

  test "possible_rename warns to rename BEFORE ash.codegen and gives the RENAME SQL" do
    x = %Column{name: "phone", type: "text", nullable: true, default: nil}
    y = %Column{name: "phone_number", type: "text", nullable: true, default: nil}
    [warn, sql] = FixHint.lines({:possible_rename, "crm_accounts", x, y})

    assert warn =~ "BEFORE ash.codegen"
    assert warn =~ "drop+add"
    assert sql == ~s(ALTER TABLE "crm_accounts" RENAME COLUMN "phone" TO "phone_number";)
  end
end
