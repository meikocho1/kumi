defmodule Kumi.Test.Account do
  @moduledoc false

  use Ash.Resource,
    domain: Kumi.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "kumi_test_accounts"
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

    attribute :industry, :string do
      public? true
    end

    timestamps()
  end

  identities do
    identity :unique_name, [:name]
  end

  relationships do
    has_many :deals, Kumi.Test.Deal
  end
end
