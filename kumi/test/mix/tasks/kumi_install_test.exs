defmodule Mix.Tasks.Kumi.InstallTest do
  @moduledoc """
  `mix kumi.install` is the blueprint §28 quick-start path — it must
  generate a `use Kumi.App` skeleton with the right module/app names and
  be a no-op on a second run (idempotent).
  """
  use ExUnit.Case, async: true

  import Igniter.Test

  test "creates <App>.App with the app name/title derived from the otp_app" do
    igniter =
      test_project(app_name: :my_app)
      |> Igniter.compose_task("kumi.install", [])

    assert_creates(igniter, "lib/my_app/app.ex")

    {source, _igniter} =
      Igniter.Project.Module.find_module!(igniter, MyApp.App)
      |> then(fn {igniter, source, _zipper} -> {source, igniter} end)

    content = Rewrite.Source.get(source, :content)

    assert content =~ "use Kumi.App"
    assert content =~ ":my_app"
    assert content =~ "\"My App\""
    assert content =~ "resources do"
  end

  test "running twice does not duplicate or touch the app module" do
    igniter =
      test_project(app_name: :my_app)
      |> Igniter.compose_task("kumi.install", [])
      |> apply_igniter!()

    igniter = Igniter.compose_task(igniter, "kumi.install", [])

    assert_unchanged(igniter, "lib/my_app/app.ex")
  end
end
