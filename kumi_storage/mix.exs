defmodule KumiStorage.MixProject do
  use Mix.Project

  def project do
    [
      app: :kumi_storage,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
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
      {:kumi, path: "../kumi"},
      {:ash, "~> 3.0"},
      {:plug, "~> 1.15"},
      {:igniter, "~> 0.6", optional: true}
    ]
  end
end
