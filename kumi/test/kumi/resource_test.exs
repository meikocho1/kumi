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

  describe "H1 — @before_compile rejects plain Ash sections mixed into `fields do ... end`" do
    # `@after_verify`-raised exceptions run in a separate checker process
    # (Module.ParallelChecker) linked to the compiling process — they
    # surface as an `exit` signal, not a normal raise `assert_raise` can
    # catch (this is also why Spark's own DSL verifiers route through
    # `Spark.Test` instead of `assert_raise` — see that module's
    # moduledoc). `compile_and_catch_after_verify_error/1` traps and
    # unwraps that exit so the specific error message can be asserted on.
    test "a plain `attributes do ... end` block alongside `fields do ... end` fails to compile" do
      source = """
      defmodule Kumi.Test.Resource.MixedAttributesCheck do
        use Kumi.Resource,
          domain: Kumi.Test.ResourceDomain,
          repo: Kumi.Test.Repo,
          table: "kumi_test_resource_mixed_attrs_check"

        fields do
          field :name, :string, required: true
        end

        attributes do
          attribute :sneaky, :string do
            public? true
          end
        end
      end
      """

      {:error, error} = compile_and_expect_error(source)

      assert %CompileError{description: message} = error

      assert message =~
               "Kumi.Test.Resource.MixedAttributesCheck declares plain Ash DSL sections that `fields do ... end` did not generate"

      assert message =~ "attributes: [:sneaky]"
      assert message =~ "would not print these"
      assert message =~ "mix kumi.expand Kumi.Test.Resource.MixedAttributesCheck"
    end

    test "a second plain `relationships do ... end` block alongside `fields do ... end` fails to compile" do
      # `belongs_to` (unlike `has_many`) doesn't require the destination
      # to already have a matching foreign key column, so it's the
      # simplest relationship kind to add here without also needing a
      # migration-shaped fixture.
      source = """
      defmodule Kumi.Test.Resource.MixedRelationshipsCheck do
        use Kumi.Resource,
          domain: Kumi.Test.ResourceDomain,
          repo: Kumi.Test.Repo,
          table: "kumi_test_resource_mixed_rels_check"

        fields do
          field :name, :string, required: true
        end

        relationships do
          belongs_to :sneaky_account, Kumi.Test.Resource.Account do
            public? true
          end
        end
      end
      """

      {:error, error} = compile_and_expect_error(source)

      assert %CompileError{description: message} = error
      assert message =~ "relationships: [:sneaky_account]"
      # `belongs_to` also implicitly adds its own `:sneaky_account_id`
      # foreign-key attribute — since it wasn't fields-declared either, it
      # shows up here too, distinct from the FK-tracking done for a
      # legitimate `fields do belongs_to ... end` (see the negative case
      # below and Customer's own :account_id, which is NOT flagged).
      assert message =~ "attributes: [:sneaky_account_id]"
    end

    test "a plain `calculations do ... end` block alongside `fields do ... end` fails to compile" do
      source = """
      defmodule Kumi.Test.Resource.MixedCalculationsCheck do
        use Kumi.Resource,
          domain: Kumi.Test.ResourceDomain,
          repo: Kumi.Test.Repo,
          table: "kumi_test_resource_mixed_calcs_check"

        fields do
          field :name, :string, required: true
        end

        calculations do
          calculate :shout, :string, expr(name <> "!")
        end
      end
      """

      {:error, error} = compile_and_expect_error(source)

      assert %CompileError{description: message} = error
      assert message =~ "calculations: [:shout]"
    end

    test "negative case: a pure-shorthand module still compiles fine, expand-vs-compiled equivalence still holds" do
      # Customer (used throughout this file) is exactly this case — no
      # plain Ash sections, only `fields do ... end`. If the H1 check were
      # miscalibrated (e.g. flagging belongs_to's own foreign-key
      # attribute), this module — and the expand-invariant test above —
      # would already have failed to compile.
      assert Ash.Resource.Info.resource?(Customer)
      assert Customer.__kumi_expand__() =~ "defmodule Kumi.Test.Resource.Customer do"
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

  # `@after_verify` failures crash the (linked) compiler-checker process
  # rather than raising in the calling process, so `assert_raise` can't
  # observe them directly. Compiling inside a `Task` we're linked to (and
  # trapping exits for) converts that crash into a normal `catch :exit`
  # in this process, from which the original raised exception can be
  # recovered. Stderr is captured because Ash also logs an unrelated
  # "not present in any known Ash.Domain" warning for these
  # not-registered-in-ResourceDomain probe modules — same reason the
  # expand-invariant test above captures it.
  # The D1 completeness check raises a CompileError from
  # `Kumi.Resource.__before_compile__/1`, i.e. synchronously during macro
  # expansion — so `rescue` sees it directly, unlike the `@after_verify`
  # mechanism this originally used (that one raises inside
  # `Module.ParallelChecker` and reaches the caller as an EXIT).
  # `capture_io/2` returns the captured output rather than the function's
  # value, hence the process-dictionary hand-off.
  defp compile_and_expect_error(source) do
    key = make_ref()

    capture_io(:stderr, fn ->
      outcome =
        try do
          Code.compile_string(source)
          :ok
        rescue
          error -> {:error, error}
        end

      Process.put(key, outcome)
    end)

    Process.get(key)
  end

  describe "H2 — field option whitelist (FieldSpec.parse/2)" do
    test "an unknown option key raises ArgumentError naming it (typo: requried instead of required)" do
      ast = quote(do: field(:name, :string, requried: true))

      assert_raise ArgumentError, ~r/unknown option\(s\) \[:requried\]/, fn ->
        Kumi.Resource.FieldSpec.parse(ast, __ENV__)
      end
    end

    test "real Ash attribute options (allow_nil?, public?) that Codegen never reads are rejected, not silently dropped" do
      ast = quote(do: field(:x, :string, allow_nil?: false, public?: false))

      assert_raise ArgumentError, ~r/unknown option\(s\) \[:allow_nil\?, :public\?\]/, fn ->
        Kumi.Resource.FieldSpec.parse(ast, __ENV__)
      end
    end

    test "error message lists the accepted keys for the field's kind" do
      ast = quote(do: field(:status, :select, bogus: true))

      assert_raise ArgumentError,
                   ~r/Accepted options for :select fields: \[:required, :default, :options\]/,
                   fn -> Kumi.Resource.FieldSpec.parse(ast, __ENV__) end
    end

    test "a scalar field accepts :required and :default (no false positive)" do
      ast = quote(do: field(:name, :string, required: true, default: "x"))

      assert [%Kumi.Resource.FieldSpec{opts: [required: true, default: "x"]}] =
               Kumi.Resource.FieldSpec.parse(ast, __ENV__)
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
