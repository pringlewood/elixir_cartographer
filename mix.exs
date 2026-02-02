defmodule ElixirCartographer.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :elixir_cartographer,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript(),
      aliases: aliases(),
      name: "Elixir Cartographer",
      description: "Reverse-engineers Elixir codebases into LLM-ready documentation"
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ElixirCartographer.Application, []}
    ]
  end

  defp escript do
    [main_module: ElixirCartographer.CLI]
  end

  defp deps do
    []
  end

  defp aliases do
    []
  end
end
