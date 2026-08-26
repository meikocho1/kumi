defmodule Mix.Tasks.KumiAdmin.Install.Docs do
  @moduledoc false

  def short_doc do
    "Mounts Kumi Admin into a host Phoenix router"
  end

  def example do
    "mix kumi_admin.install"
  end

  def long_doc do
    """
    #{short_doc()}

    Runs `kumi.install` first (composed), then mounts `KumiAdmin.Router`'s
    `kumi_admin/2` macro into your Phoenix router.

    If an `on_mount(:current_user, ...)` clause is found on the
    conventional `<AppWeb>.LiveUserAuth` module (the shape
    `ash_authentication_phoenix` generates), the mount is wired in for
    real, exactly as `KumiAdmin.Router`'s own moduledoc example shows.
    Otherwise nothing is guessed — a notice is printed with the snippet to
    add by hand, since a wrong `on_mount`/actor guess is worse than asking.

    ## Example

    ```bash
    #{example()}
    ```
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.KumiAdmin.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"

    @moduledoc __MODULE__.Docs.long_doc()

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :kumi_admin,
        adds_deps: [],
        installs: [],
        example: __MODULE__.Docs.example(),
        only: nil,
        positional: [],
        composes: ["kumi.install"],
        schema: [],
        defaults: [],
        aliases: [],
        required: []
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      igniter
      |> Igniter.compose_task("kumi.install", [])
      |> mount_router()
    end

    defp mount_router(igniter) do
      app_module = Igniter.Project.Module.module_name(igniter, "App")
      {igniter, router} = Igniter.Libs.Phoenix.select_router(igniter, "Which router should Kumi Admin be mounted in?")

      cond do
        router == nil ->
          Igniter.add_warning(igniter, """
          Kumi Admin: no Phoenix router found or selected. Mount it manually:

              import KumiAdmin.Router

              kumi_admin "/kumi-admin",
                app: #{inspect(app_module)},
                on_mount: [{MyAppWeb.LiveUserAuth, :current_user}]
          """)

        already_mounted?(igniter, router) ->
          Igniter.add_notice(igniter, "Kumi Admin: already mounted in #{inspect(router)} — leaving it untouched.")

        true ->
          {igniter, auth_module} = detect_live_user_auth(igniter)
          do_mount(igniter, router, app_module, auth_module)
      end
    end

    defp already_mounted?(igniter, router) do
      {_igniter, _source, zipper} = Igniter.Project.Module.find_module!(igniter, router)

      match?(
        {:ok, _},
        Igniter.Code.Common.move_to(
          zipper,
          &Igniter.Code.Function.function_call?(&1, :kumi_admin, [1, 2])
        )
      )
    end

    # Only auto-wires when the conventional ash_authentication_phoenix
    # LiveUserAuth module exists AND actually defines the `:current_user`
    # on_mount clause KumiAdmin.Router's example expects — never guessed.
    defp detect_live_user_auth(igniter) do
      auth_module = Igniter.Libs.Phoenix.web_module_name(igniter, "LiveUserAuth")

      {exists?, igniter} = Igniter.Project.Module.module_exists(igniter, auth_module)

      if exists? and defines_current_user_on_mount?(igniter, auth_module) do
        {igniter, auth_module}
      else
        {igniter, nil}
      end
    end

    defp defines_current_user_on_mount?(igniter, auth_module) do
      {_igniter, _source, zipper} = Igniter.Project.Module.find_module!(igniter, auth_module)

      match?(
        {:ok, _},
        Igniter.Code.Common.move_to(zipper, fn z ->
          Igniter.Code.Function.function_call?(z, :on_mount, [4]) and
            Igniter.Code.Function.argument_equals?(z, 0, :current_user)
        end)
      )
    end

    defp do_mount(igniter, router, app_module, nil) do
      igniter
      |> Igniter.add_notice("""
      Kumi Admin: could not confirm an authenticated LiveView hook, so
      nothing was mounted. Add this to #{inspect(router)} yourself, inside
      an authenticated scope:

          import KumiAdmin.Router

          kumi_admin "/kumi-admin",
            app: #{inspect(app_module)},
            on_mount: [{MyAppWeb.LiveUserAuth, :current_user}]

      See `KumiAdmin.Router`'s moduledoc for what `:on_mount`/`:actor` need
      to provide.
      """)
    end

    defp do_mount(igniter, router, app_module, auth_module) do
      contents = """
      pipe_through :browser
      import KumiAdmin.Router

      kumi_admin "/kumi-admin",
        app: #{inspect(app_module)},
        on_mount: [{#{inspect(auth_module)}, :current_user}]
      """

      igniter
      |> Igniter.Libs.Phoenix.add_scope("/", contents, router: router, placement: :after)
      |> Igniter.add_notice("""
      Kumi Admin: mounted at /kumi-admin in #{inspect(router)}, using
      #{inspect(auth_module)} to resolve the actor.
      """)
    end
  end
else
  defmodule Mix.Tasks.KumiAdmin.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"

    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    def run(_argv) do
      Mix.shell().error("""
      The task 'kumi_admin.install' requires igniter. Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
