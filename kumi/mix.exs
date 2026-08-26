defmodule Kumi.MixProject do
  use Mix.Project

  def project do
    [
      app: :kumi,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ash, "~> 3.0"},
      {:ash_postgres, "~> 2.0"},
      {:spark, "~> 2.0"},
      {:jason, "~> 1.4"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:igniter, "~> 0.6", optional: true}
    ]
  end

  defp aliases do
    [
      test: ["ash.setup --quiet", "test"]
    ]
  end
end
