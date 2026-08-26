defmodule Kumi.Test.Resource.Account do
  @moduledoc false
  # Hand-written target for Kumi.Test.Resource.Customer's `belongs_to`.

  use Ash.Resource,
    domain: Kumi.Test.ResourceDomain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "kumi_test_resource_accounts"
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
end
