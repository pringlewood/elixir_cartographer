defmodule ElixirCartographer do
  @moduledoc """
  Elixir Cartographer — reverse-engineers an Elixir codebase into LLM-ready documentation.

  ## Usage

  As a Mix task:
      mix cartographer.map /path/to/project --output ./docs

  As a CLI (escript):
      elixir_cartographer /path/to/project --output ./docs

  ## Architecture

  Four analysis layers:
  1. **Static Analysis** — AST parsing, module graph, schemas, processes
  2. **Git Mining** — commit classification, hotspots, evolution
  3. **Test Mining** — test inventory, edge cases, coverage gaps
  4. **Synthesis** — combines all layers into structured documentation
  """

  alias ElixirCartographer.{Config, Pipeline}

  @doc """
  Run the full cartography pipeline on a project.
  """
  def map(project_path, opts \\ []) do
    config = Config.new(project_path, opts)
    Pipeline.run(config)
  end
end
