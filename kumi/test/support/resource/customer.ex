defmodule Kumi.Test.Resource.Customer do
  @moduledoc false
  # The "real" Kumi.Resource shorthand example — mirrors the moduledoc
  # example almost verbatim. Kumi.Test.Resource.HandwrittenCustomer is its
  # hand-written twin (see test/kumi/resource_test.exs).

  use Kumi.Resource,
    domain: Kumi.Test.ResourceDomain,
    repo: Kumi.Test.Repo,
    table: "kumi_test_resource_customers"

  fields do
    field :name, :string, required: true
    field :email, :email
    field :status, :select, options: [:lead, :active, :lost], default: :lead
    belongs_to :account, Kumi.Test.Resource.Account
    has_many :deals, Kumi.Test.Resource.Deal
  end
end
