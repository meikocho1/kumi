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
    * `:sign_out_path` — href for the shell's "Sign out" link. Defaults to
      `"/sign-out"`. KumiAdmin does not implement sign-out itself; point
      this at the host's real route.
    * `:sign_in_path` — redirect target when a LiveView mounts with no
      actor (and either `:user_resource` is unset or already has users).
      Defaults to `"/sign-in"`. KumiAdmin does not implement sign-in
      itself; point this at the host's real route.
    * `:user_resource` — the host's user resource (e.g.
      `MyApp.Accounts.User`), optional, default `nil`. When set, an
      actor-less mount redirects to `:register_path` instead of
      `:sign_in_path` if this resource currently has zero records — a
      fresh install's "create the first user" onboarding. See
      `KumiAdmin.Gate`.
    * `:register_path` — redirect target for the zero-users case above.
      Defaults to `"/register"`.
    * `:strings` — chrome-string overrides, per locale, merged over
      `KumiAdmin.Locale.table/0`: `%{ja: %{new: "登録"}}`. Only the keys
      given change. The *language* comes from the app's own
      `app do locale ... end`, not from here.
    * `:live_session_name` — defaults to `:kumi_admin`.

  ## Requirements on managed resources

  Every resource passed to `resources`/`navigation` must have a single
  primary key named `:id` — the generic index/show/form LiveViews sort,
  link, and look up records by that name unconditionally (e.g.
  `Ash.Query.sort(:id)`). A resource with a differently-named or
  composite primary key will fail at read time, not at compile time here
  (a `Kumi.App` compile-time verifier enforces this on the app side).

  ## Auth gate

  KumiAdmin is a post-login experience: every LiveView calls
  `KumiAdmin.Gate.check/2` right after resolving the session, and an
  actor-less visit never renders the shell — it redirects (to
  `:register_path` on a fresh install with zero users, to `:sign_in_path`
  otherwise). See `KumiAdmin.Gate`.

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
      sign_out_path = Keyword.get(opts, :sign_out_path, "/sign-out")
      sign_in_path = Keyword.get(opts, :sign_in_path, "/sign-in")
      user_resource = Keyword.get(opts, :user_resource, nil)
      register_path = Keyword.get(opts, :register_path, "/register")
      on_mount_hooks = Keyword.get(opts, :on_mount, [])
      strings = Keyword.get(opts, :strings, %{})
      live_session_name = Keyword.get(opts, :live_session_name, :kumi_admin)

      live_session live_session_name,
        on_mount: on_mount_hooks,
        session:
          {KumiAdmin.Router, :__session__,
           [
             path,
             app,
             actor_fun,
             sign_out_path,
             sign_in_path,
             user_resource,
             register_path,
             strings
           ]} do
        live path, KumiAdmin.DashboardLive, :dashboard
        live "#{path}/:resource", KumiAdmin.ResourceIndexLive, :index
        live "#{path}/:resource/new", KumiAdmin.ResourceFormLive, :new
        live "#{path}/:resource/:id", KumiAdmin.ResourceShowLive, :show
        live "#{path}/:resource/:id/edit", KumiAdmin.ResourceFormLive, :edit
      end
    end
  end

  @doc false
  def __session__(
        conn,
        path,
        app,
        actor_fun,
        sign_out_path,
        sign_in_path,
        user_resource,
        register_path,
        strings
      ) do
    conn
    |> Plug.Conn.get_session()
    |> Map.put("kumi_admin_path", path)
    |> Map.put("kumi_admin_app", app)
    |> Map.put("kumi_admin_actor", actor_fun)
    |> Map.put("kumi_admin_sign_out_path", sign_out_path)
    |> Map.put("kumi_admin_sign_in_path", sign_in_path)
    |> Map.put("kumi_admin_user_resource", user_resource)
    |> Map.put("kumi_admin_register_path", register_path)
    |> Map.put("kumi_admin_strings", strings)
  end
end
