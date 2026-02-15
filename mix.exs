defmodule TomlElixir.Mixfile do
  use Mix.Project

  def project do
    version = "3.1.0"

    [
      app: :toml_elixir,
      version: version,
      elixir: ">= 1.18.0",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      description: description(),
      cli: cli(),
      elixirc_paths: elixirc_paths(Mix.env()),

      # Docs
      name: "Toml Elixir",
      source_url: "https://github.com/nikolauska/toml_elixir",
      homepage_url: "https://github.com/nikolauska/toml_elixir",
      docs: [
        main: "readme",
        extras: ["README.md", "LICENSE.md"],
        source_url: "https://github.com/nikolauska/toml_elixir",
        source_ref: "v#{version}"
      ],

      # Test coverage
      test_coverage: [tool: ExCoveralls],
      aliases: [
        tidewave: "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4000) end)'"
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  # Configuration for the OTP application
  # Type "mix help compile.app" for more information
  def application do
    []
  end

  defp package do
    [
      files: ["mix.exs", "lib", "README.md", "LICENSE.md"],
      maintainers: ["Niko Lehtovirta"],
      licenses: ["MIT"],
      links: %{
        "Github" => "https://github.com/nikolauska/toml_elixir"
      }
    ]
  end

  defp description do
    """
    Modern TOML parser and encoder for Elixir with protocol-based struct support
    """
  end

  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:ex_doc, "~> 0.39", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.10", only: [:dev, :test], runtime: false},
      {:tidewave, "~> 0.4", only: :dev},
      {:bandit, "~> 1.0", only: :dev}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
