defmodule Mix.Tasks.Kumi.Gen.Auth.Docs do
  @moduledoc false

  def short_doc do
    "Generates an OAuth2 sign-in strategy on your user resource"
  end

  def example do
    "mix kumi.gen.auth google"
  end

  def long_doc do
    """
    #{short_doc()}

    `mix ash_authentication.add_strategy` can generate `password`,
    `magic_link` and `api_key`. The OAuth2 providers have no installer
    upstream — they are hand-written DSL, and it is the same four moving
    pieces every time. This task writes those pieces as ordinary Ash
    source you can read and edit (D1 "Show Ash"), using
    `AshAuthentication`'s own public codemods to do it.

    ## Providers

      * `google` — Google OAuth2.
      * `github` — GitHub OAuth2.
      * `oidc` — any OpenID Connect provider (Microsoft Entra, Okta,
        Keycloak, your company's IdP). Requires `--base-url`.

    Several at once is fine: `mix kumi.gen.auth google github`.

    ## What it generates, per provider

      1. A `UserIdentity` resource if you don't have one. OAuth2 needs it:
         only the provider's `iss`/`sub` pair identifies a returning user
         stably. Matching on email address is not safe.
      2. The strategy block inside `authentication do strategies do`.
      3. A `register_with_<provider>` upsert action handling both
         registration and sign-in.
      4. `secret_for/4` clauses on your `Secrets` module reading from
         application env.

    Then it prints the wiring you have to do yourself: the provider console's
    redirect URI, and the config keys. It never edits your config with
    invented credentials.

    ## Example

    ```bash
    #{example()}
    mix kumi.gen.auth google github
    mix kumi.gen.auth oidc --base-url https://login.example.com
    ```

    ## Options

      * `--user`, `-u` — the user resource. Defaults to
        `YourApp.Accounts.User`.
      * `--accounts`, `-a` — the accounts domain. Defaults to
        `YourApp.Accounts`.
      * `--identity-resource` — the user identity resource. Defaults to
        `<accounts>.UserIdentity`.
      * `--base-url` — required for `oidc`, ignored otherwise.

    ## Two-factor authentication

    There is no TOTP strategy in `ash_authentication`, and Kumi does not
    add one. Generating `oidc` (or `google` against a Workspace domain)
    is the supported path to MFA: enrolment, recovery codes and hardware
    keys stay with the identity provider. See `guides/auth.md`.
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Kumi.Gen.Auth do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"

    @moduledoc __MODULE__.Docs.long_doc()

    use Igniter.Mix.Task

    # Resolved at runtime: kumi core does not depend on ash_authentication.
    # The host application this task runs in does. Held as a plain atom so
    # compiling kumi never sees a call into a module it hasn't got.
    @ash_auth_igniter AshAuthentication.Igniter

    @providers Enum.map(Kumi.Auth.Codegen.providers(), &to_string/1)

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :kumi,
        example: __MODULE__.Docs.example(),
        positional: [providers: [rest: true]],
        schema: [
          user: :string,
          accounts: :string,
          identity_resource: :string,
          base_url: :string
        ],
        aliases: [u: :user, a: :accounts],
        defaults: [],
        required: []
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      providers = igniter.args.positional[:providers] || []
      opts = resolve_options(igniter)

      with :ok <- check_providers(providers),
           :ok <- check_oidc_base_url(providers, opts),
           :ok <- check_ash_authentication() do
        case Igniter.Project.Module.module_exists(igniter, opts[:user]) do
          {true, igniter} ->
            Enum.reduce(providers, igniter, &generate(&2, &1, opts))

          {false, igniter} ->
            Igniter.add_issue(igniter, """
            User resource #{inspect(opts[:user])} was not found.

            Install authentication first, then re-run this task:

                mix ash_authentication.install --auth-strategy password

            Or point at an existing resource with --user.
            """)
        end
      else
        {:error, message} -> Igniter.add_issue(igniter, message)
      end
    end

    defp resolve_options(igniter) do
      igniter.args.options
      |> Keyword.put_new_lazy(:accounts, fn ->
        Igniter.Project.Module.module_name(igniter, "Accounts")
      end)
      |> then(fn opts ->
        opts
        |> Keyword.update!(:accounts, &parse_module/1)
        |> Keyword.put_new_lazy(:user, fn ->
          Module.concat(parse_module(opts[:accounts]), User)
        end)
        |> Keyword.update!(:user, &parse_module/1)
      end)
      |> then(fn opts ->
        opts
        |> Keyword.put_new_lazy(:identity_resource, fn ->
          Module.concat(opts[:accounts], UserIdentity)
        end)
        |> Keyword.update!(:identity_resource, &parse_module/1)
      end)
      |> Keyword.put(:secrets, Igniter.Project.Module.module_name(igniter, "Secrets"))
    end

    defp parse_module(module) when is_atom(module), do: module
    defp parse_module(string) when is_binary(string), do: Igniter.Project.Module.parse(string)

    defp check_ash_authentication do
      if Code.ensure_loaded?(@ash_auth_igniter) do
        :ok
      else
        {:error,
         """
         ash_authentication is not available in this project.

         This task generates AshAuthentication DSL and uses its own
         codemods to do it. Add the dependency and install it first:

             mix igniter.install ash_authentication --auth-strategy password
         """}
      end
    end

    defp check_providers([]) do
      {:error,
       "Name at least one provider: #{Enum.join(@providers, ", ")}. Example: mix kumi.gen.auth google"}
    end

    defp check_providers(providers) do
      case Enum.reject(providers, &(&1 in @providers)) do
        [] ->
          :ok

        unknown ->
          {:error,
           """
           Unknown provider(s): #{Enum.join(unknown, ", ")}.

           This task generates: #{Enum.join(@providers, ", ")}.

           password, magic_link and api_key have an upstream installer —
           use `mix ash_authentication.add_strategy` for those. Apple and
           Slack are not generated here yet; see guides/auth.md for the
           shape to write by hand.
           """}
      end
    end

    defp check_oidc_base_url(providers, opts) do
      if "oidc" in providers and is_nil(opts[:base_url]) do
        {:error,
         "oidc requires --base-url (your provider's issuer URL, e.g. --base-url https://login.example.com)"}
      else
        :ok
      end
    end

    defp generate(igniter, provider, opts) do
      name = String.to_atom(provider)

      igniter
      |> ensure_identity_resource(opts)
      |> add_secrets(name, opts)
      |> add_strategy(name, opts)
      |> add_register_action(name, opts)
      |> warn_about_hashed_password(opts)
      |> wiring_notice(provider, opts)
      |> Ash.Igniter.codegen("add_#{provider}_auth")
    end

    defp ensure_identity_resource(igniter, opts) do
      apply(@ash_auth_igniter, :ensure_user_identity_resource, [
        igniter,
        opts[:user],
        opts[:identity_resource]
      ])
    end

    # client_id / client_secret for every provider; redirect_uri too, because
    # it differs per environment and belongs in config rather than in source.
    defp add_secrets(igniter, name, opts) do
      Enum.reduce(Kumi.Auth.Codegen.secret_keys(name), igniter, fn {path, env_key}, igniter ->
        apply(@ash_auth_igniter, :add_new_secret_from_env, [
          igniter,
          opts[:secrets],
          opts[:user],
          path,
          env_key
        ])
      end)
    end

    defp add_strategy(igniter, name, opts) do
      apply(@ash_auth_igniter, :add_new_strategy, [
        igniter,
        opts[:user],
        name,
        name,
        Kumi.Auth.Codegen.strategy(name, opts)
      ])
    end

    defp add_register_action(igniter, name, opts) do
      {igniter, upsert_identity} = upsert_identity(igniter, opts)

      {igniter, confirm?} =
        Ash.Resource.Igniter.defines_attribute(igniter, opts[:user], :confirmed_at)

      Ash.Resource.Igniter.add_new_action(
        igniter,
        opts[:user],
        :"register_with_#{name}",
        Kumi.Auth.Codegen.register_action(name,
          upsert_identity: upsert_identity,
          confirmed_at?: confirm?
        )
      )
    end

    # Without a unique identity on the user resource the upsert has nothing
    # to match on, and generating `upsert_identity :unique_email` anyway
    # would produce a resource that fails to compile. Fall back to a plain
    # create and say so.
    defp upsert_identity(igniter, opts) do
      case Ash.Resource.Igniter.defines_identity(igniter, opts[:user], :unique_email) do
        {igniter, true} -> {igniter, :unique_email}
        {igniter, false} -> {igniter, nil}
      end
    end

    # An OAuth-only user has no password, so a NOT NULL `hashed_password`
    # makes the upsert fail at runtime rather than at compile time. This is
    # one line in the user resource and editing an attribute's options in
    # place is fragile, so say it instead of guessing at the AST.
    defp warn_about_hashed_password(igniter, opts) do
      case Ash.Resource.Igniter.defines_attribute(igniter, opts[:user], :hashed_password) do
        {igniter, true} ->
          Igniter.add_notice(igniter, """
          One edit left in #{inspect(opts[:user])} — if you keep the password
          strategy, a user who signs in with a provider has no password:

              attribute :hashed_password, :string, allow_nil?: true, sensitive?: true

          Then `mix ash.codegen make_hashed_password_nullable && mix ash.migrate`.
          """)

        {igniter, false} ->
          igniter
      end
    end

    defp wiring_notice(igniter, provider, opts) do
      Igniter.add_notice(igniter, """
      #{provider} sign-in generated. Two things left, both outside the code:

      1. Register the redirect URI with the provider:

           http://localhost:4000#{Kumi.Auth.Codegen.callback_path(provider)}

         (and the equivalent for every deployed environment)

      2. Configure the credentials — #{inspect(opts[:secrets])} reads them
         from application env, so nothing secret goes in source:

           config #{inspect(Mix.Project.config()[:app])},
             #{provider}_client_id: System.get_env("#{String.upcase(provider)}_CLIENT_ID"),
             #{provider}_client_secret: System.get_env("#{String.upcase(provider)}_CLIENT_SECRET"),
             #{provider}_redirect_uri: System.get_env("#{String.upcase(provider)}_REDIRECT_URI")

      The sign-in button renders itself once the strategy compiles —
      ash_authentication_phoenix picks it up, and `mix kumi.new`'s generated
      AuthOverrides already styles it.
      """)
    end
  end
else
  defmodule Mix.Tasks.Kumi.Gen.Auth do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"

    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    def run(_argv) do
      Mix.shell().error("""
      The task 'kumi.gen.auth' requires igniter.

      Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
