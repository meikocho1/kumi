defmodule Kumi.Test.Repo do
  @moduledoc "Test-only repo for the package's own Ash test harness. See test/support."

  use AshPostgres.Repo, otp_app: :kumi, warn_on_missing_ash_functions?: false

  @impl true
  def installed_extensions, do: []

  @impl true
  def min_pg_version, do: %Version{major: 16, minor: 0, patch: 0}
end
