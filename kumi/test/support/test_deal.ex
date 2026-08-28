defmodule Kumi.Test.Deal do
  @moduledoc false

  use Ash.Resource,
    domain: Kumi.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "kumi_test_deals"
    repo Kumi.Test.Repo

    # M2 regression coverage: a `custom_indexes` block (not an `identities`
    # unique constraint) exercises Kumi.Desired.custom_indexes/2. No
    # explicit `name:` here on purpose, to also exercise the default-naming
    # path (AshPostgres.CustomIndex.name/2). `amount`, not `stage`, so
    # dropping `stage` in Kumi.ApplyTest doesn't also cascade-drop this
    # index and change that (unrelated) test's expected op count.
    custom_indexes do
      index [:amount]
    end
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
