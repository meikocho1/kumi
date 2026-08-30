defmodule KumiNew.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/meikocho1/kumi"
  @description """
  mix kumi.new — generates a Phoenix/Ash application with Kumi and kumi_admin installed.
  """

  def project do
    [
      app: :kumi_new,
      version: @version,
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      description: @description,
      package: package(),
      name: "Kumi New",
      source_url: @source_url,
      deps: deps(),
      test_ignore_filters: [&String.starts_with?(&1, "test/fixtures/")]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  # Deliberately empty, including dev-only deps: `mix archive.build` compiles
  # in :dev, so a single unfetched dependency breaks `mix archive.install`
  # for anyone who has not run `mix deps.get` here first. That is why this
  # package has no `:ex_doc` and publishes without docs (see RELEASING.md).
  defp deps, do: []

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
end
