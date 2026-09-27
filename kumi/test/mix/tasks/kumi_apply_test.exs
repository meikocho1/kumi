defmodule Mix.Tasks.Kumi.ApplyTest do
  # The task-level refusals SECURITY.md relies on. The MIX_ENV guard fires
  # before app.start, and the codegen/migration precondition takes its
  # inputs as arguments, so only migration_statuses/1 touches the database.
  use Kumi.Test.DataCase, async: false

  alias Mix.Tasks.Kumi.Apply

  test "refuses to run outside MIX_ENV=dev" do
    assert Mix.env() == :test

    assert_raise Mix.Error, ~r/only runs under MIX_ENV=dev/, fn -> Apply.run(["--yes"]) end
  end

  test "migration_statuses/1 finds the repo's migration files, every one run here" do
    statuses = Apply.migration_statuses(Kumi.Test.Repo)

    files =
      "priv/repo/migrations/*.exs"
      |> Path.wildcard()
      |> Enum.map(&(&1 |> Path.basename(".exs") |> String.split("_", parts: 2) |> List.last()))

    assert Enum.sort(Enum.map(statuses, &elem(&1, 2))) == Enum.sort(files)
    assert Enum.all?(statuses, &match?({:up, _, _}, &1))
  end

  describe "ensure_caught_up!/2" do
    test "a pending migration refuses the run, before codegen is even asked" do
      migrations = [
        {:up, 20_260_101_000_000, "initial"},
        {:down, 20_260_102_000_000, "add_phone"}
      ]

      assert_raise Mix.Error,
                   ~r/1 migration\(s\) not run yet \(20260102000000_add_phone\).*ash\.migrate/s,
                   fn ->
                     Apply.ensure_caught_up!(migrations, fn ->
                       flunk("codegen check must not run")
                     end)
                   end
    end

    test "code ahead of the snapshot refuses the run, with codegen's own output" do
      migrations = [{:up, 20_260_101_000_000, "initial"}]

      error =
        assert_raise Mix.Error, ~r/code is ahead of the snapshot.*ash\.codegen <name>/s, fn ->
          Apply.ensure_caught_up!(migrations, fn -> {"Codegen check failed.", 1} end)
        end

      assert error.message =~ "Codegen check failed."
    end

    test "migrated and nothing left to generate lets the run continue" do
      assert Apply.ensure_caught_up!([{:up, 20_260_101_000_000, "initial"}], fn -> {"", 0} end) ==
               :ok
    end
  end
end
