defmodule Kumi.Test.Domain do
  @moduledoc """
  Minimal Ash domain exercising the attribute/relationship/identity surface
  Kumi's DESIRED-side extraction needs to cover: uuid pk, text, numeric
  (decimal), an atom `one_of` with a literal default, both `utc_datetime`
  and `utc_datetime_usec` timestamps, a `belongs_to` foreign key, and a
  unique identity.
  """

  use Ash.Domain

  resources do
    resource Kumi.Test.Account
    resource Kumi.Test.Deal
  end
end
