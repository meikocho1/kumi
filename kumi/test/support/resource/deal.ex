defmodule Kumi.Test.Resource.Deal do
  @moduledoc false
  # Hand-written target for Kumi.Test.Resource.Customer's `has_many :deals`.

  use Ash.Resource,
    domain: Kumi.Test.ResourceDomain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "kumi_test_resource_deals"
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

    timestamps()
  end

  relationships do
    belongs_to :customer, Kumi.Test.Resource.Customer do
      allow_nil? false
      public? true
    end
  end
end
