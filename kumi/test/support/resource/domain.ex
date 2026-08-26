defmodule Kumi.Test.ResourceDomain do
  @moduledoc """
  Second test-only Ash domain, isolated from `Kumi.Test.Domain` (used by
  the pre-existing plan tests — deliberately untouched). Exercises
  `Kumi.Resource`: `Kumi.Test.Resource.Customer` is the shorthand,
  `Kumi.Test.Resource.HandwrittenCustomer` is its hand-written twin,
  `Kumi.Test.Resource.Account`/`Deal` are the (hand-written)
  belongs_to/has_many targets.
  """

  use Ash.Domain

  resources do
    resource Kumi.Test.Resource.Account
    resource Kumi.Test.Resource.Customer
    resource Kumi.Test.Resource.Deal
    resource Kumi.Test.Resource.HandwrittenCustomer
  end
end
