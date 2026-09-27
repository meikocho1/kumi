defmodule Kumi.DesiredExactDdlTest do
  # `exact_type?` / `exact?` decide whether Kumi.Apply may run
  # `ADD COLUMN c <type>` / `CREATE INDEX i ON t (cols)` for a missing
  # column or index. Kumi.Desired reads only code, so these resources are
  # never migrated: their domain stays out of :ash_domains and no table
  # exists for them.
  use ExUnit.Case, async: true

  alias Kumi.Schema.Table

  defmodule Domain do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource Kumi.DesiredExactDdlTest.Priced
      resource Kumi.DesiredExactDdlTest.Overridden
      resource Kumi.DesiredExactDdlTest.Tenanted
      resource Kumi.DesiredExactDdlTest.Scoped
    end
  end

  defmodule OverridingRepo do
    @moduledoc false
    use AshPostgres.Repo, otp_app: :kumi, warn_on_missing_ash_functions?: false

    @impl true
    def installed_extensions, do: []

    @impl true
    def min_pg_version, do: %Version{major: 16, minor: 0, patch: 0}

    @impl true
    def override_migration_type(:text), do: :citext
    def override_migration_type(type), do: type
  end

  defmodule Priced do
    @moduledoc false
    use Ash.Resource, domain: Domain, data_layer: AshPostgres.DataLayer

    postgres do
      table "kumi_exact_priced"
      repo Kumi.Test.Repo
      migration_types code: {:varchar, 20}

      custom_indexes do
        index [:amount]
        index [:amount], name: "partial_index", where: "amount > 0"
        index [:amount], name: "brin_index", using: "brin"
        index [:amount], name: "covering_index", include: ["code"]
        index [:amount], name: "nulls_index", nulls_distinct: false
        index [:amount], name: "prefixed_index", prefix: "archive"
        index ["lower(code)"], name: "expression_index"
        index [{:desc, :amount}], name: "ordered_index"
      end
    end

    attributes do
      uuid_primary_key :id
      attribute :amount, :decimal
      attribute :price, :decimal, constraints: [precision: 10, scale: 2]
      attribute :embedding, :vector, constraints: [dimensions: 3]
      attribute :code, :string
      attribute :name, :string
      attribute :tags, {:array, :string}
    end
  end

  defmodule Overridden do
    @moduledoc false
    use Ash.Resource, domain: Domain, data_layer: AshPostgres.DataLayer

    postgres do
      table "kumi_exact_overridden"
      repo OverridingRepo
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string
    end
  end

  defmodule Tenanted do
    @moduledoc false
    use Ash.Resource, domain: Domain, data_layer: AshPostgres.DataLayer

    postgres do
      table "kumi_exact_tenanted"
      repo Kumi.Test.Repo

      custom_indexes do
        index [:name]
        index [:name], name: "all_tenants_index", all_tenants?: true
      end
    end

    multitenancy do
      strategy :attribute
      attribute :org_id
    end

    attributes do
      uuid_primary_key :id
      attribute :org_id, :uuid
      attribute :name, :string
    end
  end

  defmodule Scoped do
    @moduledoc false
    use Ash.Resource, domain: Domain, data_layer: AshPostgres.DataLayer

    resource do
      base_filter expr(active == true)
    end

    postgres do
      table "kumi_exact_scoped"
      repo Kumi.Test.Repo
      base_filter_sql "active = true"

      custom_indexes do
        index [:name]
        index [:name], name: "unfiltered_index", include_base_filter?: false
      end
    end

    attributes do
      uuid_primary_key :id
      attribute :active, :boolean
      attribute :name, :string
    end
  end

  defp table(name),
    do: Domain |> List.wrap() |> Kumi.Desired.extract() |> Enum.find(&(&1.name == name))

  defp exact_types(name), do: Map.new(table(name).columns, &{&1.name, &1.exact_type?})
  defp exact_indexes(name), do: Map.new(table(name).indexes, &{&1.name, &1.exact?})

  test "a column type is exact only when its name is the whole type" do
    assert exact_types("kumi_exact_priced") == %{
             "id" => true,
             "amount" => true,
             "price" => false,
             "embedding" => false,
             "code" => false,
             "name" => true,
             "tags" => true
           }
  end

  test "a repo's override_migration_type/1 makes the columns it changes inexact" do
    assert exact_types("kumi_exact_overridden") == %{"id" => true, "name" => false}
  end

  test "a custom index is exact only with no option Kumi.Schema.Index can't carry" do
    assert exact_indexes("kumi_exact_priced") == %{
             "kumi_exact_priced_amount_index" => true,
             "partial_index" => false,
             "brin_index" => false,
             "covering_index" => false,
             "nulls_index" => false,
             "prefixed_index" => false,
             "expression_index" => false,
             "ordered_index" => false
           }
  end

  test "attribute multitenancy prepends the tenant column unless all_tenants?" do
    assert exact_indexes("kumi_exact_tenanted") == %{
             "kumi_exact_tenanted_name_index" => false,
             "all_tenants_index" => true
           }
  end

  test "a resource base filter becomes the index's WHERE unless include_base_filter? is off" do
    assert exact_indexes("kumi_exact_scoped") == %{
             "kumi_exact_scoped_name_index" => false,
             "unfiltered_index" => true
           }
  end

  test "neither flag is compared: an inexact desired side against the same actual is no diff" do
    %Table{} = desired = table("kumi_exact_priced")

    actual = %Table{
      desired
      | columns: Enum.map(desired.columns, &%{&1 | exact_type?: true}),
        indexes: Enum.map(desired.indexes, &%{&1 | exact?: true})
    }

    assert Kumi.Diff.diff([desired], [actual]) == []
  end
end
