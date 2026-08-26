defmodule Kumi.Test.Deal do
  @moduledoc false

  use Ash.Resource,
    domain: Kumi.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "kumi_test_deals"
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

    attribute :amount, :decimal do
      public? true
    end

    attribute :stage, :atom do
      constraints one_of: [:lead, :qualified, :proposal, :won, :lost]
      default :lead
      public? true
    end

    # Explicit non-usec timestamp, exercising the `:utc_datetime` branch of
    # Kumi.Desired.PgType (timestamps() below already covers the _usec one).
    attribute :closed_at, :utc_datetime do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :account, Kumi.Test.Account do
      allow_nil? false
      public? true
    end
  end
end
