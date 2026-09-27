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

  test "the manual snippets name this app's modules, not MyAppWeb" do
    # A snippet that does not compile as pasted gets edited by hand under
    # time pressure — which is where `on_mount` goes missing.
    no_router =
      test_project(app_name: :shop)
      |> Igniter.compose_task("kumi_admin.install", [])

    no_auth =
      test_project(
        app_name: :shop,
        files: %{"lib/shop_web/router.ex" => String.replace(@router, "MyApp", "Shop")}
      )
      |> Igniter.compose_task("kumi_admin.install", [])

    snippets = [
      Enum.find(no_router.warnings, &(IO.iodata_to_binary(&1) =~ "kumi_admin \"")),
      Enum.find(no_auth.notices, &(IO.iodata_to_binary(&1) =~ "could not confirm"))
    ]

    for snippet <- snippets do
      assert snippet, "no manual snippet was printed"
      snippet = IO.iodata_to_binary(snippet)

      assert snippet =~ "on_mount: [{ShopWeb.LiveUserAuth, :current_user}]"
      assert snippet =~ "user_resource: Shop.Accounts.User"
      refute snippet =~ "MyApp"
    end
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

  test "the mount notice says every accepted account is a full admin, and how to narrow it" do
    igniter =
      test_project(
        app_name: :my_app,
        files: %{
          "lib/my_app_web/router.ex" => @router,
          "lib/my_app_web/live_user_auth.ex" => @live_user_auth_with_current_user
        }
      )
      |> Igniter.compose_task("kumi_admin.install", [])

    notice =
      igniter.notices
      |> Enum.map(&IO.iodata_to_binary/1)
      |> Enum.find(&(&1 =~ "mounted at /kumi-admin"))

    assert notice, "no mount notice was printed"
    assert notice =~ "Every account your authentication accepts gets full /kumi-admin"
    assert notice =~ "registration_enabled? false"
    assert notice =~ "actor: {MyAppWeb.AdminActor, :fetch}"
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
