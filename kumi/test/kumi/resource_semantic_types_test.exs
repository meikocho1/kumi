defmodule Kumi.ResourceSemanticTypesTest do
  # Kumi.Resource's :email and :select field types are meant to be more
  # than cosmetic — this proves the generated constraints actually reject
  # bad data through a real Ash.create action against the DB (not just
  # inspected statically), and that `required: true` really is NOT NULL
  # at the Postgres level (not just an Ash-side allow_nil? flag).
  use Kumi.Test.DataCase, async: false

  alias Kumi.Test.Resource.{Account, Customer}

  setup do
    {:ok, account} =
      Account
      |> Ash.Changeset.for_create(:create, %{name: "Acme"})
      |> Ash.create()

    %{account: account}
  end

  describe ":email field" do
    test "rejects an invalid address", %{account: account} do
      result =
        Customer
        |> Ash.Changeset.for_create(:create, %{
          name: "Jane",
          email: "not-an-email",
          account_id: account.id
        })
        |> Ash.create()

      assert {:error, %Ash.Error.Invalid{}} = result
    end

    test "accepts a valid address", %{account: account} do
      assert {:ok, customer} =
               Customer
               |> Ash.Changeset.for_create(:create, %{
                 name: "Jane",
                 email: "jane@example.com",
                 account_id: account.id
               })
               |> Ash.create()

      assert customer.email == "jane@example.com"
    end
  end

  describe ":select field" do
    test "rejects a value outside options", %{account: account} do
      result =
        Customer
        |> Ash.Changeset.for_create(:create, %{
          name: "Jane",
          status: :bogus,
          account_id: account.id
        })
        |> Ash.create()

      assert {:error, %Ash.Error.Invalid{}} = result
    end

    test "accepts a value from options and defaults to :lead when omitted", %{account: account} do
      assert {:ok, active} =
               Customer
               |> Ash.Changeset.for_create(:create, %{
                 name: "Jane",
                 status: :active,
                 account_id: account.id
               })
               |> Ash.create()

      assert active.status == :active

      assert {:ok, defaulted} =
               Customer
               |> Ash.Changeset.for_create(:create, %{name: "No Status", account_id: account.id})
               |> Ash.create()

      assert defaulted.status == :lead
    end
  end

  describe "required: true → NOT NULL" do
    test "database column is non-nullable" do
      import Ecto.Query

      [row] =
        Kumi.Test.Repo.all(
          from(c in "columns",
            prefix: "information_schema",
            where: c.table_name == "kumi_test_resource_customers" and c.column_name == "name",
            select: c.is_nullable
          )
        )

      assert row == "NO"
    end

    test "create fails without :name" do
      account = Ash.create!(Ash.Changeset.for_create(Account, :create, %{name: "Acme 2"}))

      assert {:error, %Ash.Error.Invalid{}} =
               Customer
               |> Ash.Changeset.for_create(:create, %{account_id: account.id})
               |> Ash.create()
    end
  end
end
