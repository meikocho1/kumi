defmodule KumiAdmin.RouterTest do
  @moduledoc """
  What `KumiAdmin.Router.kumi_admin/2` hands LiveView, and what it refuses
  to compile. The session is read back through the route's own
  `live_session` MFA — the same `apply(mod, fun, [conn | args])` that
  `Phoenix.LiveView.Plug` runs on the dead render — so the positional
  args and `__session__`'s arity are exercised together.
  """

  use ExUnit.Case, async: true

  defmodule Router do
    @moduledoc false
    use Phoenix.Router
    import KumiAdmin.Router

    kumi_admin("/admin", app: KumiAdmin.Test.App)
  end

  defp live_session_of(router, path) do
    %{phoenix_live_view: {_view, _action, _opts, live_session}} =
      Phoenix.Router.route_info(router, "GET", path, nil)

    live_session
  end

  defp compile_router(opts_ast) do
    name = Module.concat(__MODULE__, "Router#{System.unique_integer([:positive])}")

    quoted =
      quote do
        defmodule unquote(name) do
          use Phoenix.Router
          import KumiAdmin.Router

          kumi_admin("/admin", unquote(opts_ast))
        end
      end

    Code.compile_quoted(quoted)
  end

  describe "the live_session session" do
    test "carries kumi_admin's own keys and none of the cookie session" do
      %{extra: %{session: {mod, fun, args}}} = live_session_of(Router, "/admin")

      conn =
        Plug.Test.conn(:get, "/admin")
        |> Plug.Test.init_test_session(%{"user_token" => "t", "_csrf_token" => "c"})

      session = apply(mod, fun, [conn | args])

      # LiveView signs (does not encrypt) this map into the page markup,
      # and merges the cookie session in on its own — a copy here would
      # put the bearer token where any script on the page can decode it.
      refute Map.has_key?(session, "user_token")
      refute Map.has_key?(session, "_csrf_token")

      assert session["kumi_admin_app"] == KumiAdmin.Test.App
      assert session["kumi_admin_path"] == "/admin"
      assert session["kumi_admin_actor"] == {KumiAdmin.Actor, :from_current_user}
    end

    test "is exactly what KumiAdmin.Context reads back" do
      %{extra: %{session: {mod, fun, args}}} = live_session_of(Router, "/admin")
      session = apply(mod, fun, [Plug.Test.conn(:get, "/admin") | args])

      ctx =
        KumiAdmin.Context.resolve(session, %{}, %Phoenix.LiveView.Socket{
          assigns: %{current_user: :someone}
        })

      assert ctx.app == KumiAdmin.Test.App
      assert ctx.actor == :someone
      assert ctx.sign_in_path == "/sign-in"
    end
  end

  describe "option validation at router compile time" do
    test "a misspelled option raises instead of being ignored" do
      assert_raise ArgumentError, ~r/unknown keys \[:sign_in_pth\]/, fn ->
        compile_router(quote(do: [app: KumiAdmin.Test.App, sign_in_pth: "/login"]))
      end
    end

    test "a function-capture actor raises instead of failing on the first mount" do
      assert_raise ArgumentError, ~r/:actor must be a \{Module, :function\} pair/, fn ->
        compile_router(
          quote(do: [app: KumiAdmin.Test.App, actor: &KumiAdmin.Actor.from_current_user/1])
        )
      end
    end

    test "a missing :app still raises" do
      assert_raise KeyError, ~r/:app/, fn ->
        compile_router(quote(do: [on_mount: []]))
      end
    end
  end
end
