defmodule Kumi.Test.DataCase do
  @moduledoc """
  Setup for tests that need the Ecto sandbox against `Kumi.Test.Repo`.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Kumi.Test.Repo

      import Ecto.Query
      import Kumi.Test.DataCase
    end
  end

  setup tags do
    Kumi.Test.DataCase.setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Kumi.Test.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end
end
