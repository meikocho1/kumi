ExUnit.start()
{:ok, _} = Kumi.Test.Repo.start_link()
Ecto.Adapters.SQL.Sandbox.mode(Kumi.Test.Repo, :manual)
