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

  An unknown option (a typo such as `sign_in_pth:`) raises an
  `ArgumentError` when the router compiles, instead of being ignored.

    * `:app` (required) — the `Kumi.App` module to render.
    * `:on_mount` — `on_mount` hooks run before every KumiAdmin LiveView.
      Use this to populate whatever assign your `:actor` option reads
      (default `:current_user`) — KumiAdmin does not authenticate anyone
      itself. See `KumiAdmin.Actor`.
    * `:actor` — `{Module, :function}` resolving the Ash actor from the
      mounted socket. Defaults to `{KumiAdmin.Actor, :from_current_user}`.
      Anything else (e.g. a `&MyAuth.actor/1` capture) raises an
      `ArgumentError` when the router compiles.
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

  KumiAdmin's `live_session` session holds only its own keys:
  `"kumi_admin_path"`, `"kumi_admin_app"`, `"kumi_admin_actor"` (the
  `:actor` pair), `"kumi_admin_sign_out_path"`, `"kumi_admin_sign_in_path"`,
  `"kumi_admin_user_resource"`, `"kumi_admin_register_path"` and
  `"kumi_admin_strings"` (the `:strings` overrides). LiveView signs that
  map — signs, does not encrypt — into the page's `data-phx-session`
  token, so it deliberately carries no copy of the cookie session: a
  bearer token such as `ash_authentication_phoenix`'s `user_token` must
  never end up readable in the page markup.

  Your `on_mount` hooks still see the cookie session, because LiveView
  merges it in itself: from the conn on the dead render, and from the
  socket's `connect_info` on the connected mount. The latter needs the
  endpoint's

      socket "/live", Phoenix.LiveView.Socket,
        websocket: [connect_info: [session: @session_options]]

  which `phx.new` generates. Without it, a hook that reads the session
  finds nothing on the connected mount — no actor, so the gate redirects
  to `:sign_in_path`.
  """

  # Every optional key and its default, defined once: the macro validates
  # against this list and `KumiAdmin.Context` falls back to it.
  @defaults [
    on_mount: [],
    actor: {KumiAdmin.Actor, :from_current_user},
    sign_out_path: "/sign-out",
    sign_in_path: "/sign-in",
    user_resource: nil,
    register_path: "/register",
    strings: %{},
    live_session_name: :kumi_admin
  ]

  @doc false
  def __defaults__, do: @defaults

  defmacro kumi_admin(path, opts \\ []) do
    quote bind_quoted: [path: path, opts: opts] do
      import Phoenix.LiveView.Router

      opts = Keyword.validate!(opts, [:app | KumiAdmin.Router.__defaults__()])
      app = Keyword.fetch!(opts, :app)
      actor_fun = Keyword.fetch!(opts, :actor)

      # `KumiAdmin.Actor.resolve/2` applies exactly this pair; a capture
      # would otherwise compile and only fail on the first mount.
      if not match?({m, f} when is_atom(m) and is_atom(f), actor_fun) do
        raise ArgumentError,
              "kumi_admin :actor must be a {Module, :function} pair, got: #{inspect(actor_fun)}"
      end

      sign_out_path = Keyword.fetch!(opts, :sign_out_path)
      sign_in_path = Keyword.fetch!(opts, :sign_in_path)
      user_resource = Keyword.fetch!(opts, :user_resource)
      register_path = Keyword.fetch!(opts, :register_path)
      on_mount_hooks = Keyword.fetch!(opts, :on_mount)
      strings = Keyword.fetch!(opts, :strings)
      live_session_name = Keyword.fetch!(opts, :live_session_name)

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

  # Starts from an empty map, never `Plug.Conn.get_session/1`: this return
  # value is what LiveView signs into the page (see "Actor handoff").
  @doc false
  def __session__(
        _conn,
        path,
        app,
        actor_fun,
        sign_out_path,
        sign_in_path,
        user_resource,
        register_path,
        strings
      ) do
    %{
      "kumi_admin_path" => path,
      "kumi_admin_app" => app,
      "kumi_admin_actor" => actor_fun,
      "kumi_admin_sign_out_path" => sign_out_path,
      "kumi_admin_sign_in_path" => sign_in_path,
      "kumi_admin_user_resource" => user_resource,
      "kumi_admin_register_path" => register_path,
      "kumi_admin_strings" => strings
    }
  end
end
