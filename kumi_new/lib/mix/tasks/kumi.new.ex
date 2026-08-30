defmodule Mix.Tasks.Kumi.New do
  @shortdoc "Generates a new Phoenix+Ash app with Kumi and kumi_admin installed"

  @moduledoc """
  #{@shortdoc}

      mix kumi.new my_crm --kumi-path ~/Documents/Kumi --db-port 5434

  One command from nothing to `mix phx.server`: runs `mix igniter.new` with
  Ash/Phoenix/Ash Authentication, wires in Kumi + kumi_admin as path deps,
  configures the dev/test database port, installs Kumi, mounts kumi_admin,
  and runs `mix ash.setup`.

  ## Options

    * `--db-port PORT` — Postgres port for dev/test config (default: 5432).
    * `--kumi-path DIR` — directory containing the `kumi/` and `kumi_admin/`
      packages. **Required** while Kumi is not published to Hex; once it
      ships to Hex this flag becomes optional and `{:kumi, "~> x.y"}` will
      be used instead.
    * `--no-admin` — skip kumi_admin (no admin UI mounted).
    * `--no-setup` — skip `mix ash.setup` (DB create + migrate).
    * `--json-api` — also install `ash_json_api`.
    * `--auth-strategy LIST` — comma-separated ash_authentication strategies
      to generate (default: `password`). Accepts `password`, `magic_link`,
      `api_key` — the three `mix ash_authentication.add_strategy` can
      generate. OAuth providers (Google, GitHub, Apple, Slack, Auth0, OIDC)
      and two-factor auth have no installer upstream and are added by hand;
      see `kumi/guides/auth.md`.
    * `--with LIST` — comma-separated optional modules to install and wire
      in, e.g. `--with storage`. See the catalog below.
    * `--no-modules` — skip all optional modules explicitly (also
      suppresses the interactive picker).

  ## Optional modules

    * `storage` — file/image uploads (kumi_storage). Default: off.

  When neither `--with` nor `--no-modules` is given and the shell is
  interactive, you'll be prompted to pick modules. Non-interactive runs
  (CI, agents, piped input) default to none. `admin` is not part of this
  picker — it's the default product shell, controlled by `--no-admin`.
  Selected modules arrive fully wired: dep, installer, and a generated
  migration for their resources, applied by `mix ash.setup` like everything
  else.

  This task must run projectless (it generates the project) — do not run it
  from inside an existing Mix project directory.
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    with {:ok, args} <- KumiNew.Args.parse(argv),
         :ok <- check_target_dir(args.app_name),
         :ok <- preflight_archives(),
         {:ok, args} <- resolve_modules(args),
         :ok <- generate(args),
         :ok <- inject_deps(args),
         :ok <- patch_ports(args),
         :ok <- write_home_page(args),
         :ok <- write_auth_overrides(args),
         :ok <- write_page_controller_test(args),
         :ok <- format_injected(args),
         :ok <- run_in_app(args, "deps.get", []),
         :ok <- run_in_app(args, "kumi.install", ["--yes"]),
         :ok <- maybe_generate_auth_providers(args),
         :ok <- maybe_install_admin(args),
         :ok <- maybe_install_modules(args),
         :ok <- maybe_codegen_modules(args) do
      maybe_setup(args)
      print_next_steps(args)
    else
      {:error, message} ->
        Mix.shell().error("\nmix kumi.new failed: #{message}")
        exit({:shutdown, 1})
    end
  end

  defp check_target_dir(app_name) do
    if File.exists?(app_name) do
      {:error, "directory #{inspect(app_name)} already exists"}
    else
      :ok
    end
  end

  defp resolve_modules(args) do
    case KumiNew.Modules.resolve(args.modules_flag) do
      {:ok, modules} -> {:ok, %{args | modules: modules}}
      {:error, _} = error -> error
    end
  end

  defp preflight_archives do
    {output, 0} = System.cmd("mix", ["archive"])

    missing =
      for {name, flag} <- [{"igniter_new", "igniter_new"}, {"phx_new", "phx_new"}],
          not String.contains?(output, name),
          do: flag

    case missing do
      [] ->
        :ok

      _ ->
        {:error,
         "missing required mix archive(s): #{Enum.join(missing, ", ")}. Install with:\n" <>
           "  mix archive.install hex igniter_new\n" <>
           "  mix archive.install hex phx_new"}
    end
  end

  defp generate(args) do
    Mix.shell().info("\n==> mix igniter.new #{args.app_name} ...\n")

    install =
      "ash,ash_postgres,ash_phoenix,ash_authentication,ash_authentication_phoenix"

    install = if args.json_api?, do: install <> ",ash_json_api", else: install

    # OAuth providers are deliberately not passed here — igniter.new hands
    # `--auth-strategy` straight to ash_authentication, which only knows how
    # to generate password/magic_link/api_key. The providers are generated
    # afterwards by `mix kumi.gen.auth`, once the user resource exists.
    auth_flags =
      case args.auth_strategies do
        [] -> []
        strategies -> ["--auth-strategy", Enum.join(strategies, ",")]
      end

    stream_cmd(
      "mix",
      ["igniter.new", args.app_name, "--with", "phx.new", "--install", install] ++
        auth_flags ++ ["--yes"]
    )
  end

  defp inject_deps(args) do
    extra = if args.admin?, do: " + kumi_admin", else: ""
    modules_note = if args.modules == [], do: "", else: " + #{Enum.join(args.modules, ", ")}"
    Mix.shell().info("\n==> wiring kumi#{extra}#{modules_note} into mix.exs\n")
    mix_exs_path = Path.join(args.app_name, "mix.exs")

    with {:ok, content} <- read(mix_exs_path),
         {:ok, updated} <-
           KumiNew.Inject.insert_deps(content, args.kumi_path, args.admin?, args.modules) do
      write(mix_exs_path, updated)
    end
  end

  defp patch_ports(%{db_port: 5432}), do: :ok

  defp patch_ports(args) do
    Mix.shell().info("\n==> setting db port #{args.db_port} in dev.exs / test.exs\n")

    Enum.reduce_while(["config/dev.exs", "config/test.exs"], :ok, fn rel, :ok ->
      path = Path.join(args.app_name, rel)

      with {:ok, content} <- read(path),
           {:ok, updated} <- KumiNew.Inject.patch_port(content, args.db_port),
           :ok <- write(path, updated) do
        {:cont, :ok}
      else
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp write_home_page(args) do
    Mix.shell().info("\n==> branding the top page\n")

    path =
      Path.join([
        args.app_name,
        "lib",
        "#{args.app_name}_web",
        "controllers",
        "page_html",
        "home.html.heex"
      ])

    write(path, KumiNew.Inject.home_page(KumiNew.Name.title(args.app_name), args.admin?))
  end

  defp write_auth_overrides(args) do
    Mix.shell().info("\n==> restyling the sign-in page\n")
    web_module = "#{Macro.camelize(args.app_name)}Web"
    path = Path.join([args.app_name, "lib", "#{args.app_name}_web", "auth_overrides.ex"])
    write(path, KumiNew.Inject.auth_overrides(web_module, KumiNew.Name.title(args.app_name)))
  end

  defp write_page_controller_test(args) do
    web_module = "#{Macro.camelize(args.app_name)}Web"

    path =
      Path.join([
        args.app_name,
        "test",
        "#{args.app_name}_web",
        "controllers",
        "page_controller_test.exs"
      ])

    write(path, KumiNew.Inject.page_controller_test(web_module))
  end

  defp format_injected(args) do
    files = [
      "mix.exs",
      "config/dev.exs",
      "config/test.exs",
      "lib/#{args.app_name}_web/controllers/page_html/home.html.heex",
      "lib/#{args.app_name}_web/auth_overrides.ex",
      "test/#{args.app_name}_web/controllers/page_controller_test.exs"
    ]

    stream_cmd("mix", ["format" | files], cd: args.app_name)
  end

  defp run_in_app(args, task, extra_args) do
    Mix.shell().info("\n==> mix #{task} #{Enum.join(extra_args, " ")}\n")
    stream_cmd("mix", [task | extra_args], cd: args.app_name)
  end

  defp maybe_generate_auth_providers(%{auth_providers: []}), do: :ok

  defp maybe_generate_auth_providers(args) do
    run_in_app(args, "kumi.gen.auth", args.auth_providers ++ ["--yes"])
  end

  defp maybe_install_admin(%{admin?: false}), do: :ok
  defp maybe_install_admin(args), do: run_in_app(args, "kumi_admin.install", ["--yes"])

  defp maybe_install_modules(%{modules: []}), do: :ok

  defp maybe_install_modules(args) do
    Enum.reduce_while(args.modules, :ok, fn key, :ok ->
      entry = KumiNew.Modules.fetch(key)

      case run_in_app(args, entry.installer, ["--yes"]) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp maybe_codegen_modules(%{modules: []}), do: :ok

  defp maybe_codegen_modules(args) do
    # Module installers (e.g. kumi_storage.install) generate resources
    # under lib/ — not test/support — so no MIX_ENV=test workaround is
    # needed here (that's specifically a test/support gotcha, F27). One
    # migration for every selected module's new resource(s), generated
    # before `mix ash.setup` so it gets applied in the same pass.
    run_in_app(args, "ash.codegen", ["add_kumi_modules"])
  end

  defp maybe_setup(%{setup?: false}), do: :ok

  defp maybe_setup(args) do
    Mix.shell().info("\n==> mix ash.setup\n")

    case stream_cmd("mix", ["ash.setup"], cd: args.app_name) do
      :ok ->
        :ok

      {:error, message} ->
        Mix.shell().error("""

        Warning: mix ash.setup failed (#{message}).
        The app was generated successfully — you just need a reachable Postgres.
        Start one, then run inside #{args.app_name}:

            docker run -d --name kumi_db -e POSTGRES_PASSWORD=postgres \\
              -p #{args.db_port}:5432 postgres:17-alpine
            mix ash.setup
        """)
    end
  end

  defp print_next_steps(args) do
    steps =
      [
        "Add your Ash resources under `resources do ... end` in lib/#{args.app_name}/app.ex\n     (use `Kumi.Resource` shorthand, then `mix kumi.expand` / `mix ash.codegen`).",
        "mix phx.server",
        if(args.admin?, do: "Register a user at /register, then visit /kumi-admin"),
        "mix kumi.plan / mix kumi.report — inspect and verify your app."
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {step, i} -> "  #{i}. #{step}" end)

    Mix.shell().info("""

    ==> #{args.app_name} is ready.

    Next steps:
      cd #{args.app_name}
    #{steps}
    """)
  end

  defp stream_cmd(cmd, args, opts \\ []) do
    {_output, status} =
      System.cmd(
        cmd,
        args,
        Keyword.merge([into: IO.stream(:stdio, :line), stderr_to_stdout: true], opts)
      )

    if status == 0, do: :ok, else: {:error, "`#{cmd} #{Enum.join(args, " ")}` exited #{status}"}
  end

  defp read(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, "could not read #{path}: #{:file.format_error(reason)}"}
    end
  end

  defp write(path, content) do
    case File.write(path, content) do
      :ok -> :ok
      {:error, reason} -> {:error, "could not write #{path}: #{:file.format_error(reason)}"}
    end
  end
end
