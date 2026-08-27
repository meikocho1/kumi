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

  test "creates <App>.Core domain and registers it in :ash_domains when absent" do
    igniter =
      test_project(app_name: :my_app)
      |> Igniter.compose_task("kumi.install", [])

    assert_creates(igniter, "lib/my_app/core.ex")

    {source, _igniter} =
      Igniter.Project.Module.find_module!(igniter, MyApp.Core)
      |> then(fn {igniter, source, _zipper} -> {source, igniter} end)

    content = Rewrite.Source.get(source, :content)
    assert content =~ "use Ash.Domain"
    assert content =~ "resources do"

    config_content =
      igniter.rewrite
      |> Rewrite.source!("config/config.exs")
      |> Rewrite.Source.get(:content)

    assert config_content =~ "ash_domains"
    assert config_content =~ "MyApp.Core"
  end

  test "appends to an existing :ash_domains list instead of overwriting it" do
    igniter =
      test_project(app_name: :my_app)
      |> Igniter.Project.Config.configure(
        "config.exs",
        :my_app,
        [:ash_domains],
        [MyApp.Accounts]
      )
      |> apply_igniter!()
      |> Igniter.compose_task("kumi.install", [])

    config_content =
      igniter.rewrite
      |> Rewrite.source!("config/config.exs")
      |> Rewrite.Source.get(:content)

    assert config_content =~ "MyApp.Accounts"
    assert config_content =~ "MyApp.Core"
  end

  test "app.ex already existing does not skip domain creation" do
    igniter =
      test_project(
        app_name: :my_app,
        files: %{
          "lib/my_app/app.ex" => """
          defmodule MyApp.App do
            use Kumi.App

            app do
              name :my_app
              title "My App"
            end

            resources do
            end
          end
          """
        }
      )
      |> Igniter.compose_task("kumi.install", [])

    assert_creates(igniter, "lib/my_app/core.ex")
  end

  test "double-run (as kumi_admin.install composes kumi.install) does not duplicate the domain or config" do
    igniter =
      test_project(app_name: :my_app)
      |> Igniter.compose_task("kumi.install", [])
      |> apply_igniter!()

    igniter = Igniter.compose_task(igniter, "kumi.install", [])

    assert_unchanged(igniter, "lib/my_app/core.ex")

    config_content =
      igniter.rewrite
      |> Rewrite.source!("config/config.exs")
      |> Rewrite.Source.get(:content)

    assert length(Regex.scan(~r/MyApp\.Core/, config_content)) == 1
  end
end
