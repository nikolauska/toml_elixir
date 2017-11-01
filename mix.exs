defmodule TomlElixir.Mixfile do
  use Mix.Project

  def project do
    [
      app: :toml_elixir,
      version: "1.1.0",
      elixir: "~> 1.4",
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      dialyzer: dialyzer(),
      deps: deps(),
      package: package(),
      description: description(),

      # Docs
      name: "Toml Elixir",
      source_url: "https://github.com/nikolauska/toml_elixir",
      homepage_url: "http://github.com/nikolauska/toml_elixir",
      docs: [main: "TomlElixir"],

      # Test coverage
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        "coveralls": :test,
        "coveralls.detail": :test,
        "coveralls.post": :test
      ]
    ]
  end

  # Dialyzer settings
  def dialyzer do
    [
      ignore_warnings: "dialyzer.ignore-warnings"
    ]
  end

  # Configuration for the OTP application
  # Type "mix help compile.app" for more information
  def application do
    []
  end

  defp package do
    [
      files: ["mix.exs", "lib", "src", "README.md", "LICENSE.md"],
      maintainers: ["Niko Lehtovirta"],
      licenses: ["MIT"],
      links: %{
        "Github" => "https://github.com/nikolauska/toml_elixir"
      }
    ]
  end

  defp description do
    """
    TOML parser for elixir
    """
  end

  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:dialyxir, "~> 0.5.1", only: :dev, runtime: false},
      {:credo, "~> 0.8.8", only: :dev, runtime: false},
      {:ex_doc, "~> 0.18.1", only: :dev, runtime: false},
      {:excoveralls, "~> 0.7.4", only: :test, runtime: false},
      {:inch_ex, "~> 0.5.6", only: :docs}
    ]
  end
end
