defmodule Mix.Tasks.Cartographer.Map do
  @moduledoc """
  Mix task to run Elixir Cartographer on a project.

  ## Usage

      mix cartographer.map /path/to/project --output ./docs

  ## Options

  - `--output`, `-o` — Output directory (default: <project>/cartographer_docs)
  - `--name`, `-n` — Project name (auto-detected from mix.exs)
  - `--compact`, `-c` — Generate condensed output optimized for token efficiency
  - `--skip-git` — Skip git history analysis
  - `--skip-tests` — Skip test file analysis
  - `--verbose`, `-v` — Verbose output
  """

  use Mix.Task

  @shortdoc "Reverse-engineer an Elixir codebase into LLM-ready documentation"

  @impl Mix.Task
  def run(args) do
    {opts, args, _} =
      OptionParser.parse(args,
        strict: [
          output: :string,
          name: :string,
          compact: :boolean,
          skip_git: :boolean,
          skip_tests: :boolean,
          verbose: :boolean
        ],
        aliases: [
          o: :output,
          n: :name,
          c: :compact,
          v: :verbose
        ]
      )

    case args do
      [] ->
        Mix.shell().error("Usage: mix cartographer.map <project_path> [--output <path>]")

      [project_path | _] ->
        ElixirCartographer.map(project_path, opts)
    end
  end
end
