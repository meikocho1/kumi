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
            json_api?: false

  @type t :: %__MODULE__{
          app_name: String.t(),
          db_port: pos_integer(),
          kumi_path: String.t(),
          admin?: boolean(),
          setup?: boolean(),
          json_api?: boolean()
        }

  @switches [
    db_port: :integer,
    kumi_path: :string,
    admin: :boolean,
    setup: :boolean,
    json_api: :boolean
  ]

  @spec parse([String.t()]) :: {:ok, t()} | {:error, String.t()}
  def parse(argv) do
    {opts, positional, invalid} = OptionParser.parse(argv, switches: @switches)

    with :ok <- check_invalid(invalid),
         {:ok, app_name} <- fetch_app_name(positional),
         :ok <- KumiNew.Name.validate(app_name),
         {:ok, kumi_path} <- fetch_kumi_path(opts) do
      {:ok,
       %__MODULE__{
         app_name: app_name,
         db_port: Keyword.get(opts, :db_port, 5432),
         kumi_path: kumi_path,
         admin?: Keyword.get(opts, :admin, true),
         setup?: Keyword.get(opts, :setup, true),
         json_api?: Keyword.get(opts, :json_api, false)
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
