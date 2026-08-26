defmodule Kumi.ResourceTest do
  # Kumi.Resource shorthand (v0.2 slice 2, blueprint §3.2, §0 D1 "Show
  # Ash"): the DSL is sugar that must compile to exactly what a
  # hand-written Ash.Resource would be. This suite proves that two ways:
  # (1) the shorthand vs. a hand-written twin have identical
  # Ash.Resource.Info; (2) `mix kumi.expand`'s output, recompiled as a
  # fresh module, has identical Ash.Resource.Info to the original — so
  # expand can never drift from what actually compiled.
  use Kumi.Test.DataCase, async: false

  import ExUnit.CaptureIO

  alias Kumi.Test.Resource.{Account, Customer, Deal, HandwrittenCustomer}

  describe "shorthand vs. hand-written Ash.Resource — Ash.Resource.Info parity" do
    test "attributes: names/types/allow_nil?/constraints/defaults match" do
      assert normalize_attributes(Customer) == normalize_attributes(HandwrittenCustomer)
    end

    test "belongs_to :account relationship matches" do
      assert normalize_relationship(Customer, :account) ==
               normalize_relationship(HandwrittenCustomer, :account)
    end

    test "default actions match" do
      assert normalize_actions(Customer) == normalize_actions(HandwrittenCustomer)
    end

    test "table matches" do
      assert AshPostgres.DataLayer.Info.table(Customer) ==
               "kumi_test_resource_customers"

      assert AshPostgres.DataLayer.Info.table(HandwrittenCustomer) ==
               "kumi_test_resource_customers_hw"
    end

    test "has_many :deals — not on the hand-written twin, verified directly on the shorthand" do
      rel = Ash.Resource.Info.relationship(Customer, :deals)
      assert rel.type == :has_many
      assert rel.destination == Deal
    end
  end

  describe "expand invariant — mix kumi.expand output compiles to the same resource" do
    test "Customer.__kumi_expand__/0 recompiled as a new module has identical Ash.Resource.Info" do
      source = Customer.__kumi_expand__()

      renamed =
        String.replace(
          source,
          "Kumi.Test.Resource.Customer",
          "Kumi.Test.Resource.CustomerExpandCheck",
          global: false
        )

      # Recompiling standalone means it isn't listed in ResourceDomain's
      # `resources do ... end` block — Ash logs (doesn't raise) a
      # `__verify_spark_dsl__` warning about that; captured so this test's
      # own output stays clean, and irrelevant to the equivalence proven.
      capture_io(:stderr, fn -> Code.compile_string(renamed) end)

      recompiled = Kumi.Test.Resource.CustomerExpandCheck

      assert normalize_attributes(recompiled) == normalize_attributes(Customer)

      assert normalize_relationship(recompiled, :account) ==
               normalize_relationship(Customer, :account)

      recompiled_deals = Ash.Resource.Info.relationship(recompiled, :deals)
      original_deals = Ash.Resource.Info.relationship(Customer, :deals)
      assert recompiled_deals.type == original_deals.type
      assert recompiled_deals.destination == original_deals.destination

      assert normalize_actions(recompiled) == normalize_actions(Customer)

      assert AshPostgres.DataLayer.Info.table(recompiled) ==
               AshPostgres.DataLayer.Info.table(Customer)
    end

    test "expand is pure — calling it twice returns byte-identical source" do
      assert Customer.__kumi_expand__() == Customer.__kumi_expand__()
    end

    test "expand output is exactly what Kumi.Resource.Codegen.generate/3 produces (single source of truth)" do
      opts = [
        domain: Kumi.Test.ResourceDomain,
        repo: Kumi.Test.Repo,
        table: "kumi_test_resource_customers"
      ]

      specs = [
        %Kumi.Resource.FieldSpec{
          kind: :field,
          name: :name,
          type: :string,
          opts: [required: true]
        },
        %Kumi.Resource.FieldSpec{kind: :field, name: :email, type: :email, opts: []},
        %Kumi.Resource.FieldSpec{
          kind: :field,
          name: :status,
          type: :select,
          opts: [options: [:lead, :active, :lost], default: :lead]
        },
        %Kumi.Resource.FieldSpec{kind: :belongs_to, name: :account, type: Account, opts: []},
        %Kumi.Resource.FieldSpec{kind: :has_many, name: :deals, type: Deal, opts: []}
      ]

      regenerated = Kumi.Resource.Codegen.generate(Customer, opts, specs)

      assert regenerated == Customer.__kumi_expand__()
    end
  end

  describe "mix kumi.expand output compiles as a mix task would print it" do
    test "prints the same source shown by __kumi_expand__/0" do
      assert Customer.__kumi_expand__() =~ "defmodule Kumi.Test.Resource.Customer do"
      assert Customer.__kumi_expand__() =~ "use Ash.Resource,"
      assert Customer.__kumi_expand__() =~ "table(\"kumi_test_resource_customers\")"
    end

    test "mix kumi.expand prints exactly __kumi_expand__/0's output" do
      output =
        capture_io(fn ->
          Mix.Tasks.Kumi.Expand.run(["Kumi.Test.Resource.Customer"])
        end)

      assert String.trim(output) == String.trim(Customer.__kumi_expand__())
    end

    test "mix kumi.expand on a plain Ash resource errors helpfully" do
      assert_raise Mix.Error, ~r/already a plain Ash resource/, fn ->
        Mix.Tasks.Kumi.Expand.run(["Kumi.Test.Resource.Account"])
      end
    end

    test "mix kumi.expand on an unknown module errors helpfully" do
      assert_raise Mix.Error, ~r/not found/, fn ->
        Mix.Tasks.Kumi.Expand.run(["Kumi.Not.A.Real.Module"])
      end
    end
  end

  describe "Codegen field type mapping (pure, no DB — covers types not exercised by Customer/Note)" do
    test ":integer, :decimal, :boolean, :date, :datetime map to the right Ash attribute types" do
      opts = [domain: Kumi.Test.ResourceDomain, repo: Kumi.Test.Repo, table: "widgets"]

      specs = [
        %Kumi.Resource.FieldSpec{kind: :field, name: :count, type: :integer, opts: []},
        %Kumi.Resource.FieldSpec{kind: :field, name: :price, type: :decimal, opts: []},
        %Kumi.Resource.FieldSpec{kind: :field, name: :active, type: :boolean, opts: []},
        %Kumi.Resource.FieldSpec{kind: :field, name: :due_on, type: :date, opts: []},
        # :datetime is the only non-identity mapping among these — worth
        # asserting explicitly, not just via string match.
        %Kumi.Resource.FieldSpec{kind: :field, name: :happened_at, type: :datetime, opts: []}
      ]

      source = Kumi.Resource.Codegen.generate(Kumi.Test.Resource.Widget, opts, specs)

      assert source =~ "attribute :count, :integer"
      assert source =~ "attribute :price, :decimal"
      assert source =~ "attribute :active, :boolean"
      assert source =~ "attribute :due_on, :date"
      assert source =~ "attribute :happened_at, :utc_datetime_usec"
      refute source =~ ":datetime"
    end

    test ":select without options: raises a helpful compile-time error" do
      opts = [domain: Kumi.Test.ResourceDomain, repo: Kumi.Test.Repo, table: "widgets"]
      specs = [%Kumi.Resource.FieldSpec{kind: :field, name: :status, type: :select, opts: []}]

      assert_raise ArgumentError, ~r/:select field requires `options:`/, fn ->
        Kumi.Resource.Codegen.generate(Kumi.Test.Resource.Widget, opts, specs)
      end
    end
  end

  defp normalize_attributes(resource) do
    resource
    |> Ash.Resource.Info.attributes()
    |> Enum.map(fn attr ->
      {attr.name, attr.type, attr.allow_nil?, attr.default,
       normalize_constraints(attr.constraints)}
    end)
    |> Enum.sort()
  end

  defp normalize_constraints(constraints) do
    Enum.map(constraints, fn
      {:match, %Regex{} = regex} -> {:match, Regex.source(regex)}
      other -> other
    end)
    |> Enum.sort()
  end

  defp normalize_relationship(resource, name) do
    rel = Ash.Resource.Info.relationship(resource, name)
    {rel.type, rel.name, rel.destination, rel.source_attribute, rel.destination_attribute}
  end

  defp normalize_actions(resource) do
    resource
    |> Ash.Resource.Info.actions()
    |> Enum.map(&{&1.name, &1.type})
    |> Enum.sort()
  end
end
