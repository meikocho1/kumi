defmodule KumiNew.Args do
  @moduledoc """
  Pure argument parsing for `mix kumi.new`. No I/O — takes argv, returns a
  parsed struct or an error message.
  """

  defstruct app_name: nil,
            db_port: 5432,
            kumi_path: nil,
            admin?: true,
            setup?: true,
            json_api?: false,
            auth_strategies: ["password"],
            auth_providers: [],
            modules_flag: :unset,
            modules: []

  @type modules_flag :: {:with, [atom()]} | :none | :unset

  @type t :: %__MODULE__{
          app_name: String.t(),
          db_port: pos_integer(),
          kumi_path: String.t(),
          admin?: boolean(),
          setup?: boolean(),
          json_api?: boolean(),
          auth_strategies: [String.t()],
          auth_providers: [String.t()],
          modules_flag: modules_flag(),
          modules: [atom()]
        }

  @switches [
    db_port: :integer,
    kumi_path: :string,
    admin: :boolean,
    setup: :boolean,
    json_api: :boolean,
    auth_strategy: :string,
    with: :string,
    modules: :boolean
  ]

  # Split by who generates them. `mix ash_authentication.add_strategy`
  # handles the first list and runs during `igniter.new`; the OAuth2
  # providers have no upstream installer, so `mix kumi.gen.auth` writes
  # them into the generated app afterwards.
  @auth_strategies ~w(password magic_link api_key)
  @auth_providers ~w(google github)

  @spec parse([String.t()]) :: {:ok, t()} | {:error, String.t()}
  def parse(argv) do
    {opts, positional, invalid} = OptionParser.parse(argv, switches: @switches)

    with :ok <- check_invalid(invalid),
         {:ok, app_name} <- fetch_app_name(positional),
         :ok <- KumiNew.Name.validate(app_name),
         {:ok, kumi_path} <- fetch_kumi_path(opts),
         {:ok, {auth_strategies, auth_providers}} <- fetch_auth_strategies(opts),
         {:ok, modules_flag} <- fetch_modules_flag(opts) do
      {:ok,
       %__MODULE__{
         app_name: app_name,
         db_port: Keyword.get(opts, :db_port, 5432),
         kumi_path: kumi_path,
         admin?: Keyword.get(opts, :admin, true),
         setup?: Keyword.get(opts, :setup, true),
         json_api?: Keyword.get(opts, :json_api, false),
         auth_strategies: auth_strategies,
         auth_providers: auth_providers,
         modules_flag: modules_flag
       }}
    end
  end

  defp check_invalid([]), do: :ok

  defp check_invalid(invalid) do
    names = Enum.map_join(invalid, ", ", fn {flag, _} -> flag end)
    {:error, "Unrecognized or invalid option(s): #{names}"}
  end

  defp fetch_app_name([app_name]), do: {:ok, app_name}
  defp fetch_app_name([]), do: {:error, "Expected APP_NAME, e.g. mix kumi.new my_crm"}

  defp fetch_app_name(_multiple),
    do: {:error, "Expected a single APP_NAME argument, got multiple positional arguments"}

  defp fetch_kumi_path(opts) do
    case Keyword.get(opts, :kumi_path) do
      nil ->
        {:error,
         "--kumi-path is required until kumi ships to Hex. Pass the directory that " <>
           "contains the kumi/ and kumi_admin/ packages, e.g. --kumi-path ~/Documents/Kumi"}

      path ->
        validate_kumi_path(Path.expand(path))
    end
  end

  defp fetch_auth_strategies(opts) do
    case Keyword.get(opts, :auth_strategy, "password") do
      "" ->
        {:error, "--auth-strategy cannot be empty (omit the flag for the default, password)"}

      csv ->
        requested = csv |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

        case Enum.reject(requested, &(&1 in @auth_strategies or &1 in @auth_providers)) do
          [] -> {:ok, Enum.split_with(requested, &(&1 in @auth_strategies))}
          bad -> {:error, unknown_strategies_message(bad)}
        end
    end
  end

  defp unknown_strategies_message(bad) do
    "unknown --auth-strategy value(s): #{Enum.join(bad, ", ")}. " <>
      "Supported: #{Enum.join(@auth_strategies ++ @auth_providers, ", ")}. " <>
      "oidc needs an issuer URL, so it is not available here — run " <>
      "`mix kumi.gen.auth oidc --base-url ...` inside the generated app. " <>
      "Apple and Slack are not generated yet; see the auth guide."
  end

  defp fetch_modules_flag(opts) do
    with_str = Keyword.get(opts, :with)
    modules_bool = Keyword.get(opts, :modules)

    cond do
      with_str != nil and modules_bool == false ->
        {:error, "cannot combine --with with --no-modules"}

      with_str != nil ->
        case KumiNew.Modules.parse_selection(with_str) do
          {:ok, list} -> {:ok, {:with, list}}
          {:error, _} = error -> error
        end

      modules_bool == false ->
        {:ok, :none}

      true ->
        {:ok, :unset}
    end
  end

  defp validate_kumi_path(path) do
    kumi_mix = Path.join([path, "kumi", "mix.exs"])
    admin_mix = Path.join([path, "kumi_admin", "mix.exs"])

    cond do
      not File.exists?(kumi_mix) ->
        {:error, "--kumi-path #{path} does not contain a kumi/mix.exs — check the path"}

      not File.exists?(admin_mix) ->
        {:error, "--kumi-path #{path} does not contain a kumi_admin/mix.exs — check the path"}

      true ->
        {:ok, path}
    end
  end
end
