defmodule Mix.Tasks.KumiAdmin.InstallTest do
  @moduledoc """
  `mix kumi_admin.install` composes `kumi.install` and then mounts
  `KumiAdmin.Router`'s `kumi_admin/2` macro. The auto-mount-vs-TODO
  decision is the risky part (blueprint §28): a wrong `on_mount`/actor
  guess is worse than asking, so these tests pin both branches.
  """
  use ExUnit.Case, async: true

  import Igniter.Test

  @router """
  defmodule MyAppWeb.Router do
    use MyAppWeb, :router

    pipeline :browser do
      plug :accepts, ["html"]
    end

    scope "/", MyAppWeb do
      pipe_through :browser

      get "/", PageController, :home
    end
  end
  """

  @live_user_auth_with_current_user """
  defmodule MyAppWeb.LiveUserAuth do
    def on_mount(:current_user, _params, _session, socket), do: {:cont, socket}
    def on_mount(:live_user_required, _params, _session, socket), do: {:cont, socket}
  end
  """

  @accounts_user """
  defmodule MyApp.Accounts.User do
    defstruct [:id, :email]
  end
  """

  test "no router found: warns with a manual snippet, mounts nothing" do
    igniter =
      test_project(app_name: :my_app)
      |> Igniter.compose_task("kumi_admin.install", [])

    assert_creates(igniter, "lib/my_app/app.ex")

    assert Enum.any?(igniter.warnings, fn w ->
             IO.iodata_to_binary(w) =~ "kumi_admin"
           end)
  end

  test "router present, no LiveUserAuth: TODO notice only, router untouched" do
    igniter =
      test_project(app_name: :my_app, files: %{"lib/my_app_web/router.ex" => @router})
      |> Igniter.compose_task("kumi_admin.install", [])

    assert_unchanged(igniter, "lib/my_app_web/router.ex")

    assert Enum.any?(igniter.notices, fn n ->
             IO.iodata_to_binary(n) =~ "could not confirm"
           end)
  end

  test "router + LiveUserAuth with :current_user clause: mounts kumi_admin for real" do
    igniter =
      test_project(
        app_name: :my_app,
        files: %{
          "lib/my_app_web/router.ex" => @router,
          "lib/my_app_web/live_user_auth.ex" => @live_user_auth_with_current_user
        }
      )
      |> Igniter.compose_task("kumi_admin.install", [])

    {_igniter, source, _zipper} =
      Igniter.Project.Module.find_module!(igniter, MyAppWeb.Router)

    content = Rewrite.Source.get(source, :content)

    assert content =~ "kumi_admin"
    assert content =~ "MyAppWeb.LiveUserAuth"
    assert content =~ ":current_user"
  end

  test "router + LiveUserAuth + Accounts.User: mount includes user_resource and register_path" do
    igniter =
      test_project(
        app_name: :my_app,
        files: %{
          "lib/my_app_web/router.ex" => @router,
          "lib/my_app_web/live_user_auth.ex" => @live_user_auth_with_current_user,
          "lib/my_app/accounts/user.ex" => @accounts_user
        }
      )
      |> Igniter.compose_task("kumi_admin.install", [])

    {_igniter, source, _zipper} =
      Igniter.Project.Module.find_module!(igniter, MyAppWeb.Router)

    content = Rewrite.Source.get(source, :content)

    assert content =~ "user_resource: MyApp.Accounts.User"
    assert content =~ ~s(register_path: "/register")

    assert Enum.any?(igniter.notices, fn n ->
             IO.iodata_to_binary(n) =~ "MyApp.Accounts.User"
           end)
  end

  test "router + LiveUserAuth, no Accounts.User: mount omits user_resource and says so" do
    igniter =
      test_project(
        app_name: :my_app,
        files: %{
          "lib/my_app_web/router.ex" => @router,
          "lib/my_app_web/live_user_auth.ex" => @live_user_auth_with_current_user
        }
      )
      |> Igniter.compose_task("kumi_admin.install", [])

    {_igniter, source, _zipper} =
      Igniter.Project.Module.find_module!(igniter, MyAppWeb.Router)

    content = Rewrite.Source.get(source, :content)

    refute content =~ "user_resource"

    assert Enum.any?(igniter.notices, fn n ->
             IO.iodata_to_binary(n) =~ "no MyApp.Accounts.User module was found"
           end)
  end

  test "running twice does not duplicate the mount" do
    igniter =
      test_project(
        app_name: :my_app,
        files: %{
          "lib/my_app_web/router.ex" => @router,
          "lib/my_app_web/live_user_auth.ex" => @live_user_auth_with_current_user
        }
      )
      |> Igniter.compose_task("kumi_admin.install", [])
      |> apply_igniter!()

    igniter = Igniter.compose_task(igniter, "kumi_admin.install", [])

    assert_unchanged(igniter, "lib/my_app_web/router.ex")

    assert Enum.any?(igniter.notices, fn n ->
             IO.iodata_to_binary(n) =~ "already mounted"
           end)
  end
end
