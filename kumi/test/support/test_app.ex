defmodule Kumi.Test.App do
  @moduledoc """
  Minimal `Kumi.App` fixture used by `app_test.exs` and `plan_app_test.exs`.

  Deliberately declares only `Kumi.Test.Account` — not `Kumi.Test.Deal`,
  even though both belong to `Kumi.Test.Domain` and both have real,
  migrated tables in `Kumi.Test.Repo`'s database. That asymmetry is what
  `plan_app_test.exs` exercises: `kumi_test_deals` must not show up as
  drift just because it's outside this app's declared resources.
  """

  use Kumi.App

  app do
    name :test_app
    title "Test App"
  end

  resources do
    resource Kumi.Test.Account
  end

  admin do
    navigation [Kumi.Test.Account]
  end

  workflow :onboarding do
    stages [:invited, :active]
  end

  dashboard :overview do
    metric :account_count
  end
end
