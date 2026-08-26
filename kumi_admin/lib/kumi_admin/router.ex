defmodule KumiAdmin.Router do
  @moduledoc """
  Mounts the Kumi Admin shell into a host Phoenix router.

      import KumiAdmin.Router

      scope "/", MyAppWeb do
        pipe_through :browser

        kumi_admin "/admin",
          app: MyApp.App,
          on_mount: [{MyAppWeb.LiveUserAuth, :current_user}]
      end

  ## Options

    * `:app` (required) — the `Kumi.App` module to render.
    * `:on_mount` — `on_mount` hooks run before every KumiAdmin LiveView.
      Use this to populate whatever assign your `:actor` option reads
      (default `:current_user`) — KumiAdmin does not authenticate anyone
      itself. See `KumiAdmin.Actor`.
    * `:actor` — `{Module, :function}` resolving the Ash actor from the
      mounted socket. Defaults to `{KumiAdmin.Actor, :from_current_user}`.
    * `:live_session_name` — defaults to `:kumi_admin`.

  ## Actor handoff

  KumiAdmin's own `live_session` does not override the LiveView `session`
  wholesale — it reads the full Plug session (via `Plug.Conn.get_session/1`)
  and adds its own two keys, so whatever your `on_mount` hooks need from the
  Plug session (e.g. `ash_authentication_phoenix`'s `user_token`) is still
  there. Without an actor, policy-protected resources legitimately come
  back empty/forbidden — the shell renders that honestly instead of
  crashing.
  """

  defmacro kumi_admin(path, opts \\ []) do
    quote bind_quoted: [path: path, opts: opts] do
      import Phoenix.LiveView.Router

      app = Keyword.fetch!(opts, :app)
      actor_fun = Keyword.get(opts, :actor, {KumiAdmin.Actor, :from_current_user})
      on_mount_hooks = Keyword.get(opts, :on_mount, [])
      live_session_name = Keyword.get(opts, :live_session_name, :kumi_admin)

      live_session live_session_name,
        on_mount: on_mount_hooks,
        session: {KumiAdmin.Router, :__session__, [path, app, actor_fun]} do
        live path, KumiAdmin.DashboardLive, :dashboard
        live "#{path}/:resource", KumiAdmin.ResourceIndexLive, :index
        live "#{path}/:resource/:id", KumiAdmin.ResourceShowLive, :show
      end
    end
  end

  @doc false
  def __session__(conn, path, app, actor_fun) do
    conn
    |> Plug.Conn.get_session()
    |> Map.put("kumi_admin_path", path)
    |> Map.put("kumi_admin_app", app)
    |> Map.put("kumi_admin_actor", actor_fun)
  end
end
