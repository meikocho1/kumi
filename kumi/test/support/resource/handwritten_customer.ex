defmodule Kumi.Test.Resource.HandwrittenCustomer do
  @moduledoc false
  # Hand-written Ash resource with identical intent to
  # Kumi.Test.Resource.Customer (minus `has_many :deals`, which is covered
  # instead by the expand-invariant test recompiling Customer's full
  # output). Used by test/kumi/resource_test.exs to assert
  # Ash.Resource.Info parity between the shorthand and the real thing.

  use Ash.Resource,
    domain: Kumi.Test.ResourceDomain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "kumi_test_resource_customers_hw"
    repo Kumi.Test.Repo
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :email, :string do
      public? true
      constraints match: ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/
    end

    attribute :status, :atom do
      public? true
      default :lead
      constraints one_of: [:lead, :active, :lost]
    end

    timestamps()
  end

  relationships do
    belongs_to :account, Kumi.Test.Resource.Account do
      public? true
    end
  end
end
