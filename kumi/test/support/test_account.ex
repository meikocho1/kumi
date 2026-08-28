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

    # H4 regression coverage: a bare `:date` attribute exercises
    # `Kumi.Desired.PgType.precision_from_ash/2`'s `:date -> 0` clause end
    # to end. Before that fix, this column alone made the clean-state
    # zero-diff test (`Kumi.DiffCleanStateTest`) fail permanently: Ash's
    # side reported `datetime_precision: nil`, Postgres reports `0`.
    attribute :founded_on, :date do
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
