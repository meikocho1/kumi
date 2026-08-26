defmodule KumiAdmin.Test.Domain do
  @moduledoc "Fixture Ash domain backing every `KumiAdmin.Test.*` resource."

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource KumiAdmin.Test.Widget
    resource KumiAdmin.Test.Account
    resource KumiAdmin.Test.Contact
  end
end

defmodule KumiAdmin.Test.Widget do
  @moduledoc "Fixture Ash resource — enough public attributes to exercise the N=6 column cap."

  use Ash.Resource,
    domain: KumiAdmin.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id
    attribute :a, :string, public?: true
    attribute :b, :string, public?: true
    attribute :c, :string, public?: true
    attribute :d, :string, public?: true
    attribute :e, :string, public?: true
    attribute :f, :string, public?: true
    attribute :hidden, :string, public?: false
    attribute :description, :string, public?: true
    attribute :active, :boolean, public?: true
    attribute :scheduled_on, :date, public?: true
    attribute :price, :decimal, public?: true

    attribute :status, :atom do
      public? true
      constraints one_of: [:draft, :published]
    end
  end
end

defmodule KumiAdmin.Test.Account do
  @moduledoc "Fixture Ash resource for `KumiAdmin.Test.App`."

  use Ash.Resource,
    domain: KumiAdmin.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end
end

defmodule KumiAdmin.Test.Contact do
  @moduledoc "Fixture Ash resource for `KumiAdmin.Test.App`. Carries a `belongs_to` so form-field derivation can be tested against a real relationship."

  use Ash.Resource,
    domain: KumiAdmin.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  relationships do
    belongs_to :account, KumiAdmin.Test.Account, public?: true
  end
end

defmodule KumiAdmin.Test.App do
  @moduledoc "Fixture `Kumi.App` for `KumiAdmin.Slug`/`KumiAdmin.Label` tests."

  use Kumi.App

  app do
    name :fixture
    title("Fixture App")
  end

  resources do
    resource KumiAdmin.Test.Account
    resource KumiAdmin.Test.Contact
  end

  admin do
    navigation([KumiAdmin.Test.Account, KumiAdmin.Test.Contact])
  end
end
