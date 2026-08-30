defmodule KumiAdmin.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/meikocho1/kumi"
  @description """
  A LiveView admin UI derived from your Ash resources. Part of Kumi.
  """

  def project do
    [
      app: :kumi_admin,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description: @description,
      package: package(),
      docs: docs(),
      name: "Kumi Admin",
      source_url: @source_url,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      kumi_dep(),
      {:ash, "~> 3.0"},
      {:ash_phoenix, "~> 2.0"},
      {:phoenix, "~> 1.8"},
      {:phoenix_live_view, "~> 1.0"},
      {:igniter, "~> 0.6", optional: true},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  # Path dep locally, version dep when building the Hex tarball — `mix hex.build`
  # refuses any non-Hex dependency, and the packages are developed in one repo.
  # Set by `RELEASING.md`'s publish step, never in normal development.
  defp kumi_dep do
    if System.get_env("KUMI_PUBLISH") do
      {:kumi, "~> 0.1"}
    else
      {:kumi, path: "../kumi"}
    end
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => @source_url <> "/blob/main/CHANGELOG.md"
      },
      files: ~w(lib mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: ["README.md"]
    ]
  end
end
